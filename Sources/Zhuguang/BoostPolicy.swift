import Foundation

enum BoostPolicy {
    static let maximumMultiplier = 2.0

    static func multiplier(requested: Double, headroom: Double) -> Double {
        guard requested.isFinite, headroom.isFinite else { return 1 }
        return min(max(1, requested), max(1, headroom), maximumMultiplier)
    }

    static func pauseReason(sleeping: Bool, sessionActive: Bool,
                            thermalState: ProcessInfo.ThermalState,
                            lowPower: Bool, pauseOnLowPower: Bool) -> String? {
        if sleeping { return "屏幕休眠中，唤醒后恢复" }
        if !sessionActive { return "用户会话未激活，返回后恢复" }
        if thermalState == .serious || thermalState == .critical {
            return "设备温度较高，降温后恢复"
        }
        if lowPower && pauseOnLowPower { return "低电量模式已开启，增强已暂停" }
        return nil
    }
}
