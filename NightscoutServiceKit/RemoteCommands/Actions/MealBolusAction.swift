//
//  MealBolusAction.swift
//  NightscoutServiceKit
//
//  A meal and its bolus in one command. See `MealBolusRemoteNotification`.
//

import Foundation
import LoopKit

public struct MealBolusAction: Codable, Equatable {

    public let amountInGrams: Double
    public let absorptionTime: TimeInterval?
    public let foodType: String?
    public let startDate: Date?
    /// The most insulin the sender approved.
    public let bolusInUnits: Double
    /// See `RemoteMealBolus.followsRecommendation`.
    public let followsRecommendation: Bool
    /// See `BolusRemoteNotification.knownDosesUntil`.
    public let knownDosesUntil: Date?

    public init(amountInGrams: Double, absorptionTime: TimeInterval? = nil, foodType: String? = nil, startDate: Date? = nil,
                bolusInUnits: Double, followsRecommendation: Bool, knownDosesUntil: Date?)
    {
        self.amountInGrams = amountInGrams
        self.absorptionTime = absorptionTime
        self.foodType = foodType
        self.startDate = startDate
        self.bolusInUnits = bolusInUnits
        self.followsRecommendation = followsRecommendation
        self.knownDosesUntil = knownDosesUntil
    }

    var mealBolus: RemoteMealBolus {
        RemoteMealBolus(
            carbsInGrams: amountInGrams,
            absorptionTime: absorptionTime,
            foodType: foodType,
            startDate: startDate,
            approvedUnits: bolusInUnits,
            followsRecommendation: followsRecommendation,
            knownDosesUntil: knownDosesUntil
        )
    }

    /// Carries the meal out through `deliver` (the host) and says what to write back into the
    /// command: always the details of the contract with LoopFollow, also when it failed.
    ///
    /// `statusDetails`: `kind` ("mealBolus"), `carbsSaved`, `carbs`, `approvedUnits`,
    /// `recommendedUnits` (left out when Loop could not calculate one) and `deliveredUnits`, plus
    /// the details of a `RemoteActionRejection` (`reason`, …) when Loop refused.
    ///
    /// - Throws: `InboxFailure`: `rejected` or `failed` when nothing was saved, `failed` or
    ///   `uncertain` when the carbs were saved and only the bolus went wrong.
    func carryOut(with deliver: (RemoteMealBolus) async throws -> RemoteMealBolusOutcome) async throws -> InboxResult {
        let outcome: RemoteMealBolusOutcome
        do {
            outcome = try await deliver(mealBolus)
        } catch {
            throw inboxFailure(for: error)
        }
        return InboxResult(message: successMessage(outcome), details: Self.details(outcome))
    }

    func inboxFailure(for error: Error) -> InboxFailure {
        let mealError = error as? RemoteMealBolusError
        let underlying = mealError?.underlyingError ?? error
        let outcome = mealError?.outcome ?? RemoteMealBolusOutcome(
            carbsSaved: false, carbsInGrams: amountInGrams, approvedUnits: bolusInUnits, recommendedUnits: nil, deliveredUnits: 0)

        var details = Self.details(outcome)
        if let rejection = underlying as? RemoteActionRejection {
            details.merge(rejection.remoteActionDetails) { mine, _ in mine }
        }

        let status: InboxStatus
        let message: String
        if case PumpManagerError.uncertainDelivery = underlying {
            status = .uncertain
        } else if !outcome.carbsSaved, underlying is RemoteActionRejection {
            status = .rejected
        } else {
            status = .failed
        }
        if outcome.carbsSaved {
            let format = status == .uncertain
                ? LocalizedString("%1$@ g carbs saved. The bolus may or may not have been given: %2$@", comment: "Outcome of a remote meal with bolus whose carbs were saved and whose bolus is uncertain (1: grams, 2: why)")
                : LocalizedString("%1$@ g carbs saved, but the bolus was not given: %2$@", comment: "Outcome of a remote meal with bolus whose carbs were saved and whose bolus failed (1: grams, 2: why)")
            message = String(format: format, Self.format(outcome.carbsInGrams), underlying.localizedDescription)
        } else {
            message = underlying.localizedDescription
        }
        return InboxFailure(status: status, message: message, details: details, underlyingError: underlying)
    }

    private func successMessage(_ outcome: RemoteMealBolusOutcome) -> String {
        if outcome.deliveredUnits > 0 {
            return String(format: LocalizedString("%1$@ g carbs saved and %2$@ U given", comment: "Outcome of a remote meal with bolus (1: grams, 2: units)"),
                          Self.format(outcome.carbsInGrams), Self.format(outcome.deliveredUnits))
        }
        return String(format: LocalizedString("%1$@ g carbs saved, no bolus given", comment: "Outcome of a remote meal with bolus when no bolus was needed (1: grams)"),
                      Self.format(outcome.carbsInGrams))
    }

    static let kind = "mealBolus"

    static func details(_ outcome: RemoteMealBolusOutcome) -> [String: Any] {
        var details: [String: Any] = [
            "kind": kind,
            "carbsSaved": outcome.carbsSaved,
            "carbs": outcome.carbsInGrams,
            "approvedUnits": outcome.approvedUnits,
            "deliveredUnits": outcome.deliveredUnits,
        ]
        if let recommended = outcome.recommendedUnits {
            details["recommendedUnits"] = recommended
        }
        return details
    }

    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// A meal with bolus came by push alone. It is only carried out from the command inbox in
/// Nightscout, which tells the sender whether the carbs were saved.
struct MealBolusNotFromInbox: LocalizedError {
    var errorDescription: String? {
        LocalizedString("A meal with bolus is only accepted through Nightscout. Nothing was saved or given.", comment: "Remote command error: a meal with bolus arrived by push without the Nightscout command inbox.")
    }
}

/// No one in the host to carry out the command.
struct RemoteActionHostMissing: LocalizedError {
    var errorDescription: String? {
        LocalizedString("Loop could not carry out the command. Nothing was saved or given.", comment: "Remote command error: the service has no host app to carry out the command.")
    }
}
