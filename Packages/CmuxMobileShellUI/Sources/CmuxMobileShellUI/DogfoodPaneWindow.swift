#if os(iOS) && DEBUG
import CmuxMobileShell
import UIKit

/// The dedicated `UIWindow` that hosts the floating DEV dogfood pane above the
/// app's scene, so the pill/overlay floats over the terminal regardless of the
/// SwiftUI view tree.
///
/// It is a passthrough window: a touch outside the pane's interactive region
/// returns `nil` from `hitTest` so it falls through to the app window
/// underneath. Only the pane's visible control (the bug pill when collapsed, the
/// card when expanded) is hittable. Without this, a full-screen overlay window
/// would eat every terminal touch.
///
/// The interactive region is taken from ``DogfoodFeedbackModel/interactiveFrame``
/// (which the overlay publishes), NOT from walking the view tree: SwiftUI hosts
/// the pill's tap + drag on the single hosting view, so a hit on the pill and a
/// hit on empty space both resolve to that one view. Comparing against the root
/// view (the previous approach) therefore could only ever eat all touches or
/// kill the pill's gestures. A positive frame test is the only correct
/// discriminator.
///
/// DEBUG-only; absent in release builds.
final class DogfoodPaneWindow: UIWindow {
    /// The pane model whose ``DogfoodFeedbackModel/interactiveFrame`` defines the
    /// hittable region. Held weak: the model is owned by the app composition root.
    weak var model: DogfoodFeedbackModel?

    /// Hit-tests so only the pane's published interactive region is interactive;
    /// everything else passes through to the window below.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Before the overlay reports a frame (`.zero`), treat the whole window as
        // passthrough so the terminal is never blocked while the pane initializes.
        guard let frame = model?.interactiveFrame, !frame.isEmpty else { return nil }
        guard frame.contains(point) else { return nil }
        // Inside the pane region: return the real hit so SwiftUI's gestures (tap
        // to expand, drag to reposition) and the expanded card's controls receive
        // the touch.
        return super.hitTest(point, with: event)
    }
}
#endif
