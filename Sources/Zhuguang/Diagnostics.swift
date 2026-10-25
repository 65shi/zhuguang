import AppKit

@MainActor
enum Diagnostics {
    static func printScreenReport() {
        let screens: [[String: Any]] = NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return ["name": screen.localizedName, "builtIn": CGDisplayIsBuiltin(id) != 0,
                    "currentEDR": screen.maximumExtendedDynamicRangeColorComponentValue,
                    "potentialEDR": screen.maximumPotentialExtendedDynamicRangeColorComponentValue,
                    "width": screen.frame.width, "height": screen.frame.height]
        }
        emit(["app": "Zhuguang 1.0.2", "os": ProcessInfo.processInfo.operatingSystemVersionString,
              "compatibleBuiltInScreen": BoostEngine.compatibleScreen() != nil,
              "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
              "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
              "screens": screens])
    }

    /// Brief integration test, including process-owned window teardown and unchanged gamma.
    /// A colorimeter or direct observation is still needed to assess physical luminance.
    static func runSmokeTest(app: NSApplication) {
        guard let screen = BoostEngine.compatibleScreen() else {
            emit(["passed": false, "reason": "No compatible built-in display"])
            exit(2)
        }
        if let reason = BoostPolicy.pauseReason(sleeping: false, sessionActive: true,
            thermalState: ProcessInfo.processInfo.thermalState,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, pauseOnLowPower: true) {
            emit(["passed": false, "reason": reason])
            exit(2)
        }
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let baseline = gamma(display: id)
        let baselineWindows = Set(app.windows.map(\.windowNumber))
        do {
            let engine = try BoostEngine()
            let initialHeadroom = screen.maximumExtendedDynamicRangeColorComponentValue
            try engine.start(screen: screen)
            let workspace = NSWorkspace.shared.notificationCenter
            let safetyObservers = [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                                   NSWorkspace.sessionDidResignActiveNotification].map { name in
                workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated {
                        engine.stop()
                        emit(["passed": false, "reason": "Screen sleep or inactive session", "engineStopped": !engine.isRunning])
                        exit(2)
                    }
                }
            }
            defer { safetyObservers.forEach { workspace.removeObserver($0) } }
            var ticks = 0
            var maximumApplied = 1.0
            var maximumHeadroom = Double(initialHeadroom)
            let timer = Timer(timeInterval: 0.2, repeats: true) { timer in
                MainActor.assumeIsolated {
                    if let reason = BoostPolicy.pauseReason(sleeping: false, sessionActive: true,
                        thermalState: ProcessInfo.processInfo.thermalState,
                        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, pauseOnLowPower: true) {
                        timer.invalidate()
                        engine.stop()
                        emit(["passed": false, "reason": reason, "engineStopped": !engine.isRunning])
                        exit(2)
                    }
                    ticks += 1
                    maximumApplied = max(maximumApplied, engine.update(multiplier: 1.1))
                    maximumHeadroom = max(maximumHeadroom, Double(BoostEngine.compatibleScreen()?.maximumExtendedDynamicRangeColorComponentValue ?? 1))
                    guard ticks >= 20 else { return }
                    timer.invalidate()
                    let frames = engine.renderedFrames
                    let boostedFrames = engine.boostedRenderedFrames
                    let renderedMultiplier = engine.lastRenderedMultiplier
                    let error = engine.lastRenderError
                    engine.stop()
                    let after = gamma(display: id)
                    let delta: Double? = baseline.count == after.count && !baseline.isEmpty
                        ? Double(zip(baseline, after).map { abs($0 - $1) }.max() ?? 0) : nil
                    let extraWindows = app.windows.filter { !baselineWindows.contains($0.windowNumber) && $0.isVisible }.count
                    let passed = boostedFrames > 0 && renderedMultiplier > 1 && error == nil && maximumApplied > 1 && delta != nil && delta! < 0.0001 && extraWindows == 0 && !engine.isRunning
                    emit(["passed": passed, "initialEDR": initialHeadroom, "maximumEDR": maximumHeadroom,
                          "maximumApplied": maximumApplied, "renderedFrames": frames,
                          "boostedRenderedFrames": boostedFrames, "lastRenderedMultiplier": renderedMultiplier,
                          "gammaMaxDelta": delta.map { $0 as Any } ?? NSNull(),
                          "remainingVisibleOverlayWindows": extraWindows,
                          "engineStopped": !engine.isRunning, "renderError": error.map { $0 as Any } ?? NSNull(),
                          "note": "API/render/cleanup test; physical luminance is not measured"])
                    app.stop(nil)
                    // Wake NSApplication's event loop so stop() returns without another user event.
                    app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                        subtype: 0, data1: 0, data2: 0)!, atStart: false)
                    if !passed { exit(1) }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            app.run()
        } catch {
            emit(["passed": false, "reason": error.localizedDescription])
            exit(1)
        }
    }

    private static func gamma(display: CGDirectDisplayID) -> [Float] {
        let capacity = max(256, Int(CGDisplayGammaTableCapacity(display)))
        var red = [Float](repeating: 0, count: capacity)
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, UInt32(capacity), &red, &green, &blue, &count) == .success else { return [] }
        return Array(red.prefix(Int(count))) + Array(green.prefix(Int(count))) + Array(blue.prefix(Int(count)))
    }

    private static func emit(_ object: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) { print(string) }
    }
}
