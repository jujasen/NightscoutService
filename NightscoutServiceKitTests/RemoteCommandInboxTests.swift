//
//  RemoteCommandInboxTests.swift
//  NightscoutServiceKitTests
//

import LoopKit
import XCTest
@testable import NightscoutServiceKit

final class RemoteCommandInboxTests: XCTestCase {

    private let secret = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"
    private let sentAt = ISO8601DateFormatter.withFractionalSeconds.date(from: "2026-11-16T10:00:00.000Z")!

    private func payload(commandId: String = "A", units: Double = 0.5, sentAt: Date? = nil, lifetime: TimeInterval = 10 * 60) -> String {
        let sent = sentAt ?? self.sentAt
        let dict: [String: Any] = [
            "bolus-entry": units,
            "command-id": commandId,
            "remote-address": "LoopFollow",
            "entered-by": "LoopFollow",
            "sent-at": ISO8601DateFormatter.withFractionalSeconds.string(from: sent),
            "expiration": ISO8601DateFormatter.withFractionalSeconds.string(from: sent.addingTimeInterval(lifetime)),
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private func treatment(id: String = "ns1", commandId: String = "A", payload: String? = nil, signedWith key: String? = nil, status: String = "pending") -> [String: Any] {
        let payload = payload ?? self.payload(commandId: commandId)
        return [
            "_id": id,
            "eventType": "Remote Command",
            "created_at": "2026-11-16T10:00:00.000Z",
            "commandId": commandId,
            "payload": payload,
            "signature": InboxCommand.sign(payload: payload, secret: key ?? secret),
            "status": status,
        ]
    }

    // MARK: Validation

    func testSignatureMatchesLoopFollow() {
        // The same vector as LoopFollow's RemoteCommandInboxTests.testSignatureMatchesLoop.
        XCTAssertEqual(InboxCommand.sign(payload: #"{"bolus-entry":0.5,"command-id":"A"}"#, secret: secret), "LfRxQ+eCLDBWwMd1nSq0WOL6K2XHZkMyjZQhzgAyKhA=")
    }

    func testValidCommandGivesTheNotification() throws {
        let command = try XCTUnwrap(InboxCommand(treatment: treatment()))
        let notification = try command.validate(secret: secret, now: sentAt.addingTimeInterval(240))
        XCTAssertEqual(notification["bolus-entry"] as? Double, 0.5)
    }

    func testSignatureFromAnotherSecretIsRejected() throws {
        let command = try XCTUnwrap(InboxCommand(treatment: treatment(signedWith: "SOMETHINGELSE")))
        XCTAssertThrowsError(try command.validate(secret: secret, now: sentAt)) { error in
            XCTAssertEqual(error as? InboxRejection, .badSignature)
        }
    }

    func testChangedAmountBreaksTheSignature() throws {
        var t = treatment()
        t["payload"] = payload(units: 5)
        let command = try XCTUnwrap(InboxCommand(treatment: t))
        XCTAssertThrowsError(try command.validate(secret: secret, now: sentAt)) { error in
            XCTAssertEqual(error as? InboxRejection, .badSignature)
        }
    }

    func testPayloadReusedUnderAnotherIdIsRejected() throws {
        // A signed payload copied into a new treatment with a new commandId must not run again.
        let command = try XCTUnwrap(InboxCommand(treatment: treatment(commandId: "B", payload: payload(commandId: "A"))))
        XCTAssertThrowsError(try command.validate(secret: secret, now: sentAt)) { error in
            XCTAssertEqual(error as? InboxRejection, .unreadable)
        }
    }

    func testExpiredCommandIsRejected() throws {
        let command = try XCTUnwrap(InboxCommand(treatment: treatment()))
        XCTAssertThrowsError(try command.validate(secret: secret, now: sentAt.addingTimeInterval(10 * 60 + 1))) { error in
            XCTAssertEqual(error as? InboxRejection, .expired(sentAt: sentAt))
        }
    }

    func testLongLivedCommandIsRejected() throws {
        let command = try XCTUnwrap(InboxCommand(treatment: treatment(payload: payload(lifetime: 60 * 60))))
        XCTAssertThrowsError(try command.validate(secret: secret, now: sentAt)) { error in
            XCTAssertEqual(error as? InboxRejection, .badTimes)
        }
    }

    func testMissingSecretIsRejected() throws {
        let command = try XCTUnwrap(InboxCommand(treatment: treatment()))
        XCTAssertThrowsError(try command.validate(secret: nil, now: sentAt))
    }

    // MARK: Polling

    func testCommandIsCarriedOutOnceAndTheOutcomeWritten() async {
        let transport = FakeTransport(treatments: [treatment()])
        let store = MemoryStore()
        var executed = 0
        let inbox = makeInbox(transport: transport, store: store) { _ in executed += 1; return "Bolus 0.5 U" }

        await inbox.poll(force: true)
        await inbox.poll(force: true)

        XCTAssertEqual(executed, 1)
        XCTAssertEqual(transport.writtenStatuses, ["running", "done"])
        XCTAssertEqual(transport.treatments.first?["statusMessage"] as? String, "Bolus 0.5 U")
    }

    func testHandledCommandIsNotRunAgainEvenIfStillPending() async {
        // The write of the outcome failed, so Nightscout still says pending.
        let transport = FakeTransport(treatments: [treatment()])
        transport.keepPending = true
        let store = MemoryStore()
        var executed = 0
        let inbox = makeInbox(transport: transport, store: store) { _ in executed += 1; return "ok" }

        await inbox.poll(force: true)
        await inbox.poll(force: true)

        XCTAssertEqual(executed, 1)
    }

    func testNothingIsGivenWhenTheClaimCannotBeWritten() async {
        let transport = FakeTransport(treatments: [treatment()])
        transport.failWrites = true
        var executed = 0
        let inbox = makeInbox(transport: transport, store: MemoryStore()) { _ in executed += 1; return "ok" }

        await inbox.poll(force: true)

        XCTAssertEqual(executed, 0)
    }

    func testFailedCommandIsMarkedFailed() async {
        let transport = FakeTransport(treatments: [treatment()])
        let inbox = makeInbox(transport: transport, store: MemoryStore()) { _ in throw PumpManagerError.deviceState(nil) }

        await inbox.poll(force: true)

        XCTAssertEqual(transport.writtenStatuses, ["running", "failed"])
    }

    func testUncertainDeliveryIsMarkedUncertain() async {
        let transport = FakeTransport(treatments: [treatment()])
        let inbox = makeInbox(transport: transport, store: MemoryStore()) { _ in throw PumpManagerError.uncertainDelivery }

        await inbox.poll(force: true)

        XCTAssertEqual(transport.writtenStatuses, ["running", "uncertain"])
    }

    func testARefusalWithDetailsIsMarkedRejectedAndTheDetailsWritten() async {
        // Loop stopped the bolus: someone gave a dose on the phone that the sender had not seen.
        struct Stopped: LocalizedError, RemoteActionRejection {
            var errorDescription: String? { "Nothing was given" }
            var remoteActionDetails: [String: Any] {
                ["reason": "unknownDoses", "doses": [["date": "2026-11-16T09:58:00.000Z", "units": 0.5, "source": "phone"]]]
            }
        }
        let transport = FakeTransport(treatments: [treatment()])
        let inbox = makeInbox(transport: transport, store: MemoryStore()) { _ in throw Stopped() }

        await inbox.poll(force: true)

        XCTAssertEqual(transport.writtenStatuses, ["running", "rejected"])
        XCTAssertEqual(transport.treatments.first?["statusMessage"] as? String, "Nothing was given")
        let details = transport.treatments.first?["statusDetails"] as? [String: Any]
        XCTAssertEqual(details?["reason"] as? String, "unknownDoses")
        XCTAssertEqual((details?["doses"] as? [[String: Any]])?.first?["units"] as? Double, 0.5)
    }

    func testABolusSaysWhichDosesItsSenderHadSeen() throws {
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload().utf8)) as? [String: AnyObject])
        dict["known-doses-until"] = "2026-11-16T09:41:07.250Z" as AnyObject
        guard case .bolusEntry(let bolus) = try dict.toRemoteNotification().toRemoteAction() else { return XCTFail("Not a bolus") }
        XCTAssertEqual(bolus.amountInUnits, 0.5)
        XCTAssertEqual(bolus.knownDosesUntil, ISO8601DateFormatter.withFractionalSeconds.date(from: "2026-11-16T09:41:07.250Z"))
    }

    func testABolusFromAnOlderSenderSaysNothingAboutDoses() throws {
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload().utf8)) as? [String: AnyObject])
        guard case .bolusEntry(let bolus) = try dict.toRemoteNotification().toRemoteAction() else { return XCTFail("Not a bolus") }
        XCTAssertNil(bolus.knownDosesUntil)
    }

    func testExpiredCommandIsMarkedRejectedWithoutRunning() async {
        let transport = FakeTransport(treatments: [treatment()])
        var executed = 0
        let inbox = makeInbox(transport: transport, store: MemoryStore(), now: sentAt.addingTimeInterval(11 * 60)) { _ in executed += 1; return "ok" }

        await inbox.poll(force: true)

        XCTAssertEqual(executed, 0)
        XCTAssertEqual(transport.writtenStatuses, ["rejected"])
    }

    func testPollsAreSpacedUnlessForced() async {
        let transport = FakeTransport(treatments: [])
        let inbox = makeInbox(transport: transport, store: MemoryStore()) { _ in "ok" }

        await inbox.poll(force: false)
        await inbox.poll(force: false)
        XCTAssertEqual(transport.fetches, 1)

        await inbox.poll(force: true)
        XCTAssertEqual(transport.fetches, 2)
    }

    func testOldestCommandRunsFirst() async {
        var later = treatment(id: "ns2", commandId: "B", payload: payload(commandId: "B"))
        later["created_at"] = "2026-11-16T10:01:00.000Z"
        let transport = FakeTransport(treatments: [later, treatment()])
        var order: [String] = []
        let inbox = makeInbox(transport: transport, store: MemoryStore()) { notification in
            order.append(notification["command-id"] as? String ?? "")
            return "ok"
        }

        await inbox.poll(force: true)

        XCTAssertEqual(order, ["A", "B"])
    }

    // MARK: Helpers

    private func makeInbox(transport: FakeTransport, store: MemoryStore, now: Date? = nil, execute: @escaping RemoteCommandInbox.Execute) -> RemoteCommandInbox {
        let now = now ?? sentAt.addingTimeInterval(60)
        let secret = self.secret
        return RemoteCommandInbox(transport: { transport }, secret: { secret }, store: store, now: { now }, execute: execute)
    }
}

private final class FakeTransport: RemoteCommandInboxTransport {
    var treatments: [[String: Any]]
    var writtenStatuses: [String] = []
    var fetches = 0
    var failWrites = false
    var keepPending = false

    init(treatments: [[String: Any]]) {
        self.treatments = treatments
    }

    func fetchPending(since: Date) async throws -> [[String: Any]] {
        fetches += 1
        return treatments.filter { $0["status"] as? String == "pending" }
    }

    func replace(_ treatment: [String: Any]) async throws {
        if failWrites { throw URLError(.notConnectedToInternet) }
        writtenStatuses.append(treatment["status"] as? String ?? "")
        guard !keepPending else { return }
        if let index = treatments.firstIndex(where: { $0["_id"] as? String == treatment["_id"] as? String }) {
            treatments[index] = treatment
        }
    }
}

private final class MemoryStore: RemoteCommandHandledStore {
    var handled: [String: Date] = [:]
    func wasHandled(_ commandId: String) -> Bool { handled[commandId] != nil }
    func markHandled(_ commandId: String, at date: Date) { handled[commandId] = date }
}
