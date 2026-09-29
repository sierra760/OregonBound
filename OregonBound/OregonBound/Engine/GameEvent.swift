import Foundation

/// Structured events emitted by the day cycle engine.
/// Raw message IDs match game_loop_constants.json event_message_ids section.
enum GameEvent: Equatable {

    // MARK: - Party-level events (FUN_00002906 dispatch)

    case goodTravelDay          // id 0
    case badTravelDay           // id 1
    case trailImpassable        // id 4 — severe storm blocks trail
    case goodHunting            // id 5
    case fogStop                // id 7 — fog/obstacle stops travel
    case stormStop              // id 8 — storm stops travel
    case reachedFort            // id 9
    case rest10Days             // id 10 — short fort rest
    case rest20Days             // id 11 — long fort rest
    case arrivedLandmark        // id 12

    // MARK: - Player-level events (FUN_0000294a dispatch)

    case lostDays(playerIndex: Int)                                 // id 20
    case minorAccident(playerIndex: Int)                            // id 21
    case supplyFoundTech(playerIndex: Int)                          // id 22
    case supplyFoundA(playerIndex: Int)                             // id 23
    case supplyFoundB(playerIndex: Int)                             // id 24
    case mildInjury(playerIndex: Int)                               // id 26
    case moderateInjury(playerIndex: Int)                           // id 27
    case seriousInjury(playerIndex: Int)                            // id 28
    case coldExposure(playerIndex: Int)                             // id 29
    case theftBlocked(playerIndex: Int)                             // id 30
    case theftPrevented(playerIndex: Int)                           // id 31
    case theftSupplyStolen(playerIndex: Int, supplyType: Int)       // id 33
    case theftCriticalStolen(playerIndex: Int, supplyType: Int)     // id 34
    case starvation(playerIndex: Int)                               // id 35
    case playerDeath(playerIndex: Int)                              // id 44 (0x2C)
    case diseaseRecovery(playerIndex: Int)                          // id 52
    case diseaseMild(playerIndex: Int)                              // id 54
    case diseaseModerate(playerIndex: Int)                          // id 55
    case diseaseVariant(playerIndex: Int)                           // id 58
    case suppliesFound(playerIndex: Int)                            // id 63
    case theftCashStolen(playerIndex: Int)                          // id 64
    case accidentSupplies(playerIndex: Int)                         // id 65

    // MARK: - Message ID

    var messageId: Int {
        switch self {
        case .goodTravelDay:               return 0
        case .badTravelDay:                return 1
        case .trailImpassable:             return 4
        case .goodHunting:                 return 5
        case .fogStop:                     return 7
        case .stormStop:                   return 8
        case .reachedFort:                 return 9
        case .rest10Days:                  return 10
        case .rest20Days:                  return 11
        case .arrivedLandmark:             return 12
        case .lostDays:                    return 20
        case .minorAccident:               return 21
        case .supplyFoundTech:             return 22
        case .supplyFoundA:                return 23
        case .supplyFoundB:                return 24
        case .mildInjury:                  return 26
        case .moderateInjury:              return 27
        case .seriousInjury:               return 28
        case .coldExposure:                return 29
        case .theftBlocked:                return 30
        case .theftPrevented:              return 31
        case .theftSupplyStolen:           return 33
        case .theftCriticalStolen:         return 34
        case .starvation:                  return 35
        case .playerDeath:                 return 44
        case .diseaseRecovery:             return 52
        case .diseaseMild:                 return 54
        case .diseaseModerate:             return 55
        case .diseaseVariant:              return 58
        case .suppliesFound:               return 63
        case .theftCashStolen:             return 64
        case .accidentSupplies:            return 65
        }
    }
}
