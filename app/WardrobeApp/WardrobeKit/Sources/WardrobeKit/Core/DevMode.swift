import Foundation

/// Gate for developer-only affordances (the dev menu).
///
/// On in DEBUG and in TestFlight builds, off in App Store builds — testers on
/// TestFlight are us, App Store users are not.
public enum DevMode {
    // ponytail: receipt filename is the cheap TestFlight signal; swap to
    // StoreKit 2 `AppTransaction` (async) if this ever stops compiling.
    public static let isEnabled: Bool = {
        #if DEBUG
            true
        #else
            Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()

    /// UI-verification seam: `-devMenu` opens the sheet on launch, because a
    /// long press cannot be scripted against the simulator.
    public static let opensOnLaunch: Bool = {
        #if DEBUG
            isEnabled && ProcessInfo.processInfo.arguments.contains("-devMenu")
        #else
            false
        #endif
    }()
}
