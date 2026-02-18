//
//  PhoneNumberService.swift
//  TonePhone
//
//  Normalizes phone number input to E.164 format using PhoneNumberKit.
//

import Foundation
import PhoneNumberKit

/// Provides phone number normalization for SIP URI construction.
struct PhoneNumberService {
    private static let phoneNumberUtility = PhoneNumberUtility()

    private static var defaultRegion: String {
        Locale.current.region?.identifier ?? "US"
    }

    /// Attempts to parse the input as a phone number and return E.164 format.
    ///
    /// Returns the original input unchanged if parsing fails (e.g. extensions, star codes).
    static func normalizeToE164(_ input: String) -> String {
        do {
            let phoneNumber = try phoneNumberUtility.parse(input, withRegion: defaultRegion)
            return phoneNumberUtility.format(phoneNumber, toType: .e164)
        } catch {
            return input
        }
    }
}
