//
//  TherapySettingsAction.swift
//  NightscoutServiceKit
//
//  Replaces the carb ratio and/or insulin sensitivity schedule from a caregiver's phone.
//

import Foundation
import HealthKit
import LoopKit

public struct TherapySettingsAction: Codable, Equatable {

    public struct ScheduleItem: Codable, Equatable {
        /// Seconds after midnight.
        public let start: TimeInterval
        public let value: Double

        public init(start: TimeInterval, value: Double) {
            self.start = start
            self.value = value
        }
    }

    /// Grams per unit.
    public let carbRatio: [ScheduleItem]?
    /// `insulinSensitivityUnit` per unit.
    public let insulinSensitivity: [ScheduleItem]?
    /// "mg/dL" or "mmol/L".
    public let insulinSensitivityUnit: String?

    enum CodingKeys: String, CodingKey {
        case carbRatio = "carb-ratio"
        case insulinSensitivity = "insulin-sensitivity"
        case insulinSensitivityUnit = "insulin-sensitivity-unit"
    }

    public init(carbRatio: [ScheduleItem]?, insulinSensitivity: [ScheduleItem]?, insulinSensitivityUnit: String?) {
        self.carbRatio = carbRatio
        self.insulinSensitivity = insulinSensitivity
        self.insulinSensitivityUnit = insulinSensitivityUnit
    }

    public func change() throws -> RemoteTherapySettingsChange {
        return try RemoteTherapySettingsChange(
            carbRatioItems: carbRatio?.map { RepeatingScheduleValue(startTime: $0.start, value: $0.value) },
            insulinSensitivityItems: insulinSensitivity?.map { RepeatingScheduleValue(startTime: $0.start, value: $0.value) },
            insulinSensitivityUnit: insulinSensitivityUnit.flatMap(Self.glucoseUnit(from:))
        )
    }

    /// `HKUnit(from: "mmol/L")` is not the molar-mass-aware unit Loop stores, so map by name.
    private static func glucoseUnit(from string: String) -> HKUnit? {
        switch string.lowercased() {
        case "mg/dl":
            return .milligramsPerDeciliter
        case "mmol/l":
            return .millimolesPerLiter
        default:
            return nil
        }
    }
}
