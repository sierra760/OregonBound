import Foundation

struct SubsystemConstants: Codable {
    let metadata: Metadata
    let hunt_minigame: [String: AnyCodable]
    let river_crossing: [String: AnyCodable]
    let raft_crossing: [String: AnyCodable]
    let shopping: [String: AnyCodable]
    let ending_scoring: [String: AnyCodable]
}

extension SubsystemConstants {
    struct Metadata: Codable {
        let source: String
        let segments_analyzed: [String]
        let generated_at: String
        let notes: String
    }
}
