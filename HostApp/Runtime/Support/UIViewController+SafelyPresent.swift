import UIKit

extension UIViewController {
    /// iPad 上 present popover 风格控制器必须指定 sourceView/sourceRect，
    /// 否则 UIPopoverPresentationController 在呈现动画中抛 NSException 导致崩溃。
    /// 该异常发生在 runloop afterCACommit 阶段，ObjC @try/@catch 无法捕获，只能预先配置。
    func presentSafely(_ vc: UIViewController,
                       animated: Bool = true,
                       completion: (() -> Void)? = nil) {
        if let pop = vc.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX,
                                    y: view.bounds.midY,
                                    width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(vc, animated: animated, completion: completion)
    }
}
