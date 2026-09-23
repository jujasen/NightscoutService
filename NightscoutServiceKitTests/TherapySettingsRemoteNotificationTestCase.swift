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
}
