//
//  RemoteCommandInbox.swift
//  NightscoutServiceKit
//
//  Remote commands that wait in Nightscout until Loop fetches them.
//

import CryptoKit
import Foundation
import LoopKit
import OSLog

/// A remote command left in Nightscout as a treatment for Loop to fetch.
///
/// A push only reaches Loop when iOS lets it, and iOS often holds a background push until someone
/// opens the app. Loop runs every five minutes anyway, so it looks in Nightscout on every run (and at
/// once when a push arrives, which is then only a nudge), carries each command out at most once, and
/// writes the outcome back into the same treatment. That is how the sender learns what happened.
///
/// The treatment:
/// - `eventType`: "Remote Command"
/// - `commandId`: a UUID chosen by the sender
/// - `payload`: the command as a JSON string, with the keys of a V1 push (`bolus-entry`, `sent-at`,
///   `expiration`, …) and `command-id` repeated, so the signature covers the id
/// - `signature`: base64 HMAC-SHA256 of the payload's UTF-8 bytes, keyed with the UTF-8 bytes of
///   Loop's OTP secret (the `secret` of the QR code). Reading Nightscout is not enough to make one.
/// - `status`: `pending` from the sender; Loop sets `running`, then `done`, `failed`, `uncertain` or `rejected`
/// - `statusMessage`, `handledAt`: written by Loop
/// - `statusDetails`: written by Loop when it refused for a reason the sender can show in its own
///   words (`RemoteActionRejection`), such as a bolus stopped by a dose the sender had not seen,
///   and for every outcome of a meal with bolus (see `MealBolusAction.carryOut(with:)`)
struct InboxCommand: Equatable {
    static let eventType = "Remote Command"
    /// A command must expire this soon after it was sent, so nothing old is ever carried out.
    static let maximumLifetime: TimeInterval = 15 * 60
    /// The sender's clock may run a little ahead of this phone's.
    static let allowedClockSkew: TimeInterval = 2 * 60

    let objectId: String
    let commandId: String
    let payload: String
    let signature: String
    let status: String

    init?(treatment: [String: Any]) {
        guard treatment["eventType"] as? String == Self.eventType,
              let objectId = treatment["_id"] as? String,
              let commandId = treatment["commandId"] as? String, !commandId.isEmpty,
              let payload = treatment["payload"] as? String,
              let signature = treatment["signature"] as? String
        else {
            return nil
        }
        self.objectId = objectId
        self.commandId = commandId
        self.payload = payload
        self.signature = signature
        self.status = treatment["status"] as? String ?? InboxStatus.pending.rawValue
    }

    static func sign(payload: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return Data(code).base64EncodedString()
    }

    /// Checks the command and returns the push-shaped notification to carry out.
    func validate(secret: String?, now: Date) throws -> [String: AnyObject] {
        guard let secret, !secret.isEmpty,
              let signatureData = Data(base64Encoded: signature),
              HMAC<SHA256>.isValidAuthenticationCode(signatureData, authenticating: Data(payload.utf8), using: SymmetricKey(data: Data(secret.utf8)))
        else {
            throw InboxRejection.badSignature
        }

        guard let data = payload.data(using: .utf8),
              let notification = (try? JSONSerialization.jsonObject(with: data)) as? [String: AnyObject],
              notification["command-id"] as? String == commandId
        else {
            throw InboxRejection.unreadable
        }

        let remoteNotification: RemoteNotification
        do {
            remoteNotification = try notification.toRemoteNotification()
        } catch {
            throw InboxRejection.unreadable
        }

        guard let sentAt = remoteNotification.sentAt, let expiration = remoteNotification.expiration else {
            throw InboxRejection.missingTimes
        }
        guard expiration.timeIntervalSince(sentAt) <= Self.maximumLifetime,
              sentAt <= now.addingTimeInterval(Self.allowedClockSkew)
        else {
            throw InboxRejection.badTimes
        }
        guard now <= expiration else {
            throw InboxRejection.expired(sentAt: sentAt)
        }
        return notification
    }
}

/// What a command did, written back into it.
struct InboxResult: ExpressibleByStringLiteral {
    let message: String
    var details: [String: Any]?

    init(message: String, details: [String: Any]? = nil) {
        self.message = message
        self.details = details
    }

    init(stringLiteral message: String) {
        self.init(message: message)
    }
}

/// A command that did not do all it was meant to, with the status and details to write back.
struct InboxFailure: LocalizedError {
    let status: InboxStatus
    let message: String
    let details: [String: Any]?
    let underlyingError: Error

    var errorDescription: String? { message }
}

enum InboxStatus: String {
    case pending
    case running
    case done
    case failed
    /// The pump may or may not have delivered: never send it again blindly.
    case uncertain
    case rejected
}

enum InboxRejection: LocalizedError, Equatable {
    case badSignature
    case unreadable
    case missingTimes
    case badTimes
    case expired(sentAt: Date)
    case alreadyHandled
    case couldNotClaim

    var errorDescription: String? {
        switch self {
        case .badSignature:
            return "The command's signature does not match this Loop's secret. Scan Loop's QR code again in LoopFollow."
        case .unreadable:
            return "Loop could not read the command."
        case .missingTimes:
            return "The command has no send or expiration time."
        case .badTimes:
            return "The command's send and expiration times are not allowed."
        case .expired(let sentAt):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "The command sent at \(formatter.string(from: sentAt)) expired before Loop saw it. Nothing was given."
        case .alreadyHandled:
            return "Loop has already handled this command."
        case .couldNotClaim:
            return "Loop could not mark the command as started in Nightscout, so it did not carry it out."
        }
    }
}

/// Where the commands live: Nightscout, or a fake in tests.
protocol RemoteCommandInboxTransport {
    func fetchPending(since: Date) async throws -> [[String: Any]]
    /// Replaces the treatment with the same `_id`.
    func replace(_ treatment: [String: Any]) async throws
}

/// The ids of the commands Loop has taken on, kept for two days, so none is carried out twice.
protocol RemoteCommandHandledStore: AnyObject {
    func wasHandled(_ commandId: String) -> Bool
    func markHandled(_ commandId: String, at date: Date)
}

final class UserDefaultsRemoteCommandHandledStore: RemoteCommandHandledStore {
    private let defaults: UserDefaults
    private let key = "com.loopkit.NightscoutService.handledRemoteCommands"
    private let keepTime: TimeInterval = 48 * 60 * 60
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func wasHandled(_ commandId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (defaults.dictionary(forKey: key) as? [String: Double])?[commandId] != nil
    }

    func markHandled(_ commandId: String, at date: Date) {
        lock.lock(); defer { lock.unlock() }
        var handled = (defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
        let oldest = date.addingTimeInterval(-keepTime).timeIntervalSince1970
        handled = handled.filter { $0.value >= oldest }
        handled[commandId] = date.timeIntervalSince1970
        defaults.set(handled, forKey: key)
    }
}

/// Fetches the commands waiting in Nightscout and carries each out once.
actor RemoteCommandInbox {
    typealias Execute = (_ notification: [String: AnyObject]) async throws -> InboxResult

    /// Commands beyond the usual ones that this Loop carries out from the inbox, uploaded in every
    /// device status as `loop.testingDetails.remoteCommands`. LoopFollow offers a command only when
    /// it is listed (`Storage.loopRemoteCommands`).
    static let advertisedCommands = [MealBolusAction.kind]

    /// Loop runs every five minutes; don't look more often than this unless a push asks.
    static let minimumPollInterval: TimeInterval = 20
    static let lookBack: TimeInterval = 24 * 60 * 60

    private let transport: () -> RemoteCommandInboxTransport?
    private let secret: () -> String?
    private let store: RemoteCommandHandledStore
    private let now: () -> Date
    private let execute: Execute
    private let log = OSLog(category: "RemoteCommandInbox")

    private var lastPoll: Date?
    private var isPolling = false
    private var pollAgain = false

    init(transport: @escaping () -> RemoteCommandInboxTransport?,
         secret: @escaping () -> String?,
         store: RemoteCommandHandledStore = UserDefaultsRemoteCommandHandledStore(),
         now: @escaping () -> Date = { Date() },
         execute: @escaping Execute)
    {
        self.transport = transport
        self.secret = secret
        self.store = store
        self.now = now
        self.execute = execute
    }

    /// Looks in Nightscout. `force` (a push) skips the minimum interval.
    func poll(force: Bool) async {
        if isPolling {
            if force { pollAgain = true }
            return
        }
        if !force, let lastPoll, now().timeIntervalSince(lastPoll) < Self.minimumPollInterval {
            return
        }
        guard let transport = transport() else { return }

        isPolling = true
        repeat {
            pollAgain = false
            lastPoll = now()
            await pollOnce(transport)
        } while pollAgain
        isPolling = false
    }

    private func pollOnce(_ transport: RemoteCommandInboxTransport) async {
        let treatments: [[String: Any]]
        do {
            treatments = try await transport.fetchPending(since: now().addingTimeInterval(-Self.lookBack))
        } catch {
            log.error("Could not fetch remote commands: %{public}@", String(describing: error))
            return
        }

        let pending = treatments
            .filter { InboxCommand(treatment: $0)?.status == InboxStatus.pending.rawValue }
            .sorted { ($0["created_at"] as? String ?? "") < ($1["created_at"] as? String ?? "") }

        for treatment in pending {
            await handle(treatment, transport: transport)
        }
    }

    private func handle(_ treatment: [String: Any], transport: RemoteCommandInboxTransport) async {
        guard let command = InboxCommand(treatment: treatment) else { return }

        // Taken on before (perhaps this run's write of the outcome failed): never again.
        if store.wasHandled(command.commandId) {
            log.default("Remote command %{public}@ was already handled", command.commandId)
            return
        }

        let notification: [String: AnyObject]
        do {
            notification = try command.validate(secret: secret(), now: now())
        } catch {
            store.markHandled(command.commandId, at: now())
            log.error("Rejected remote command %{public}@: %{public}@", command.commandId, error.localizedDescription)
            try? await transport.replace(Self.updated(treatment, status: .rejected, message: error.localizedDescription, at: now()))
            return
        }

        // Remember it before anything else, so a crash or a second poll can't carry it out twice.
        store.markHandled(command.commandId, at: now())

        do {
            try await transport.replace(Self.updated(treatment, status: .running, message: nil, at: now()))
        } catch {
            // Without the claim the sender can't tell it was started; giving nothing is the safe side.
            log.error("Could not claim remote command %{public}@: %{public}@", command.commandId, String(describing: error))
            return
        }

        // The claim can take a while on a bad network; check the time again.
        if let expiration = (try? notification.toRemoteNotification())?.expiration, now() > expiration {
            let rejection = InboxRejection.expired(sentAt: (try? notification.toRemoteNotification())?.sentAt ?? now())
            try? await transport.replace(Self.updated(treatment, status: .rejected, message: rejection.localizedDescription, at: now()))
            return
        }

        let status: InboxStatus
        let message: String
        var details: [String: Any]?
        do {
            let result = try await execute(notification)
            message = result.message
            details = result.details
            status = .done
        } catch {
            if let failure = error as? InboxFailure {
                // The command said itself what happened (a meal with bolus whose carbs were saved).
                status = failure.status
                details = failure.details
            } else if case PumpManagerError.uncertainDelivery = error {
                status = .uncertain
            } else if let rejection = error as? RemoteActionRejection {
                // Loop chose to give nothing, and says why in a form the sender can show.
                status = .rejected
                details = rejection.remoteActionDetails
            } else {
                status = .failed
            }
            message = error.localizedDescription
        }
        log.default("Remote command %{public}@: %{public}@ %{public}@", command.commandId, status.rawValue, message)

        do {
            try await transport.replace(Self.updated(treatment, status: status, message: message, details: details, at: now()))
        } catch {
            log.error("Could not write the outcome of remote command %{public}@: %{public}@", command.commandId, String(describing: error))
        }
    }

    static func updated(_ treatment: [String: Any], status: InboxStatus, message: String?, details: [String: Any]? = nil, at date: Date) -> [String: Any] {
        var treatment = treatment
        treatment["status"] = status.rawValue
        if let message {
            treatment["statusMessage"] = message
        }
        if let details, JSONSerialization.isValidJSONObject(details) {
            treatment["statusDetails"] = details
        }
        treatment["handledAt"] = ISO8601DateFormatter.withFractionalSeconds.string(from: date)
        return treatment
    }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// Nightscout's v1 treatments API, authenticated with Loop's API secret.
struct NightscoutRemoteCommandTransport: RemoteCommandInboxTransport {
    let siteURL: URL
    let apiSecret: String
    var session: URLSession = .shared

    enum TransportError: Error {
        case badResponse(Int)
        case badBody
    }

    private var hashedSecret: String {
        Insecure.SHA1.hash(data: Data(apiSecret.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func fetchPending(since: Date) async throws -> [[String: Any]] {
        var components = URLComponents(url: siteURL.appendingPathComponent("api/v1/treatments.json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "find[eventType]", value: InboxCommand.eventType),
            URLQueryItem(name: "find[status]", value: InboxStatus.pending.rawValue),
            URLQueryItem(name: "find[created_at][$gte]", value: ISO8601DateFormatter.withFractionalSeconds.string(from: since)),
            URLQueryItem(name: "count", value: "20"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(hashedSecret, forHTTPHeaderField: "api-secret")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw TransportError.badResponse(code) }
        guard let treatments = (try JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw TransportError.badBody
        }
        return treatments
    }

    func replace(_ treatment: [String: Any]) async throws {
        var request = URLRequest(url: siteURL.appendingPathComponent("api/v1/treatments"))
        request.httpMethod = "PUT"
        request.setValue(hashedSecret, forHTTPHeaderField: "api-secret")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: treatment)

        let (_, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw TransportError.badResponse(code) }
    }
}
