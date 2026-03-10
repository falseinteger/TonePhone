//
//  PhoneNumberService.swift
//  TonePhone
//
//  Normalizes phone number input to E.164 format using PhoneNumberKit.
//

import Foundation
import PhoneNumberKit

/// Provides phone number normalization and formatting for SIP URI construction and display.
struct PhoneNumberService {
    private static let phoneNumberUtility = PhoneNumberUtility()

    /// Cached partial formatter and the region it was created for.
    private static var cachedPartialFormatter: PartialFormatter?
    private static var cachedRegion: String?

    /// Resolves the phone number region: user setting > system locale > "US".
    private static var defaultRegion: String {
        if let saved = UserDefaults.standard.string(forKey: "settings.phoneNumberRegion"),
           !saved.isEmpty {
            return saved
        }
        return Locale.current.region?.identifier ?? "US"
    }

    /// Returns a PartialFormatter for the current region, recreating if region changed.
    private static var partialFormatter: PartialFormatter {
        let region = defaultRegion
        if let cached = cachedPartialFormatter, cachedRegion == region {
            return cached
        }
        let formatter = PartialFormatter(defaultRegion: region, withPrefix: true)
        cachedPartialFormatter = formatter
        cachedRegion = region
        return formatter
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

    /// Formats partial phone number input as-you-type (e.g. `9492895839` → `(949) 289-5839`).
    ///
    /// Returns the input unchanged if it contains non-phone characters (letters, `@`, `sip:` prefix).
    static func formatPartial(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        // Pass through non-phone input (SIP URIs, alphabetic names)
        if input.lowercased().hasPrefix("sip:") || input.contains("@") ||
            input.contains(where: { $0.isLetter }) {
            return input
        }
        return partialFormatter.formatPartial(input)
    }

    /// Formats a full phone number for display (e.g. `+19492895839` → `+1 (949) 289-5839`).
    ///
    /// Returns the input unchanged if it can't be parsed as a phone number (e.g. `alice`, `100`, `*72`).
    static func formatForDisplay(_ input: String) -> String {
        do {
            let phoneNumber = try phoneNumberUtility.parse(input, withRegion: defaultRegion)
            return phoneNumberUtility.format(phoneNumber, toType: .international)
        } catch {
            return input
        }
    }
}
