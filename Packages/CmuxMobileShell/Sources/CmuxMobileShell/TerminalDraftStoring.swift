/// Persistence seam for per-terminal composer drafts.
///
/// A draft is the unsent text the user has typed for one terminal. Drafts are
/// keyed by the terminal's stable id (``MobileTerminalPreview/ID/rawValue``) so
/// switching terminals shows that terminal's own draft, and they survive an app
/// kill/relaunch because the store writes them to disk.
///
/// The shell (``MobileShellComposite``) owns one of these and calls it when the
/// selected terminal changes, when a draft edit lands, and when a draft is sent
/// or the user signs out. Injected as `any TerminalDraftStoring` so tests pass a
/// fake (or a temp-directory-backed real store) without touching the user's
/// container.
///
/// ## Concurrency
///
/// All methods are `async` so the conforming type can serialize disk access on
/// an `actor` and keep file I/O off the main thread. The shell awaits a `load`
/// before showing a terminal's draft and fires `save`/`clear` without awaiting
/// (the in-memory ``MobileShellComposite/terminalInputText`` is the live value;
/// disk is the durable mirror).
public protocol TerminalDraftStoring: Sendable {
    /// The persisted draft for `terminalID`, or `nil` if none was saved.
    /// - Parameter terminalID: The terminal's stable id raw string.
    /// - Returns: The saved draft text, or `nil` when absent or unreadable.
    func draft(forTerminalID terminalID: String) async -> String?

    /// Persist (or, for an empty/whitespace draft, remove) the draft for
    /// `terminalID`.
    ///
    /// An empty or whitespace-only draft is treated as "no draft" and removed, so
    /// a cleared field never resurrects on relaunch and the store does not
    /// accumulate empty entries.
    /// - Parameters:
    ///   - draft: The draft text to persist.
    ///   - terminalID: The terminal's stable id raw string.
    func saveDraft(_ draft: String, forTerminalID terminalID: String) async

    /// Remove the persisted draft for `terminalID` (e.g. after it was sent).
    /// - Parameter terminalID: The terminal's stable id raw string.
    func clearDraft(forTerminalID terminalID: String) async

    /// Remove every persisted draft (e.g. on sign-out, so the next account never
    /// sees the previous user's unsent text).
    func clearAllDrafts() async
}
