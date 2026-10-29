//
//  PhoneNumberService.swift
//  TonePhone
//
//  Phone number display and dialing formats, backed by PhoneNumberKit.
//

import Foundation
import PhoneNumberKit

/// How phone numbers are shown in the app.
enum PhoneNumberDisplayFormat: String, Codable, CaseIterable {
    /// `+1 415-555-0123`
    case international
    /// `(415) 555-0123` for numbers in your region, international otherwise.
    case national
    /// `+14155550123`
    case e164
    /// Exactly what the server sent.
    case asReceived

    var displayName: String {
        switch self {
        case .international: return "International (+1 415-555-0123)"
        case .national: return "National ((415) 555-0123)"
        case .e164: return "Compact (+14155550123)"
        case .asReceived: return "As Received"
        }
    }
}

/// How dialed phone numbers are sent to the SIP server.
enum PhoneNumberDialFormat: String, Codable, CaseIterable {
    /// `+14155550123`
    case e164
    /// `14155550123`
    case e164WithoutPlus
    /// `01114155550123` — the international prefix replaces the plus sign.
    case internationalPrefix
    /// `4155550123` for numbers in your region, international prefix otherwise.
    case national
    /// The digits exactly as typed.
    case asTyped

    var displayName: String {
        switch self {
        case .e164: return "International (+14155550123)"
        case .e164WithoutPlus: return "International Without Plus (14155550123)"
        case .internationalPrefix: return "International Prefix (011…)"
        case .national: return "National (4155550123)"
        case .asTyped: return "As Typed"
        }
    }
}

/// UserDefaults keys for phone number settings, shared with `SettingsStore`.
enum PhoneNumberSettingsKey {
    static let region = "settings.phoneNumberRegion"
    static let displayFormat = "settings.phoneNumberDisplayFormat"
    static let dialFormat = "settings.phoneNumberDialFormat"
    static let internationalPrefix = "settings.phoneNumberInternationalPrefix"
    static let formatAsYouType = "settings.phoneNumberFormatAsYouType"
}

/// Formats phone numbers for display and converts dialed input for SIP URIs.
///
/// Input that is not a valid phone number (extensions like `100`, star codes
/// like `*72`, SIP usernames) always passes through unchanged.
enum PhoneNumberService {
    private static let utility = PhoneNumberUtility()

    /// Cached partial formatter and the region it was created for.
    private static var cachedPartialFormatter: PartialFormatter?
    private static var cachedRegion: String?

    // MARK: - Settings

    /// Region used to interpret numbers without a country code: user setting, then system locale, then US.
    static var region: String {
        if let saved = UserDefaults.standard.string(forKey: PhoneNumberSettingsKey.region), !saved.isEmpty {
            return saved
        }
        return Locale.current.region?.identifier ?? "US"
    }

    static var displayFormat: PhoneNumberDisplayFormat {
        UserDefaults.standard.string(forKey: PhoneNumberSettingsKey.displayFormat)
            .flatMap(PhoneNumberDisplayFormat.init(rawValue:)) ?? .international
    }

    static var dialFormat: PhoneNumberDialFormat {
        UserDefaults.standard.string(forKey: PhoneNumberSettingsKey.dialFormat)
            .flatMap(PhoneNumberDialFormat.init(rawValue:)) ?? .e164
    }

    /// Digits that replace `+` when dialing with `.internationalPrefix`.
    static var internationalPrefix: String {
        let saved = UserDefaults.standard.string(forKey: PhoneNumberSettingsKey.internationalPrefix) ?? ""
        return saved.isEmpty ? defaultInternationalPrefix(for: region) : saved
    }

    static var formatsAsYouType: Bool {
        UserDefaults.standard.object(forKey: PhoneNumberSettingsKey.formatAsYouType) as? Bool ?? true
    }

    /// The international call prefix used in a region (`011` in North America, `00` in most others).
    static func defaultInternationalPrefix(for region: String) -> String {
        let nanp: Set<String> = [
            "US", "CA", "AG", "AI", "AS", "BB", "BM", "BS", "DM", "DO", "GD", "GU", "JM",
            "KN", "KY", "LC", "MP", "MS", "PR", "SX", "TC", "TT", "VC", "VG", "VI",
        ]
        if nanp.contains(region) { return "011" }
        switch region {
        case "AU": return "0011"
        case "JP": return "010"
        case "RU", "KZ", "BY": return "810"
        default: return "00"
        }
    }

    // MARK: - Dialing

    /// Converts dialed input into the user part of a SIP URI.
    ///
    /// - Parameters:
    ///   - input: What the user typed or picked from history.
    ///   - format: Dial format; defaults to the global setting.
    /// - Returns: The number in the requested format, or the input with
    ///   whitespace and punctuation removed when it is not a phone number.
    static func dialString(for input: String, format: PhoneNumberDialFormat? = nil) -> String {
        let format = format ?? dialFormat
        let typed = dialableCharacters(of: input)

        guard format != .asTyped, let number = parse(input) else {
            return typed
        }

        let e164 = utility.format(number, toType: .e164)
        let international = internationalPrefix + e164.dropFirst()

        switch format {
        case .e164:
            return e164
        case .e164WithoutPlus:
            return String(e164.dropFirst())
        case .internationalPrefix:
            return international
        case .national:
            guard isInHomeRegion(number) else { return international }
            return dialableCharacters(of: utility.format(number, toType: .national))
        case .asTyped:
            return typed
        }
    }

    /// Characters that are meaningful when dialing: digits, `+`, `*`, `#`.
    static func dialableCharacters(of input: String) -> String {
        input.filter { "0123456789+*#".contains($0) }
    }

    // MARK: - Display

    /// Formats a number for display according to the display format setting.
    ///
    /// Returns the input unchanged if it can't be parsed as a phone number (e.g. `alice`, `100`, `*72`).
    static func formatForDisplay(_ input: String) -> String {
        let format = displayFormat
        guard format != .asReceived, let number = parse(input) else {
            return input
        }

        switch format {
        case .international:
            return utility.format(number, toType: .international)
        case .national:
            return isInHomeRegion(number)
                ? utility.format(number, toType: .national)
                : utility.format(number, toType: .international)
        case .e164:
            return utility.format(number, toType: .e164)
        case .asReceived:
            return input
        }
    }

    /// Formats partial input as the user types (e.g. `4155550123` → `(415) 555-0123`).
    ///
    /// Returns the input unchanged for SIP addresses, names, or when
    /// format-as-you-type is turned off.
    static func formatPartial(_ input: String) -> String {
        guard !input.isEmpty, formatsAsYouType, !looksLikeAddress(input) else { return input }
        return partialFormatter.formatPartial(input)
    }

    /// Whether input is a SIP address or name rather than a number.
    static func looksLikeAddress(_ input: String) -> Bool {
        let lowered = input.lowercased()
        return lowered.hasPrefix("sip:") || lowered.hasPrefix("sips:") ||
            input.contains("@") || input.contains(where: { $0.isLetter })
    }

    // MARK: - SIP Addresses

    /// The user part of a SIP URI: `"Bob" <sip:+1415@host;x=y>` → `+1415`.
    static func userPart(ofURI uri: String) -> String {
        var value = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = value.firstIndex(of: "<"), let close = value.lastIndex(of: ">"), open < close {
            value = String(value[value.index(after: open)..<close])
        }
        for scheme in ["sips:", "sip:", "tel:"] where value.lowercased().hasPrefix(scheme) {
            value = String(value.dropFirst(scheme.count))
        }
        if let at = value.firstIndex(of: "@") {
            value = String(value[..<at])
        }
        if let semicolon = value.firstIndex(of: ";") {
            value = String(value[..<semicolon])
        }
        return value.removingPercentEncoding ?? value
    }

    /// The `user@host` part of a SIP URI, without scheme, brackets or parameters.
    static func address(ofURI uri: String) -> String {
        var value = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = value.firstIndex(of: "<"), let close = value.lastIndex(of: ">"), open < close {
            value = String(value[value.index(after: open)..<close])
        }
        for scheme in ["sips:", "sip:"] where value.lowercased().hasPrefix(scheme) {
            value = String(value.dropFirst(scheme.count))
        }
        if let semicolon = value.firstIndex(of: ";") {
            value = String(value[..<semicolon])
        }
        return value
    }

    /// Primary and secondary labels for a remote party.
    ///
    /// The title is the display name when the caller sent one, otherwise the
    /// formatted number (or SIP user). The subtitle is the formatted number
    /// when a name is shown, otherwise nil.
    static func partyLabels(name: String?, uri: String?) -> (title: String, subtitle: String?) {
        let user = uri.map(userPart(ofURI:)) ?? ""
        let number = user.isEmpty ? nil : formatForDisplay(user)
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
           name != user {
            return (formatForDisplay(name), number)
        }
        if let number {
            return (number, nil)
        }
        return ("Unknown Caller", nil)
    }

    // MARK: - Private

    private static func parse(_ input: String) -> PhoneNumber? {
        let candidate = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !looksLikeAddress(candidate) else { return nil }
        return try? utility.parse(candidate, withRegion: region)
    }

    private static func isInHomeRegion(_ number: PhoneNumber) -> Bool {
        number.countryCode == utility.countryCode(for: region)
    }

    /// Returns a PartialFormatter for the current region, recreating if region changed.
    private static var partialFormatter: PartialFormatter {
        let region = region
        if let cached = cachedPartialFormatter, cachedRegion == region {
            return cached
        }
        let formatter = PartialFormatter(utility: utility, defaultRegion: region, withPrefix: true)
        cachedPartialFormatter = formatter
        cachedRegion = region
        return formatter
    }
}
