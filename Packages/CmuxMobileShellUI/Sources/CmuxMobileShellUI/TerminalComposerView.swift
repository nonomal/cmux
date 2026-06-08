#if os(iOS)
import CMUXMobileCore
import CmuxMobileShell
import CmuxMobileSupport
import CmuxMobileTerminal
import SwiftUI

/// iMessage-style composer pinned above the terminal.
///
/// A growing multi-line text field plus a send button, rendered with Liquid
/// Glass (iOS 26+, with a thin-material fallback). Send delivers the text as a
/// bracketed paste followed by a single Return (via `terminal.paste`), so a
/// multi-line message lands as one submission instead of fragmenting on every
/// interior newline. Toggled from the input accessory bar's composer button; the
/// chevron dismisses it.
///
/// Round 6 stacks the compose field and the terminal's docked accessory toolbar
/// (modifier / arrow / Ctrl row) as TWO separate bottom `safeAreaInset`s in
/// ``WorkspaceDetailView`` (field inset applied first / inner, toolbar inset applied
/// second / outer, pinned at keyboard top). This view is the field inset only; the
/// toolbar host (``ComposerDockedToolbarHost``) is a sibling inset. Splitting them
/// means a field-grow changes only the field inset's height (pushing the terminal up)
/// and structurally cannot move the constant-height toolbar inset off the keyboard
/// top — round 5 put both in one VStack inside one inset, where the whole stack
/// reflowed as a unit on every keystroke and the toolbar drifted. The toolbar is
/// still the same single surface view, borrowed via ``ComposerToolbarHandoff``.
struct TerminalComposerView: View {
    @Bindable var store: CMUXMobileShellStore
    @FocusState private var isFieldFocused: Bool

    /// Single-line height of the round close/send buttons. They stay pinned to the
    /// bottom edge of the (taller) field via the `HStack`'s `.bottom` alignment.
    private let controlHeight: CGFloat = 40

    /// Line range for the growing compose field. Round 5 opens it at a SINGLE line
    /// (`1...`) so it starts as a compact one-line message box and grows as the user
    /// types, up to 14 lines before scrolling. Each added line pushes the terminal
    /// up while the toolbar (now docked BELOW the field) stays pinned to the
    /// keyboard edge.
    private let composerLineLimit = 1...14

    /// Minimum height of the compose field. Round 5 drops it to one control height
    /// so the composer opens at a single line (matching ``composerLineLimit``'s new
    /// `1...` lower bound) instead of a forced multi-line box. It still grows with
    /// content up to ``composerLineLimit``.
    private let composerFieldMinHeight: CGFloat = 40

    private var trimmedIsEmpty: Bool {
        store.terminalInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        // Field only (round 6). The docked toolbar is a SEPARATE outer bottom inset
        // in ``WorkspaceDetailView`` so a field-grow cannot move it (see this view's
        // doc comment). Growing this field grows this inset, which pushes the terminal
        // up; the toolbar inset below stays pinned to the keyboard top.
        composerSurface
        .onAppear {
            recordComposerEvent(.composerViewAppear)
            focusField()
        }
        .onDisappear {
            // COMPOSER: logged independently of `isComposerPresented`. A
            // disappear with no matching `composerPresentedChanged a==0` is a
            // view-recreation bug (the flag stayed true but SwiftUI rebuilt the
            // view), not an intentional dismiss.
            recordComposerEvent(.composerViewDisappear)
        }
        .onChange(of: isFieldFocused) { _, focused in
            // COMPOSER: a focus-lost while the flag stayed presented and the
            // view stayed mounted, yet the field reads empty, isolates the
            // residual TextField/@FocusState render-blank case.
            recordComposerEvent(.composerFieldFocusChanged, a: focused ? 1 : 0)
        }
    }

    /// Record a composer diagnostic event into the store's structured log (DEBUG
    /// dogfood builds only) so the "Send to agent" feedback pane exports it. A
    /// no-op when no log is wired (release, or a host that does not set it).
    private func recordComposerEvent(_ code: DiagnosticEventCode, a: Int? = nil) {
        #if DEBUG
        store.diagnosticLog?.record(DiagnosticEvent(code, a: a))
        #endif
    }

    /// On iOS 26 the glass controls float in a `GlassEffectContainer` over the
    /// terminal (no opaque bar — that would be glass-on-glass). Earlier OSes get
    /// a `.bar` material backing behind the material controls.
    @ViewBuilder
    private var composerSurface: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                composerBar
            }
        } else {
            composerBar
                .background(.bar)
        }
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                store.toggleComposer()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: controlHeight, height: controlHeight)
            }
            .buttonStyle(.plain)
            .foregroundStyle(TerminalPalette.foreground.opacity(0.7))
            .mobileGlassCircle()
            .accessibilityIdentifier("MobileComposerClose")
            .accessibilityLabel(L10n.string("mobile.composer.close", defaultValue: "Hide Composer"))

            TextField(
                L10n.string("mobile.composer.placeholder", defaultValue: "Message"),
                text: $store.terminalInputText,
                axis: .vertical
            )
            // Draft mode keeps the docked toolbar visible (the bar no longer hides
            // when the composer opens), and the composer is the taller surface: it
            // starts at a comfortable multi-line height and grows up to 14 lines so
            // a long message has room instead of the bar disappearing to make space.
            .lineLimit(composerLineLimit)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .focused($isFieldFocused)
            .foregroundStyle(TerminalPalette.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: composerFieldMinHeight, alignment: .top)
            .mobileGlassField(cornerRadius: 20)
            .accessibilityIdentifier("MobileComposerField")

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: controlHeight, height: controlHeight)
                    .foregroundStyle(trimmedIsEmpty ? TerminalPalette.foreground.opacity(0.35) : Color.accentColor)
            }
            .buttonStyle(.plain)
            .mobileGlassCircle()
            .disabled(trimmedIsEmpty)
            .accessibilityIdentifier("MobileComposerSend")
            .accessibilityLabel(L10n.string("mobile.composer.send", defaultValue: "Send"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Focus the field one runloop after appearing. Setting `@FocusState` inline
    /// in `onAppear` is unreliable (the field may not be in the window yet);
    /// deferring lets it take first responder from the terminal input proxy
    /// while that keyboard is still up, so the keyboard hands over in place
    /// instead of dropping and re-animating.
    private func focusField() {
        Task { @MainActor in
            isFieldFocused = true
        }
    }

    private func send() {
        guard !trimmedIsEmpty else { return }
        isFieldFocused = true
        Task { @MainActor in
            await store.submitComposerInput()
        }
    }
}
#endif
