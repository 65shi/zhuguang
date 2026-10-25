import AppKit
import Combine
import ServiceManagement

@MainActor
final class LightModel: NSObject, ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var active = false
    @Published private(set) var title = "让屏幕，再亮一点"
    @Published private(set) var detail = "开启后，使用内置 XDR 屏幕的额外亮度空间。"
    @Published private(set) var screenName = "正在检测屏幕…"
    @Published private(set) var supported = false
    @Published private(set) var currentHeadroom = 1.0
    @Published private(set) var potentialHeadroom = 1.0
    @Published private(set) var appliedMultiplier = 1.0
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginMessage: String?
    @Published private(set) var remainingMinutes: Int?
    @Published var requestedMultiplier: Double {
        didSet {
            let bounded = requestedMultiplier.isFinite ? min(2, max(1, requestedMultiplier)) : 1.25
            if requestedMultiplier != bounded { requestedMultiplier = bounded; return }
            UserDefaults.standard.set(bounded, forKey: "multiplier")
            refresh()
        }
    }
    @Published var pauseOnLowPower: Bool {
        didSet { UserDefaults.standard.set(pauseOnLowPower, forKey: "pauseOnLowPower"); refresh() }
    }
    @Published var autoOffMinutes: Int {
        didSet {
            UserDefaults.standard.set(autoOffMinutes, forKey: "autoOffMinutes")
            if enabled { resetDeadline() }
        }
    }

    private var engine: BoostEngine?
    private var timer: Timer?
    private var sleeping = false
    private var sessionActive = true
    private var deadline: Date?
    private var activationStarted: Date?
    private var reconfiguration: DispatchWorkItem?
    private var rebuilding = false
    private var failed = false
    private var screenSignature = ""
    private var environmentObservers: [NSObjectProtocol] = []

    override init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["multiplier": 1.25, "pauseOnLowPower": true, "autoOffMinutes": 0])
        let stored = defaults.double(forKey: "multiplier")
        requestedMultiplier = stored.isFinite ? min(2, max(1, stored)) : 1.25
        pauseOnLowPower = defaults.bool(forKey: "pauseOnLowPower")
        let minutes = defaults.integer(forKey: "autoOffMinutes")
        autoOffMinutes = [0, 10, 20, 30, 60].contains(minutes) ? minutes : 0
        super.init()
        screenSignature = Self.topologySignature()
        loginEnabled = SMAppService.mainApp.status == .enabled
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange] {
            environmentObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            workspace.addObserver(self, selector: #selector(willSleep), name: name, object: nil)
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            workspace.addObserver(self, selector: #selector(didWake), name: name, object: nil)
        }
        workspace.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        refresh()
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        failed = false
        if value { resetDeadline() } else { deadline = nil; remainingMinutes = nil }
        refresh()
    }

    func restore() {
        setEnabled(false)
        title = "已恢复标准亮度"
        detail = "增强图层已移除，可继续使用系统亮度键。"
    }

    func shutdown() {
        enabled = false
        timer?.invalidate()
        reconfiguration?.cancel()
        stopEngine()
        NotificationCenter.default.removeObserver(self)
        for observer in environmentObservers { NotificationCenter.default.removeObserver(observer) }
        environmentObservers.removeAll()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func setLoginEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许逐光。" : nil
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = "设置失败：\(error.localizedDescription)。请先把 App 放入“应用程序”文件夹。"
        }
    }

    func refresh() {
        let screen = BoostEngine.compatibleScreen()
        supported = screen != nil
        screenName = screen?.localizedName ?? "未检测到兼容的内置 XDR 屏幕"
        potentialHeadroom = Double(screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1)
        currentHeadroom = Double(screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1)

        guard enabled else {
            stopEngine()
            title = "让屏幕，再亮一点"
            detail = supported ? "增强已关闭。系统亮度保持原样。" : "仅支持具有 EDR 能力的 MacBook Pro 内置屏幕。"
            return
        }
        guard let screen else {
            stopEngine()
            title = "等待内置 XDR 屏幕"
            detail = "打开 MacBook 屏幕后会自动重新检测。"
            return
        }
        if let reason = BoostPolicy.pauseReason(sleeping: sleeping, sessionActive: sessionActive,
            thermalState: ProcessInfo.processInfo.thermalState,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, pauseOnLowPower: pauseOnLowPower) {
            stopEngine()
            title = "增强已暂停"
            detail = reason
            return
        }
        guard !rebuilding, !failed else { return }
        do {
            if engine == nil {
                let newEngine = try BoostEngine()
                try newEngine.start(screen: screen)
                engine = newEngine
                activationStarted = Date()
            }
            appliedMultiplier = engine?.update(multiplier: requestedMultiplier) ?? 1
            active = appliedMultiplier > 1.01 && (engine?.renderedFrames ?? 0) > 0
            if let error = engine?.lastRenderError {
                throw NSError(domain: "Zhuguang.Metal", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            if active {
                title = "XDR 增强已开启"
                detail = appliedMultiplier + 0.02 < requestedMultiplier
                    ? "系统当前可用余量有限，已自动限制增强强度。"
                    : "继续用键盘亮度键调节基础亮度。"
            } else if Date().timeIntervalSince(activationStarted ?? Date()) > 6 {
                title = "系统暂未提供额外亮度"
                detail = "可检查显示器是否使用 Apple XDR 预设；温度和低电量模式也会限制亮度。"
            } else {
                title = "正在激活 XDR…"
                detail = "等待 macOS 分配额外亮度空间。"
            }
        } catch {
            stopEngine()
            failed = true
            title = "暂时无法开启增强"
            detail = error.localizedDescription + "。关闭后可重试。"
        }
    }

    private func stopEngine() {
        engine?.stop()
        engine = nil
        active = false
        appliedMultiplier = 1
        activationStarted = nil
    }

    private func resetDeadline() {
        deadline = autoOffMinutes > 0 ? Date().addingTimeInterval(Double(autoOffMinutes * 60)) : nil
        remainingMinutes = autoOffMinutes > 0 ? autoOffMinutes : nil
    }

    @objc private func tick() {
        if let deadline {
            if Date() >= deadline {
                restore()
                title = "定时已结束"
                detail = "已自动关闭增强，恢复标准亮度。"
                return
            }
            remainingMinutes = max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))
        }
        refresh()
    }

    @objc private func willSleep() { sleeping = true; refresh() }
    @objc private func didWake() { sleeping = false; scheduleRebuild() }
    @objc private func sessionResigned() { sessionActive = false; refresh() }
    @objc private func sessionBecameActive() { sessionActive = true; scheduleRebuild() }

    @objc private func screenChanged() {
        let signature = Self.topologySignature()
        // This notification also covers live EDR headroom. Rebuilding for that would
        // tear down the very HDR layer that caused the notification.
        guard signature != screenSignature else { refresh(); return }
        screenSignature = signature
        scheduleRebuild()
    }

    private static func topologySignature() -> String {
        NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return "\(id):\(NSStringFromRect(screen.frame)):\(screen.backingScaleFactor):\(screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.05)"
        }.sorted().joined(separator: "|")
    }

    private func scheduleRebuild() {
        reconfiguration?.cancel()
        rebuilding = true
        stopEngine()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.rebuilding = false
            self.failed = false
            self.refresh()
        }
        reconfiguration = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}
