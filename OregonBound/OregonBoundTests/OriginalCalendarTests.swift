import Testing
@testable import OregonBound

struct OriginalCalendarTests {
    @Test func leapDayAndMonthBoundaries() {
        #expect(OriginalCalendar.nextDay(.init(year: 1848, month: 2, day: 28)) == .init(year: 1848, month: 2, day: 29))
        #expect(OriginalCalendar.nextDay(.init(year: 1848, month: 2, day: 29)) == .init(year: 1848, month: 3, day: 1))
        #expect(OriginalCalendar.nextDay(.init(year: 1849, month: 2, day: 28)) == .init(year: 1849, month: 3, day: 1))
        #expect(OriginalCalendar.nextDay(.init(year: 1848, month: 4, day: 30)) == .init(year: 1848, month: 5, day: 1))
    }

    @Test func originalCenturyAndUnsignedYearWrap() {
        #expect(OriginalCalendar.nextDay(.init(year: 1900, month: 2, day: 28)) == .init(year: 1900, month: 2, day: 29))
        #expect(OriginalCalendar.nextDay(.init(year: 65535, month: 12, day: 31)) == .init(year: 0, month: 1, day: 1))
        #expect(OriginalCalendar.nextDay(.init(year: 0, month: 2, day: 28)) == .init(year: 0, month: 2, day: 29))
    }

    @Test func elapsedJourneyDatesAndWholeYearCycle() {
        #expect(OriginalCalendar.date(departureMonth: 3, daysElapsed: 0) == .init(year: 1848, month: 3, day: 1))
        #expect(OriginalCalendar.date(departureMonth: 3, daysElapsed: 306) == .init(year: 1849, month: 1, day: 1))
        #expect(OriginalCalendar.date(departureMonth: 3, daysElapsed: 1461) == .init(year: 1852, month: 3, day: 1))
        #expect(OriginalCalendar.date(departureMonth: 3, daysElapsed: 18_992) == .init(year: 1900, month: 2, day: 29))
        #expect(OriginalCalendar.date(departureMonth: 8, daysElapsed: 23_937_024) == .init(year: 1848, month: 8, day: 1))
    }

    @Test func formatterDoesNotNormalizeOriginalLeapDay() {
        #expect(OriginalCalendar.Components(year: 1900, month: 2, day: 29).text == "February 29, 1900")
        #expect(OriginalCalendar.Components(year: 0, month: 1, day: 1).text == "January 1, 0")
    }

    @Test func optimizedOrdinalMatchesDayTransitions() {
        for month in 3...8 {
            var date = OriginalCalendar.Components(year: 1848, month: month, day: 1)
            for elapsed in 0...1500 {
                #expect(OriginalCalendar.date(departureMonth: month, daysElapsed: elapsed) == date)
                date = OriginalCalendar.nextDay(date)
            }
        }
    }
}
