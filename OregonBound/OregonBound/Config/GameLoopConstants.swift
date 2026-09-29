import Foundation

// MARK: - Shared entry types

/// A value and its source references from game_loop_constants.json.
/// `T` is typically `Int` or `String`.
struct ConstantEntry<T: Codable>: Codable {
    let value: T
    let hex: String?
    let source_function: String?
    let address: String?
    let context: String?
}

// MARK: - Top-level model

struct GameLoopConstants: Codable {
    let metadata: Metadata
    let game_initialization: GameInitialization
    let game_state_block_layout: [String: AnyCodable]
    let player_data_layout: [String: AnyCodable]
    let weather_system: [String: AnyCodable]
    let event_probabilities: [String: AnyCodable]
    let illness_system: [String: AnyCodable]
    let death_system: [String: AnyCodable]
    let supply_capacity_limits: [String: AnyCodable]
    let random_number_system: [String: AnyCodable]
    let event_message_ids: [String: AnyCodable]
    let display_engine: [String: AnyCodable]
    let a5_jump_table_entries: [String: AnyCodable]
}

// MARK: - Metadata

extension GameLoopConstants {
    struct Metadata: Codable {
        let source: String
        let segments_analyzed: [String]
        let generated_at: String
        let notes: String
        let functions_analyzed: FunctionsAnalyzed

        struct FunctionsAnalyzed: Codable {
            let Display: Int
            let Model: Int
        }
    }
}

// MARK: - Game Initialization

extension GameLoopConstants {
    /// Initialization constants derived from FUN_00000564 and related functions.
    struct GameInitialization: Codable {
        let starting_year: ConstantEntry<Int>
        let trail_total_distance: ConstantEntry<Int>
        let max_party_size: ConstantEntry<Int>
        let player_record_size: ConstantEntry<Int>
        let player_data_base_offset: ConstantEntry<Int>
        let doctor_headstart_max_miles: ConstantEntry<Int>
        /// Non-standard entry: describes the formula for starting distance rather than a bare value.
        let distance_start_formula: DistanceStartFormula
        let save_file_signature: ConstantEntry<String>
        let save_resource_id: ConstantEntry<Int>
    }

    struct DistanceStartFormula: Codable {
        let description: String
        let formula: String
        let range: String
        let source_function: String
        let address: String
        let context: String
    }
}
