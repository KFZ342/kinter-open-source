import UIKit
import WebKit

/// 使用国内极速 CDN 的顶级 Markdown 渲染器（GitHub 风格 + Highlight.js）
final class MarkdownRenderView: UIView, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var heightConstraint: NSLayoutConstraint!
    private var isLoaded = false
    private var pendingMarkdown: String?
    private var isDark = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "sizeChanged")
        config.userContentController = userContentController
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        
        heightConstraint = webView.heightAnchor.constraint(equalToConstant: 20)
        heightConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightConstraint
        ])
    }

    func update(markdown: String, isDark: Bool) {
        let themeChanged = self.isDark != isDark
        self.isDark = isDark
        
        if !isLoaded || themeChanged {
            pendingMarkdown = markdown
            loadBaseHTML(isDark: isDark)
        } else {
            injectContent(markdown)
        }
    }

    private func loadBaseHTML(isDark: Bool) {
        let colorMode = isDark ? "dark" : "light"
        let textColor = isDark ? "#f2f2f7" : "#1c1c1e"

        // 使用国内极速 CDN: staticfile.org
        let html = """
        <!DOCTYPE html>
        <html data-color-mode="\(colorMode)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        
        <!-- GitHub Markdown CSS -->
        <link rel="stylesheet" href="https://cdn.staticfile.org/github-markdown-css/5.2.0/github-markdown.min.css">
        <!-- Highlight.js 样式 -->
        <link rel="stylesheet" href="https://cdn.staticfile.org/highlight.js/11.9.0/styles/github\(isDark ? "-dark" : "").min.css">
        
        <style>
            html, body {
                background-color: transparent !important;
                margin: 0;
                padding: 0;
                color: \(textColor) !important;
            }
            .markdown-body {
                background-color: transparent !important;
                color: inherit !important;
                font-family: -apple-system, "SF Pro Text", sans-serif !important;
                font-size: 15px !important;
                padding: 0 !important;
                box-sizing: border-box;
            }
            /* 修复代码块字体 */
            .markdown-body pre, .markdown-body code {
                font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace !important;
            }
            /* 精细排版调整 */
            .markdown-body p, .markdown-body ul, .markdown-body ol {
                margin-bottom: 10px !important;
                font-size: 15px !important;
                line-height: 1.6 !important;
                word-wrap: break-word !important;
                overflow-wrap: break-word !important;
                white-space: normal !important;
            }
            .markdown-body p:last-child, .markdown-body ul:last-child {
                margin-bottom: 0 !important;
            }
            /* 修复列表的悬挂缩进 */
            .markdown-body ul, .markdown-body ol {
                padding-left: 24px !important;
                margin-left: 0 !important;
            }
            .markdown-body li {
                margin-bottom: 4px !important;
                word-wrap: break-word !important;
            }
            .markdown-body li > p {
                margin-bottom: 4px !important;
            }
            /* 防止代码块/长单词撑破容器 */
            .markdown-body * {
                max-width: 100% !important;
                box-sizing: border-box !important;
            }
            .markdown-body pre {
                white-space: pre-wrap !important;
                word-wrap: break-word !important;
            }
            /* 表格横向滚动 */
            .markdown-body table {
                display: block;
                width: max-content;
                max-width: 100%;
                overflow: auto;
            }
            ::-webkit-scrollbar { display: none; }
        </style>
        
        <script src="https://cdn.staticfile.org/marked/11.1.1/marked.min.js"></script>
        <script src="https://cdn.staticfile.org/highlight.js/11.9.0/highlight.min.js"></script>
        </head>
        <body>
        <article class="markdown-body" id="content"></article>
        <script>
        marked.setOptions({
            highlight: function (code, lang) {
                if (lang && hljs.getLanguage(lang)) {
                    try { return hljs.highlight(code, { language: lang }).value; } catch (e) {}
                }
                return hljs.highlightAuto(code).value;
            },
            breaks: true
        });
        
        function render(md) {
            document.getElementById('content').innerHTML = marked.parse(md);
            // 通知 Swift 更新高度
            window.webkit.messageHandlers.sizeChanged.postMessage(document.body.scrollHeight);
        }
        </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func injectContent(_ markdown: String) {
        let escaped = markdown.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        let js = "render(`\(escaped)`);"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        if let pending = pendingMarkdown {
            injectContent(pending)
            pendingMarkdown = nil
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "sizeChanged", let height = message.body as? CGFloat {
            DispatchQueue.main.async {
                // 加一点余量防止截断
                let finalHeight = max(20, height + 2)
                if self.heightConstraint.constant != finalHeight {
                    self.heightConstraint.constant = finalHeight
                }
            }
        }
    }
}
