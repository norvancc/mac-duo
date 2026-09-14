import AppKit
import MetalKit
import DuoCore

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private var view: MTKView?
    private let renderer = FoldRenderer()
    private var animationTimer: Timer?
    private var currentAngle = 110.0
    private var targetAngle = 110.0
    private var lastTick = Date()
    var isVisible: Bool { panel?.isVisible == true }
    var available: Bool { renderer != nil }

    func show(image: CGImage, screen: NSScreen, angle: Double, settings: FoldSettings) {
        dismiss()
        guard let renderer else { return }
        let panel = OverlayPanel(contentRect: screen.frame,
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.setFrame(screen.frame, display: false)
        let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: renderer.device)
        renderer.configure(view)
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: image.width, height: image.height)
        renderer.snapshot = CIImage(cgImage: image)
        renderer.settings = settings
        // The first frame is the exact desktop, avoiding a flash on capture completion.
        renderer.angle = settings.startAngle
        currentAngle = settings.startAngle
        targetAngle = angle
        panel.contentView = view
        self.panel = panel
        self.view = view
        panel.orderFrontRegardless()
        view.draw()
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func update(angle: Double, settings: FoldSettings) {
        targetAngle = angle
        renderer?.settings = settings
    }

    private func tick() {
        let now = Date()
        let dt = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now
        guard abs(currentAngle - targetAngle) > 0.015 else { return }
        // ~25 ms low-pass interpolation smooths the whole-degree sensor without
        // turning the interaction into a fixed-duration closing animation.
        currentAngle += (targetAngle - currentAngle) * (1 - exp(-dt / 0.025))
        renderer?.angle = currentAngle
        view?.draw()
    }

    func dismiss() {
        animationTimer?.invalidate()
        animationTimer = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        view = nil
        renderer?.snapshot = nil
    }
}
