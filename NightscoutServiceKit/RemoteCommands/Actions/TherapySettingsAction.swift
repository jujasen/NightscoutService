//
//  TherapySettingsAction.swift
//  NightscoutServiceKit
//
//  Replaces therapy settings from a caregiver's phone. Every key is optional; only the settings
//  the caregiver changed are sent.
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

    public struct RangeScheduleItem: Codable, Equatable {
        /// Seconds after midnight.
        public let start: TimeInterval
        public let low: Double
        public let high: Double

        public init(start: TimeInterval, low: Double, high: Double) {
            self.start = start
            self.low = low
            self.high = high
        }
    }

    public struct Range: Codable, Equatable {
        public let low: Double
        public let high: Double

        public init(low: Double, high: Double) {
            self.low = low
            self.high = high
        }
    }

    public struct OverridePreset: Codable, Equatable {
        public let name: String
        public let symbol: String
        /// Seconds; 0 means indefinite.
        public let duration: TimeInterval
        public let insulinNeedsScaleFactor: Double?
        /// `glucoseUnit`; both or neither.
        public let targetLow: Double?
        public let targetHigh: Double?

        enum CodingKeys: String, CodingKey {
            case name
            case symbol
            case duration
            case insulinNeedsScaleFactor = "insulin-needs-scale-factor"
            case targetLow = "target-low"
            case targetHigh = "target-high"
        }

        public init(name: String, symbol: String, duration: TimeInterval, insulinNeedsScaleFactor: Double? = nil, targetLow: Double? = nil, targetHigh: Double? = nil) {
            self.name = name
            self.symbol = symbol
            self.duration = duration
            self.insulinNeedsScaleFactor = insulinNeedsScaleFactor
            self.targetLow = targetLow
            self.targetHigh = targetHigh
        }
    }

    /// Grams per unit.
    public let carbRatio: [ScheduleItem]?
    /// `insulinSensitivityUnit` per unit.
    public let insulinSensitivity: [ScheduleItem]?
    /// "mg/dL" or "mmol/L".
    public let insulinSensitivityUnit: String?

    /// "mg/dL" or "mmol/L"; the unit of every glucose value below.
    public let glucoseUnit: String?
    /// Units per hour.
    public let basalRate: [ScheduleItem]?
    public let correctionRange: [RangeScheduleItem]?
    public let preMealRange: Range?
    public let workoutRange: Range?
    public let suspendThreshold: Double?
    /// Units per hour.
    public let maximumBasalRate: Double?
    /// Units.
    public let maximumBolus: Double?
    /// An `ExponentialInsulinModelPreset` raw value, e.g. "rapidActingChild".
    public let insulinModel: String?
    /// "tempBasalOnly" or "automaticBolus".
    public let dosingStrategy: String?
    public let closedLoop: Bool?
    /// Replaces the whole preset list.
    public let overridePresets: [OverridePreset]?
    public let glucoseBasedPartialApplication: Bool?
    public let integralRetrospectiveCorrection: Bool?

    enum CodingKeys: String, CodingKey {
        case carbRatio = "carb-ratio"
        case insulinSensitivity = "insulin-sensitivity"
        case insulinSensitivityUnit = "insulin-sensitivity-unit"
        case glucoseUnit = "glucose-unit"
        case basalRate = "basal-rate"
        case correctionRange = "correction-range"
        case preMealRange = "pre-meal-range"
        case workoutRange = "workout-range"
        case suspendThreshold = "suspend-threshold"
        case maximumBasalRate = "maximum-basal-rate"
        case maximumBolus = "maximum-bolus"
        case insulinModel = "insulin-model"
        case dosingStrategy = "dosing-strategy"
        case closedLoop = "closed-loop"
        case overridePresets = "override-presets"
        case glucoseBasedPartialApplication = "glucose-based-partial-application"
        case integralRetrospectiveCorrection = "integral-retrospective-correction"
    }

    public init(
        carbRatio: [ScheduleItem]?,
        insulinSensitivity: [ScheduleItem]?,
        insulinSensitivityUnit: String?,
        glucoseUnit: String? = nil,
        basalRate: [ScheduleItem]? = nil,
        correctionRange: [RangeScheduleItem]? = nil,
        preMealRange: Range? = nil,
        workoutRange: Range? = nil,
        suspendThreshold: Double? = nil,
        maximumBasalRate: Double? = nil,
        maximumBolus: Double? = nil,
        insulinModel: String? = nil,
        dosingStrategy: String? = nil,
        closedLoop: Bool? = nil,
        overridePresets: [OverridePreset]? = nil,
        glucoseBasedPartialApplication: Bool? = nil,
        integralRetrospectiveCorrection: Bool? = nil
    ) {
        self.carbRatio = carbRatio
        self.insulinSensitivity = insulinSensitivity
        self.insulinSensitivityUnit = insulinSensitivityUnit
        self.glucoseUnit = glucoseUnit
        self.basalRate = basalRate
        self.correctionRange = correctionRange
        self.preMealRange = preMealRange
        self.workoutRange = workoutRange
        self.suspendThreshold = suspendThreshold
        self.maximumBasalRate = maximumBasalRate
        self.maximumBolus = maximumBolus
        self.insulinModel = insulinModel
        self.dosingStrategy = dosingStrategy
        self.closedLoop = closedLoop
        self.overridePresets = overridePresets
        self.glucoseBasedPartialApplication = glucoseBasedPartialApplication
        self.integralRetrospectiveCorrection = integralRetrospectiveCorrection
    }

    public func change() throws -> RemoteTherapySettingsChange {
        let insulinModel = try self.insulinModel.map { name -> ExponentialInsulinModelPreset in
            guard let model = ExponentialInsulinModelPreset(rawValue: name) else {
                throw RemoteTherapySettingsError.unknownInsulinModel(name)
            }
            return model
        }
        let dosingStrategy = try self.dosingStrategy.map { name -> AutomaticDosingStrategy in
            guard let strategy = Self.dosingStrategy(from: name) else {
                throw RemoteTherapySettingsError.unknownDosingStrategy(name)
            }
            return strategy
        }
        let overridePresets = try self.overridePresets?.map { preset -> RemoteTherapySettingsChange.OverridePreset in
            let targetRange: DoubleRange?
            switch (preset.targetLow, preset.targetHigh) {
            case (let low?, let high?):
                targetRange = DoubleRange(minValue: low, maxValue: high)
            case (nil, nil):
                targetRange = nil
            default:
                throw RemoteTherapySettingsError.incompleteOverrideTargetRange(preset.name)
            }
            return RemoteTherapySettingsChange.OverridePreset(
                name: preset.name,
                symbol: preset.symbol,
                duration: preset.duration,
                insulinNeedsScaleFactor: preset.insulinNeedsScaleFactor ?? 1.0,
                targetRange: targetRange
            )
        }
        let glucoseUnit = glucoseUnit.flatMap(Self.glucoseUnit(from:))

        return try RemoteTherapySettingsChange(
            carbRatioItems: carbRatio?.map { RepeatingScheduleValue(startTime: $0.start, value: $0.value) },
            insulinSensitivityItems: insulinSensitivity?.map { RepeatingScheduleValue(startTime: $0.start, value: $0.value) },
            // A v2 sender may give only the shared glucose unit.
            insulinSensitivityUnit: insulinSensitivityUnit.flatMap(Self.glucoseUnit(from:)) ?? (insulinSensitivityUnit == nil ? glucoseUnit : nil),
            glucoseUnit: glucoseUnit,
            basalRateItems: basalRate?.map { RepeatingScheduleValue(startTime: $0.start, value: $0.value) },
            correctionRangeItems: correctionRange?.map { RepeatingScheduleValue(startTime: $0.start, value: DoubleRange(minValue: $0.low, maxValue: $0.high)) },
            preMealTargetRange: preMealRange.map { DoubleRange(minValue: $0.low, maxValue: $0.high) },
            workoutTargetRange: workoutRange.map { DoubleRange(minValue: $0.low, maxValue: $0.high) },
            suspendThreshold: suspendThreshold,
            maximumBasalRatePerHour: maximumBasalRate,
            maximumBolus: maximumBolus,
            insulinModel: insulinModel,
            dosingStrategy: dosingStrategy,
            closedLoop: closedLoop,
            overridePresets: overridePresets,
            glucoseBasedPartialApplication: glucoseBasedPartialApplication,
            integralRetrospectiveCorrection: integralRetrospectiveCorrection
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

    /// `AutomaticDosingStrategy` is an `Int` enum, so map by case name.
    private static func dosingStrategy(from string: String) -> AutomaticDosingStrategy? {
        switch string {
        case "tempBasalOnly":
            return .tempBasalOnly
        case "automaticBolus":
            return .automaticBolus
        default:
            return nil
        }
    }

    /// The names of the settings this action changes, for logs and the caregiver's return notification.
    public var changedSettingNames: [String] {
        var changed = [String]()
        if carbRatio != nil {
            changed.append(LocalizedString("Carb Ratios", comment: "The remote therapy settings name for the carb ratio schedule"))
        }
        if insulinSensitivity != nil {
            changed.append(LocalizedString("Insulin Sensitivities", comment: "The remote therapy settings name for the insulin sensitivity schedule"))
        }
        if basalRate != nil {
            changed.append(LocalizedString("Basal Rates", comment: "The remote therapy settings name for the basal rate schedule"))
        }
        if correctionRange != nil {
            changed.append(LocalizedString("Correction Range", comment: "The remote therapy settings name for the correction range schedule"))
        }
        if preMealRange != nil {
            changed.append(LocalizedString("Pre-Meal Range", comment: "The remote therapy settings name for the pre-meal correction range"))
        }
        if workoutRange != nil {
            changed.append(LocalizedString("Workout Range", comment: "The remote therapy settings name for the workout correction range"))
        }
        if suspendThreshold != nil {
            changed.append(LocalizedString("Glucose Safety Limit", comment: "The remote therapy settings name for the suspend threshold"))
        }
        if maximumBasalRate != nil {
            changed.append(LocalizedString("Maximum Basal Rate", comment: "The remote therapy settings name for the maximum basal rate"))
        }
        if maximumBolus != nil {
            changed.append(LocalizedString("Maximum Bolus", comment: "The remote therapy settings name for the maximum bolus"))
        }
        if insulinModel != nil {
            changed.append(LocalizedString("Insulin Model", comment: "The remote therapy settings name for the insulin model"))
        }
        if dosingStrategy != nil {
            changed.append(LocalizedString("Dosing Strategy", comment: "The remote therapy settings name for the dosing strategy"))
        }
        if closedLoop != nil {
            changed.append(LocalizedString("Closed Loop", comment: "The remote therapy settings name for closed loop"))
        }
        if overridePresets != nil {
            changed.append(LocalizedString("Override Presets", comment: "The remote therapy settings name for the override presets"))
        }
        if glucoseBasedPartialApplication != nil {
            changed.append(LocalizedString("Glucose Based Partial Application", comment: "The remote therapy settings name for the glucose based partial application experiment"))
        }
        if integralRetrospectiveCorrection != nil {
            changed.append(LocalizedString("Integral Retrospective Correction", comment: "The remote therapy settings name for the integral retrospective correction experiment"))
        }
        return changed
    }
}
