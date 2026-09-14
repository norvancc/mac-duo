import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import MetalKit
import DuoCore

final class FoldRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let inFlight = DispatchSemaphore(value: 2)
    var snapshot: CIImage?
    var angle: Double = 110
    var settings = FoldSettings()
    private(set) var lastError: String?

    init? (device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .name: "Mac Duo"])
        super.init()
    }

    func configure(_ view: MTKView) {
        view.device = device
        view.delegate = self
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = true
        (view.layer as? CAMetalLayer)?.colorspace = colorSpace
    }

    func image(size: CGSize) -> CIImage? {
        guard let snapshot, size.width > 0, size.height > 0 else { return nil }
        let extent = CGRect(origin: .zero, size: size)
        let source = snapshot.transformed(by: .init(scaleX: size.width / snapshot.extent.width,
                                                    y: size.height / snapshot.extent.height))
        let frame = FoldGeometry.frame(angle: angle, settings: settings)
        if frame.progress == 0 { return source.cropped(to: extent) }
        let pixelScale = size.width / 1512
        let radius = frame.blur * pixelScale
        // Mask feathering starts earlier and spreads farther than content blur.
        // Both tend continuously to zero as the screen returns to its start angle.
        let edgeRadius = max(0, settings.maxBlur) * 2.8 * pixelScale
            * sqrt(FoldGeometry.smoothstep(0, 0.92, frame.progress))
        var foreground = source
        // The screenshot stays in screen coordinates throughout. Only its
        // local blur changes; text, windows and icons never undergo projection.
        if radius > 0.01 {
            let detail = CIFilter.maskedVariableBlur()
            detail.inputImage = source.clampedToExtent()
            detail.mask = verticalMask(size: size, bottom: 0.08, top: 1)
            detail.radius = Float(radius)
            foreground = detail.outputImage?.cropped(to: extent) ?? source
        }
        let fade = CIFilter.colorMatrix()
        fade.inputImage = foreground
        let light = Float(1 - frame.darkness)
        fade.rVector = .init(x: CGFloat(light), y: 0, z: 0, w: 0)
        fade.gVector = .init(x: 0, y: CGFloat(light), z: 0, w: 0)
        fade.bVector = .init(x: 0, y: 0, z: CGFloat(light), w: 0)
        foreground = fade.outputImage ?? foreground
        let black = CIImage(color: .black).cropped(to: extent)
        var visibility = apertureMask(quad: frame.quad, size: size, spread: edgeRadius)
        if edgeRadius > 0.01 {
            let product = CIFilter.multiplyCompositing()
            product.inputImage = visibility
            product.backgroundImage = viewportMask(size: size, spread: edgeRadius)
            visibility = product.outputImage ?? visibility
        }
        // Equivalent to a black Lomo-style overlay above an unchanged photo:
        // white mask reveals the screenshot, gray shades it, black hides it.
        let vignette = CIFilter.blendWithMask()
        vignette.inputImage = foreground
        vignette.backgroundImage = black
        vignette.maskImage = visibility
        return (vignette.outputImage ?? black).composited(over: black).cropped(to: extent)
    }

    private func viewportMask(size: CGSize, spread: Double) -> CIImage {
        let side = min(spread * 0.85, size.width * 0.08)
        let top = min(spread * 1.25, size.height * 0.16)
        // Keep the hinge feather short: the bottom edge remains full width.
        let bottom = min(spread * 0.35, size.height * 0.035)
        // End the fade at the outermost pixel centers, not half a pixel beyond
        // them, so even a bright source leaves no residual illuminated seam.
        let ramps: [(CGPoint, CGPoint)] = [
            (.init(x: 0.5, y: 0), .init(x: 0.5 + side, y: 0)),
            (.init(x: size.width - 0.5, y: 0), .init(x: size.width - 0.5 - side, y: 0)),
            (.init(x: 0, y: size.height - 0.5), .init(x: 0, y: size.height - 0.5 - top)),
            (.init(x: 0, y: 0.5), .init(x: 0, y: 0.5 + bottom))
        ]
        var mask = CIImage(color: .white)
        for (outside, inside) in ramps {
            let gradient = CIFilter.smoothLinearGradient()
            gradient.point0 = outside
            gradient.point1 = inside
            gradient.color0 = .black
            gradient.color1 = .white
            // Multiplication gives corners a smooth falloff in both axes,
            // avoiding the diagonal crease of a minimum-distance rectangle.
            let product = CIFilter.multiplyCompositing()
            product.inputImage = mask
            product.backgroundImage = gradient.outputImage
            mask = product.outputImage!
        }
        // Gradually engage the outermost pixel too when the fold first starts.
        let activation = FoldGeometry.smoothstep(0, 2 * size.width / 1512, spread)
        if activation < 1 {
            let mix = CIFilter.colorMatrix()
            mix.inputImage = mask
            mix.rVector = .init(x: activation, y: 0, z: 0, w: 0)
            mix.gVector = .init(x: 0, y: activation, z: 0, w: 0)
            mix.bVector = .init(x: 0, y: 0, z: activation, w: 0)
            mix.biasVector = .init(x: 1 - activation, y: 1 - activation, z: 1 - activation, w: 0)
            mask = mix.outputImage!
        }
        return mask
    }

    private func verticalMask(size: CGSize, bottom: Double, top: Double) -> CIImage {
        let gradient = CIFilter.linearGradient()
        gradient.point0 = .zero
        gradient.point1 = .init(x: 0, y: size.height)
        gradient.color0 = CIColor(red: bottom, green: bottom, blue: bottom)
        gradient.color1 = CIColor(red: top, green: top, blue: top)
        return gradient.outputImage!
    }

    private func apertureMask(quad: FoldQuad, size: CGSize, spread: Double) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        func pixel(_ point: FoldPoint) -> CGPoint {
            .init(x: point.x * size.width, y: point.y * size.height)
        }
        // Project a SOLID WHITE MASK, never the screenshot. Its bottom corners
        // stay on the two hinge endpoints as the upper aperture narrows.
        let shape = CIFilter.perspectiveTransform()
        shape.inputImage = CIImage(color: .white).cropped(to: extent)
        shape.topLeft = pixel(quad.topLeft)
        shape.topRight = pixel(quad.topRight)
        shape.bottomLeft = pixel(quad.bottomLeft)
        shape.bottomRight = pixel(quad.bottomRight)
        var mask = shape.outputImage!
        if spread > 0.01 {
            let padding = CIImage(color: .clear).cropped(to: extent.insetBy(dx: -spread * 3, dy: -spread * 3))
            let feather = CIFilter.maskedVariableBlur()
            feather.inputImage = mask.composited(over: padding)
            feather.mask = verticalMask(size: size, bottom: 0, top: 1)
            feather.radius = Float(spread)
            mask = feather.outputImage ?? mask
        }
        // Convert the softened alpha silhouette into an opaque grayscale mask.
        return mask.composited(over: CIImage(color: .black)).cropped(to: extent)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let output = image(size: view.drawableSize), let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        let semaphore = inFlight
        buffer.addCompletedHandler { _ in semaphore.signal() }
        context.render(output, to: drawable.texture, commandBuffer: buffer,
                       bounds: CGRect(origin: .zero, size: view.drawableSize), colorSpace: colorSpace)
        buffer.present(drawable)
        buffer.commit()
    }

    func benchmark(size: CGSize, count: Int = 90) -> (median: Double, p95: Double)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: Int(size.width), height: Int(size.height), mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var samples: [Double] = []
        for i in 0..<(count + 10) {
            angle = settings.startAngle - Double(i % 90)
            guard let output = image(size: size), let buffer = queue.makeCommandBuffer() else { return nil }
            let start = CACurrentMediaTime()
            context.render(output, to: texture, commandBuffer: buffer,
                           bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
            buffer.commit()
            buffer.waitUntilCompleted()
            guard buffer.status == .completed else { return nil }
            if i >= 10 { samples.append((CACurrentMediaTime() - start) * 1000) }
        }
        samples.sort()
        return (samples[samples.count / 2], samples[Int(Double(samples.count - 1) * 0.95)])
    }

    func export(size: CGSize) -> CGImage? {
        guard let output = image(size: size) else { return nil }
        return context.createCGImage(output, from: CGRect(origin: .zero, size: size),
                                     format: .RGBA8, colorSpace: colorSpace)
    }
}
