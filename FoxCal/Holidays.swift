import Foundation

enum GermanState: String, CaseIterable, Identifiable {
    case badenWuerttemberg = "BW"
    case bayern = "BY"
    case berlin = "BE"
    case brandenburg = "BB"
    case bremen = "HB"
    case hamburg = "HH"
    case hessen = "HE"
    case mecklenburgVorpommern = "MV"
    case niedersachsen = "NI"
    case nordrheinWestfalen = "NW"
    case rheinlandPfalz = "RP"
    case saarland = "SL"
    case sachsen = "SN"
    case sachsenAnhalt = "ST"
    case schleswigHolstein = "SH"
    case thueringen = "TH"

    var id: Self { self }

    var abbreviation: String { rawValue }

    var name: String {
        switch self {
        case .badenWuerttemberg: "Baden-Württemberg"
        case .bayern: "Bayern"
        case .berlin: "Berlin"
        case .brandenburg: "Brandenburg"
        case .bremen: "Bremen"
        case .hamburg: "Hamburg"
        case .hessen: "Hessen"
        case .mecklenburgVorpommern: "Mecklenburg-Vorpommern"
        case .niedersachsen: "Niedersachsen"
        case .nordrheinWestfalen: "Nordrhein-Westfalen"
        case .rheinlandPfalz: "Rheinland-Pfalz"
        case .saarland: "Saarland"
        case .sachsen: "Sachsen"
        case .sachsenAnhalt: "Sachsen-Anhalt"
        case .schleswigHolstein: "Schleswig-Holstein"
        case .thueringen: "Thüringen"
        }
    }
}

struct Holiday: Identifiable, Hashable {
    enum Category: Hashable {
        /// Gesetzlicher Feiertag – `nil` = bundesweit, sonst nur in diesen Bundesländern.
        case statutory(states: Set<GermanState>?)
        /// Besonderer Tag ohne Feiertagsstatus, z. B. Heiligabend oder Martinstag.
        case observance
    }

    let name: String
    let date: Date
    let category: Category

    var id: String { "\(name)-\(date.timeIntervalSinceReferenceDate)" }

    /// Arbeitsfreier Feiertag im angegebenen Bundesland?
    func isStatutory(in state: GermanState) -> Bool {
        guard case .statutory(let states) = category else { return false }
        return states?.contains(state) ?? true
    }

    /// Länderkürzel bei regionalen Feiertagen, z. B. „BW, BY“.
    var stateList: String? {
        guard case .statutory(let states?) = category else { return nil }
        return states.map(\.abbreviation).sorted().joined(separator: ", ")
    }
}

/// Berechnet die Feiertage und besonderen Tage in Deutschland.
/// „Rot“ (arbeitsfrei) sind die gesetzlichen Feiertage des in den Einstellungen
/// gewählten Bundeslandes; die übrigen werden zusätzlich angezeigt.
/// Ergebnisse werden pro Jahr zwischengespeichert.
final class GermanHolidayProvider {
    static let shared = GermanHolidayProvider()

    private struct DayKey: Hashable {
        let year: Int
        let month: Int
        let day: Int
    }

    private let calendar: Calendar
    private let settings: AppSettings
    private var cache: [Int: [DayKey: [Holiday]]] = [:]

    init(calendar: Calendar = .foxCal, settings: AppSettings = .shared) {
        self.calendar = calendar
        self.settings = settings
    }

    /// Der gesetzliche Feiertag im gewählten Bundesland an diesem Tag, falls vorhanden.
    func holiday(on date: Date) -> Holiday? {
        let state = settings.homeState
        return holidays(on: date).first { $0.isStatutory(in: state) }
    }

    /// Alle Feiertage und besonderen Tage an diesem Tag.
    func holidays(on date: Date) -> [Holiday] {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return []
        }
        return holidaysByDay(in: year)[DayKey(year: year, month: month, day: day)] ?? []
    }

    func holidays(in year: Int) -> [Holiday] {
        holidaysByDay(in: year).values.flatMap { $0 }.sorted { $0.date < $1.date }
    }

    private func holidaysByDay(in year: Int) -> [DayKey: [Holiday]] {
        if let cached = cache[year] { return cached }

        var result: [DayKey: [Holiday]] = [:]
        for holiday in computeHolidays(in: year) {
            let c = calendar.dateComponents([.year, .month, .day], from: holiday.date)
            guard let y = c.year, let m = c.month, let d = c.day else { continue }
            result[DayKey(year: y, month: m, day: d), default: []].append(holiday)
        }
        cache[year] = result
        return result
    }

    // MARK: - Berechnung

    private func computeHolidays(in year: Int) -> [Holiday] {
        var holidays: [Holiday] = []

        func add(_ date: Date?, _ name: String, _ category: Holiday.Category) {
            if let date {
                holidays.append(Holiday(name: name, date: date, category: category))
            }
        }
        func national(_ date: Date?, _ name: String) {
            add(date, name, .statutory(states: nil))
        }
        func regional(_ date: Date?, _ name: String, _ states: Set<GermanState>) {
            guard !states.isEmpty else { return }
            add(date, name, .statutory(states: states))
        }
        func fixed(_ month: Int, _ day: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
        let easter = easterSunday(in: year)
        func easterOffset(_ days: Int) -> Date? {
            easter.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
        }

        // Bundesweite Feiertage
        national(fixed(1, 1), "Neujahr")
        national(easterOffset(-2), "Karfreitag")
        national(easterOffset(1), "Ostermontag")
        national(fixed(5, 1), "Tag der Arbeit")
        national(easterOffset(39), "Christi Himmelfahrt")
        national(easterOffset(50), "Pfingstmontag")
        if year >= 1990 {
            national(fixed(10, 3), "Tag der Deutschen Einheit")
        }
        national(fixed(12, 25), "1. Weihnachtstag")
        national(fixed(12, 26), "2. Weihnachtstag")

        // Feiertage einzelner Bundesländer
        regional(fixed(1, 6), "Heilige Drei Könige", [.badenWuerttemberg, .bayern, .sachsenAnhalt])

        var womensDayStates: Set<GermanState> = []
        if year >= 2019 { womensDayStates.insert(.berlin) }
        if year >= 2023 { womensDayStates.insert(.mecklenburgVorpommern) }
        regional(fixed(3, 8), "Internationaler Frauentag", womensDayStates)

        regional(easter, "Ostersonntag", [.brandenburg])
        // Einmalige Berliner Feiertage zum 75. und 80. Jahrestag des Kriegsendes.
        if year == 2020 || year == 2025 {
            regional(fixed(5, 8), "Tag der Befreiung", [.berlin])
        }
        regional(easterOffset(49), "Pfingstsonntag", [.brandenburg])
        regional(
            easterOffset(60), "Fronleichnam",
            [.badenWuerttemberg, .bayern, .hessen, .nordrheinWestfalen, .rheinlandPfalz, .saarland]
        )
        regional(fixed(8, 15), "Mariä Himmelfahrt", [.bayern, .saarland])
        if year >= 2019 {
            regional(fixed(9, 20), "Weltkindertag", [.thueringen])
        }

        if year == 2017 {
            // Bundesweit einmalig zum 500. Reformationsjubiläum.
            national(fixed(10, 31), "Reformationstag")
        } else {
            var states: Set<GermanState> = [.brandenburg, .mecklenburgVorpommern, .sachsen, .sachsenAnhalt, .thueringen]
            if year >= 2018 {
                states.formUnion([.bremen, .hamburg, .niedersachsen, .schleswigHolstein])
            }
            regional(fixed(10, 31), "Reformationstag", states)
        }
        regional(
            fixed(11, 1), "Allerheiligen",
            [.badenWuerttemberg, .bayern, .nordrheinWestfalen, .rheinlandPfalz, .saarland]
        )
        regional(repentanceDay(in: year), "Buß- und Bettag", [.sachsen])

        // Besondere Tage (keine gesetzlichen Feiertage)
        add(fixed(2, 14), "Valentinstag", .observance)
        add(easterOffset(-52), "Weiberfastnacht", .observance)
        add(easterOffset(-48), "Rosenmontag", .observance)
        add(easterOffset(-47), "Faschingsdienstag", .observance)
        add(easterOffset(-46), "Aschermittwoch", .observance)
        add(easterOffset(-7), "Palmsonntag", .observance)
        add(easterOffset(-3), "Gründonnerstag", .observance)
        add(easterOffset(-1), "Karsamstag", .observance)
        add(lastSunday(ofMonth: 3, in: year), "Beginn der Sommerzeit", .observance)
        add(nthSunday(2, ofMonth: 5, in: year), "Muttertag", .observance)
        add(nthSunday(1, ofMonth: 10, in: year), "Erntedankfest", .observance)
        add(lastSunday(ofMonth: 10, in: year), "Ende der Sommerzeit", .observance)
        add(fixed(11, 11), "St. Martin", .observance)
        if let firstAdvent = firstAdvent(in: year) {
            add(calendar.date(byAdding: .day, value: -14, to: firstAdvent), "Volkstrauertag", .observance)
            add(calendar.date(byAdding: .day, value: -7, to: firstAdvent), "Totensonntag", .observance)
            for week in 0..<4 {
                add(calendar.date(byAdding: .day, value: 7 * week, to: firstAdvent), "\(week + 1). Advent", .observance)
            }
        }
        add(fixed(12, 6), "Nikolaus", .observance)
        add(fixed(12, 24), "Heiligabend", .observance)
        add(fixed(12, 31), "Silvester", .observance)

        return holidays
    }

    /// Ostersonntag nach dem Gauß'schen Algorithmus (Meeus/Jones/Butcher)
    /// für den gregorianischen Kalender.
    private func easterSunday(in year: Int) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// 1. Advent: der vierte Sonntag vor dem 25. Dezember.
    private func firstAdvent(in year: Int) -> Date? {
        guard let christmas = calendar.date(from: DateComponents(year: year, month: 12, day: 25)) else { return nil }
        // Wochentag: 1 = Sonntag … 7 = Samstag. Abstand zum vorherigen Sonntag (mind. 1 Tag).
        let weekday = calendar.component(.weekday, from: christmas)
        let daysBack = weekday == 1 ? 7 : weekday - 1
        return calendar.date(byAdding: .day, value: -daysBack - 21, to: christmas)
    }

    /// Buß- und Bettag: der Mittwoch vor dem 23. November.
    private func repentanceDay(in year: Int) -> Date? {
        guard let november23 = calendar.date(from: DateComponents(year: year, month: 11, day: 23)) else { return nil }
        let weekday = calendar.component(.weekday, from: november23)
        // Mittwoch = 4; Abstand zum vorherigen Mittwoch (mind. 1 Tag).
        let daysBack = (weekday - 4 + 7) % 7 == 0 ? 7 : (weekday - 4 + 7) % 7
        return calendar.date(byAdding: .day, value: -daysBack, to: november23)
    }

    private func nthSunday(_ n: Int, ofMonth month: Int, in year: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, weekday: 1, weekdayOrdinal: n))
    }

    private func lastSunday(ofMonth month: Int, in year: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, weekday: 1, weekdayOrdinal: -1))
    }
}

extension GermanHolidayProvider: CalendarItemSource {
    func items(on day: Date, calendar: Calendar) -> [CalendarItem] {
        let state = settings.homeState
        return holidays(on: day).compactMap { holiday in
            let id = "holiday-\(holiday.id)"
            if holiday.isStatutory(in: state) {
                return CalendarItem(id: id, kind: .holiday, title: holiday.name)
            }
            if case .statutory = holiday.category {
                guard settings.showsRegionalHolidays else { return nil }
                return CalendarItem(
                    id: id,
                    kind: .observance(isRegionalHoliday: true),
                    title: holiday.name,
                    detail: holiday.stateList
                )
            }
            guard settings.showsObservances else { return nil }
            return CalendarItem(id: id, kind: .observance(isRegionalHoliday: false), title: holiday.name)
        }
    }
}
