//
//  BolusRemoteNotification.swift
//  NightscoutUploadKit
//
//  Created by Bill Gestrich on 2/25/23.
//  Copyright © 2023 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKit

public struct BolusRemoteNotification: RemoteNotification, Codable {

    public let amount: Double
    public let remoteAddress: String
    public let expiration: Date?
    public let sentAt: Date?
    public let otp: String?
    public let enteredBy: String?
    public let encryptedReturnNotification: String?
    /// The sender had seen every dose given by hand up to this time. Loop gives nothing when it
    /// has a later one: someone bolused on the phone and the sender did not know.
    public let knownDosesUntil: Date?
    
    enum CodingKeys: String, CodingKey {
        case remoteAddress = "remote-address"
        case amount = "bolus-entry"
        case expiration = "expiration"
        case sentAt = "sent-at"
        case otp = "otp"
        case enteredBy = "entered-by"
        case encryptedReturnNotification = "encrypted_return_notification"
        case knownDosesUntil = "known-doses-until"
    }
    
    func toRemoteAction() -> Action {
        return .bolusEntry(BolusAction(amountInUnits: amount, knownDosesUntil: knownDosesUntil))
    }
    
    func otpValidationRequired() -> Bool {
        return true
    }
    
    public static func includedInNotification(_ notification: [String: Any]) -> Bool {
        return notification["bolus-entry"] != nil
    }
}
