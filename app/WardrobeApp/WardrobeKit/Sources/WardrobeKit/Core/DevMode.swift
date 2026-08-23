import Foundation

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

    public static let opensOnLaunch: Bool = {
        #if DEBUG
            isEnabled && ProcessInfo.processInfo.arguments.contains("-devMenu")
        #else
            false
        #endif
    }()
    public static let isXcodeDebugBuild: Bool = {
            #if DEBUG
                true
            #else
                false
            #endif
        }()
}
