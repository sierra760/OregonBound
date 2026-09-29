import XCTest
@testable import OregonBound

final class OriginalSaveImportTests: XCTestCase {
    private var runtime: OriginalSaveImport.RuntimeContext {
        .init(journeyID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
              difficulty: .adventurer, randomSeed: 0x12345678, lastSuccessfulHuntMileage: 37)
    }
    /// Synthetic fixture: no claim that it came from the original emulator.
    private func fixture(destination: Int = 0, remaining: UInt8 = 82, length: UInt8 = 102,
                         miles: UInt16 = 20, routeFlags: UInt8 = 0) throws -> OriginalSaveArchive {
        var bytes = Data(repeating: 0, count: OriginalSaveArchive.byteCount)
        bytes.replaceSubrange(0..<6, with: [0x4d,0x45,0x43,0x43,0,2])
        // Saved landmark artwork was not suppressed at this destination.
        bytes[38] = 255; bytes[39] = 254
        var archive = try OriginalSaveArchive(data: bytes)
        var world = archive.worldBytes
        world[8] = 1; world[0x23f] = 1
        world[0x25e+0x61] = 255; world[0x25e+0x62] = 4
        world[0x25e+0x66] = 0; world[0x25e+0x67] = 3
        world[0x22a] = 11; world[0x22b] = 70
        try archive.replaceWorldBytes(world)
        archive.setWorldByte(.wagonSlotCount,1)
        archive.setWorldByte(.departureMonth,4); archive.setWorldByte(.departureDay,1)
        archive.setWorldWord(.year,1848); archive.setWorldByte(.month,4); archive.setWorldByte(.day,2)
        archive.setWorldByte(.simulationSpeed,4); archive.setWorldByte(.huntTime,3)
        archive.setWorldByte(.destinationRaw,UInt8(truncatingIfNeeded: destination))
        archive.setWorldByte(.remainingMiles,remaining); archive.setWorldByte(.legLength,length)
        archive.setWorldWord(.cumulativeMiles,miles); archive.setWorldByte(.routeFlags,routeFlags)
        archive.setWorldByte(.flags,15); archive.setWorldByte(.restDays,6)
        archive.setWorldByte(.temperatureCategory,2); archive.setWorldByte(.weatherCategory,131)
        archive.setWorldByte(.climateRow,5); archive.setWorldWord(.rainAccumulator,1234)
        archive.setWorldWord(.snowAccumulator,700); archive.setWorldWord(.rainIncrement,80)
        archive.setWorldWord(.snowIncrement,160); archive.setWorldByte(.lastMovement,20)
        try archive.setPlayerByte(.flags,14,record:0) // All three saved broken parts; reset on original load.
        try archive.setPlayerByte(.memberSlotCount,2,record:0)
        try archive.setPlayerByte(.survivors,2,record:0)
        try archive.setPlayerByte(.occupation,5,record:0)
        try archive.setPlayerByte(.healthBadness,70,record:0)
        try archive.setPlayerByte(.auxiliaryHealth,3,record:0)
        try archive.setPlayerByte(.pendingPenalty,7,record:0)
        try archive.setMemberName(" Alice ",memberSlot:0,wagonSlot:0)
        try archive.setMemberName("André",memberSlot:1,wagonSlot:0)
        try archive.setPlayerWord(.rawOxen,11,record:0)
        try archive.setPlayerWord(.food,1234,record:0)
        try archive.setPlayerWord(.spareWheels,2,record:0)
        try archive.setPlayerLong(.cashCents,12345,record:0)
        return archive
    }
    func testNormalTravelProjectionPreservesOriginalBytesAndRuntimeContext() throws {
        let archive = try fixture()
        let result = try OriginalSaveImport.read(archive,runtime:runtime)
        let trip = result.journey
        XCTAssertEqual(result.archive.data,archive.data)
        XCTAssertEqual(trip.id,runtime.journeyID)
        XCTAssertEqual(trip.randomState,runtime.randomSeed)
        XCTAssertEqual(trip.original?.lastSuccessfulHuntMileage,37)
        XCTAssertEqual(trip.profession,.merchant)
        XCTAssertEqual(trip.difficulty,.adventurer)
        XCTAssertEqual(trip.phase,.travel)
        XCTAssertEqual(trip.locationID,"independence")
        XCTAssertEqual(trip.destinationID,"kansas")
        XCTAssertEqual(trip.legProgress,20)
        XCTAssertEqual(trip.milesToNext,82)
        XCTAssertEqual(trip.visited,["independence"])
        XCTAssertEqual(trip.daysElapsed,1)
        XCTAssertEqual(trip.members.map(\.name),[" Alice ","André"])
        XCTAssertEqual(trip.members[1].illness,"Typhoid")
        XCTAssertEqual(trip.members[1].sickDays,3)
        XCTAssertEqual(trip.members.map(\.health),[35,35])
        XCTAssertEqual(trip.inventory[.oxen],11)
        XCTAssertEqual(trip.displayQuantity(.oxen),6)
        XCTAssertEqual(trip.cash,12345)
        XCTAssertEqual(trip.original?.weather.rain,1234)
        XCTAssertEqual(trip.original?.weather.category,131)
        XCTAssertEqual(trip.original?.weather.region,5)
        XCTAssertEqual(trip.original?.flags,0)
        XCTAssertEqual(trip.original?.restDays,6)
        XCTAssertEqual(trip.damagedParts,[])
        XCTAssertTrue(trip.journal.isEmpty)
        XCTAssertFalse(result.unmapped.isEmpty)
        try JourneyStore(directory: URL(fileURLWithPath:"/tmp/unused-import-validation")).validate(trip)
    }
    func testStoppedRiverUsesStoredDimensionsAndSavedMapSuppression() throws {
        let source = try fixture(remaining:0,miles:102)
        var bytes = source.data
        bytes[38] = 0; bytes[39] = 0
        let result = try OriginalSaveImport.read(OriginalSaveArchive(data:bytes),runtime:runtime)
        XCTAssertEqual(result.journey.phase,.river)
        XCTAssertEqual(result.journey.locationID,"kansas")
        XCTAssertEqual(result.journey.originalMapSuppressedLandmarkID,"kansas")
        XCTAssertEqual(result.journey.riverDepth,5.5)
        XCTAssertEqual(result.journey.riverWidth,700)
        XCTAssertEqual(result.journey.visited,["independence","kansas"])
        // Current rain would produce different dimensions; no recomputation permitted.
        XCTAssertNotEqual(result.journey.originalRiverDimensions,
                          OriginalRiverRules.dimensions(destination:0,rain:1234))
    }
    func testBothForksRecoverSkippedFortsAndCurrentLeg() throws {
        let green = try OriginalSaveImport.read(fixture(destination:8,remaining:100,length:125,miles:957,routeFlags:1),runtime:runtime).journey
        XCTAssertEqual(green.locationID,"south-pass")
        XCTAssertEqual(green.destinationID,"green")
        XCTAssertFalse(green.visited.contains("bridger"))
        let dalles = try OriginalSaveImport.read(fixture(destination:15,remaining:100,length:125,miles:1739,routeFlags:3),runtime:runtime).journey
        XCTAssertEqual(dalles.locationID,"blue-mountains")
        XCTAssertFalse(dalles.visited.contains("walla"))
        XCTAssertFalse(dalles.visited.contains("bridger"))
    }
    func testInitialLandmarkFinalRoadAndDeceasedMember() throws {
        let initial = try OriginalSaveImport.read(fixture(destination:-1,remaining:0,length:0,miles:0),runtime:runtime).journey
        XCTAssertEqual(initial.phase,.landmark)
        XCTAssertEqual(initial.locationID,"independence")
        // Via both skipped forts:1839 miles at The Dalles, then20 on the final road.
        var archive = try fixture(destination:16,remaining:80,length:100,miles:1859,routeFlags:3)
        var world = archive.worldBytes
        world[0x25e+0x62] = 9
        try archive.replaceWorldBytes(world)
        try archive.setPlayerByte(.survivors,1,record:0)
        let finalRoad = try OriginalSaveImport.read(archive,runtime:runtime).journey
        XCTAssertEqual(finalRoad.phase,.travel)
        XCTAssertEqual(finalRoad.locationID,"dalles")
        XCTAssertEqual(finalRoad.destinationID,"oregon")
        XCTAssertFalse(finalRoad.members[1].alive)
        XCTAssertEqual(finalRoad.members[1].name,"André")
        try JourneyStore(directory:URL(fileURLWithPath:"/tmp/unused-import-validation")).validate(finalRoad)
    }
    func testOriginalLeapCalendarAndInvalidDateRejection() throws {
        var archive = try fixture()
        archive.setWorldWord(.year,1900); archive.setWorldByte(.month,2); archive.setWorldByte(.day,29)
        let trip = try OriginalSaveImport.read(archive,runtime:runtime).journey
        XCTAssertEqual(trip.originalDate,.init(year:1900,month:2,day:29))
        archive.setWorldWord(.year,1901)
        XCTAssertThrowsError(try OriginalSaveImport.read(archive,runtime:runtime))
        archive.setWorldWord(.year,0)
        XCTAssertThrowsError(try OriginalSaveImport.read(archive,runtime:runtime))
    }
    func testUnknownJournalAndAllOpaqueBytesSurviveWithoutInventedNativeRows() throws {
        var bytes = try fixture().data
        bytes[10000] = 0xa5
        bytes.append(contentsOf:[1,2,3])
        let state = OriginalSaveArchive.journalStateOffset
        bytes[state+7] = 2 // used byte count; zero base
        bytes[OriginalSaveArchive.journalOffset] = 96 // unsupported opcode
        let result = try OriginalSaveImport.read(OriginalSaveArchive(data:bytes),runtime:runtime)
        XCTAssertEqual(result.archive.data,bytes)
        XCTAssertEqual(result.compactJournal,.undecodable(.unsupportedOpcode(96,offset:0)))
        XCTAssertTrue(result.journey.journal.isEmpty)
    }
    func testUnsupportedStatesFailExplicitlyInsteadOfCoercing() throws {
        var multi = try fixture(); multi.setWorldByte(.wagonSlotCount,2)
        XCTAssertThrowsError(try OriginalSaveImport.read(multi,runtime:runtime))
        for (field,value): (OriginalSaveArchive.WorldByteField,UInt8) in [(.routeFlags,4),(.destinationRaw,16),(.pace,3),(.huntTime,0),(.climateRow,6),(.temperatureCategory,6)] {
            var archive = try fixture(); archive.setWorldByte(field,value)
            XCTAssertThrowsError(try OriginalSaveImport.read(archive,runtime:runtime))
        }
        var dead = try fixture(); try dead.setPlayerByte(.survivors,0,record:0)
        XCTAssertThrowsError(try OriginalSaveImport.read(dead,runtime:runtime))
        var brokenMileage = try fixture(); brokenMileage.setWorldWord(.cumulativeMiles,21)
        XCTAssertThrowsError(try OriginalSaveImport.read(brokenMileage,runtime:runtime))
    }

    func testOriginalLoadRetainsDormantDelayWithoutChangingContinuation() throws {
        var archive = try fixture()
        archive.setWorldByte(.delayDays, 255)
        let result = try OriginalSaveImport.read(archive, runtime: runtime)
        XCTAssertEqual(result.archive.data, archive.data)
        var imported = result.journey
        XCTAssertEqual(imported.delayDays, 255)
        XCTAssertEqual(imported.original?.flags, 0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("oregon-import-delay-\(UUID())")
        defer {
            if FileManager.default.fileExists(atPath: directory.path) { try? FileManager.default.removeItem(at: directory) }
        }
        let store = JourneyStore(directory: directory)
        XCTAssertNoThrow(try store.validate(imported))
        try store.save(imported)
        imported = try store.load()
        XCTAssertEqual(imported, result.journey)
        for invalidCounter in [-1, 256] {
            var invalid = imported
            invalid.delayDays = invalidCounter
            XCTAssertThrowsError(try store.validate(invalid))
        }
        let paused = imported
        XCTAssertFalse(JourneyEngine.advanceActionDay(in: &imported))
        XCTAssertEqual(imported, paused)
        var control = imported
        control.delayDays = 0
        JourneyEngine.resumeTravel(in: &imported)
        JourneyEngine.resumeTravel(in: &control)
        XCTAssertTrue(JourneyEngine.advanceActionDay(in: &imported))
        XCTAssertTrue(JourneyEngine.advanceActionDay(in: &control))
        XCTAssertEqual(imported.delayDays, 255)
        XCTAssertEqual(imported.original!.flags & 8, 0)
        imported.delayDays = 0
        XCTAssertEqual(imported, control)
    }
}
