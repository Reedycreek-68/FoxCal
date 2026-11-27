import Foundation

extension Calendar {
    /// Gregorianischer Kalender nach deutscher Konvention:
    /// Woche beginnt am Montag, Kalenderwochen nach ISO 8601.
    static let foxCal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }

    /// Die sieben Tage (Mo–So) der Woche, die `date` enthält.
    func daysOfWeek(containing date: Date) -> [Date] {
        let start = startOfWeek(for: date)
        return (0..<7).compactMap { self.date(byAdding: .day, value: $0, to: start) }
    }

    /// Alle Tage, die im Monatsraster erscheinen – vom Montag der ersten
    /// bis zum Sonntag der letzten Woche des Monats.
    func monthGridDays(for date: Date) -> [Date] {
        guard
            let month = dateInterval(of: .month, for: date),
            let lastDayOfMonth = self.date(byAdding: .day, value: -1, to: month.end),
            let gridEnd = dateInterval(of: .weekOfYear, for: lastDayOfMonth)?.end
        else { return [] }

        var days: [Date] = []
        var current = startOfWeek(for: month.start)
        while current < gridEnd {
            days.append(current)
            guard let next = self.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    func isWeekend(_ date: Date) -> Bool {
        isDateInWeekend(date)
    }
}

extension Locale {
    static let german = Locale(identifier: "de_DE")
}

extension FormatStyle where Self == Date.FormatStyle {
    /// Uhrzeit im deutschen Format mit zwei Stellen, z. B. „09:05“.
    static var foxTime: Date.FormatStyle {
        .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(.german)
    }
}
