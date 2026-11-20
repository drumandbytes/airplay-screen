import Foundation

/// AirPlay receivers advertise a feature bitmask in their Bonjour TXT record
/// (`features=0xLOW,0xHIGH`); bit 7 of the low word is screen mirroring, so this
/// separates TVs and Macs from speakers.
func supportsMirroring(features: String?) -> Bool {
    guard let low = features?.split(separator: ",").first, low.hasPrefix("0x"),
          let bits = UInt64(low.dropFirst(2), radix: 16) else { return false }
    return bits & 0x80 != 0
}

/// A connected AirPlay display names itself "<device> (AirPlay)".
func airPlayDisplayName(_ screenName: String) -> String? {
    let suffix = " (AirPlay)"
    return screenName.hasSuffix(suffix) ? String(screenName.dropLast(suffix.count)) : nil
}

/// A 1-based list number or a case-insensitive name.
func resolveChoice(_ input: String, from names: [String]) -> String? {
    let t = input.trimmingCharacters(in: .whitespaces)
    if let n = Int(t) { return names.indices.contains(n - 1) ? names[n - 1] : nil }
    return names.first { $0.localizedCaseInsensitiveCompare(t) == .orderedSame }
}
