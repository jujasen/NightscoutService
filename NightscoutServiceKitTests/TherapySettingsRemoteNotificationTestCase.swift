//
//  TherapySettingsRemoteNotificationTestCase.swift
//  NightscoutServiceKitTests
//

import XCTest
import HealthKit
import LoopKit
@testable import NightscoutServiceKit

final class TherapySettingsRemoteNotificationTestCase: XCTestCase {

    func testParse_BothSchedules_Succeeds() throws {
        let notification: [String: Any] = [
            "remote-address": "LoopFollow",
            "sent-at": "2026-09-23T20:46:35.778Z",
            "expiration": "2026-09-23T20:51:35.778Z",
            "otp": "123456",
            "therapy-settings": [
                "carb-ratio": [["start": 0, "value": 12], ["start": 21600, "value": 10.5]],
                "insulin-sensitivity": [["start": 0, "value": 9.5]],
                "insulin-sensitivity-unit": "mmol/L"
            ]
        ]

        let parsed = try (notification as! [String: AnyObject]).toRemoteNotification()
        XCTAssertTrue(parsed is TherapySettingsRemoteNotification)
        XCTAssertTrue(parsed.otpValidationRequired())

        guard case .therapySettings(let action) = parsed.toRemoteAction() else {
            return XCTFail("Expected a therapy settings action")
        }
        let change = try action.change()
        XCTAssertEqual(change.carbRatioItems, [
            RepeatingScheduleValue(startTime: 0, value: 12),
            RepeatingScheduleValue(startTime: .hours(6), value: 10.5)
        ])
        XCTAssertEqual(change.insulinSensitivityItems, [RepeatingScheduleValue(startTime: 0, value: 9.5)])
        XCTAssertEqual(change.insulinSensitivityUnit, .millimolesPerLiter)
    }

    func testParse_CarbRatioOnly_LeavesSensitivityAlone() throws {
        let action = TherapySettingsAction(carbRatio: [.init(start: 0, value: 15)], insulinSensitivity: nil, insulinSensitivityUnit: nil)
        let change = try action.change()
        XCTAssertNil(change.insulinSensitivityItems)
        XCTAssertNil(change.insulinSensitivityUnit)
    }

    func testChange_ScheduleNotStartingAtMidnight_Throws() {
        let action = TherapySettingsAction(carbRatio: [.init(start: 3600, value: 15)], insulinSensitivity: nil, insulinSensitivityUnit: nil)
        XCTAssertThrowsError(try action.change()) { error in
            XCTAssertEqual(error as? RemoteTherapySettingsError, .invalidSchedule)
        }
    }

    func testChange_TimesOutOfOrder_Throws() {
        let action = TherapySettingsAction(carbRatio: [.init(start: 0, value: 15), .init(start: 7200, value: 12), .init(start: 3600, value: 10)], insulinSensitivity: nil, insulinSensitivityUnit: nil)
        XCTAssertThrowsError(try action.change())
    }

    func testChange_SensitivityWithoutUnit_Throws() {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: [.init(start: 0, value: 9)], insulinSensitivityUnit: nil)
        XCTAssertThrowsError(try action.change()) { error in
            XCTAssertEqual(error as? RemoteTherapySettingsError, .unsupportedGlucoseUnit)
        }
    }

    func testChange_Empty_Throws() {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil)
        XCTAssertThrowsError(try action.change()) { error in
            XCTAssertEqual(error as? RemoteTherapySettingsError, .nothingToChange)
        }
    }

    func testChange_MilligramsUnit_IsRecognized() throws {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: [.init(start: 0, value: 180)], insulinSensitivityUnit: "mg/dL")
        XCTAssertEqual(try action.change().insulinSensitivityUnit, .milligramsPerDeciliter)
    }

    func testChange_UnknownUnit_Throws() {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: [.init(start: 0, value: 9)], insulinSensitivityUnit: "mmol")
        XCTAssertThrowsError(try action.change())
    }

    // MARK: - v2 settings

    func testParse_EveryV2Key_Succeeds() throws {
        let notification: [String: Any] = [
            "remote-address": "LoopFollow",
            "sent-at": "2026-10-01T08:00:00.000Z",
            "expiration": "2026-10-01T08:05:00.000Z",
            "otp": "123456",
            "therapy-settings": [
                "glucose-unit": "mmol/L",
                "basal-rate": [["start": 0, "value": 0.35], ["start": 1800, "value": 0.4]],
                "correction-range": [["start": 0, "low": 5.5, "high": 6.5], ["start": 79200, "low": 6, "high": 7]],
                "pre-meal-range": ["low": 4.5, "high": 5],
                "workout-range": ["low": 8, "high": 9],
                "suspend-threshold": 4.2,
                "maximum-basal-rate": 1.5,
                "maximum-bolus": 2.5,
                "insulin-model": "rapidActingChild",
                "dosing-strategy": "automaticBolus",
                "closed-loop": false,
                "override-presets": [
                    ["name": "Sick", "symbol": "🤒", "duration": 0, "insulin-needs-scale-factor": 1.3, "target-low": 6, "target-high": 7],
                    ["name": "Nap", "symbol": "😴", "duration": 7200]
                ],
                "glucose-based-partial-application": true,
                "integral-retrospective-correction": false
            ]
        ]

        let parsed = try (notification as! [String: AnyObject]).toRemoteNotification()
        XCTAssertTrue(parsed is TherapySettingsRemoteNotification)
        XCTAssertTrue(parsed.otpValidationRequired())

        guard case .therapySettings(let action) = parsed.toRemoteAction() else {
            return XCTFail("Expected a therapy settings action")
        }
        let change = try action.change()
        XCTAssertEqual(change.glucoseUnit, .millimolesPerLiter)
        XCTAssertEqual(change.basalRateItems, [RepeatingScheduleValue(startTime: 0, value: 0.35), RepeatingScheduleValue(startTime: .minutes(30), value: 0.4)])
        XCTAssertEqual(change.correctionRangeItems, [
            RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 5.5, maxValue: 6.5)),
            RepeatingScheduleValue(startTime: .hours(22), value: DoubleRange(minValue: 6, maxValue: 7))
        ])
        XCTAssertEqual(change.preMealTargetRange, DoubleRange(minValue: 4.5, maxValue: 5))
        XCTAssertEqual(change.workoutTargetRange, DoubleRange(minValue: 8, maxValue: 9))
        XCTAssertEqual(change.suspendThreshold, 4.2)
        XCTAssertEqual(change.maximumBasalRatePerHour, 1.5)
        XCTAssertEqual(change.maximumBolus, 2.5)
        XCTAssertEqual(change.insulinModel, .rapidActingChild)
        XCTAssertEqual(change.dosingStrategy, .automaticBolus)
        XCTAssertEqual(change.closedLoop, false)
        XCTAssertEqual(change.overridePresets, [
            RemoteTherapySettingsChange.OverridePreset(name: "Sick", symbol: "🤒", duration: 0, insulinNeedsScaleFactor: 1.3, targetRange: DoubleRange(minValue: 6, maxValue: 7)),
            RemoteTherapySettingsChange.OverridePreset(name: "Nap", symbol: "😴", duration: .hours(2), insulinNeedsScaleFactor: 1.0, targetRange: nil)
        ])
        XCTAssertEqual(change.glucoseBasedPartialApplication, true)
        XCTAssertEqual(change.integralRetrospectiveCorrection, false)
        XCTAssertNil(change.carbRatioItems)
        XCTAssertNil(change.insulinSensitivityItems)
        XCTAssertFalse(change.onlyChangesCarbRatioOrInsulinSensitivity)

        let description = parsed.toRemoteAction().actionParameterDescription
        XCTAssertTrue(description.contains("Basal Rates"))
        XCTAssertTrue(description.contains("Override Presets"))
        XCTAssertFalse(description.contains("Carb Ratios"))
    }

    func testChange_V1Only_IsOnlyCarbRatioOrSensitivity() throws {
        let action = TherapySettingsAction(carbRatio: [.init(start: 0, value: 15)], insulinSensitivity: nil, insulinSensitivityUnit: nil)
        XCTAssertTrue(try action.change().onlyChangesCarbRatioOrInsulinSensitivity)
        XCTAssertEqual(Action.therapySettings(action).actionParameterDescription, "Carb Ratios")
    }

    func testChange_SingleSetting_Succeeds() throws {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, maximumBolus: 3)
        let change = try action.change()
        XCTAssertEqual(change.maximumBolus, 3)
        XCTAssertNil(change.glucoseUnit)
        XCTAssertEqual(Action.therapySettings(action).actionParameterDescription, "Maximum Bolus")
    }

    func testChange_OnlyBooleans_Succeeds() throws {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, closedLoop: true, integralRetrospectiveCorrection: true)
        let change = try action.change()
        XCTAssertEqual(change.closedLoop, true)
        XCTAssertEqual(change.integralRetrospectiveCorrection, true)
        XCTAssertNil(change.glucoseBasedPartialApplication)
    }

    func testChange_GlucoseSettingWithoutUnit_Throws() {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, suspendThreshold: 4.0)
        XCTAssertThrowsError(try action.change()) { error in
            XCTAssertEqual(error as? RemoteTherapySettingsError, .unsupportedGlucoseUnit)
        }
    }

    func testChange_OverrideTargetWithoutUnit_Throws() {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil,
                                           overridePresets: [.init(name: "Sick", symbol: "🤒", duration: 0, targetLow: 6, targetHigh: 7)])
        XCTAssertThrowsError(try action.change()) { error in
            XCTAssertEqual(error as? RemoteTherapySettingsError, .unsupportedGlucoseUnit)
        }
    }

    func testChange_OverrideWithoutTargetNeedsNoUnit() throws {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil,
                                           overridePresets: [.init(name: "Sick", symbol: "🤒", duration: 0, insulinNeedsScaleFactor: 1.2)])
        XCTAssertEqual(try action.change().overridePresets?.first?.insulinNeedsScaleFactor, 1.2)
    }

    func testChange_OverrideWithHalfTarget_Throws() {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, glucoseUnit: "mg/dL",
                                           overridePresets: [.init(name: "Sick", symbol: "🤒", duration: 0, targetLow: 110)])
        XCTAssertThrowsError(try action.change()) { error in
            XCTAssertEqual(error as? RemoteTherapySettingsError, .incompleteOverrideTargetRange("Sick"))
        }
    }

    func testChange_EmptyOverrideList_IsAllowed() throws {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, overridePresets: [])
        XCTAssertEqual(try action.change().overridePresets, [])
    }

    func testChange_UnknownInsulinModel_Throws() {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, insulinModel: "novolog")
        XCTAssertThrowsError(try action.change()) { error in
            XCTAssertEqual(error as? RemoteTherapySettingsError, .unknownInsulinModel("novolog"))
        }
    }

    func testChange_EveryInsulinModel_IsRecognized() throws {
        let expected: [String: ExponentialInsulinModelPreset] = [
            "rapidActingAdult": .rapidActingAdult, "rapidActingChild": .rapidActingChild, "fiasp": .fiasp, "lyumjev": .lyumjev, "afrezza": .afrezza
        ]
        for (name, model) in expected {
            let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, insulinModel: name)
            XCTAssertEqual(try action.change().insulinModel, model)
        }
    }

    func testChange_DosingStrategies_AreRecognized() throws {
        let tempBasal = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, dosingStrategy: "tempBasalOnly")
        XCTAssertEqual(try tempBasal.change().dosingStrategy, .tempBasalOnly)
        let unknown = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, dosingStrategy: "1")
        XCTAssertThrowsError(try unknown.change()) { error in
            XCTAssertEqual(error as? RemoteTherapySettingsError, .unknownDosingStrategy("1"))
        }
    }

    func testChange_BasalScheduleNotStartingAtMidnight_Throws() {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, basalRate: [.init(start: 1800, value: 0.3)])
        XCTAssertThrowsError(try action.change()) { error in
            XCTAssertEqual(error as? RemoteTherapySettingsError, .invalidSchedule)
        }
    }

    func testChange_CorrectionRangeWithTooManyRows_Throws() {
        let items = (0..<49).map { TherapySettingsAction.RangeScheduleItem(start: TimeInterval($0 * 60), low: 100, high: 110) }
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, glucoseUnit: "mg/dL", correctionRange: items)
        XCTAssertThrowsError(try action.change()) { error in
            XCTAssertEqual(error as? RemoteTherapySettingsError, .invalidSchedule)
        }
    }

    func testChange_SensitivityFallsBackToGlucoseUnit() throws {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: [.init(start: 0, value: 9)], insulinSensitivityUnit: nil, glucoseUnit: "mmol/L")
        XCTAssertEqual(try action.change().insulinSensitivityUnit, .millimolesPerLiter)
    }

    func testChange_GlucoseUnitWithoutGlucoseSetting_IsDropped() throws {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, glucoseUnit: "mg/dL", maximumBolus: 2)
        XCTAssertNil(try action.change().glucoseUnit)
    }

    func testChange_NonFiniteValue_Throws() {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, maximumBasalRate: .infinity)
        XCTAssertThrowsError(try action.change()) { error in
            XCTAssertEqual(error as? RemoteTherapySettingsError, .invalidValue)
        }
    }

    func testEncodeDecode_RoundTrips() throws {
        let action = TherapySettingsAction(carbRatio: nil, insulinSensitivity: nil, insulinSensitivityUnit: nil, glucoseUnit: "mg/dL",
                                           correctionRange: [.init(start: 0, low: 100, high: 110)], preMealRange: .init(low: 80, high: 90),
                                           overridePresets: [.init(name: "Sick", symbol: "🤒", duration: 0, insulinNeedsScaleFactor: 1.3, targetLow: 110, targetHigh: 120)])
        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["correction-range"])
        XCTAssertNotNil(json["pre-meal-range"])
        XCTAssertEqual((json["override-presets"] as? [[String: Any]])?.first?["insulin-needs-scale-factor"] as? Double, 1.3)
        XCTAssertEqual(try JSONDecoder().decode(TherapySettingsAction.self, from: data), action)
    }
}
