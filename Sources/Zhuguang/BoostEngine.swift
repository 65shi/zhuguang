import AppKit
import Metal
import QuartzCore

/// EDR activation plus a uniform multiply surface. No display gamma or backlight state is changed.
/// Apple documents that an onscreen EDR layer permits values above SDR white:
/// https://developer.apple.com/documentation/quartzcore/cametallayer/wantsextendeddynamicrangecontent
/// The multiply-overlay approach is adapted from MaxNits (MIT); see ThirdPartyNotices.md.
/// WindowServer compositing behavior still needs validation on each macOS/display combination.
@MainActor
final class BoostEngine {
    enum EngineError: LocalizedError {
        case metalUnavailable
        case unsupportedDisplay

        var errorDescription: String? {
            switch self {
            case .metalUnavailable: return "无法创建 Metal 渲染设备，亮度增强未启动。"
            case .unsupportedDisplay: return "没有找到支持 EDR 的内建显示屏。"
            }
        }
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var trigger: BoostSurface?
    private var booster: BoostSurface?
    private var screenID: CGDirectDisplayID?
    private var generation = UUID()
    private(set) var isRunning = false
    private(set) var renderedFrames = 0
    private(set) var boostedRenderedFrames = 0
    private(set) var lastRenderedMultiplier = 1.0
    private(set) var lastRenderError: String?

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw EngineError.metalUnavailable
        }
        self.device = device
        self.commandQueue = queue
    }

    static func compatibleScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = displayID(for: screen) else { return false }
            return CGDisplayIsBuiltin(id) != 0 &&
                screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.05
        }
    }

    func start(screen: NSScreen) throws {
        stop()
        guard let id = Self.displayID(for: screen), CGDisplayIsBuiltin(id) != 0,
              screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.05 else {
            throw EngineError.unsupportedDisplay
        }

        screenID = id
        lastRenderError = nil
        renderedFrames = 0
        boostedRenderedFrames = 0
        lastRenderedMultiplier = 1
        isRunning = true
        let token = generation

        let activator = BoostSurface(
            frame: NSRect(x: screen.frame.maxX - 1, y: screen.frame.maxY - 1, width: 1, height: 1),
            device: device, queue: commandQueue, multiply: false, initialValue: 2.0
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.isRunning else { return }
                if let error { self.lastRenderError = error }
            }
        }

        let fullScreen = BoostSurface(
            frame: screen.frame, device: device, queue: commandQueue,
            multiply: true, initialValue: 1.0
        ) { [weak self] renderedMultiplier, error in
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.isRunning else { return }
                if let error {
                    self.lastRenderError = error
                } else {
                    self.renderedFrames += 1
                    self.lastRenderedMultiplier = renderedMultiplier
                    if renderedMultiplier > 1.001 { self.boostedRenderedFrames += 1 }
                    // White × desktop is neutral. Reveal only after a completed neutral frame.
                    self.booster?.reveal()
                }
            }
        }
        trigger = activator
        booster = fullScreen
        activator.start()
        fullScreen.start()
    }

    /// Returns the submitted multiplier, never an estimate of physical luminance.
    @discardableResult
    func update(multiplier: Double) -> Double {
        guard isRunning, let screenID,
              let screen = NSScreen.screens.first(where: { Self.displayID(for: $0) == screenID }) else {
            return 1
        }
        let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        let actual = BoostPolicy.multiplier(requested: multiplier, headroom: headroom)
        // Avoid clipping ordinary SDR while macOS is still allocating EDR headroom.
        booster?.setValue(headroom > 1.05 ? actual : 1)
        return headroom > 1.05 ? actual : 1
    }

    func stop() {
        generation = UUID()
        isRunning = false
        trigger?.close()
        booster?.close()
        trigger = nil
        booster = nil
        screenID = nil
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@MainActor
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class BoostSurface {
    private let window: OverlayWindow
    private let renderer: SolidMetalRenderer

    init(frame: NSRect, device: MTLDevice, queue: MTLCommandQueue,
         multiply: Bool, initialValue: Double,
         onFrame: @escaping @Sendable (Double, String?) -> Void) {
        let window = OverlayWindow(contentRect: frame, styleMask: .borderless,
                                   backing: .buffered, defer: false)
        self.window = window
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + (multiply ? 0 : 1))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none
        window.hidesOnDeactivate = false
        window.canHide = false
        window.isReleasedWhenClosed = false
        window.title = multiply ? "Zhuguang 亮度增强" : "Zhuguang EDR 激活"
        window.alphaValue = multiply ? 0 : 1

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.wantsExtendedDynamicRangeContent = true
        layer.isOpaque = false
        layer.contentsScale = 1
        layer.contentsGravity = .resize
        layer.drawableSize = CGSize(width: 4, height: 4)
        layer.allowsNextDrawableTimeout = true
        layer.maximumDrawableCount = 2
        if multiply { layer.compositingFilter = "multiply" }

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view
        renderer = SolidMetalRenderer(layer: layer, commandQueue: queue,
                                      value: initialValue, onFrame: onFrame)
    }

    func start() {
        window.orderFrontRegardless()
        renderer.start()
    }

    func reveal() {
        if window.alphaValue == 0 { window.alphaValue = 1 }
    }

    func setValue(_ value: Double) { renderer.setValue(value) }

    func close() {
        renderer.stop()
        window.orderOut(nil)
        window.close()
    }
}

/// The tiny texture is stretched over its window: rendering cost does not grow with display size.
/// `nextDrawable()` can wait; all drawable acquisition happens on this private queue.
private final class SolidMetalRenderer: @unchecked Sendable {
    private let layer: CAMetalLayer
    private let commandQueue: MTLCommandQueue
    private let renderingQueue = DispatchQueue(label: "Zhuguang.uniform-surface", qos: .utility)
    private let lock = NSLock()
    private let onFrame: @Sendable (Double, String?) -> Void
    private var value: Double
    private var stopped = false
    private var timer: DispatchSourceTimer?
    private var consecutiveDrawableFailures = 0

    init(layer: CAMetalLayer, commandQueue: MTLCommandQueue, value: Double,
         onFrame: @escaping @Sendable (Double, String?) -> Void) {
        self.layer = layer
        self.commandQueue = commandQueue
        self.value = value
        self.onFrame = onFrame
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: renderingQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200), leeway: .milliseconds(30))
        timer.setEventHandler { [weak self] in self?.render() }
        self.timer = timer
        timer.resume()
    }

    func setValue(_ newValue: Double) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        timer?.cancel()
        timer = nil
    }

    private func render() {
        lock.lock()
        let currentValue = value
        let shouldStop = stopped
        lock.unlock()
        guard !shouldStop else { return }
        autoreleasepool {
            guard let drawable = layer.nextDrawable() else {
                consecutiveDrawableFailures += 1
                if consecutiveDrawableFailures == 5 { onFrame(currentValue, "Metal 暂时无法取得显示缓冲区。") }
                return
            }
            consecutiveDrawableFailures = 0
            guard let buffer = commandQueue.makeCommandBuffer() else {
                onFrame(currentValue, "无法创建 Metal 命令缓冲区。")
                return
            }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(
                red: currentValue, green: currentValue, blue: currentValue, alpha: 1
            )
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
                onFrame(currentValue, "无法创建 Metal 渲染编码器。")
                return
            }
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.addCompletedHandler { [onFrame] completed in
                onFrame(currentValue, completed.status == .completed ? nil :
                    (completed.error?.localizedDescription ?? "Metal 渲染未完成。"))
            }
            buffer.commit()
        }
    }
}
