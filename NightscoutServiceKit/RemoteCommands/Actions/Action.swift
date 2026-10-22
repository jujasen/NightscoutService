//
//  Action.swift
//  LoopKit
//
//  Created by Bill Gestrich on 12/25/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

public enum Action: Codable {
    case temporaryScheduleOverride(OverrideAction)
    case cancelTemporaryOverride(OverrideCancelAction)
    case bolusEntry(BolusAction)
    case carbsEntry(CarbAction)
    case therapySettings(TherapySettingsAction)
    case carbsEdit(CarbEditAction)
    
    public var description: String {
        return "\(actionName) \(actionParameterDescription)"
    }
    
    var actionName: String {
        switch self {
        case .carbsEntry:
            return LocalizedString("Carb Entry", comment: "The remote action name for Carb Entry")
        case .bolusEntry:
            return LocalizedString("Bolus Entry", comment: "The remote action name for Bolus Entry")
        case .cancelTemporaryOverride:
            return LocalizedString("Cancel Override", comment: "The remote action name for Cancel Override")
        case .temporaryScheduleOverride:
            return LocalizedString("Override", comment: "The remote action name for Override")
        case .therapySettings:
            return LocalizedString("Therapy Settings", comment: "The remote action name for Therapy Settings")
        case .carbsEdit(let carbEditAction):
            if carbEditAction.isDelete {
                return LocalizedString("Delete Carb Entry", comment: "The remote action name for deleting a carb entry")
            }
            return LocalizedString("Edit Carb Entry", comment: "The remote action name for editing a carb entry")
        }
    }
    
    var actionParameterDescription: String {
        switch self {
        case .carbsEntry(let carbAction):
            let amountFormatted = Self.numberFormatter.string(from: carbAction.amountInGrams as NSNumber) ?? ""
            return "\(amountFormatted)" + " " + carbGramAbbreviation
        case .bolusEntry(let bolusAction):
            let amountFormatted = Self.numberFormatter.string(from: bolusAction.amountInUnits as NSNumber) ?? ""
            return "\(amountFormatted)" + " " + bolusUnitAbbreviation
        case .cancelTemporaryOverride:
            return ""
        case .temporaryScheduleOverride(let overrideAction):
            return overrideAction.name
        case .therapySettings(let therapySettingsAction):
            return therapySettingsAction.changedSettingNames.joined(separator: ", ")
        case .carbsEdit(let carbEditAction):
            guard !carbEditAction.isDelete, let amountInGrams = carbEditAction.amountInGrams else {
                return ""
            }
            let amountFormatted = Self.numberFormatter.string(from: amountInGrams as NSNumber) ?? ""
            return "\(amountFormatted)" + " " + carbGramAbbreviation
        }
    }
    
    var carbGramAbbreviation: String {
        LocalizedString("g", comment: "The remote action abbreviation for gram units")
    }
    
    var bolusUnitAbbreviation: String {
        LocalizedString("U", comment: "The remote action abbreviation for bolus units")
    }
    
    static var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}
