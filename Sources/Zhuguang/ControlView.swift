import SwiftUI

struct ControlView: View {
    @ObservedObject var model: LightModel
    let quit: () -> Void
    @State private var showHelp = false
    private let amber = Color(red: 1, green: 0.74, blue: 0.35)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusCard
                strengthControls
                Divider().opacity(0.5)
                settingsControls
                helpControls
                footerControls
            }
            .padding(24)
        }
        .frame(width: 410, height: 660)
        .background(Color(red: 0.07, green: 0.085, blue: 0.11))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(amber)
                .frame(width: 50, height: 50)
                .background(amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 3) {
                Text("逐光").font(.system(size: 23, weight: .semibold))
                Text("Zhuguang · XDR 亮度增强")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("1.0.2").font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Circle().fill(model.active ? amber : Color.gray).frame(width: 6, height: 6)
                Text(model.active ? "XDR ACTIVE" : (model.enabled ? "XDR STANDBY" : "STANDARD"))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.6).foregroundStyle(amber)
                Spacer()
                if let remaining = model.remainingMinutes {
                    Label("\(remaining) 分钟", systemImage: "timer")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Text(model.title).font(.system(size: 22, weight: .semibold))
            Text(model.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Button {
                model.setEnabled(!model.enabled)
            } label: {
                Label(model.enabled ? "关闭增强" : "开启 XDR 增强",
                      systemImage: model.enabled ? "power" : "sun.max")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent).tint(amber).foregroundStyle(.black)
            .disabled(!model.supported && !model.enabled)
            .accessibilityIdentifier("toggleBoost")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [amber.opacity(0.13), Color.white.opacity(0.025)],
            startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(amber.opacity(0.18), lineWidth: 1))
    }

    private var strengthControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("增强强度").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(String(format: "%.2f×", model.requestedMultiplier))
                    .font(.system(size: 24, weight: .light, design: .rounded)).foregroundStyle(amber)
            }
            Slider(value: $model.requestedMultiplier, in: 1...2, step: 0.05)
                .tint(amber).accessibilityLabel("增强强度").accessibilityIdentifier("boostSlider")
            HStack {
                Text("标准 1×")
                Spacer()
                Text("最高 2×")
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                preset("轻度", value: 1.15)
                preset("明亮", value: 1.5)
                preset("户外", value: 2)
            }
            HStack {
                Text("当前应用 \(String(format: "%.2f", model.appliedMultiplier))×")
                Spacer()
                Text("EDR 余量 \(String(format: "%.2f", model.currentHeadroom))×")
            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    private var settingsControls: some View {
        VStack(spacing: 14) {
            Toggle("低电量模式时暂停", isOn: $model.pauseOnLowPower)
                .toggleStyle(.switch).controlSize(.small)
            HStack {
                Text("定时关闭")
                Spacer()
                Picker("定时关闭", selection: $model.autoOffMinutes) {
                    Text("不定时").tag(0)
                    ForEach([10, 20, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                }.labelsHidden().frame(width: 120)
            }
            Toggle("登录时打开逐光", isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                .toggleStyle(.switch).controlSize(.small)
            if let message = model.loginMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.font(.system(size: 12))
    }

    private var helpControls: some View {
        DisclosureGroup("使用提示", isExpanded: $showHelp) {
            VStack(alignment: .leading, spacing: 8) {
                Text("配合系统亮度键使用。倍数是请求的图层增益，实际亮度由 macOS、内容和温度共同决定，并非尼特测量值。")
                Text("高亮度会增加耗电和发热。调色、修图或观看 HDR 视频时建议关闭增强。")
                Text("退出会移除所有增强图层。登录启动后仍需手动开启增强。")
                Link("了解 Apple 的 XDR 亮度限制 ↗", destination: URL(string: "https://support.apple.com/101865")!)
            }.font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                .padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private var footerControls: some View {
        HStack {
            Label(model.supported ? "内置 XDR 屏幕" : "等待兼容屏幕", systemImage: "laptopcomputer")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Button("恢复标准") { model.restore() }
                .accessibilityIdentifier("restoreBrightness")
            Button("退出", action: quit)
        }.font(.system(size: 11)).buttonStyle(.borderless)
    }

    private func preset(_ name: String, value: Double) -> some View {
        Button { model.requestedMultiplier = value } label: {
            Text(name).font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(abs(model.requestedMultiplier - value) < 0.02 ? amber.opacity(0.2) : Color.white.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(abs(model.requestedMultiplier - value) < 0.02 ? amber : Color.secondary)
        }.buttonStyle(.plain)
    }
}
