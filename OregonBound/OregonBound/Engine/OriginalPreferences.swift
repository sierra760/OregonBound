import Foundation

/// Configuration globals differ from the timing bytes captured in each world.
/// CODE15:178c, CODE8:1090 and CODE16:056c/0594. No RNG or simulation-day effects.
enum OriginalPreferences {
    enum Speed: UInt8, Codable, CaseIterable {
        case fast = 2, medium = 4, slow = 8
        var title: String { switch self { case .fast: return "Fast"; case .medium: return "Medium"; case .slow: return "Slow" } }
    }
    enum HuntTime: UInt8, Codable, CaseIterable {
        case seconds20 = 1, seconds30, seconds45, seconds60, seconds90, minutes2
        var seconds: Int { [0, 20, 30, 45, 60, 90, 120][Int(rawValue)] }
        var title: String { self == .minutes2 ? "2 minutes" : "\(seconds) seconds" }
    }
    struct Timing: Codable, Equatable {
        var speed: Speed = .medium
        var huntTime: HuntTime = .seconds45
        var timerThreshold: UInt8 { speed.rawValue }
        var huntSelector: UInt8 { huntTime.rawValue }
        var huntDurationTicks: Int { huntTime.seconds * 60 }
        var travelAnimationTicks: Int { Int(speed.rawValue) * 60 }
        var simulationDayTicks: Int { Int(speed.rawValue) * 75 }
    }
    struct Configuration: Codable, Equatable {
        var timing = Timing()
        private(set) var password = "boom"
        private(set) var hint = "See the Oregon Trail User’s Guide."
        init() {}
        /// CODE16 snapshots these values only when initializing a new world.
        func beginJourney() -> Timing { timing }
        func accepts(password candidate: String) -> Bool {
            password.compare(candidate, options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) == .orderedSame
        }
        mutating func changePassword(old: String, new: String, hint: String) -> PasswordError? {
            guard accepts(password: old) else { return .incorrect }
            guard !new.isEmpty else { return .empty }
            // CODE15:0114–014a copies raw GetIText bytes and exposes at most10.
            // GetIText itself caps the hint at255 bytes before BlockMove (:0160).
            // No filtering occurs here; even a pasted CRLF may be split in two.
            self.password = Self.committedText(new, byteLimit: 10)
            self.hint = Self.committedText(hint, byteLimit: 255)
            return nil
        }
        private static func committedText(_ text: String, byteLimit: Int) -> String {
            if let bytes = text.data(using: .macOSRoman, allowLossyConversion: false),
               let original = String(data: Data(bytes.prefix(byteLimit)), encoding: .macOSRoman) {
                return original
            }
            // Earlier native configurations allowed Unicode unavailable to the
            // original OS. Preserve that compatibility without lossy substitution.
            return String(text.prefix(byteLimit))
        }
        private enum CodingKeys: CodingKey { case timing, password, hint }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            timing = try values.decode(Timing.self, forKey: .timing)
            password = try values.decode(String.self, forKey: .password)
            hint = try values.decode(String.self, forKey: .hint)
            guard !password.isEmpty, password.utf8.count <= 40, password.count <= 10, hint.count <= 255 else {
                throw DecodingError.dataCorruptedError(forKey: .password, in: values, debugDescription: "Invalid original management strings")
            }
        }
    }
    enum PasswordError: Error, Equatable {
        case incorrect, empty
        var message: String {
            switch self {
            case .incorrect: return "That was not the correct password.  Please try again"
            case .empty: return "You have not entered a new password.  Your password must be at least one character long"
            }
        }
    }
    /// Runtime-only A5−1f8a; deliberately not Codable or part of Configuration.
    struct ManagementSession: Equatable {
        private(set) var enabled = false
        mutating func enable(password: String, configuration: Configuration) -> Bool {
            guard configuration.accepts(password: password) else { return false }
            enabled = true
            return true
        }
        mutating func disable() { enabled = false }
        func permits(_ item: ManagementItem, networkUser: Bool = false) -> Bool {
            switch item {
            case .about, .enableDisable: return true
            case .clearLegends, .timeOptions: return enabled && !networkUser
            case .network, .changePassword: return enabled
            }
        }
    }
    enum ManagementItem { case about, enableDisable, clearLegends, timeOptions, network, changePassword }
    /// CODE15 password-key filter accepts printable non-space ASCII. This is
    /// keyboard input filtering, not a transformation of stored passwords.
    static func typedPassword(_ value: String, maximumLength: Int = 255) -> String {
        String(value.unicodeScalars.filter { (33...126).contains(Int($0.value)) }.prefix(maximumLength).map(Character.init))
    }
    struct Introduction: Equatable {
        private(set) var page = 1
        var pictureResource: Int { 2049 + page }
        var canGoPrevious: Bool { page > 1 }
        var canGoNext: Bool { page < 3 }
        var doneIsDefault: Bool { page == 3 }
        mutating func next() { if canGoNext { page += 1 } }
        mutating func previous() { if canGoPrevious { page -= 1 } }
    }
}
