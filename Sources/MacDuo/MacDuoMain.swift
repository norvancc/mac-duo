import AppKit
import SwiftUI
import Combine
import Carbon

@main
@MainActor
enum MacDuoMain {
    static func main() {
        if CommandLine.arguments.contains("--render-check") {
            RenderCheck.run()
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "macbook", accessibilityDescription: "Mac Duo")
        rebuildMenu()
        model.objectWillChange
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] in self?.rebuildMenu() }.store(in: &cancellables)
        registerEscapeShortcut()
        model.start()
        showSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    @objc func showSettings() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "Mac Duo"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor(red: 0.055, green: 0.064, blue: 0.083, alpha: 1)
            window.setContentSize(controller.view.fittingSize)
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let angle = model.angle.map { "\(Int($0))°" } ?? "无传感器"
        menu.addItem(withTitle: "Mac Duo · \(angle)", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: model.status, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let enabled = menu.addItem(withTitle: "启用合盖效果", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.state = model.enabled ? .on : .off
        menu.addItem(withTitle: "全屏试播…", action: #selector(playDemo), keyEquivalent: "p")
        menu.addItem(withTitle: "打开设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "停止当前效果  ⌃⌥⌘D", action: #selector(stopEffect), keyEquivalent: "")
        if !model.permission {
            menu.addItem(withTitle: "重新检查屏幕录制权限", action: #selector(requestPermission), keyEquivalent: "")
            menu.addItem(withTitle: "打开权限设置…", action: #selector(openPrivacySettings), keyEquivalent: "")
            menu.addItem(withTitle: "重新启动 Mac Duo", action: #selector(restartApp), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Mac Duo", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
        statusItem.button?.toolTip = "Mac Duo · \(angle) · \(model.status)"
    }

    @objc private func toggleEnabled() { model.enabled.toggle() }
    @objc private func playDemo() { model.playDemo() }
    @objc private func stopEffect() { model.emergencyStop() }
    @objc private func requestPermission() { model.requestPermission() }
    @objc private func openPrivacySettings() { model.openPrivacySettings() }
    @objc private func restartApp() { model.restartApplication() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func registerEscapeShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerResult = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.stopEffect() }
            return noErr
        }, 1, &event, pointer, &hotKeyHandler)
        let identifier = EventHotKeyID(signature: OSType(0x4D44554F), id: 1)
        let hotKeyResult = RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey | cmdKey), identifier,
                                              GetApplicationEventTarget(), 0, &hotKey)
        if handlerResult != noErr || hotKeyResult != noErr { model.reportShortcutFailure() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.model.cancelEffect()
            }
            return event
        }
    }
}
