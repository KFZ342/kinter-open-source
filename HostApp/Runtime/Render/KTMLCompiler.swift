import Foundation

/// KTML 编译器。
/// 编译期只做两件事：提取 `<script>` 块、把模板原样保留到 `<template>`。
/// 真正的数据绑定在运行时完成：用户脚本执行后，bootstrap 收集数据并调用 KTML.renderInto 渲染模板。
final class KTMLCompiler {
    static let shared = KTMLCompiler()
    private init() {}

    enum CompileError: LocalizedError {
        case scriptMissing
        case compileFailed(String)

        var errorDescription: String? {
            switch self {
            case .scriptMissing:        return "ktml.js 未打包进 Bundle"
            case .compileFailed(let s): return "编译失败: \(s)"
            }
        }
    }

    /// 编译 .ktml 源码为完整 HTML 文档。
    func compile(source: String, baseURL: URL) throws -> String {
        // 运行时依赖 ktml.js，先确认它被打了进去
        guard Bundle.main.url(forResource: "ktml", withExtension: "js") != nil else {
            throw CompileError.scriptMissing
        }
        let (template, scripts) = extractScripts(source)
        return wrapDocument(template: template, userScripts: scripts)
    }

    // MARK: - 提取脚本

    /// 从源码里提取所有 <script>...</script> 块，返回（去掉脚本的模板, 脚本内容数组）。
    private func extractScripts(_ source: String) -> (String, [String]) {
        let pattern = "<script[^>]*>([\\s\\S]*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (source, [])
        }

        var template = source
        var scripts: [String] = []
        let range = NSRange(source.startIndex..., in: source)
        let matches = regex.matches(in: source, options: [], range: range)

        // 从后往前删，避免索引偏移
        for m in matches.reversed() {
            guard let fullRange = Range(m.range, in: template) else { continue }
            if let contentRange = Range(m.range(at: 1), in: template) {
                scripts.insert(String(template[contentRange]), at: 0)
            }
            template.removeSubrange(fullRange)
        }

        return (template, scripts)
    }

    // MARK: - 组装文档

    private func wrapDocument(template: String, userScripts: [String]) -> String {
        let userCode = userScripts.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
          <style>
            * { box-sizing: border-box; }
            html, body { margin: 0; padding: 0; }
            body { font-family: -apple-system, "SF Pro Text", sans-serif; -webkit-text-size-adjust: 100%; }
            @media (prefers-color-scheme: dark) {
              body { color: #f2f2f7; background: #000; }
            }
          </style>
        </head>
        <body>
        <div id="ktml-root"></div>
        <template id="ktml-template">\(template)</template>
        <script>window.__ktmlBefore = Object.keys(window);</script>
        <script>
        \(userCode)
        </script>
        <script>
        (function(){
          try {
            var tplEl = document.getElementById('ktml-template');
            var tpl = tplEl ? tplEl.innerHTML : '';
            var before = new Set(window.__ktmlBefore || []);
            var data = {};
            Object.keys(window).forEach(function(k){
              if (!before.has(k) && k.indexOf('__') !== 0) {
                data[k] = window[k];
              }
            });
            var root = document.getElementById('ktml-root');
            if (window.KTML && window.KTML.renderInto) {
              window.KTML.renderInto(root, tpl, data);
            } else {
              root.innerHTML = '<div style="padding:20px;color:#c00">KTML 运行时未加载</div>';
            }
          } catch (e) {
            var r = document.getElementById('ktml-root');
            if (r) r.innerHTML = '<div style="padding:20px;color:#c00">渲染失败: ' + (e && e.message ? e.message : e) + '</div>';
          }
        })();
        </script>
        </body>
        </html>
        """
    }
}
