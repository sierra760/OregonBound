/// CODE6:1c1e–1c56,096e–0a28. These are the original single-wagon action checks;
/// app lifecycle/phase validation belongs to the caller and consumes no RNG.
enum OriginalHuntEligibility {
    enum Decision: Equatable {
        case allowed, severeWeather, occupiedLandmark, noBullets, silentBusy, beepBusy

        /// Original STR3022 notices omit a terminal period.
        func notice(landmarkName: String) -> String? {
            switch self {
            case .severeWeather: return "You can’t go hunting because the weather is too severe"
            case .occupiedLandmark: return "Hunting is not allowed near \(landmarkName), because there are too many people around"
            case .noBullets: return "You can’t go hunting because you have no bullets"
            case .allowed, .silentBusy, .beepBusy: return nil
            }
        }
    }

    /// playerFlags is player+0; playerActionFlags is player+1, NOT world+5.
    /// Multiplayer callers would count matches over all active wagons instead.
    static func evaluate(weatherCategory: UInt8, milesRemaining: UInt8, ammunition: Int16,
                         playerFlags: UInt8 = 0, playerActionFlags: UInt8 = 0) -> Decision {
        if weatherCategory >= 7 { return .severeWeather } // CODE6:1c24–1c32.
        if playerFlags & 0x80 != 0 { return .silentBusy } // 1c3a–1c54.
        if milesRemaining == 0 { return .occupiedLandmark } // 0974–0980.
        if ammunition <= 0 { return .noBullets } // 09ca–09da signed word.
        if playerFlags & 0xf0 != 0 || playerActionFlags & 2 != 0 { return .beepBusy } // 09e2–0a02.
        return .allowed
    }
}
