import Testing
@testable import OregonBound

struct CDHuntRulesTests {
    @Test func terrainUsesRainAndOriginalBranchOrder() {
        let cases: [(Int, Int, [Int], Int)] = [
            (2,40,[0],9), (2,40,[1],1), (2,41,[0],3), (2,41,[1],0),
            (3,0,[],7), (4,0,[],7), (5,0,[0],2), (5,0,[1],7),
            (6,0,[1],4), (9,0,[0,1],6), (9,0,[0,0],2),
            (10,0,[0],5), (12,0,[1],4), (13,0,[],6),
            (14,0,[0],4), (16,0,[1],5), (17,0,[2],8)
        ]
        for (destination,rain,rolls,expected) in cases {
            var pending = rolls
            let habitat = CDHuntRules.habitat(destination: destination,rain: rain) { bound in
                #expect(bound == (destination >= 14 ? 3 : 2))
                return pending.removeFirst()
            }
            #expect(habitat == expected)
            #expect(pending.isEmpty)
        }
    }

    @Test func seasonalFlyingPopulationsAndHabitatExclusions() {
        #expect(CDHuntRules.initialWeights(destination: 2,month: 4,habitat: 1,repeated: false)
                == [15,25,20,20,0,0,0,0,15,8,0])
        #expect(CDHuntRules.initialWeights(destination: 6,month: 4,habitat: 2,repeated: false)
                == [0,0,20,20,0,0,20,15,0,15,0])
        #expect(CDHuntRules.initialWeights(destination: 13,month: 11,habitat: 6,repeated: true)
                == [0,0,40,40,15,0,20,15,0,15,0])
        #expect(CDHuntRules.initialWeights(destination: 14,month: 10,habitat: 4,repeated: false)
                == [0,25,20,20,15,10,20,0,0,8,0])
        for month in 1...12 {
            let w = CDHuntRules.initialWeights(destination: 3,month: month,habitat: 7,repeated: false)
            #expect(w[9] == ([2,3,9,10,11].contains(month) ? 15 : 8))
            #expect(w[7] == ([1,2,3,12].contains(month) ? 15 : 0))
            #expect(w[8] == ((4...10).contains(month) ? 15 : 8))
            #expect(w[10] == 0)
        }
    }

    @Test func firstVisitPreservesLastCountedLargeAnimalAndRandomCallOrder() {
        var rolls = [0,0,1,8]
        var bounds: [Int] = []
        let weights = CDHuntRules.population(destination: 2,month: 4,habitat: 1,repeated: false) {
            bounds.append($0); return rolls.removeFirst()
        }
        #expect(weights == [0,25,0,20,0,0,0,0,0,8,0])
        #expect(bounds == [2,11,11,11] && rolls.isEmpty)
    }

    @Test func sourceCountExcludesClassSixButRemovalProtectsIt() {
        var rolls = [0,6,9]
        let weights = CDHuntRules.population(destination: 6,month: 4,habitat: 2,repeated: false) { _ in
            rolls.removeFirst()
        }
        #expect(weights == [0,0,0,20,0,0,20,15,0,0,0])
        #expect(rolls.isEmpty)
    }

    @Test func repeatedAreaAllowsRemovingEveryLargeAnimal() {
        var rolls = [0,1,2]
        let weights = CDHuntRules.population(destination: 2,month: 4,habitat: 1,repeated: true) { bound in
            #expect(bound == 11); return rolls.removeFirst()
        }
        #expect(weights == [0,0,0,40,0,0,0,0,15,8,0])
        #expect(rolls.isEmpty)
    }

    @Test func preparationReseedsMileageThenTicksBeforePopulation() {
        var stream = OriginalRandom(seed: 999)
        var seeds: [UInt32] = []
        let prepared = CDHuntRules.prepare(destination: 6,month: 4,rain: 0,mileage: 65537,
                                          repeated: false,tickSeed: 1234,reseed: {
            seeds.append($0); stream.seed = $0
        },random: { stream.bounded($0) })
        var terrainRandom = OriginalRandom(seed: 1)
        let habitat = CDHuntRules.habitat(destination: 6,rain: 0) { terrainRandom.bounded($0) }
        var populationRandom = OriginalRandom(seed: 1234)
        let population = CDHuntRules.population(destination: 6,month: 4,habitat: habitat,repeated: false) {
            populationRandom.bounded($0)
        }
        #expect(seeds == [1,1234])
        #expect(prepared.habitat == habitat && prepared.population == population)
        #expect(stream.seed == populationRandom.seed)
    }
}
