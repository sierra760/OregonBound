import Foundation

/// The shared CONF1000 layout in Macintosh 1.1 and CD 1.2. Only recovered
/// preference fields are exposed; other configuration bytes remain uninterpreted.
/// CD CODE9:10c8 copies CONF+26 to the globals read by CODE16:162a/1632
/// and captured in a new world at CODE17:0bf6/0c1e.
enum ConfigurationExtractor {
    struct Defaults: Codable, Equatable {
        let hint: String
        let password: String
        let speed: UInt8
        let huntTime: UInt8

        init(hint: String, password: String, speed: UInt8, huntTime: UInt8) throws {
            guard let hintBytes = hint.data(using: .macOSRoman, allowLossyConversion: false), hintBytes.count <= 255,
                  let passwordBytes = password.data(using: .macOSRoman, allowLossyConversion: false),
                  (1...10).contains(passwordBytes.count), [2, 4, 8].contains(speed), (1...6).contains(huntTime) else {
                throw ReferenceDecodeError.value("Invalid CONF preference defaults")
            }
            self.hint = hint; self.password = password; self.speed = speed; self.huntTime = huntTime
        }
        private enum CodingKeys: CodingKey { case hint, password, speed, huntTime }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(hint: values.decode(String.self, forKey: .hint),
                          password: values.decode(String.self, forKey: .password),
                          speed: values.decode(UInt8.self, forKey: .speed),
                          huntTime: values.decode(UInt8.self, forKey: .huntTime))
        }
    }
    struct Profile: Codable {
        let schemaVersion: Int
        let edition: GameEdition
        let role: GameDataSourceRole
        let resourceID: Int
        let resourceSHA256: String
        let defaults: Defaults
    }

    static func parse(_ data: Data) throws -> Defaults {
        guard data.count == 1108 else { throw ReferenceDecodeError.value("Unsupported CONF1000 payload length") }
        let reader = BinaryReader(data)
        guard (1...10).contains(Int(try reader.u8(0x126))) else {
            throw ReferenceDecodeError.value("Invalid CONF1000 password length")
        }
        return try Defaults(hint: reader.pascalString(0x26).text,
                            password: reader.pascalString(0x126).text,
                            speed: reader.u8(0x135), huntTime: reader.u8(0x136))
    }
}
