# GPU 多核并行算力 metal（L0）

## 是什么

直接调用设备的 Metal GPU，每个像素/元素分配一个线程，由 GPU **多核并行**执行计算。
适合图像批量处理、大数组归约、矩阵乘法、复杂渲染——CPU 逐像素处理这些会慢几十倍。

全部 shader 进程内只编译一次（pipeline 缓存），后续调用零编译开销。

## 6 个算子

| API | 参数 | 返回 | 说明 |
|---|---|---|---|
| `wx.applyMetalFilter` | `{imagePath, filterType, amount?}` | `{path, filterType}` | 逐像素滤镜 |
| `wx.convolveMetalImage` | `{imagePath, kernel:[9], divisor?, bias?}` | `{path, divisor, bias}` | 通用 3×3 卷积 |
| `wx.batchResizeMetalImages` | `{paths:[], width, height}` | `{images:[], count}` | 批量双线性缩放 |
| `wx.gpuReduce` | `{values:[], operation}` | `{operation, count, result}` | 并行归约 |
| `wx.gpuMatMul` | `{a:[[..]], b:[[..]]}` | `{rows, cols, data}` | 平铺矩阵乘 |
| `wx.renderMetalFractal` | `{}` | `{path, width, height}` | Mandelbrot 分形 |

## 滤镜类型

- `gray`：灰度
- `invert`：反色
- `sepia`：复古
- `threshold`：二值化（`amount` 为阈值，默认 0.5）
- `brightness`：亮度（`amount` 为倍率，默认 0.5）

## 卷积 kernel 示例

```js
// 锐化
wx.convolveMetalImage({
  imagePath: '/path/to/img.jpg',
  kernel: [0, -1, 0, -1, 5, -1, 0, -1, 0]
});

// 高斯模糊（3×3）
wx.convolveMetalImage({
  imagePath: p,
  kernel: [1, 2, 1, 2, 4, 2, 1, 2, 1],
  divisor: 16
});

// Sobel 边缘
wx.convolveMetalImage({
  imagePath: p,
  kernel: [-1, 0, 1, -2, 0, 2, -1, 0, 1],
  divisor: 1,
  bias: 0.5
});
```

## 批量缩放

```js
const r = await wx.batchResizeMetalImages({
  paths: ['a.jpg', 'b.jpg', 'c.jpg'],
  width: 256,
  height: 256
});
// r.images: 缩放后的本地路径数组（≤4096 边长）
```

## 归约

```js
await wx.gpuReduce({ values: [1, 2, 3, ..., 1000000], operation: 'sum' });
// operation: sum / avg / min / max；上限 1000 万元素
```

## 矩阵乘

```js
await wx.gpuMatMul({ a: [[1,2],[3,4]], b: [[5,6],[7,8]] });
// → { rows: 2, cols: 2, data: [19, 22, 43, 50] }（行主序展开）
// 上限：M×K×N ≤ 400 万元素
```

## 性能要点

- **多核并行**：所有 kernel 按线程组并行调度，图像越大/数组越大并行收益越明显
- **零重编译**：shader 与 pipeline 进程内缓存
- **批量流水**：批量缩放每张图独立 command buffer，GPU 队列流水并行
- **限制**：图片 ≤4096 边长、数组 ≤1000 万、矩阵 ≤400 万元素，防内存爆炸
