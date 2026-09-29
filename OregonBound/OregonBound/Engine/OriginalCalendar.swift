/// CODE16:1e9e–1f22: unsigned 16-bit years and a leap day every four years.
/// Foundation's Gregorian century exception would erase February29,1900.
enum OriginalCalendar {
    struct Components: Equatable, Sendable {
        let year: Int
        let month: Int
        let day: Int

        var text: String { "\(OriginalCalendar.monthNames[month - 1]) \(day), \(year)" }
    }

    static let monthNames = ["January", "February", "March", "April", "May", "June",
                             "July", "August", "September", "October", "November", "December"]
    private static let monthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    private static let yearCycleDays = 23_937_024 // 65,536 / 4 * 1,461

    /// Requires valid original components, including February29 in years%4==0.
    static func nextDay(_ date: Components) -> Components {
        var year = date.year, month = date.month, day = date.day + 1
        if day > monthLengths[month - 1] {
            if day == 29 && year % 4 == 0 { return .init(year: year, month: month, day: day) }
            day = 1
            month += 1
            if month > 12 {
                month = 1
                year = (year + 1) & 0xffff
            }
        }
        return .init(year: year, month: month, day: day)
    }

    /// Original departure is day1 of a selected month in1848. Normalizes the
    /// elapsed ordinal in constant time across the original UInt16 year cycle.
    /// Invalid external month/day-count inputs are clamped before indexing.
    static func date(departureMonth: Int, daysElapsed: Int) -> Components {
        let startingMonth = min(12, max(1, departureMonth))
        let beforeMonth = monthLengths.prefix(startingMonth - 1).reduce(0, +)
            + (startingMonth > 2 ? 1 : 0) // 1848 is leap
        let start = (1848 / 4) * 1461 + beforeMonth
        let ordinal = (start + max(0, daysElapsed) % yearCycleDays) % yearCycleDays
        var year = (ordinal / 1461) * 4
        var dayOfYear = ordinal % 1461
        if dayOfYear >= 366 {
            dayOfYear -= 366
            year += 1 + dayOfYear / 365
            dayOfYear %= 365
        }
        var month = 1
        while month < 12 {
            let count = monthLengths[month - 1] + (month == 2 && year % 4 == 0 ? 1 : 0)
            if dayOfYear < count { break }
            dayOfYear -= count
            month += 1
        }
        return .init(year: year, month: month, day: dayOfYear + 1)
    }
}
