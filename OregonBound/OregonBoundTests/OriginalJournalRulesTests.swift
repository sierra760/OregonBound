import Testing
@testable import OregonBound

struct OriginalJournalRulesTests {
    @Test func originalTerminalByteRuleHasLiteralBoundaryQuirks() {
        #expect(OriginalJournalRules.finishSentence("Heavy fog") == "Heavy fog.")
        #expect(OriginalJournalRules.finishSentence("A period.") == "A period.")
        #expect(OriginalJournalRules.finishSentence("A") == "A.")
        #expect(OriginalJournalRules.finishSentence("y") == "y.")
        #expect(OriginalJournalRules.finishSentence("z") == "z") // CODE14:18ae uses BLS.
        #expect(OriginalJournalRules.finishSentence("[") == "[.")
        #expect(OriginalJournalRules.finishSentence("10") == "10")
        #expect(OriginalJournalRules.finishSentence("é") == "é")
        #expect(OriginalJournalRules.finishSentence("") == "")
        let full = String(repeating: "a",count: 255)
        #expect(OriginalJournalRules.finishSentence(full) == full) // CODE14:1c08.
    }
    @Test func originalPurchaseListMatchesReferenceAndKeepsTwoItemComma() {
        let full = OriginalJournalRules.supplyEvent(id: 68,
            rawQuantities: [12,10,100,1,1,1,1000],cashCents: 114000)
        #expect(full == "You started down the trail with 6 oxen, 10 sets of clothing, 100 bullets, 1 wagon wheel, 1 wagon axle, 1 wagon tongue, 1,000 pounds of food, and $1,140.00.")
        #expect(OriginalJournalRules.supplyList(rawQuantities: [0,0,1,0,0,0,1]) == "1 bullet, and 1 pound of food")
        #expect(OriginalJournalRules.supplyList(rawQuantities: [0,0,0,0,0,0,0],cashCents: 114005) == "$1,140.05")
        #expect(OriginalJournalRules.supplyList(rawQuantities: [3,0,0,0,0,0,0]) == "2 oxen")
    }
    @Test func packetWidthsAndEmptyLossesPreserveOriginalMessages() {
        #expect(OriginalJournalRules.supplyList(rawQuantities: [0,260,-30,0,0,0,-30],cashCents: -100) == "4 sets of clothing")
        #expect(OriginalJournalRules.supplyEvent(id: 63,rawQuantities: [0,0,0,0,0,0,0]) == "You found an abandoned wagon, but there were no supplies to be scavenged.")
        #expect(OriginalJournalRules.supplyEvent(id: 66,rawQuantities: [0,0,0,0,0,0,-30]) == "Your wagon tipped but you lost nothing.")
        #expect(OriginalJournalRules.supplyEvent(id: 66,rawQuantities: [0,0,0,0,0,0,1]) == "Your wagon tipped and you lost 1 pound of food.")
    }
    @Test func shortJournalActionsDifferFromDetailedHuntingPane() {
        #expect(OriginalJournalRules.huntReturn(food: 100) == "You brought back 100 pounds of food from hunting.")
        #expect(OriginalJournalRules.decision(.hunt) == "You decided to hunt.")
        #expect(OriginalJournalRules.decision(.rest(1)) == "You decided to rest for one day.")
        #expect(OriginalJournalRules.decision(.rest(2)) == "You decided to rest for 2 days.")
        #expect(OriginalJournalRules.decision(.pace(2)) == "You decided to change the pace to grueling.")
        #expect(OriginalJournalRules.decision(.crossing(2)) == "You chose to caulk your wagon and float it across the river.")
        #expect(OriginalJournalRules.decision(.trail(name: "Fort Bridger",originalIndex: 8)) == "You decided to take the trail to Fort Bridger.")
        #expect(OriginalJournalRules.decision(.trail(name: "take the Barlow Toll Road",originalIndex: 17)) == "You decided to take the Barlow Toll Road.") // Literal prefix omission.
        #expect(OriginalJournalRules.rations(2) == "You changed your rations to bare bones.")
        #expect(OriginalJournalRules.drownedMembers(1) == "1 member of your wagon drowned.")
        #expect(OriginalJournalRules.drownedMembers(2) == "2 members of your wagon drowned.")
        #expect(OriginalJournalRules.currentWagonTemplate(event: 44) == "Everyone in your wagon has died.")
        #expect(OriginalJournalRules.weatherEvent(8) == "Severe storm.")
    }
    @Test func cdFoodSupplyListDistinguishesBothPoolsAndSignedLossWords() {
        #expect(OriginalJournalRules.supplyList(rawQuantities: [0,0,0,0,0,0,1,2], edition: .macintoshCD12)
                == "1 pound of food, and 2 pounds of perishable food")
        #expect(OriginalJournalRules.supplyList(rawQuantities: [0,0,0,0,0,0,-5,1], edition: .macintoshCD12)
                == "1 pound of perishable food")
    }

}
