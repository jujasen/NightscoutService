//
//  MealBolusRemoteNotification.swift
//  NightscoutServiceKit
//
//  A meal and its bolus in one command, as Loop's own «Save and Deliver». Contract with
//  LoopFollow («Måltid med bolus»); change both apps together.
//
//  { "meal-carbs": 45, "meal-absorption-time": 3, "meal-food-type": "🍕 Pizza",
//    "meal-start-time": "2026-11-25T12:30:00.000Z", "meal-bolus": 3.25,
//    "meal-bolus-follows-recommendation": true, "known-doses-until": "…",
//    "command-id": "…", "remote-address": "LoopFollow", "sent-at": "…", "expiration": "…" }
//
//  The keys are deliberately not `carbs-entry` and `bolus-entry`: a Loop without this command
//  would have read one of them and carried out half the meal. With keys of their own, it rejects
//  the whole command as unknown and gives nothing.
//
//  Only carried out from the command inbox in Nightscout, never from a push on its own: the inbox
//  writes back what was done, and the sender must know whether the carbs were saved.
//

import Foundation
import LoopKit

public struct MealBolusRemoteNotification: RemoteNotification, Codable {

    /// Grams.
    public let carbs: Double
    /// Hours.
    public let absorptionInHours: Double?
    public let foodType: String?
    public let startDate: Date?
    /// The most insulin the sender approved, in units.
    public let bolus: Double
    /// Missing counts as true: then no more than Loop's own fresh recommendation is given.
    public let followsRecommendation: Bool?
    public let knownDosesUntil: Date?
    public let remoteAddress: String
    public let expiration: Date?
    public let sentAt: Date?
    public let otp: String?
    public let enteredBy: String?
    public let encryptedReturnNotification: String?

    static let keyPrefix = "meal-"

    enum CodingKeys: String, CodingKey {
        case carbs = "meal-carbs"
        case absorptionInHours = "meal-absorption-time"
        case foodType = "meal-food-type"
        case startDate = "meal-start-time"
        case bolus = "meal-bolus"
        case followsRecommendation = "meal-bolus-follows-recommendation"
        case knownDosesUntil = "known-doses-until"
        case remoteAddress = "remote-address"
        case expiration = "expiration"
        case sentAt = "sent-at"
        case otp = "otp"
        case enteredBy = "entered-by"
        case encryptedReturnNotification = "encrypted_return_notification"
    }

    func toRemoteAction() -> Action {
        return .mealBolus(MealBolusAction(
            amountInGrams: carbs,
            absorptionTime: absorptionInHours.map { TimeInterval(hours: $0) },
            foodType: foodType,
            startDate: startDate,
            bolusInUnits: bolus,
            followsRecommendation: followsRecommendation ?? true,
            knownDosesUntil: knownDosesUntil
        ))
    }

    func otpValidationRequired() -> Bool {
        return true
    }

    /// Any `meal-` key makes it a meal with bolus, so a command that is missing a key is rejected
    /// as unreadable instead of being taken for something else.
    public static func includedInNotification(_ notification: [String: Any]) -> Bool {
        return notification.keys.contains { $0.hasPrefix(keyPrefix) }
    }
}
