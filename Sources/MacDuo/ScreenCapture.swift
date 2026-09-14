import AppKit
import ScreenCaptureKit
import os

@MainActor
final class ScreenCapture {
    private let logger = Logger(subsystem: "app.norvan.MacDuo", category: "permission")
    private var display: SCDisplay?
    private var cachedAt = Date.distantPast
    private var verifiedAccess: Bool?

    // A successful ScreenCaptureKit call is authoritative. A stale CoreGraphics
    // preflight result must not overwrite it on the next housekeeping tick.
    var authorized: Bool { verifiedAccess ?? CGPreflightScreenCaptureAccess() }
    var preflightAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    func invalidate() { display = nil; cachedAt = .distantPast }

    @discardableResult
    func verifyAccess() async throws -> SCShareableContent {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            verifiedAccess = true
            logger.notice("ScreenCaptureKit access verified; preflight=\(self.preflightAuthorized, privacy: .public).")
            return content
        } catch {
            let nsError = error as NSError
            logger.error("ScreenCaptureKit access check failed: \(nsError.domain, privacy: .public) / \(nsError.code, privacy: .public).")
            if Self.isPermissionError(error) { verifiedAccess = false; invalidate() }
            throw error
        }
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }

    func prepare() async throws {
        if display != nil, Date().timeIntervalSince(cachedAt) < 30 { return }
        let content = try await verifyAccess()
        guard let builtIn = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
              NSScreen.screens.contains(where: { $0.displayID == builtIn.displayID }) else {
            throw CaptureError.noBuiltIn
        }
        display = builtIn
        cachedAt = Date()
    }

    func take() async throws -> (CGImage, NSScreen) {
        try await prepare()
        guard let display, let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else {
            throw CaptureError.noBuiltIn
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let pixelWidth = Int(screen.frame.width * screen.backingScaleFactor)
        let ratio = min(1, 2400.0 / Double(pixelWidth))
        config.width = Int(Double(pixelWidth) * ratio)
        config.height = Int(screen.frame.height * screen.backingScaleFactor * ratio)
        config.showsCursor = false
        config.capturesAudio = false
        config.ignoreShadowsSingleWindow = true
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            verifiedAccess = true
            return (image, screen)
        } catch {
            if Self.isPermissionError(error) { verifiedAccess = false; invalidate() }
            throw error
        }
    }

    enum CaptureError: LocalizedError {
        case permission, noBuiltIn
        var errorDescription: String? {
            switch self {
            case .permission: return "请先允许屏幕录制，再启用合盖效果。"
            case .noBuiltIn: return "未找到正在使用的 Mac 内置屏幕。"
            }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
