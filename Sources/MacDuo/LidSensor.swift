import Foundation
import IOKit.hid

/// All HID calls and ownership live on one queue; UI/rendering never wait on I/O.
final class LidSensor {
    var onSample: ((Double?) -> Void)?
    private let queue = DispatchQueue(label: "app.macduo.hinge", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var failures = 0
    private var nextDiscovery = Date.distantPast

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 60, leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.close()
            self.nextDiscovery = .distantPast
        }
    }

    private func close() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        manager = nil
    }

    private func discover() {
        close()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x05ac,
            kIOHIDProductIDKey: 0x8104,
            kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8a
        ] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        for candidate in IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? [] {
            if IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                device = candidate
                failures = 0
                break
            }
        }
    }

    private func poll() {
        if device == nil, Date() >= nextDiscovery {
            nextDiscovery = Date().addingTimeInterval(3)
            discover()
        }
        var angle: Double?
        if let device {
            var bytes = [UInt8](repeating: 0, count: 8)
            var count = bytes.count
            let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &count)
            if result == kIOReturnSuccess, count >= 3, bytes[0] == 1 {
                // Report 1 is an unsigned, little-endian angle in whole degrees.
                let value = Int(bytes[1]) | (Int(bytes[2]) << 8)
                if (0...180).contains(value) { angle = Double(value) }
            }
            failures = angle == nil ? failures + 1 : 0
            if failures > 30 { close() }
        }
        let callback = onSample
        DispatchQueue.main.async { callback?(angle) }
    }
}
