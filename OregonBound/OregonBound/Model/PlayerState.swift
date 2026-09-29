import Foundation

/// Per-player data block (110 bytes in the original A5 heap).
/// Covers all 11 named fields from player_data_layout in game_loop_constants.json.
struct PlayerState: Codable, Equatable {
    var statusFlags: UInt8 = 0
    /// 7 supply quantities: food, medicine, ammo, clothing, spareParts, fodder, goods.
    var supply: [Int] = Array(repeating: 0, count: 7)
    var cashInt: Int = 0
    var extraResource: Int = 0
    var illnessRate: Int = 0
    var sickDaysLeft: Int = 0
    /// 0xFF (255) = healthy; 0–8 = disease type (cold, cholera, typhoid, etc.)
    var diseaseType: Int = 0xFF
    var diseaseDuration: Int = 0
    var technologyLevel: Int = 0
    var restDays: Int = 0
    var scoreField: Int = 0
}
