import Testing
@testable import OregonBound

@Suite(.enabled(if: GameData.isReady))
struct OriginalRiverResultContentTests {
    private func outcome(status: Int, losses: [Int] = Array(repeating: 0, count: 7),
                         drowned: [Int] = []) -> OriginalRiverRules.Outcome {
        .init(requestedMethodRaw: 2, animationMethodRaw: 2, failureKind: status == 1 ? 1 : 2,
              status: status, currentFactor: 0, losses: losses, drownedMembers: drowned)
    }

    @Test func bothFailuresRetainTheAuthoredTippedTitleAndPlainTwelve() {
        for status in [1,2] {
            let content = OriginalRiverResultContent(outcome: outcome(status: status), names: [])
            #expect(content.isFailure)
            #expect(content.heading == "Your wagon tipped over while crossing the river.")
            #expect(content.headingFont == .plain12)
        }
    }

    @Test func safeWetAndMudUseTheirOriginalTemplatesAndBoldFourteen() {
        for (status, text) in [
            (0,"You made it safely across the river."),
            (3,"You made it across the river, but got stuck in the muddy river banks."),
            (4,"You made it across the river, but all of your supplies got wet.")
        ] {
            let content = OriginalRiverResultContent(outcome: outcome(status: status), names: [])
            #expect(!content.isFailure && content.heading == text)
            #expect(content.headingFont == .bold14)
            #expect(content.lossRuns.isEmpty)
        }
    }

    @Test func noLossDetailsAreTwoUnindentedOriginalDrawStrings() {
        let content = OriginalRiverResultContent(outcome: outcome(status: 2), names: [])
        #expect(content.lossRuns == [
            .init(text: "Fortunately, nobody was injured and you", x: 10, y: 30),
            .init(text: "recovered all of your supplies.", x: 10, y: 42)
        ])
    }

    @Test func quantityColumnUsesOriginalOrderRoundedOxenAndCommaFormatting() {
        let content = OriginalRiverResultContent(
            outcome: outcome(status: 2, losses: [3,1,2000,0,1,0,1234]), names: [])
        #expect(content.lossRuns == [
            .init(text: "You lost:", x: 10, y: 30),
            .init(text: "2 oxen", x: 60, y: 30),
            .init(text: "1 set of clothing", x: 60, y: 42),
            .init(text: "2,000 bullets", x: 60, y: 54),
            .init(text: "1 wagon axle", x: 60, y: 66),
            .init(text: "1,234 pounds of food", x: 60, y: 78)
        ])
    }

    @Test func drowningUsesSlotOrderAndLeaderFlagSelectsWholePartyText() {
        let names = ["Leader","Anna","Beth","Joey","Mary"]
        let companions = OriginalRiverResultContent(outcome: outcome(status: 2, drowned: [3,1]), names: names)
        #expect(companions.lossRuns == [
            .init(text: "You lost:", x: 10, y: 30),
            .init(text: "Anna (drowned)", x: 60, y: 30),
            .init(text: "Joey (drowned)", x: 60, y: 42)
        ])
        let everyone = OriginalRiverResultContent(outcome: outcome(status: 1, drowned: [4,3,2,1,0]), names: names)
        #expect(everyone.lossRuns == [
            .init(text: "You lost:", x: 10, y: 30),
            .init(text: "Everyone in your wagon has died.", x: 60, y: 30)
        ])
    }
}

struct CDRiverResultContentTests {
    @Test func eightSlotLabelsUseTheCDSingularOffsetAndKeepRowOrder() {
        let outcome = OriginalRiverRules.Outcome(requestedMethodRaw: 1, animationMethodRaw: 1,
            failureKind: 1, status: 1, currentFactor: 0, losses: [2,2,0,0,0,0,1,1])
        let content = OriginalRiverResultContent(outcome: outcome, names: [], edition: .macintoshCD12) { id in
            if id == 3011 { return (0..<8).map { "plural\($0)" } + (0..<8).map { "singular\($0)" } }
            return ["safe", "mud", "wet", "crossing", "none1", "none2", "Lost:", " drowned"]
        }
        #expect(content.lossRuns == [
            .init(text: "Lost:", x: 10, y: 30),
            .init(text: "1 singular0", x: 60, y: 30),
            .init(text: "2 plural1", x: 60, y: 42),
            .init(text: "1 singular6", x: 60, y: 54),
            .init(text: "1 singular7", x: 60, y: 66)
        ])
    }
}
