import Sparkle

/// Thin wrapper around SPUStandardUpdaterController so SwiftUI views
/// can trigger update checks without knowing about Sparkle internals.
@Observable
final class UpdaterViewModel {
    // nonisolated(unsafe) because SPUStandardUpdaterController is an ObjC
    // class that is not Sendable; we only ever access it on the MainActor.
    nonisolated(unsafe) private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
