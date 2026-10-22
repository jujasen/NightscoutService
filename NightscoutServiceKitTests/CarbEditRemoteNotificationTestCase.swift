//
//  CarbEditRemoteNotificationTestCase.swift
//  NightscoutServiceKitTests
//

import XCTest
import LoopKit
@testable import NightscoutServiceKit

final class CarbEditRemoteNotificationTestCase: XCTestCase {

    func testParse_Edit_Succeeds() throws {
        let notification: [String: Any] = [
            "remote-address": "LoopFollow",
            "sent-at": "2026-10-22T12:46:35.778Z",
            "expiration": "2026-10-22T12:51:35.778Z",
            "otp": "123456",
            "carbs-edit": [
                "sync-identifier": "ABC-123",
                "carbs": 40.5,
                "absorption-time": 3.5,
                "food-type": "🍕 Pizza",
                "start-time": "2026-10-22T12:30:00.000Z"
            ]
        ]

        let parsed = try (notification as! [String: AnyObject]).toRemoteNotification()
        XCTAssertTrue(parsed is CarbEditRemoteNotification)
        XCTAssertTrue(parsed.otpValidationRequired())

        guard case .carbsEdit(let action) = parsed.toRemoteAction() else {
            return XCTFail("Expected a carb edit action")
        }
        let edit = try action.edit()
        XCTAssertEqual(edit.syncIdentifier, "ABC-123")
        XCTAssertEqual(edit.amountInGrams, 40.5)
        XCTAssertEqual(edit.absorptionTime, .hours(3.5))
        XCTAssertEqual(edit.foodType, "🍕 Pizza")
        XCTAssertEqual(edit.startDate, ISO8601DateFormatter().date(from: "2026-10-22T12:30:00Z"))
        XCTAssertFalse(edit.delete)
    }

    func testParse_OnlyAmount_KeepsTheRest() throws {
        let edit = try CarbEditAction(syncIdentifier: "ABC-123", amountInGrams: 25).edit()
        XCTAssertEqual(edit.amountInGrams, 25)
        XCTAssertNil(edit.absorptionTime)
        XCTAssertNil(edit.foodType)
        XCTAssertNil(edit.startDate)
    }

    func testParse_Delete_IgnoresValues() throws {
        let notification: [String: Any] = [
            "remote-address": "LoopFollow",
            "otp": "123456",
            "carbs-edit": ["sync-identifier": "ABC-123", "delete": true, "carbs": 10]
        ]

        let parsed = try (notification as! [String: AnyObject]).toRemoteNotification()
        guard case .carbsEdit(let action) = parsed.toRemoteAction() else {
            return XCTFail("Expected a carb edit action")
        }
        let edit = try action.edit()
        XCTAssertTrue(edit.delete)
        XCTAssertNil(edit.amountInGrams)
    }

    func testEdit_NothingToChange_Throws() {
        XCTAssertThrowsError(try CarbEditAction(syncIdentifier: "ABC-123").edit()) { error in
            XCTAssertEqual(error as? RemoteCarbEditError, .nothingToChange)
        }
    }

    func testEdit_MissingSyncIdentifier_Throws() {
        XCTAssertThrowsError(try CarbEditAction(syncIdentifier: "", delete: true).edit()) { error in
            XCTAssertEqual(error as? RemoteCarbEditError, .missingSyncIdentifier)
        }
    }

    func testNewCarbEntry_IsNotAnEdit() throws {
        let notification: [String: Any] = [
            "remote-address": "LoopFollow",
            "otp": "123456",
            "carbs-entry": 15.0
        ]
        let parsed = try (notification as! [String: AnyObject]).toRemoteNotification()
        XCTAssertTrue(parsed is CarbRemoteNotification)
    }
}
