import AppKit
import Combine
import SwiftUI

@main
struct ZhuguangApp {
    @MainActor static func main() {
        let args = CommandLine.arguments
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if args.contains("--diagnose") {
            Diagnostics.printScreenReport()
            return
        }
        if args.contains("--help") {
            print("Zhuguang 逐光 1.0.2\n--diagnose   查看屏幕 EDR 能力，不更改亮度\n--self-test  短时 1.10× 增强测试，随后自动关闭\n无参数打开菜单栏控制面板。")
            return
        }
        do {
            guard let instanceLock = try InstanceLock.acquire() else {
                if args.contains("--self-test") {
                    fputs("逐光已有实例运行。请先退出逐光，再运行自检；已阻止叠加增强。\n", stderr)
                    exit(2)
                }
                if let identifier = Bundle.main.bundleIdentifier {
                    NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                        .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                        .activate(options: [.activateAllWindows])
                }
                return
            }
            withExtendedLifetime(instanceLock) {
                if args.contains("--self-test") {
                    Diagnostics.runSmokeTest(app: app)
                } else {
                    let delegate = AppDelegate()
                    app.delegate = delegate
                    withExtendedLifetime(delegate) { app.run() }
                }
            }
        } catch {
            fputs("无法取得逐光进程锁：\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: LightModel!
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var cancellables = Set<AnyCancellable>()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = LightModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "逐光 XDR 亮度增强")
            button.image?.isTemplate = true
            button.toolTip = "逐光 · 点击调节 XDR 亮度，右键打开快捷菜单"
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 660),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "逐光 · Zhuguang"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = NSHostingController(rootView: ControlView(model: model) { NSApp.terminate(nil) })
        window.center()
        model.$active.sink { [weak self] active in
            self?.statusItem.button?.image = NSImage(systemSymbolName: active ? "sun.max.fill" : "sun.max", accessibilityDescription: "逐光")
            self?.statusItem.button?.image?.isTemplate = true
        }.store(in: &cancellables)
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        showWindow()
    }

    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window != nil { showWindow() }
        return true
    }

    @objc private func statusClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            if window.isVisible && window.isKeyWindow { window.orderOut(nil) } else { showWindow() }
            return
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "打开逐光", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: model.enabled ? "关闭 XDR 增强" : "开启 XDR 增强", action: #selector(toggleBoost), keyEquivalent: "")
        menu.addItem(withTitle: "恢复标准亮度", action: #selector(restoreBrightness), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出逐光", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        if let button = statusItem.button {
            NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: button)
        }
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    @objc private func toggleBoost() { model.setEnabled(!model.enabled) }
    @objc private func restoreBrightness() { model.restore() }
    @objc private func quit() { NSApp.terminate(nil) }
}
