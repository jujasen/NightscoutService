//
//  MealBolusRemoteNotificationTestCase.swift
//  NightscoutServiceKitTests
//
//  A meal with its bolus in one command: how it is read, and what is written back.
//

import LoopKit
import XCTest
@testable import NightscoutServiceKit

final class MealBolusRemoteNotificationTestCase: XCTestCase {

    private let secret = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"
    private let sentAt = "2026-11-25T12:00:00.000Z"
    private let expiration = "2026-11-25T12:10:00.000Z"

    private func notification(_ keys: [String: Any]) -> [String: AnyObject] {
        var dict: [String: Any] = [
            "remote-address": "LoopFollow",
            "entered-by": "LoopFollow",
            "sent-at": sentAt,
            "expiration": expiration,
        ]
        dict.merge(keys) { _, new in new }
        // Through JSON, as the inbox reads it.
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONSerialization.jsonObject(with: data) as! [String: AnyObject]
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter.withFractionalSeconds.date(from: string)!
    }

    // MARK: Reading the command

    func testOnlyMealKeysMakeAMealWithBolus() throws {
        let parsed = try notification(["meal-carbs": 45, "meal-bolus": 3.25]).toRemoteNotification()
        XCTAssertTrue(parsed is MealBolusRemoteNotification)
        guard case .mealBolus(let action) = parsed.toRemoteAction() else { return XCTFail("Not a meal with bolus") }
        XCTAssertEqual(action.amountInGrams, 45)
        XCTAssertEqual(action.bolusInUnits, 3.25)
        XCTAssertNil(action.absorptionTime)
        XCTAssertNil(action.foodType)
        XCTAssertNil(action.startDate)
        XCTAssertNil(action.knownDosesUntil)
        // Missing counts as following Loop's recommendation: never more than Loop's own.
        XCTAssertTrue(action.followsRecommendation)
    }

    func testEveryKeyIsRead() throws {
        let parsed = try notification([
            "meal-carbs": 45,
            "meal-absorption-time": 3.5,
            "meal-food-type": "🍕 Pizza",
            "meal-start-time": "2026-11-25T11:55:00.000Z",
            "meal-bolus": 3.25,
            "meal-bolus-follows-recommendation": false,
            "known-doses-until": "2026-11-25T11:41:07.250Z",
            "command-id": "A",
        ]).toRemoteNotification()
        guard case .mealBolus(let action) = parsed.toRemoteAction() else { return XCTFail("Not a meal with bolus") }
        XCTAssertEqual(action.amountInGrams, 45)
        XCTAssertEqual(action.absorptionTime, .hours(3.5))
        XCTAssertEqual(action.foodType, "🍕 Pizza")
        XCTAssertEqual(action.startDate, date("2026-11-25T11:55:00.000Z"))
        XCTAssertEqual(action.bolusInUnits, 3.25)
        XCTAssertFalse(action.followsRecommendation)
        XCTAssertEqual(action.knownDosesUntil, date("2026-11-25T11:41:07.250Z"))

        let mealBolus = action.mealBolus
        XCTAssertEqual(mealBolus.carbsInGrams, 45)
        XCTAssertEqual(mealBolus.approvedUnits, 3.25)
        XCTAssertFalse(mealBolus.followsRecommendation)
    }

    func testMealKeysWithABolusEntryAreNeverAPlainBolus() {
        XCTAssertThrowsError(try notification(["meal-carbs": 45, "meal-bolus": 3, "bolus-entry": 3]).toRemoteNotification()) { error in
            XCTAssertFalse(error is DecodingError)
        }
        XCTAssertThrowsError(try notification(["meal-carbs": 45, "bolus-entry": 3]).toRemoteNotification())
    }

    func testCarbsAndBolusInTheOldKeysAreNeverAPlainBolus() {
        XCTAssertThrowsError(try notification(["carbs-entry": 45, "bolus-entry": 3]).toRemoteNotification())
    }

    func testMealKeysWithACarbsEntryAreRejected() {
        XCTAssertThrowsError(try notification(["meal-carbs": 45, "meal-bolus": 3, "carbs-entry": 45]).toRemoteNotification())
    }

    func testAMealWithoutItsBolusIsUnreadable() {
        // Never taken for carbs alone.
        XCTAssertThrowsError(try notification(["meal-carbs": 45]).toRemoteNotification())
    }

    func testPlainCommandsAreReadAsBefore() throws {
        XCTAssertTrue(try notification(["bolus-entry": 0.5]).toRemoteNotification() is BolusRemoteNotification)
        XCTAssertTrue(try notification(["carbs-entry": 20]).toRemoteNotification() is CarbRemoteNotification)
    }

    func testLoopSaysItTakesAMealWithBolus() {
        XCTAssertEqual(RemoteCommandInbox.advertisedCommands, ["mealBolus"])
    }

    // MARK: What is written back

    private let action = MealBolusAction(amountInGrams: 45, bolusInUnits: 3.25, followsRecommendation: true, knownDosesUntil: Date(timeIntervalSince1970: 1_795_000_000))

    private func outcome(carbsSaved: Bool, recommended: Double? = 3.2, delivered: Double) -> RemoteMealBolusOutcome {
        RemoteMealBolusOutcome(carbsSaved: carbsSaved, carbsInGrams: 45, approvedUnits: 3.25, recommendedUnits: recommended, deliveredUnits: delivered)
    }

    func testDetailsAreWrittenOnSuccess() async throws {
        var received: RemoteMealBolus?
        let result = try await action.carryOut { mealBolus in
            received = mealBolus
            return self.outcome(carbsSaved: true, delivered: 3.2)
        }
        XCTAssertEqual(received, action.mealBolus)
        let details = try XCTUnwrap(result.details)
        XCTAssertEqual(details["kind"] as? String, "mealBolus")
        XCTAssertEqual(details["carbsSaved"] as? Bool, true)
        XCTAssertEqual(details["carbs"] as? Double, 45)
        XCTAssertEqual(details["approvedUnits"] as? Double, 3.25)
        XCTAssertEqual(details["recommendedUnits"] as? Double, 3.2)
        XCTAssertEqual(details["deliveredUnits"] as? Double, 3.2)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(details))
    }

    func testNoBolusNeededIsDoneWithZeroDelivered() async throws {
        let result = try await action.carryOut { _ in self.outcome(carbsSaved: true, recommended: 0, delivered: 0) }
        XCTAssertEqual(result.details?["deliveredUnits"] as? Double, 0)
        XCTAssertEqual(result.details?["recommendedUnits"] as? Double, 0)
        XCTAssertEqual(result.details?["carbsSaved"] as? Bool, true)
    }

    func testAMissingRecommendationIsLeftOut() async throws {
        let result = try await action.carryOut { _ in self.outcome(carbsSaved: true, recommended: nil, delivered: 3.25) }
        XCTAssertNil(result.details?["recommendedUnits"])
    }

    func testBolusFailureAfterTheCarbsWereSavedIsFailedWithCarbsSaved() async {
        do {
            _ = try await action.carryOut { _ in
                throw RemoteMealBolusError(outcome: self.outcome(carbsSaved: true, delivered: 0), underlyingError: PumpManagerError.communication(nil))
            }
            XCTFail("Should fail")
        } catch let failure as InboxFailure {
            XCTAssertEqual(failure.status, .failed)
            XCTAssertEqual(failure.details?["carbsSaved"] as? Bool, true)
            XCTAssertEqual(failure.details?["deliveredUnits"] as? Double, 0)
            XCTAssertTrue(failure.message.contains("45"))
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testUncertainBolusAfterTheCarbsWereSavedIsUncertain() async {
        do {
            _ = try await action.carryOut { _ in
                throw RemoteMealBolusError(outcome: self.outcome(carbsSaved: true, delivered: 3.2), underlyingError: PumpManagerError.uncertainDelivery)
            }
            XCTFail("Should fail")
        } catch let failure as InboxFailure {
            XCTAssertEqual(failure.status, .uncertain)
            XCTAssertEqual(failure.details?["carbsSaved"] as? Bool, true)
            XCTAssertEqual(failure.details?["deliveredUnits"] as? Double, 3.2)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    private struct Stopped: LocalizedError, RemoteActionRejection {
        var errorDescription: String? { "Nothing was given" }
        var remoteActionDetails: [String: Any] { ["reason": "unknownDoses", "doses": [["units": 0.5, "source": "phone"]]] }
    }

    func testARefusalBeforeAnythingWasSavedIsRejectedWithItsReason() async {
        do {
            _ = try await action.carryOut { _ in
                throw RemoteMealBolusError(outcome: self.outcome(carbsSaved: false, recommended: nil, delivered: 0), underlyingError: Stopped())
            }
            XCTFail("Should fail")
        } catch let failure as InboxFailure {
            XCTAssertEqual(failure.status, .rejected)
            XCTAssertEqual(failure.message, "Nothing was given")
            XCTAssertEqual(failure.details?["kind"] as? String, "mealBolus")
            XCTAssertEqual(failure.details?["carbsSaved"] as? Bool, false)
            XCTAssertEqual(failure.details?["reason"] as? String, "unknownDoses")
            XCTAssertNotNil(failure.details?["doses"])
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testARefusalAfterTheCarbsWereSavedIsFailedNotRejected() async {
        // A dose given on the phone in the seconds between saving the carbs and the bolus.
        do {
            _ = try await action.carryOut { _ in
                throw RemoteMealBolusError(outcome: self.outcome(carbsSaved: true, delivered: 0), underlyingError: Stopped())
            }
            XCTFail("Should fail")
        } catch let failure as InboxFailure {
            XCTAssertEqual(failure.status, .failed)
            XCTAssertEqual(failure.details?["carbsSaved"] as? Bool, true)
            XCTAssertEqual(failure.details?["reason"] as? String, "unknownDoses")
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testAnyOtherErrorSaysNothingWasSaved() async {
        do {
            _ = try await action.carryOut { _ in throw URLError(.timedOut) }
            XCTFail("Should fail")
        } catch let failure as InboxFailure {
            XCTAssertEqual(failure.status, .failed)
            XCTAssertEqual(failure.details?["carbsSaved"] as? Bool, false)
            XCTAssertEqual(failure.details?["deliveredUnits"] as? Double, 0)
            XCTAssertEqual(failure.details?["approvedUnits"] as? Double, 3.25)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    // MARK: Through the inbox

    private func treatment(_ keys: [String: Any]) -> [String: Any] {
        var dict: [String: Any] = ["command-id": "M", "remote-address": "LoopFollow", "sent-at": sentAt, "expiration": expiration]
        dict.merge(keys) { _, new in new }
        let payload = String(data: try! JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]), encoding: .utf8)!
        return [
            "_id": "ns1",
            "eventType": "Remote Command",
            "created_at": sentAt,
            "commandId": "M",
            "payload": payload,
            "signature": InboxCommand.sign(payload: payload, secret: secret),
            "status": "pending",
        ]
    }

    private func inbox(_ transport: MealFakeTransport, deliver: @escaping (RemoteMealBolus) async throws -> RemoteMealBolusOutcome) -> RemoteCommandInbox {
        let secret = self.secret
        let now = date(sentAt).addingTimeInterval(60)
        return RemoteCommandInbox(transport: { transport }, secret: { secret }, store: MealMemoryStore(), now: { now }) { notification in
            guard case .mealBolus(let action) = try notification.toRemoteNotification().toRemoteAction() else {
                throw InboxRejection.unreadable
            }
            return try await action.carryOut(with: deliver)
        }
    }

    func testTheInboxWritesTheDetailsOfADoneMeal() async {
        let transport = MealFakeTransport(treatments: [treatment(["meal-carbs": 45, "meal-bolus": 3.25, "meal-bolus-follows-recommendation": true])])
        let inbox = inbox(transport) { _ in self.outcome(carbsSaved: true, delivered: 3.2) }

        await inbox.poll(force: true)

        XCTAssertEqual(transport.writtenStatuses, ["running", "done"])
        let details = transport.treatments.first?["statusDetails"] as? [String: Any]
        XCTAssertEqual(details?["kind"] as? String, "mealBolus")
        XCTAssertEqual(details?["deliveredUnits"] as? Double, 3.2)
        XCTAssertNotNil(transport.treatments.first?["statusMessage"] as? String)
    }

    func testTheInboxMarksAFailedBolusAfterSavedCarbsAsFailedWithCarbsSaved() async {
        let transport = MealFakeTransport(treatments: [treatment(["meal-carbs": 45, "meal-bolus": 3.25])])
        let inbox = inbox(transport) { _ in
            throw RemoteMealBolusError(outcome: self.outcome(carbsSaved: true, delivered: 0), underlyingError: PumpManagerError.deviceState(nil))
        }

        await inbox.poll(force: true)

        XCTAssertEqual(transport.writtenStatuses, ["running", "failed"])
        let details = transport.treatments.first?["statusDetails"] as? [String: Any]
        XCTAssertEqual(details?["carbsSaved"] as? Bool, true)
    }

    func testTheInboxCarriesAMealOutOnce() async {
        let transport = MealFakeTransport(treatments: [treatment(["meal-carbs": 45, "meal-bolus": 3.25])])
        transport.keepPending = true
        var calls = 0
        let inbox = inbox(transport) { _ in
            calls += 1
            return self.outcome(carbsSaved: true, delivered: 3.2)
        }

        await inbox.poll(force: true)
        await inbox.poll(force: true)

        XCTAssertEqual(calls, 1)
    }
}

private final class MealFakeTransport: RemoteCommandInboxTransport {
    var treatments: [[String: Any]]
    var writtenStatuses: [String] = []
    var keepPending = false

    init(treatments: [[String: Any]]) {
        self.treatments = treatments
    }

    func fetchPending(since: Date) async throws -> [[String: Any]] {
        treatments.filter { $0["status"] as? String == "pending" }
    }

    func replace(_ treatment: [String: Any]) async throws {
        writtenStatuses.append(treatment["status"] as? String ?? "")
        guard !keepPending else { return }
        if let index = treatments.firstIndex(where: { $0["_id"] as? String == treatment["_id"] as? String }) {
            treatments[index] = treatment
        }
    }
}

private final class MealMemoryStore: RemoteCommandHandledStore {
    var handled: [String: Date] = [:]
    func wasHandled(_ commandId: String) -> Bool { handled[commandId] != nil }
    func markHandled(_ commandId: String, at date: Date) { handled[commandId] = date }
}
