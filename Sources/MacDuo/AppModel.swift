import AppKit
import SwiftUI
import DuoCore
import os

@MainActor
final class AppModel: ObservableObject {
    private let logger = Logger(subsystem: "app.norvan.MacDuo", category: "lifecycle")
    @Published var settings: FoldSettings {
        didSet {
            saveSettings()
            if oldValue.startAngle != settings.startAngle { cancelEffect() }
        }
    }
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled"); cancelEffect() }
    }
    @Published private(set) var angle: Double?
    @Published private(set) var permission = false
    @Published private(set) var checkingPermission = false
    @Published private(set) var permissionRequested = UserDefaults.standard.bool(forKey: "permissionRequested")
    @Published private var armed = false
    @Published private(set) var active = false
    @Published private(set) var demoRunning = false
    @Published private(set) var error: String?
    @Published var previewAngle = 75.0
    @Published var followSensor = false
    @Published var wireframe = false
    @Published private(set) var captureMilliseconds: Int?

    private let sensor = LidSensor()
    private let capture = ScreenCapture()
    private let overlay = OverlayController()
    private var trigger = FoldTrigger()
    private var generation = 0
    private var housekeeping: Timer?
    private var demoTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastSample = Date()
    private var lastMotion = Date()
    private var lastAngle: Double?
    private var lastPrepare = Date.distantPast
    private var preparing = false
    private var suspended = false
    private var started = false

    var displayAngle: Double { followSensor ? (angle ?? settings.startAngle) : previewAngle }
    var status: String {
        if let error { return error }
        if demoRunning { return "正在试播 · 自动返回桌面" }
        if checkingPermission { return "正在检查屏幕录制权限…" }
        if !permission {
            return permissionRequested ? "权限尚未生效；已开启时可重新检查或重启应用。" : "需要屏幕录制权限"
        }
        if angle == nil { return "未检测到铰链角度传感器" }
        if !enabled { return "效果已暂停" }
        if active { return "正在跟随屏幕角度" }
        if !armed { return "打开至 \(Int(settings.startAngle + 2))° 以上即可就绪" }
        return "已就绪，轻轻合上屏幕试试"
    }
    var ready: Bool { permission && angle != nil && enabled && !suspended }

    init() {
        let defaults = UserDefaults.standard
        var settings = FoldSettings()
        if defaults.object(forKey: "startAngle") != nil {
            settings.startAngle = FoldGeometry.clamp(defaults.double(forKey: "startAngle"), 70, 125)
            settings.perspective = FoldGeometry.clamp(defaults.double(forKey: "perspective"), 0, 1)
            settings.viewingDistance = FoldGeometry.clamp(defaults.double(forKey: "viewingDistance"), 1.2, 5)
            settings.maxBlur = FoldGeometry.clamp(defaults.double(forKey: "maxBlur"), 0, 70)
        }
        if defaults.integer(forKey: "renderingVersion") < 2 {
            settings.perspective = 0.55
            defaults.set(0.55, forKey: "perspective")
            defaults.set(2, forKey: "renderingVersion")
        }
        self.settings = settings
        enabled = defaults.object(forKey: "enabled") == nil ? true : defaults.bool(forKey: "enabled")
        permission = capture.authorized
        if !overlay.available { error = "这台 Mac 无法初始化 Metal 渲染。" }
    }

    func start() {
        guard !started else { return }
        started = true
        sensor.onSample = { [weak self] in self?.receive($0) }
        sensor.start()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.maintenance() }
        }
        housekeeping = timer
        RunLoop.main.add(timer, forMode: .common)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelEffect()
                self?.capture.invalidate()
            }
        })
        maintenance()
        // Verify once with the capture API itself. Never block this check behind
        // CGPreflightScreenCaptureAccess, which may be stale after an OS grant.
        refreshPermission()
    }

    private func receive(_ value: Double?) {
        guard !suspended else { return }
        if let value {
            lastSample = Date()
            if lastAngle != value { lastMotion = Date(); lastAngle = value }
            if angle != value { angle = value }
        }
        guard let value, !demoRunning else { return }
        let action = trigger.consume(angle: value, startAngle: settings.startAngle,
                                     enabled: enabled && permission && overlay.available)
        if armed != trigger.armed { armed = trigger.armed }
        switch action {
        case .capture: beginCapture(demo: false)
        case .update: overlay.update(angle: value, settings: settings)
        case .dismiss: cancelEffect()
        case .none: break
        }
    }

    private func maintenance() {
        let authorized = capture.authorized
        if authorized != permission {
            permission = authorized
            if !authorized { cancelEffect(); capture.invalidate() }
            else { error = nil }
        }
        if Date().timeIntervalSince(lastSample) > 1.2, angle != nil {
            angle = nil
            cancelEffect()
        }
        // Don't leave a frozen snapshot covering a desktop if someone stops
        // mid-close and returns to work. Opening above the threshold re-arms it.
        if active && !demoRunning && Date().timeIntervalSince(lastMotion) > 12 { cancelEffect() }
        guard permission, enabled, !suspended, !preparing, !active,
              Date().timeIntervalSince(lastPrepare) > 20 else { return }
        preparing = true
        lastPrepare = Date()
        Task {
            defer { preparing = false }
            do { try await capture.prepare() }
            catch {
                if ScreenCapture.isPermissionError(error) {
                    permission = false
                    permissionRequested = true
                    cancelEffect()
                }
            }
        }
    }

    func requestPermission() {
        permissionRequested = true
        UserDefaults.standard.set(true, forKey: "permissionRequested")
        refreshPermission()
    }

    private func refreshPermission() {
        guard !checkingPermission else { return }
        checkingPermission = true
        Task {
            defer { checkingPermission = false }
            do {
                try await capture.verifyAccess()
                permission = true
                error = nil
                permissionRequested = true
                UserDefaults.standard.set(true, forKey: "permissionRequested")
                lastPrepare = .distantPast
                maintenance()
            } catch {
                permission = capture.authorized
                if ScreenCapture.isPermissionError(error) {
                    permissionRequested = true
                    UserDefaults.standard.set(true, forKey: "permissionRequested")
                    self.error = nil
                } else {
                    self.error = "权限检查暂时失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func restartApplication() {
        cancelEffect()
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The bundle path is a positional argument, never interpolated as code.
        relaunch.arguments = ["-c", "sleep 0.5; exec /usr/bin/open -n \"$1\"", "mac-duo-relaunch", Bundle.main.bundlePath]
        do { try relaunch.run(); NSApp.terminate(nil) }
        catch { self.error = "无法重新打开应用：\(error.localizedDescription)" }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func playDemo() {
        guard permission else { requestPermission(); return }
        cancelEffect()
        demoRunning = true
        // Let the menu dismiss before capturing the user's desktop.
        let token = generation
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard token == generation, demoRunning else { return }
            beginCapture(demo: true)
        }
    }

    private func beginCapture(demo: Bool) {
        guard !active else { return }
        active = true
        error = nil
        generation += 1
        let token = generation
        let started = Date()
        Task {
            do {
                let (image, screen) = try await capture.take()
                guard token == generation, !suspended, permission,
                      demo || (enabled && trigger.active) else { return }
                captureMilliseconds = Int(Date().timeIntervalSince(started) * 1000)
                logger.notice("Screenshot ready in \(self.captureMilliseconds ?? 0, privacy: .public) ms; \(image.width, privacy: .public) × \(image.height, privacy: .public).")
                lastMotion = Date()
                overlay.show(image: image, screen: screen,
                             angle: demo ? settings.startAngle : (angle ?? settings.startAngle), settings: settings)
                if demo { startDemoAnimation() }
            } catch {
                guard token == generation else { return }
                cancelEffect()
                if ScreenCapture.isPermissionError(error) {
                    permission = false
                    permissionRequested = true
                } else { self.error = error.localizedDescription }
            }
        }
    }

    private func startDemoAnimation() {
        let started = Date()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
            guard let self else { return }
            let time = Date().timeIntervalSince(started)
            if time >= 5.2 { self.cancelEffect(); return }
            let p: Double
            if time < 0.5 { p = 0 }
            else if time < 2.3 { p = FoldGeometry.smoothstep(0.5, 2.3, time) }
            else if time < 2.8 { p = 1 }
            else { p = 1 - FoldGeometry.smoothstep(2.8, 4.9, time) }
            self.overlay.update(angle: self.settings.startAngle - p * (self.settings.startAngle - 20),
                                settings: self.settings)
            }
        }
        demoTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancelEffect() {
        if active { logger.notice("Overlay dismissed; snapshot released.") }
        generation += 1
        demoTimer?.invalidate()
        demoTimer = nil
        demoRunning = false
        active = false
        overlay.dismiss()
        trigger.reset()
        armed = false
    }

    func clearError() { error = nil; capture.invalidate(); maintenance() }
    func reportShortcutFailure() { error = "退出快捷键被占用，请从菜单栏停止效果。" }
    func emergencyStop() {
        logger.notice("Emergency exit shortcut received.")
        cancelEffect()
    }
    func restoreDefaults() { cancelEffect(); settings = FoldSettings(); previewAngle = 75 }

    private func suspend() {
        suspended = true
        cancelEffect()
        capture.invalidate()
        sensor.stop()
        angle = nil
    }
    private func resume() {
        suspended = false
        cancelEffect()
        capture.invalidate()
        lastSample = Date()
        sensor.start()
    }
    func shutdown() { cancelEffect(); sensor.stop(); housekeeping?.invalidate() }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(settings.startAngle, forKey: "startAngle")
        defaults.set(settings.perspective, forKey: "perspective")
        defaults.set(settings.viewingDistance, forKey: "viewingDistance")
        defaults.set(settings.maxBlur, forKey: "maxBlur")
    }
}
