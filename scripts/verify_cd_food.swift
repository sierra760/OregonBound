// Optional integration verification using a player's prepared CD data.
// Contains no original resource payloads. See CD_DEVELOPMENT.md for build/run steps.
import Foundation

@testable import OregonBound

func require(_ value: Bool, _ message: String = "") { precondition(value, message) }
func requireEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "\(a) != \(b)") }
func requireGreaterThan<T: Comparable>(_ a: T, _ b: T) { precondition(a > b) }
func fail(_ message: String) { preconditionFailure(message) }
func unwrap<T>(_ value: T?) throws -> T {
  guard let value else { throw NSError(domain: "Acceptance", code: 1) }
  return value
}
@main struct Run {
  @MainActor static func main() throws {
    guard CommandLine.arguments.count == 3 else {
      throw NSError(
        domain: "CD food verification", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Usage: verify-cd-food PREPARED_CD_DIRECTORY OUTPUT_DIRECTORY"
        ])
    }
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    for mode in [PreparedGameSession.ColorMode.color256, .color16] {
      let installation = try PreparedGameSession(root: root, colorMode: mode)
      GameData.activate(installation)
      try JourneyAcceptance(installation: installation, output: output).checkAllJourneys()
    }
  }
}
@MainActor final class JourneyAcceptance {
  let installation: PreparedGameSession
  let assets: CDHuntAssets
  let output: URL
  init(installation: PreparedGameSession, output: URL) throws {
    self.installation = installation
    self.assets = try CDHuntAssets(session: installation)
    self.output = output
  }
  func checkAllJourneys() throws {
    for longRoute in [false, true] {
      for raftEnding in [false, true] {
        var trip = Journey(profession: .banker, seed: 73, edition: .macintoshCD12)
        for (item, quantity) in [
          (Supply.oxen, 8), (.food, 1000), (.clothing, 10), (.bullets, 400), (.wheels, 2),
          (.axles, 2), (.tongues, 2),
        ] {
          try JourneyEngine.buy(item, quantity: quantity, in: &trip)
        }
        try JourneyEngine.depart(&trip)
        var hunts = 0
        var meat = 0
        var reloads = 0
        var purchases = 0
        var crossings = 0
        var lastHuntMiles = -1
        let store = JourneyStore(
          directory: output.appendingPathComponent("save"), edition: .macintoshCD12,
          session: installation)
        for _ in 0..<1500 where trip.phase != .finished {
          if trip.canShop && trip.inventory[.food] < 600
            && trip.cash > JourneyEngine.price(.food, quantity: 500, in: trip)
          {
            try JourneyEngine.buy(.food, quantity: 500, in: &trip)
            purchases += 1
          }
          if trip.canCamp && trip.inventory[.oxen] == 0 {
            try requestTrade(.oxen, in: &trip)
          }
          if trip.canCamp && trip.brokenPart != nil {
            for part in trip.damagedParts where trip.inventory[part] == 0 {
              try requestTrade(part, in: &trip)
            }
            try JourneyEngine.repair(&trip)
            continue
          }
          if trip.canHunt && trip.miles != lastHuntMiles && trip.huntingFood < 200
            && trip.totalFood < 600
          {
            lastHuntMiles = trip.miles
            try JourneyEngine.beginHunt(&trip)
            guard trip.phase == .hunting else { break }
            var random = OriginalRandom(seed: trip.randomState)
            let input = OriginalHuntSession.Input(
              destination: (TrailCatalog.stops.firstIndex {
                $0.id == (trip.destinationID ?? trip.locationID)
              } ?? 1) - 1,
              month: trip.month, weatherCategory: trip.originalWeatherCategory,
              snow: (trip.original?.weather.snow ?? 0) != 0, mileage: trip.miles,
              lastSuccessfulHuntMileage: trip.original?.lastSuccessfulHuntMileage ?? 0,
              ammunition: trip.inventory[.bullets], survivors: trip.livingMembers.count,
              currentFood: trip.huntingFood, foodCapacity: trip.huntingFoodCapacity,
              timeSetting: 3, originalDisplayFlag: true, edition: trip.gameEdition,
              rain: Int(trip.original?.weather.rain ?? 0))
            let preparation = CDHuntRules.prepare(
              destination: input.destination, month: input.month, rain: input.rain,
              mileage: input.mileage,
              repeated: input.mileage == input.lastSuccessfulHuntMileage,
              tickSeed: UInt32(100000 + trip.daysElapsed * 131 + hunts * 3001),
              reseed: { random.seed = $0 }, random: { random.bounded($0) })
            var hunt = CDHuntSession(
              input: input, preparation: preparation, assets: assets, startTick: 0
            ) { random.bounded($0) }
            for tick in stride(from: 0, through: 3000, by: 3) where !hunt.isComplete {
              hunt.advance(to: tick) { random.bounded($0) }
              if hunt.foodShot >= 200 { hunt.stop() }
              if hunt.projectile == nil,
                let animal = hunt.animals.first(where: {
                  !$0.dead && $0.species < 10 && $0.rect.x > 80 && $0.rect.right < 430
                })
              {
                let y = animal.rect.y + animal.rect.height / 2
                var x = animal.rect.x + animal.rect.width / 2
                for _ in 0..<3 {
                  let flight = max(abs(x - 256), abs(y - 228)) / 20
                  x = animal.rect.x + animal.rect.width / 2 + animal.velocityX * (flight + 1)
                }
                _ = hunt.shoot(x: x, y: y, at: tick)
              }
            }
            let result = try unwrap(hunt.result)
            trip.randomState = random.seed
            let stored = trip.inventory[.food]
            try JourneyEngine.finishHunt(result: result, in: &trip)
            precondition(trip.inventory[.food] == stored)
            hunts += 1
            meat += result.foodCarried
            continue
          }
          // Original Fair health can be a stable cold-weather state;
          // resting whenever a compatibility percentage is below75
          // creates a permanent rest/travel cycle. Rest at Poor instead.
          if trip.canCamp && trip.healthBadness >= 70 && trip.totalFood > 80 {
            try JourneyEngine.rest(days: 2, in: &trip)
          }
          switch trip.phase {
          case .travel: JourneyEngine.advanceDay(&trip)
          case .landmark, .outfitting: try JourneyEngine.depart(&trip)
          case .departure: try JourneyEngine.chooseDeparture(month: 4, in: &trip)
          case .river:
            let available = JourneyEngine.availableCrossings(in: trip)
            let method: CrossingMethod =
              trip.riverDepth < 2.5
              ? .ford
              : available.contains(.ferry) && trip.cash >= 500
                ? .ferry
                : available.contains(.guide) && trip.inventory[.clothing] >= 3 ? .guide : .caulk
            try JourneyEngine.cross(method, in: &trip)
            crossings += 1
          case .fork:
            if trip.locationID == "dalles" {
              if raftEnding {
                try JourneyEngine.beginRaft(&trip)
              } else {
                try JourneyEngine.takeBarlowRoad(&trip)
              }
            } else {
              let route = longRoute ? trip.location.routes.first! : trip.location.routes.last!
              try JourneyEngine.chooseRoute(route.destination, in: &trip)
            }
          case .rafting:
            try completeRaft(&trip)
          case .hunting: fail("Hunting should settle in its own action")
          case .finished: break
          }
          try store.validate(trip)
          if trip.canSave && trip.daysElapsed % 10 == 0 {
            try store.save(trip)
            let loaded = try store.load()
            precondition(
              loaded.inventory == trip.inventory && loaded.randomState == trip.randomState)
            trip = loaded
            reloads += 1
          }
        }
        requireEqual(trip.phase, .finished)
        require(
          trip.won,
          "route=\(longRoute), raft=\(raftEnding): \(trip.finishReason), days=\(trip.daysElapsed)")
        requireEqual(trip.locationID, "oregon")
        requireGreaterThan(JourneyEngine.score(trip), 0)
        require(trip.visited.contains("bridger") == longRoute)
        require(trip.visited.contains("walla") == longRoute)
        precondition(hunts > 0 && meat > 0 && reloads > 0 && crossings > 0)
        print(
          installation.colorMode.rawValue, "long", longRoute, "raft", raftEnding, "days",
          trip.daysElapsed, "hunts", hunts, "meat", meat, "reloads", reloads, "buys", purchases,
          "crossings", crossings, "stored", trip.inventory[.food], "fresh",
          trip.inventory.perishableFood, "score", JourneyEngine.score(trip))
      }
    }
  }

  private func requestTrade(_ item: Supply, in trip: inout Journey) throws {
    let index = try unwrap(Supply.allCases.firstIndex(of: item))
    for _ in 0..<100 where trip.inventory[item] == 0 {
      try OriginalTradingRules.begin(item: index, displayedQuantity: 1, in: &trip)
      _ = try OriginalTradingRules.finish(accept: true, in: &trip)
    }
    requireGreaterThan(trip.inventory[item], 0)
  }

  private func completeRaft(_ trip: inout Journey) throws {
    var random = OriginalRandom(seed: trip.randomState)
    var raft = OriginalRaftSession(
      input: JourneyEngine.originalRaftInput(trip), startTick: 0, edition: trip.gameEdition
    ) { random.bounded($0) }
    for tick in stride(from: 0, through: 15000, by: 3) where !raft.isComplete {
      // Look ahead using the visible rock trajectories, without peeking at RNG.
      // Choose the nearest reachable gap that stays clear of every visible rock.
      let targets = Array(stride(from: 10, through: 350, by: 20)) + [raft.raftLeft]
      let target = targets.min { predictedRisk($0, raft: raft) < predictedRisk($1, raft: raft) }!
      let mouseX =
        target < raft.raftLeft ? target : target > raft.raftLeft ? target + 63 : target + 31
      raft.dismissCollision()
      raft.advance(to: tick, mouseX: mouseX) { random.bounded($0) }
    }
    let result = try unwrap(raft.result)
    try JourneyEngine.finishRaft(result: result, randomSeed: random.seed, in: &trip)
  }

  private func predictedRisk(_ target: Int, raft: OriginalRaftSession) -> Int {
    var x = raft.raftLeft
    var rocks = raft.rocks
    var collisions = 0
    for _ in 0..<110 {
      let direction = target > x ? 1 : target < x ? -1 : 0
      for i in rocks.indices {
        if OriginalRaftSession.hits(
          rockX: rocks[i].x, rockY: rocks[i].y, raftLeft: x, direction: direction)
        {
          collisions += 1
        }
        rocks[i].accumulator = Float(Double(rocks[i].accumulator) + Double(rocks[i].slope) * 2)
        if rocks[i].slope < 0 && rocks[i].accumulator < -2 {
          rocks[i].x -= 2
          rocks[i].accumulator += 2
        }
        if rocks[i].slope > 0 && rocks[i].accumulator > 2 {
          rocks[i].x += 2
          rocks[i].accumulator -= 2
        }
        rocks[i].y += 2
      }
      x = min(350, max(10, x + direction * min(4, abs(target - x))))
    }
    return collisions * 10000 + abs(target - raft.raftLeft)
  }

}
