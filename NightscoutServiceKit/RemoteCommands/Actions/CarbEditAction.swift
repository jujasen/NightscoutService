//
//  CarbEditAction.swift
//  NightscoutServiceKit
//
//  Changes or deletes a carb entry Loop already has, from a caregiver's phone. Every value is
//  optional; only the ones the caregiver changed are sent.
//

import Foundation
import LoopKit

public struct CarbEditAction: Codable, Equatable {

    /// The `syncIdentifier` of the carb treatment in Nightscout.
    public let syncIdentifier: String
    /// Grams.
    public let amountInGrams: Double?
    /// Hours, as in the carb entry command.
    public let absorptionInHours: Double?
    /// An empty string clears the food type.
    public let foodType: String?
    public let startDate: Date?
    public let delete: Bool?

    enum CodingKeys: String, CodingKey {
        case syncIdentifier = "sync-identifier"
        case amountInGrams = "carbs"
        case absorptionInHours = "absorption-time"
        case foodType = "food-type"
        case startDate = "start-time"
        case delete
    }

    public init(syncIdentifier: String, amountInGrams: Double? = nil, absorptionInHours: Double? = nil, foodType: String? = nil, startDate: Date? = nil, delete: Bool? = nil) {
        self.syncIdentifier = syncIdentifier
        self.amountInGrams = amountInGrams
        self.absorptionInHours = absorptionInHours
        self.foodType = foodType
        self.startDate = startDate
        self.delete = delete
    }

    public func edit() throws -> RemoteCarbEdit {
        return try RemoteCarbEdit(
            syncIdentifier: syncIdentifier,
            amountInGrams: amountInGrams,
            absorptionTime: absorptionInHours.map { TimeInterval(hours: $0) },
            foodType: foodType,
            startDate: startDate,
            delete: delete ?? false
        )
    }

    public var isDelete: Bool {
        return delete ?? false
    }
}
