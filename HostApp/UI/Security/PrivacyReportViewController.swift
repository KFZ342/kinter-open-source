import UIKit
import SwiftUI
import Charts

/// App 隐私记录页（UIKit 外壳 + SwiftUI 内容）。
final class PrivacyReportViewController: UIViewController {
    private let sessionId: String?

    init(sessionId: String? = nil) {
        self.sessionId = sessionId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "App 隐私记录"
        view.backgroundColor = .systemGroupedBackground

        let entries: [TraceEntry]
        if let sid = sessionId {
            entries = TraceRecorder.shared.entries(sessionId: sid)
        } else {
            entries = TraceRecorder.shared.allSessionIds()
                .flatMap { TraceRecorder.shared.entries(sessionId: $0) }
        }

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
