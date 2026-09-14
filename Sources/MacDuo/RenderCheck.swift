import AppKit
import DuoCore

@MainActor
enum RenderCheck {
    static func run() {
        guard let renderer = FoldRenderer() else {
            fputs("Metal unavailable\n", stderr)
            exit(1)
        }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/render-check", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { fputs("\(error)\n", stderr); exit(1) }
        renderer.snapshot = CIImage(cgImage: SampleDesktop.image)
        if CommandLine.arguments.contains("--benchmark") {
            guard let result = renderer.benchmark(size: .init(width: 2400, height: 1560)) else {
                fputs("GPU benchmark failed\n", stderr)
                exit(1)
            }
            print(String(format: "2400 × 1560, 90 GPU frames: median %.2f ms, p95 %.2f ms", result.median, result.p95))
            return
        }
        for angle in [110.0, 95, 80, 65, 50, 35, 12] {
            renderer.angle = angle
            if angle == 65 {
                verifyBlackBackground(renderer)
            }
            guard let image = renderer.export(size: .init(width: 1440, height: 936)),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                fputs("Rendering failed at \(angle)\n", stderr)
                exit(1)
            }
            do { try png.write(to: directory.appendingPathComponent("fold-\(Int(angle)).png")) }
            catch { fputs("\(error)\n", stderr); exit(1) }
            print("Rendered \(Int(angle))°")
        }
        verifyEdgeDiffusion(renderer, directory: directory)
        verifyViewportFeather(renderer)
        verifyStationaryScreenshot(renderer)
        // Without content blur, the stationary screenshot under the mask is clear.
        renderer.settings.maxBlur = 0
        renderer.angle = 65
        if let image = renderer.export(size: .init(width: 1440, height: 936)),
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("fixed-image-65.png"))
        }
        print("Render check complete: \(directory.path)")
    }

    private static func verifyBlackBackground(_ renderer: FoldRenderer) {
        let size = CGSize(width: 1440, height: 936)
        // With diffusion disabled, uncovered pixels must be opaque black.
        // With diffusion enabled, those pixels may receive a faint color tail.
        let originalBlur = renderer.settings.maxBlur
        renderer.settings.maxBlur = 0
        defer { renderer.settings.maxBlur = originalBlur }
        guard let output = renderer.image(size: size) else { exit(1) }
        func pixel(x: Int, y: Int) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 4)
            renderer.context.render(output, toBitmap: &bytes, rowBytes: 4,
                                    bounds: CGRect(x: x, y: y, width: 1, height: 1),
                                    format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            return bytes
        }
        for x in [2, 1437] {
            let corner = pixel(x: x, y: 933)
            guard corner.prefix(3).allSatisfy({ $0 <= 1 }), corner[3] == 255 else {
                fputs("Expected an opaque black background outside the trapezoid; got \(corner).\n", stderr)
                exit(1)
            }
        }
        guard pixel(x: 720, y: 468).prefix(3).contains(where: { $0 > 10 }) else {
            fputs("The screenshot must remain visible inside the trapezoid.\n", stderr)
            exit(1)
        }
        print("Verified: black, opaque corners; visible screenshot at center.")
    }

    private static func verifyEdgeDiffusion(_ renderer: FoldRenderer, directory: URL) {
        let originalSnapshot = renderer.snapshot
        let originalSettings = renderer.settings
        defer {
            renderer.snapshot = originalSnapshot
            renderer.settings = originalSettings
        }
        let size = CGSize(width: 1440, height: 936)
        renderer.snapshot = CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        renderer.settings = FoldSettings()
        renderer.angle = 65
        guard let output = renderer.image(size: size) else { exit(1) }
        let y = 608
        var row = [UInt8](repeating: 0, count: 1440 * 4)
        renderer.context.render(output, toBitmap: &row, rowBytes: 1440 * 4,
                                bounds: CGRect(x: 0, y: y, width: 1440, height: 1),
                                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let luminance = (0..<720).map { Int(row[$0 * 4]) }
        let quad = FoldGeometry.frame(angle: renderer.angle, settings: renderer.settings).quad
        let boundary = Int(quad.topLeft.x * (Double(y) / size.height) / quad.topLeft.y * size.width)
        guard let low = luminance.firstIndex(where: { $0 >= 26 }),
              let high = luminance.firstIndex(where: { $0 >= 230 }), high - low >= 30,
              luminance[max(0, boundary - 12)] >= 10,
              luminance[min(719, boundary + 12)] < 245,
              zip(luminance, luminance.dropFirst()).allSatisfy({ abs($1 - $0) <= 16 }),
              (0..<1440).allSatisfy({ row[$0 * 4 + 3] == 255 }) else {
            fputs("Edge diffusion must extend outside the quad, fade smoothly inward, and stay opaque.\n", stderr)
            fputs("Edge samples: \(stride(from: 0, to: 200, by: 8).map { luminance[$0] })\n", stderr)
            exit(1)
        }
        if let image = renderer.export(size: size),
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("edge-diffusion-65.png"))
        }
        print("Verified: edge diffusion extends outside the quad; 10–90% transition spans \(high - low) px.")
    }

    private static func verifyViewportFeather(_ renderer: FoldRenderer) {
        let originalSnapshot = renderer.snapshot
        let originalSettings = renderer.settings
        let originalAngle = renderer.angle
        defer {
            renderer.snapshot = originalSnapshot
            renderer.settings = originalSettings
            renderer.angle = originalAngle
        }
        let width = 720, height = 468
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        renderer.snapshot = CIImage(color: .white).cropped(to: bounds)
        renderer.settings = FoldSettings()
        // No projection isolates clipping from the trapezoid's own dark edges.
        // Also cover the user's start angle, and the normal projected image.
        for (start, perspective, angle) in [(110.0, 0.0, 80.0), (90, 0, 65), (110, 0.55, 65)] {
            renderer.settings.startAngle = start
            renderer.settings.perspective = perspective
            renderer.angle = angle
            guard let output = renderer.image(size: bounds.size) else { exit(1) }
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            renderer.context.render(output, toBitmap: &rgba, rowBytes: width * 4, bounds: bounds,
                                    format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            func value(_ x: Int, _ y: Int) -> Int { Int(rgba[(y * width + x) * 4]) }
            for y in 0..<height {
                for x in 0..<width where x == 0 || x == width - 1 || y == 0 || y == height - 1 {
                    guard value(x, y) <= 4, rgba[(y * width + x) * 4 + 3] == 255 else {
                        fputs("Physical display edge is still visibly clipped at (\(x), \(y)): \(value(x, y)).\n", stderr)
                        exit(1)
                    }
                }
            }
            guard value(width / 2, height / 2) >= 250 else {
                fputs("Viewport feather must leave the center unchanged.\n", stderr); exit(1)
            }
            if perspective == 0 {
                let profiles = [
                    (0..<width / 2).map { value($0, height / 2) },
                    (0..<width / 2).map { value(width - 1 - $0, height / 2) },
                    (0..<height / 2).map { value(width / 2, $0) },
                    (0..<height / 2).map { value(width / 2, height - 1 - $0) }
                ]
                for profile in profiles {
                    guard profile.contains(where: { $0 > 20 && $0 < 230 }),
                          zip(profile, profile.dropFirst()).allSatisfy({ $1 >= $0 - 1 && $1 - $0 <= 65 }) else {
                        fputs("Viewport edge must fade smoothly inward without a hard band.\n", stderr); exit(1)
                    }
                }
            }
        }
        // At the trigger angle the screenshot must still be an exact full frame.
        renderer.angle = renderer.settings.startAngle
        guard let identity = renderer.image(size: bounds.size) else { exit(1) }
        var pixel = [UInt8](repeating: 0, count: 4)
        renderer.context.render(identity, toBitmap: &pixel, rowBytes: 4,
                                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        guard pixel == [255, 255, 255, 255] else {
            fputs("No viewport fade is allowed at the start angle.\n", stderr); exit(1)
        }
        print("Verified: all four display edges fade to opaque black; center and initial frame preserved.")
    }

    private static func verifyStationaryScreenshot(_ renderer: FoldRenderer) {
        let originalSnapshot = renderer.snapshot
        let originalSettings = renderer.settings
        let originalAngle = renderer.angle
        defer {
            renderer.snapshot = originalSnapshot
            renderer.settings = originalSettings
            renderer.angle = originalAngle
        }
        let size = CGSize(width: 720, height: 468)
        let bounds = CGRect(origin: .zero, size: size)
        // Asymmetric colored blocks expose shifts, scaling and perspective even
        // if a white-field test would look identical after those transformations.
        var source = CIImage(color: .black).cropped(to: bounds)
        for y in 0..<18 {
            for x in 0..<24 {
                let color = CIColor(red: Double((x * 7 + y * 3) % 17) / 16,
                                    green: Double((x * 3 + y * 11) % 19) / 18,
                                    blue: Double((x * 13 + y * 5) % 23) / 22)
                let cell = CIImage(color: color).cropped(to: CGRect(x: x * 30, y: y * 26, width: 30, height: 26))
                source = cell.composited(over: source)
            }
        }
        renderer.snapshot = source
        renderer.settings = FoldSettings()
        renderer.settings.maxBlur = 0
        let region = CGRect(x: 230, y: 94, width: 260, height: 235)
        func pixels(_ image: CIImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: Int(region.width * region.height) * 4)
            renderer.context.render(image, toBitmap: &bytes, rowBytes: Int(region.width) * 4, bounds: region,
                                    format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            return bytes
        }
        let reference = pixels(source)
        for strength in [0.55, 1] {
            renderer.settings.perspective = strength
            for angle in [95.0, 80, 65] {
                renderer.angle = angle
                guard let output = renderer.image(size: size),
                      zip(reference, pixels(output)).allSatisfy({ abs(Int($0) - Int($1)) <= 1 }) else {
                    fputs("Screenshot pixels moved or changed under the mask at \(angle)° / \(strength).\n", stderr)
                    exit(1)
                }
            }
        }
        print("Verified: screenshot coordinates and proportions stay unchanged across six mask states.")
    }
}
