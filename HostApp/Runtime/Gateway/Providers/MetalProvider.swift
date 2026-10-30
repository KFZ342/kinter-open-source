import Foundation
import Metal
import UIKit

/// 原生 Metal GPU 多核并行算力 Provider（L0）。
///
/// 所有算子均为 compute kernel：每个像素/元素一个线程，由 GPU 多核并行执行。
/// - `applyFilter`  逐像素滤镜（灰度/反色/复古/阈值/亮度）
/// - `convolve`     通用 3×3 卷积（模糊/锐化/边缘/浮雕，kernel 权重可传）
/// - `batchResize`  批量双线性缩放（每张图一个 command buffer，GPU 流水并行）
/// - `reduce`       大数组并行归约（sum/avg/min/max，threadgroup 内归约）
/// - `matMul`       平铺矩阵乘法（16×16 tile，多核并行）
/// - `renderFractal` Mandelbrot 分形渲染
///
/// 性能要点：所有 shader 与 pipeline 一次性编译并缓存（`static`），
/// 后续调用零编译开销；图像→纹理→GPU→回读全程零 CPU 逐像素处理。
final class MetalProvider: CapabilityProvider, AppContextInjectable {
    static var capability: String { "metal" }
    static var level: CapabilityLevel { .l0 }

    var appId: String?
    private let device = MTLCreateSystemDefaultDevice()
    private let commandQueue: MTLCommandQueue?

    init() {
        commandQueue = device?.makeCommandQueue()
    }

    // MARK: - Pipeline 缓存（shader 编译昂贵，进程内只编译一次）

    private static var library: MTLLibrary?
    private static var pipelineCache: [String: MTLComputePipelineState] = [:]
    private static let pipelineLock = NSLock()

    private func pipeline(named name: String) -> MTLComputePipelineState? {
        guard let device = device else { return nil }
        Self.pipelineLock.lock()
        defer { Self.pipelineLock.unlock() }
        if let cached = Self.pipelineCache[name] { return cached }
        if Self.library == nil {
            Self.library = try? device.makeLibrary(source: Self.shaderSource, options: nil)
        }
        guard let lib = Self.library,
              let fn = lib.makeFunction(name: name),
              let p = try? device.makeComputePipelineState(function: fn) else { return nil }
        Self.pipelineCache[name] = p
        return p
    }

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let device = device else {
            return completion(.failure(.unsupported("当前设备不支持 Metal")))
        }

        switch method {
        case "applyFilter":
            guard let imagePath = params["imagePath"] as? String,
                  let filterType = params["filterType"] as? String else {
                return completion(.failure(.invalidParams("缺少 imagePath 或 filterType")))
            }
            applyFilter(imagePath: imagePath, filterType: filterType,
                        params: params, completion: completion)

        case "convolve":
            guard let imagePath = params["imagePath"] as? String,
                  let kernel = params["kernel"] as? [NSNumber], kernel.count == 9 else {
                return completion(.failure(.invalidParams("convolve 需要 imagePath 与 9 个元素的 kernel 权重")))
            }
            convolve(imagePath: imagePath,
                     kernel: kernel.map { $0.floatValue },
                     divisor: (params["divisor"] as? NSNumber)?.floatValue ?? 1.0,
                     bias: (params["bias"] as? NSNumber)?.floatValue ?? 0.0,
                     completion: completion)

        case "batchResize":
            guard let paths = params["paths"] as? [String], !paths.isEmpty,
                  let width = (params["width"] as? NSNumber)?.intValue,
                  let height = (params["height"] as? NSNumber)?.intValue,
                  width > 0, height > 0, width <= 4096, height <= 4096 else {
                return completion(.failure(.invalidParams("batchResize 需要 paths、width、height（≤4096）")))
            }
            batchResize(paths: paths, width: width, height: height, completion: completion)

        case "reduce":
            guard let values = params["values"] as? [NSNumber], !values.isEmpty else {
                return completion(.failure(.invalidParams("reduce 需要非空 values 数组")))
            }
            let op = (params["operation"] as? String) ?? "sum"
            reduce(values: values.map { $0.doubleValue }, operation: op, completion: completion)

        case "matMul":
            guard let a = params["a"] as? [[NSNumber]],
                  let b = params["b"] as? [[NSNumber]],
                  !a.isEmpty, !b.isEmpty else {
                return completion(.failure(.invalidParams("matMul 需要二维数组 a 和 b")))
            }
            matMul(a: a.map { $0.map { $0.doubleValue } },
                   b: b.map { $0.map { $0.doubleValue } },
                   completion: completion)

        case "renderFractal":
            renderMandelbrot(completion: completion)

        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }

    // MARK: - 逐像素滤镜

    /// 滤镜模式：gray / invert / sepia / threshold / brightness
    private func applyFilter(imagePath: String, filterType: String,
                             params: [String: Any],
                             completion: @escaping (Result<Any, GatewayError>) -> Void) {
        let mode: Int32
        switch filterType {
        case "gray", "grayscale":  mode = 0
        case "invert":             mode = 1
        case "sepia":              mode = 2
        case "threshold":          mode = 3
        case "brightness":         mode = 4
        default:
            return completion(.failure(.invalidParams("未知 filterType：\(filterType)，可选 gray/invert/sepia/threshold/brightness")))
        }
        let amount = (params["amount"] as? NSNumber)?.floatValue ?? 0.5
        guard let pipeline = pipeline(named: "pixelFilter") else {
            return completion(.failure(.providerError("Metal 滤镜管线加载失败")))
        }

        processImage(imagePath: imagePath, outName: "filter") { texture, commandBuffer, encoder in
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(texture, index: 0)
            encoder.setTexture(texture, index: 1)
            var p = SIMD4<Float>(Float(mode), amount, 0, 0)
            encoder.setBytes(&p, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            Self.dispatchGrid(encoder: encoder, pipeline: pipeline, w: texture.width, h: texture.height)
        } completion: { outPath in
            completion(.success(["path": outPath, "filterType": filterType, "gpu": "metal"]))
        }
    }

    // MARK: - 通用卷积

    private func convolve(imagePath: String, kernel: [Float], divisor: Float, bias: Float,
                          completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let pipeline = pipeline(named: "convolve3x3") else {
            return completion(.failure(.providerError("Metal 卷积管线加载失败")))
        }
        processImage(imagePath: imagePath, outName: "conv") { texture, commandBuffer, encoder in
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(texture, index: 0)
            encoder.setTexture(texture, index: 1)
            var kbuf = kernel
            encoder.setBytes(&kbuf, length: MemoryLayout<Float>.size * 9, index: 0)
            var p = SIMD4<Float>(divisor == 0 ? 1 : divisor, bias, 0, 0)
            encoder.setBytes(&p, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
            Self.dispatchGrid(encoder: encoder, pipeline: pipeline, w: texture.width, h: texture.height)
        } completion: { outPath in
            completion(.success(["path": outPath, "divisor": divisor, "bias": bias, "gpu": "metal"]))
        }
    }

    // MARK: - 批量缩放

    private func batchResize(paths: [String], width: Int, height: Int,
                             completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let pipeline = pipeline(named: "resize") else {
            return completion(.failure(.providerError("Metal 缩放管线加载失败")))
        }
        let outDir = Self.metalDir()
        var results: [String: Any] = ["gpu": "metal", "width": width, "height": height]
        var images: [String] = []

        // 每张图独立 command buffer 提交同一队列，GPU 多核流水并行处理
        for (i, path) in paths.enumerated() {
            guard let input = UIImage(contentsOfFile: path),
                  let cg = input.cgImage else {
                results["error_\(i)"] = "无法读取 \(path)"
                continue
            }
            let srcW = cg.width, srcH = cg.height
            guard let srcTex = Self.texture(from: cg, device: device),
                  let dstTex = device?.makeTexture(descriptor: Self.textureDescriptor(width: width, height: height)) else {
                results["error_\(i)"] = "纹理创建失败"
                continue
            }
            guard let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                results["error_\(i)"] = "命令缓冲创建失败"
                continue
            }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(srcTex, index: 0)
            encoder.setTexture(dstTex, index: 1)
            var scale = SIMD2<Float>(Float(srcW) / Float(width), Float(srcH) / Float(height))
            encoder.setBytes(&scale, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
            Self.dispatchGrid(encoder: encoder, pipeline: pipeline, w: width, h: height)
            encoder.endEncoding()
            commandBuffer.commit()

            let outPath = outDir.appendingPathComponent("resize_\(i)_\(UUID().uuidString).jpg")
            if let image = Self.image(from: dstTex, width: width, height: height),
               let jpg = image.jpegData(compressionQuality: 0.85) {
                try? jpg.write(to: outPath)
                images.append(outPath.path)
            } else {
                results["error_\(i)"] = "回读失败"
            }
        }
        results["images"] = images
        results["count"] = images.count
        completion(.success(results))
    }

    // MARK: - 并行归约

    private func reduce(values: [Double], operation: String,
                        completion: @escaping (Result<Any, GatewayError>) -> Void) {
        let count = values.count
        guard count <= 10_000_000 else {
            return completion(.failure(.invalidParams("数组过大（\(count) 元素，上限 1000 万）")))
        }
        guard let device = device,
              let pipeline = pipeline(named: "reduceK") else {
            return completion(.failure(.providerError("Metal 归约管线加载失败")))
        }
        // 归约操作直接编译进 kernel 会重复缓存；这里用 CPU 校验归约语义，GPU 算并行和。
        // 更通用做法：传 op 参数进 kernel（0=sum 1=avg 2=min 3=max）
        let opMode: Int32
        switch operation {
        case "avg": opMode = 1
        case "min": opMode = 2
        case "max": opMode = 3
        default:    opMode = 0
        }

        var floats = values.map { Float($0) }
        let bytes = count * MemoryLayout<Float>.size
        let inBuffer = device.makeBuffer(length: bytes, options: [.storageModeShared])
        guard let inBuffer = inBuffer else {
            return completion(.failure(.providerError("缓冲创建失败")))
        }
        floats.withUnsafeBytes { ptr in
            inBuffer.contents().copyMemory(from: ptr.baseAddress!, byteCount: bytes)
        }

        let tgSize = 1024
        let partialCount = (count + tgSize - 1) / tgSize
        guard let partialBuffer = device.makeBuffer(length: partialCount * MemoryLayout<Float>.size,
                                                    options: [.storageModeShared]) else {
            return completion(.failure(.providerError("归约缓冲创建失败")))
        }

        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return completion(.failure(.providerError("命令缓冲创建失败")))
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inBuffer, offset: 0, index: 0)
        encoder.setBuffer(partialBuffer, offset: 0, index: 1)
        var c32 = UInt32(count)
        encoder.setBytes(&c32, length: MemoryLayout<UInt32>.size, index: 2)
        var mode32 = UInt32(opMode)
        encoder.setBytes(&mode32, length: MemoryLayout<UInt32>.size, index: 3)
        let tg = MTLSize(width: tgSize, height: 1, depth: 1)
        let grid = MTLSize(width: partialCount, height: 1, depth: 1)
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // 归约 partial（≤ ceil(10M/1024) ≈ 9766 个，CPU 亚毫秒完成）
        let partialPtr = partialBuffer.contents().assumingMemoryBound(to: Float.self)
        var result: Double
        switch opMode {
        case 1: // avg
            var s: Double = 0
            for i in 0..<partialCount { s += Double(partialPtr[i]) }
            result = s / Double(count)
        case 2: // min
            var m = Double.greatestFiniteMagnitude
            for i in 0..<partialCount { m = min(m, Double(partialPtr[i])) }
            result = m
        case 3: // max
            var m = -Double.greatestFiniteMagnitude
            for i in 0..<partialCount { m = max(m, Double(partialPtr[i])) }
            result = m
        default: // sum
            var s: Double = 0
            for i in 0..<partialCount { s += Double(partialPtr[i]) }
            result = s
        }
        completion(.success(["operation": operation, "count": count, "result": result, "gpu": "metal"]))
    }

    // MARK: - 平铺矩阵乘法

    private func matMul(a: [[Double]], b: [[Double]],
                        completion: @escaping (Result<Any, GatewayError>) -> Void) {
        let m = a.count
        guard m > 0 else { return completion(.failure(.invalidParams("矩阵 a 为空"))) }
        let k = a[0].count
        guard k > 0, b.count == k else {
            return completion(.failure(.invalidParams("矩阵维度不匹配：a 为 \(m)×\(k)，b 行数必须等于 \(k)")))
        }
        let n = b[0].count
        guard n > 0, m * k * n <= 4_000_000 else {
            return completion(.failure(.invalidParams("矩阵过大（元素数上限 400 万）")))
        }
        guard let device = device,
              let pipeline = pipeline(named: "matMulTiled") else {
            return completion(.failure(.providerError("Metal 矩阵管线加载失败")))
        }

        var fa = [Float](repeating: 0, count: m * k)
        var fb = [Float](repeating: 0, count: k * n)
        for i in 0..<m { for j in 0..<k { fa[i * k + j] = Float(a[i][j]) } }
        for i in 0..<k { for j in 0..<n { fb[i * n + j] = Float(b[i][j]) } }

        guard let aBuf = device.makeBuffer(bytes: fa, length: m * k * MemoryLayout<Float>.size,
                                           options: [.storageModeShared]),
              let bBuf = device.makeBuffer(bytes: fb, length: k * n * MemoryLayout<Float>.size,
                                           options: [.storageModeShared]),
              let cBuf = device.makeBuffer(length: m * n * MemoryLayout<Float>.size,
                                           options: [.storageModeShared]) else {
            return completion(.failure(.providerError("矩阵缓冲创建失败")))
        }

        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return completion(.failure(.providerError("命令缓冲创建失败")))
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(aBuf, offset: 0, index: 0)
        encoder.setBuffer(bBuf, offset: 0, index: 1)
        encoder.setBuffer(cBuf, offset: 0, index: 2)
        var dims = SIMD3<UInt32>(UInt32(m), UInt32(k), UInt32(n))
        encoder.setBytes(&dims, length: MemoryLayout<SIMD3<UInt32>>.size, index: 3)

        let ts = 16
        let tg = MTLSize(width: ts, height: ts, depth: 1)
        let grid = MTLSize(width: (n + ts - 1) / ts, height: (m + ts - 1) / ts, depth: 1)
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let cPtr = cBuf.contents().assumingMemoryBound(to: Float.self)
        var data = [Double](repeating: 0, count: m * n)
        for i in 0..<m { for j in 0..<n { data[i * n + j] = Double(cPtr[i * n + j]) } }
        completion(.success(["rows": m, "cols": n, "data": data, "gpu": "metal"]))
    }

    // MARK: - Mandelbrot 分形（走缓存管线）

    private func renderMandelbrot(completion: @escaping (Result<Any, GatewayError>) -> Void) {
        let width = 1024, height = 1024
        guard let device = device,
              let pipeline = pipeline(named: "fractal") else {
            return completion(.failure(.providerError("Metal 分形管线加载失败")))
        }
        guard let outTexture = device.makeTexture(descriptor: Self.textureDescriptor(width: width, height: height)),
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return completion(.failure(.providerError("分形纹理/命令缓冲创建失败")))
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(outTexture, index: 0)
        Self.dispatchGrid(encoder: encoder, pipeline: pipeline, w: width, h: height)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard let image = Self.image(from: outTexture, width: width, height: height) else {
            return completion(.failure(.providerError("分形回读失败")))
        }
        let outPath = Self.metalDir().appendingPathComponent("fractal_\(UUID().uuidString).jpg")
        try? image.jpegData(compressionQuality: 0.9)?.write(to: outPath)
        completion(.success(["path": outPath.path, "width": width, "height": height, "gpu": "metal"]))
    }

    // MARK: - 图像管线工具

    /// 读图→纹理→执行 kernel→回读→写 JPEG 的统一管线
    private func processImage(imagePath: String, outName: String,
                              encode: (MTLTexture, MTLCommandBuffer, MTLComputeCommandEncoder) -> Void,
                              completion: @escaping (String) -> Void) {
        guard let input = UIImage(contentsOfFile: imagePath),
              let cg = input.cgImage,
              let device = device else {
            return completion("")
        }
        let w = cg.width, h = cg.height
        guard let srcTex = Self.texture(from: cg, device: device),
              let dstTex = device.makeTexture(descriptor: Self.textureDescriptor(width: w, height: h)),
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return completion("")
        }
        encode(srcTex, commandBuffer, encoder)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard let image = Self.image(from: dstTex, width: w, height: h),
              let jpg = image.jpegData(compressionQuality: 0.9) else { return completion("") }
        let outPath = Self.metalDir().appendingPathComponent("\(outName)_\(UUID().uuidString).jpg")
        try? jpg.write(to: outPath)
        completion(outPath.path)
    }

    /// 统一调度：每像素一线程，GPU 多核并行
    private static func dispatchGrid(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState,
                                     w: Int, h: Int) {
        let tw = pipeline.threadExecutionWidth
        let th = min(pipeline.maxTotalThreadsPerThreadgroup / tw, 32)
        let tg = MTLSize(width: tw, height: th, depth: 1)
        let grid = MTLSize(width: w, height: h, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: tg)
    }

    private static func textureDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                         width: width, height: height,
                                                         mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        return d
    }

    /// CGImage → MTLTexture（逐行拷贝，CPU 只在边缘做一次，像素计算全在 GPU）
    private static func texture(from cg: CGImage, device: MTLDevice?) -> MTLTexture? {
        guard let device = device else { return nil }
        let w = cg.width, h = cg.height
        let bytesPerRow = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let tex = device.makeTexture(descriptor: textureDescriptor(width: w, height: h))
        tex?.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                     withBytes: pixels, bytesPerRow: bytesPerRow)
        return tex
    }

    /// MTLTexture → UIImage
    private static func image(from tex: MTLTexture, width: Int, height: Int) -> UIImage? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        tex.getBytes(&pixels, bytesPerRow: bytesPerRow,
                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let ctx = CGContext(data: &pixels, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func metalDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MetalRender", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Shader 源码（全部 compute kernel）

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // ---- 逐像素滤镜：0=gray 1=invert 2=sepia 3=threshold 4=brightness ----
    kernel void pixelFilter(texture2d<float, access::read> inTex [[texture(0)]],
                            texture2d<float, access::write> outTex [[texture(1)]],
                            constant float4 &params [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
        float4 c = inTex.read(gid);
        int mode = int(params.x);
        float amount = params.y;
        float3 out;
        switch (mode) {
            case 0: {
                float g = dot(c.rgb, float3(0.299, 0.587, 0.114));
                out = float3(g);
                break;
            }
            case 1: {
                out = 1.0 - c.rgb;
                break;
            }
            case 2: {
                out = float3(dot(c.rgb, float3(0.393, 0.769, 0.189)),
                             dot(c.rgb, float3(0.349, 0.686, 0.168)),
                             dot(c.rgb, float3(0.272, 0.534, 0.131)));
                break;
            }
            case 3: {
                float g = dot(c.rgb, float3(0.299, 0.587, 0.114));
                out = float3(g > amount ? 1.0 : 0.0);
                break;
            }
            case 4: {
                out = c.rgb * amount;
                break;
            }
            default: out = c.rgb;
        }
        outTex.write(float4(out, c.a), gid);
    }

    // ---- 3×3 卷积：权重由 CPU 传入，divisor 归一化，bias 偏移 ----
    kernel void convolve3x3(texture2d<float, access::read> inTex [[texture(0)]],
                            texture2d<float, access::write> outTex [[texture(1)]],
                            constant float *kernel [[buffer(0)]],
                            constant float4 &params [[buffer(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
        int w = outTex.get_width();
        int h = outTex.get_height();
        float4 acc(0.0);
        for (int ky = -1; ky <= 1; ky++) {
            for (int kx = -1; kx <= 1; kx++) {
                int x = clamp(int(gid.x) + kx, 0, w - 1);
                int y = clamp(int(gid.y) + ky, 0, h - 1);
                acc += inTex.read(uint2(x, y)) * kernel[(ky + 1) * 3 + (kx + 1)];
            }
        }
        float4 out = acc / (params.x == 0.0 ? 1.0 : params.x) + params.y;
        outTex.write(float4(clamp(out.rgb, 0.0, 1.0), 1.0), gid);
    }

    // ---- 双线性缩放 ----
    kernel void resize(texture2d<float, access::read> inTex [[texture(0)]],
                       texture2d<float, access::write> outTex [[texture(1)]],
                       constant float2 &scale [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
        float2 uv = (float2(gid) + 0.5) * scale;
        int x0 = int(uv.x), y0 = int(uv.y);
        float fx = uv.x - float(x0), fy = uv.y - float(y0);
        x0 = min(x0, int(inTex.get_width()) - 1);
        y0 = min(y0, int(inTex.get_height()) - 1);
        int x1 = min(x0 + 1, int(inTex.get_width()) - 1);
        int y1 = min(y0 + 1, int(inTex.get_height()) - 1);
        float4 tl = inTex.read(uint2(x0, y0));
        float4 tr = inTex.read(uint2(x1, y0));
        float4 bl = inTex.read(uint2(x0, y1));
        float4 br = inTex.read(uint2(x1, y1));
        float4 top = mix(tl, tr, fx);
        float4 bot = mix(bl, br, fx);
        outTex.write(mix(top, bot, fy), gid);
    }

    // ---- 并行归约：每 1024 元素一组，threadgroup 内树状归约到 partial ----
    kernel void reduceK(device const float *in [[buffer(0)]],
                        device float *partial [[buffer(1)]],
                        constant uint &count [[buffer(2)]],
                        constant uint &mode [[buffer(3)]],
                        uint3 tgid [[threadgroup_position_in_grid]],
                        uint3 tid [[thread_position_in_threadgroup]]) {
        threadgroup float acc[1024];
        uint i = tgid.x * 1024 + tid.x;
        acc[tid.x] = (i < count) ? in[i] : (mode == 2 ? 3.40282e+38 : 0.0);
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint s = 512; s > 0; s >>= 1) {
            if (tid.x < s) {
                if (mode == 2) { acc[tid.x] = min(acc[tid.x], acc[tid.x + s]); }
                else if (mode == 3) { acc[tid.x] = max(acc[tid.x], acc[tid.x + s]); }
                else { acc[tid.x] += acc[tid.x + s]; }
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        if (tid.x == 0) partial[tgid.x] = acc[0];
    }

    // ---- 平铺矩阵乘：16×16 tile，多核并行 ----
    kernel void matMulTiled(device const float *A [[buffer(0)]],
                            device const float *B [[buffer(1)]],
                            device float *C [[buffer(2)]],
                            constant uint3 &dims [[buffer(3)]],
                            uint2 gid [[thread_position_in_threadgroup]],
                            uint2 tgid [[threadgroup_position_in_grid]]) {
        const uint TS = 16;
        threadgroup float As[16][16];
        threadgroup float Bs[16][16];
        uint M = dims.x, K = dims.y, N = dims.z;
        uint row = tgid.x * TS + gid.x;
        uint col = tgid.y * TS + gid.y;
        float acc = 0.0;
        for (uint k = 0; k < K; k += TS) {
            As[gid.y][gid.x] = (row < M && k + gid.x < K) ? A[row * K + k + gid.x] : 0.0;
            Bs[gid.y][gid.x] = (k + gid.y < K && col < N) ? B[(k + gid.y) * N + col] : 0.0;
            threadgroup_barrier(mem_flags::mem_threadgroup);
            for (uint i = 0; i < TS; i++) acc += As[gid.y][i] * Bs[i][gid.x];
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        if (row < M && col < N) C[row * N + col] = acc;
    }

    // ---- Mandelbrot 分形 ----
    kernel void fractal(texture2d<float, access::write> outTexture [[texture(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;
        float x0 = (float(gid.x) / outTexture.get_width()) * 3.5 - 2.5;
        float y0 = (float(gid.y) / outTexture.get_height()) * 2.0 - 1.0;
        float x = 0.0, y = 0.0;
        int iteration = 0;
        int max_iteration = 300;
        while (x*x + y*y <= 4.0 && iteration < max_iteration) {
            float xtemp = x*x - y*y + x0;
            y = 2*x*y + y0;
            x = xtemp;
            iteration = iteration + 1;
        }
        float4 color = float4(0.0, 0.0, 0.0, 1.0);
        if (iteration < max_iteration) {
            float log_zn = log(x*x + y*y) / 2.0;
            float nu = log(log_zn / log(2.0)) / log(2.0);
            float i = float(iteration) + 1.0 - nu;
            color = float4(0.5 + 0.5 * cos(3.0 + i * 0.15),
                           0.5 + 0.5 * cos(3.0 + i * 0.15 + 2.0),
                           0.5 + 0.5 * cos(3.0 + i * 0.15 + 4.0),
                           1.0);
        }
        outTexture.write(color, gid);
    }
    """
}
