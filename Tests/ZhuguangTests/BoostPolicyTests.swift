import Foundation

// Compile with the same production BoostPolicy.swift using scripts/test.sh.
// This also works with Command Line Tools installations that lack XCTest.
@main
struct BoostPolicyTests {
    static func main() {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            assertions += 1
            guard condition() else { fputs("FAIL: \(description)\n", stderr); exit(1) }
        }
        check(BoostPolicy.multiplier(requested: 2, headroom: 1) == 1, "No EDR means no boost")
        check(BoostPolicy.multiplier(requested: 1.5, headroom: 1.2) == 1.2, "Respect live headroom")
        check(BoostPolicy.multiplier(requested: 1.25, headroom: 4) == 1.25, "Respect requested gain")
        check(BoostPolicy.multiplier(requested: 20, headroom: 20) == 2, "Respect app ceiling")
        check(BoostPolicy.multiplier(requested: -1, headroom: 0.5) == 1, "Reject negative gain")
        for value in [Double.nan, .infinity, -.infinity] {
            check(BoostPolicy.multiplier(requested: value, headroom: 2) == 1, "Nonfinite request")
            check(BoostPolicy.multiplier(requested: 2, headroom: value) == 1, "Nonfinite EDR")
        }
        for state in [ProcessInfo.ThermalState.serious, .critical] {
            check(BoostPolicy.pauseReason(sleeping: false, sessionActive: true,
                thermalState: state, lowPower: false, pauseOnLowPower: false) != nil, "Thermal pause")
        }
        check(BoostPolicy.pauseReason(sleeping: true, sessionActive: true,
            thermalState: .nominal, lowPower: false, pauseOnLowPower: false) != nil, "Sleep pause")
        check(BoostPolicy.pauseReason(sleeping: false, sessionActive: false,
            thermalState: .nominal, lowPower: false, pauseOnLowPower: false) != nil, "Inactive session")
        check(BoostPolicy.pauseReason(sleeping: false, sessionActive: true,
            thermalState: .nominal, lowPower: true, pauseOnLowPower: true) != nil, "Low power pause")
        check(BoostPolicy.pauseReason(sleeping: false, sessionActive: true,
            thermalState: .fair, lowPower: true, pauseOnLowPower: false) == nil, "Low power opt out")
        print("PASS: \(assertions) brightness limit and pause policy checks")
    }
}
