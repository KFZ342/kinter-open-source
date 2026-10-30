import Foundation
import Metal
import UIKit

/// 原生 Metal GPU 算力 Provider
final class MetalProvider: CapabilityProvider, AppContextInjectable {
    static var capability: String { "metal" }
    static var level: CapabilityLevel { .l0 }
    
    var appId: String?
    private let device = MTLCreateSystemDefaultDevice()
    
    init() {}
    
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
            applyMetalFilter(imagePath: imagePath, filterType: filterType, completion: completion)
            
        case "renderFractal":
            renderMandelbrot(device: device, completion: completion)
            
        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }
    
    // MARK: - 复杂图形渲染 (Mandelbrot 分形)
    private func renderMandelbrot(device: MTLDevice, completion: @escaping (Result<Any, GatewayError>) -> Void) {
        let width = 1024
        let height = 1024
        
        // 纯 GPU 片元着色器，计算复杂的数学分形
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        kernel void fractal(texture2d<float, access::write> outTexture [[texture(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;
            
            // 映射坐标到复平面
            float x0 = (float(gid.x) / outTexture.get_width()) * 3.5 - 2.5;
            float y0 = (float(gid.y) / outTexture.get_height()) * 2.0 - 1.0;
            float x = 0.0;
            float y = 0.0;
            int iteration = 0;
            int max_iteration = 300;
            
            // 迭代计算逃逸时间
            while (x*x + y*y <= 4.0 && iteration < max_iteration) {
                float xtemp = x*x - y*y + x0;
                y = 2*x*y + y0;
                x = xtemp;
                iteration = iteration + 1;
            }
            
            // 根据迭代次数计算酷炫的颜色
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
        
        do {
            NSLog("[Metal] 开始编译着色器...")
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            NSLog("[Metal] 着色器编译成功")
            guard let function = library.makeFunction(name: "fractal") else {
                return completion(.failure(.providerError("无法加载 Metal 函数")))
            }
            let pipeline = try device.makeComputePipelineState(function: function)
            NSLog("[Metal] 管线创建成功")
            let commandQueue = device.makeCommandQueue()
            let commandBuffer = commandQueue?.makeCommandBuffer()
            let encoder = commandBuffer?.makeComputeCommandEncoder()
            
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                     width: width,
                                                                     height: height,
                                                                     mipmapped: false)
            descriptor.usage = [.shaderWrite, .shaderRead]
            NSLog("[Metal] 创建纹理...")
            guard let outTexture = device.makeTexture(descriptor: descriptor) else {
                return completion(.failure(.providerError("无法创建纹理")))
            }
            
            encoder?.setComputePipelineState(pipeline)
            encoder?.setTexture(outTexture, index: 0)
            
            let w = pipeline.threadExecutionWidth
            let h = pipeline.maxTotalThreadsPerThreadgroup / w
            let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
            let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
            
            encoder?.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            encoder?.endEncoding()
            commandBuffer?.commit()
            commandBuffer?.waitUntilCompleted()
            NSLog("[Metal] GPU 执行完成")
            
            // 读取渲染结果
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            var rawBytes = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
            outTexture.getBytes(&rawBytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            
            let outCGImage = rawBytes.withUnsafeBytes { ptr -> CGImage? in
                guard let baseAddress = ptr.baseAddress else { return nil }
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let context = CGContext(data: UnsafeMutableRawPointer(mutating: baseAddress), width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                return context?.makeImage()
            }
            
            guard let finalCG = outCGImage else { return completion(.failure(.providerError("生成图片失败"))) }
            let finalImage = UIImage(cgImage: finalCG)
            
            let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("MetalRender")
            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let outPath = outDir.appendingPathComponent("fractal_\(UUID().uuidString).jpg")
            try finalImage.jpegData(compressionQuality: 0.9)?.write(to: outPath)
            
            DispatchQueue.main.async {
                completion(.success(["path": outPath.path, "width": width, "height": height]))
            }
        } catch {
            NSLog("[Metal] 报错: \(error.localizedDescription)")
            completion(.failure(.providerError("Metal 执行出错: \(error.localizedDescription)")))
        }
    }

    // MARK: - 图像处理（保留之前的逻辑，省略细节...）
    private func applyMetalFilter(imagePath: String, filterType: String, completion: @escaping (Result<Any, GatewayError>) -> Void) {
        // 略（保持之前的灰度处理代码）
        completion(.failure(.providerError("代码保留")))
    }
}
