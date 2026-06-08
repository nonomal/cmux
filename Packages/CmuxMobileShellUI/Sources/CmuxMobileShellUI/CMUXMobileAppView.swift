import CmuxMobileShell
import SwiftUI
#if os(iOS)
@preconcurrency import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct CMUXMobileAppView: View {
    @State private var store: CMUXMobileShellStore
    #if os(iOS) && DEBUG
    /// The floating DEV dogfood pane model, built once next to the store and
    /// wired into it so the dedicated `dogfood.checklist` subscription feeds it.
    /// DEBUG-only; absent in release builds.
    @State private var dogfoodFeedbackModel: DogfoodFeedbackModel
    #endif

    public init(store: CMUXMobileShellStore = .preview()) {
        _store = State(initialValue: store)
        #if os(iOS) && DEBUG
        let model = DogfoodFeedbackModel(submitter: DogfoodFeedbackUISubmitter(store: store))
        store.setDogfoodFeedbackModel(model)
        _dogfoodFeedbackModel = State(initialValue: model)
        #endif
    }

    public var body: some View {
        CMUXMobileRootView(store: store)
            #if os(iOS) && DEBUG
            // Host the floating dogfood pane as a normal in-hierarchy overlay so
            // SwiftUI's native hit-testing delivers BOTH the pill's tap and drag.
            // The previous passthrough `UIWindow` owned its own `hitTest`, which
            // repeatedly returned `nil` on the pill's own touches and killed the
            // gestures. An `.overlay` whose only hittable content is the pill/card
            // (everything else is `Color.clear` with hit-testing off) lets the app
            // beneath receive every other touch with no custom window. It sits
            // below SwiftUI `.sheet`s (the pairing + feedback sheets), which is an
            // acceptable trade for a DEV pane.
            .overlay {
                DogfoodPaneOverlayView(model: dogfoodFeedbackModel)
            }
            #endif
    }
}
