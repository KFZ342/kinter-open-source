import UIKit
import SwiftUI
import Charts

/// App 隐私记录页（UIKit 外壳 + SwiftUI 内容）。
/// 记录解析放到后台队列：20 个会话文件、每个上限 2MB，放主线程会把页面卡住。
final class PrivacyReportViewController: UIViewController {
    private let sessionId: String?
    /// 图表只画最近这么多条，避免历史很长时一次性塞给 Charts
    private static let maxEntries = 5000

    init(sessionId: String? = nil) {
        self.sessionId = sessionId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "App 隐私记录"
        view.backgroundColor = .systemGroupedBackground

        let loading = makeLoadingView()
        view.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        let sid = sessionId
        DispatchQueue.global(qos: .userInitiated).async {
            let entries: [TraceEntry]
            if let sid = sid {
                entries = TraceRecorder.shared.entries(sessionId: sid)
            } else {
                entries = TraceRecorder.shared.allSessionIds()
                    .flatMap { TraceRecorder.shared.entries(sessionId: $0) }
            }
            let capped = entries.count > Self.maxEntries
                ? Array(entries.suffix(Self.maxEntries))
                : entries
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                loading.removeFromSuperview()
                self.embed(entries: capped)
            }
        }
    }

    private func makeLoadingView() -> UIView {
        let box = UIView()
        box.translatesAutoresizingMaskIntoConstraints = false
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = "正在读取记录…"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(spinner)
        box.addSubview(label)
        NSLayoutConstraint.activate([
            spinner.topAnchor.constraint(equalTo: box.topAnchor),
            spinner.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor)
        ])
        return box
    }

    private func embed(entries: [TraceEntry]) {
        let host = UIHostingController(rootView: PrivacyReportView(entries: entries))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}
