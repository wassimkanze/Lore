import Foundation
import Security

public enum SignedIdentity {
    private static var information: [String: Any]? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return nil }
        return info as? [String: Any]
    }
    public static var teamID: String? { information?[kSecCodeInfoTeamIdentifier as String] as? String }
    public static var isDebuggable: Bool {
        let entitlements = information?[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return entitlements?["com.apple.security.get-task-allow"] as? Bool ?? false
    }
    public static func requirement(identifier: String, team: String) -> String? {
        guard team.count == 10, team.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.union(.decimalDigits).contains($0) }),
              identifier.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-")).contains($0) }) else { return nil }
        let text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\" and entitlement[\"com.apple.security.get-task-allow\"] absent"
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &parsed) == errSecSuccess else { return nil }
        return text
    }
}
