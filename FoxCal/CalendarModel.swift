import EventKit
import Foundation
import Observation

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case month
    case week
    case day

    var id: Self { self }

    var title: String {
        switch self {
        case .month: "Monat"
        case .week: "Woche"
        case .day: "Tag"
        }
    }
}

/// Welcher Editor gerade geöffnet werden soll.
enum EditorRequest: Identifiable, Hashable {
    case newTask(date: Date, hasTime: Bool)
    case newNote(date: Date)
    case newEvent(date: Date, hasTime: Bool)
    case task(UUID)
    case note(UUID)
    case event(EventReference)

    var id: String {
        switch self {
        case .newTask(let date, let hasTime): "new-task-\(date.timeIntervalSinceReferenceDate)-\(hasTime)"
        case .newNote(let date): "new-note-\(date.timeIntervalSinceReferenceDate)"
        case .newEvent(let date, let hasTime): "new-event-\(date.timeIntervalSinceReferenceDate)-\(hasTime)"
        case .task(let id): "task-\(id)"
        case .note(let id): "note-\(id)"
        case .event(let reference): "event-\(reference.eventID)-\(reference.occurrenceStart.timeIntervalSinceReferenceDate)"
        }
    }
}

@Observable
final class CalendarModel {
    var mode: CalendarViewMode = .month
    var selectedDate: Date = .now
    var editorRequest: EditorRequest?

    @ObservationIgnored let settings = AppSettings.shared
    @ObservationIgnored private let holidayProvider = GermanHolidayProvider.shared
    @ObservationIgnored let birthdayStore = BirthdayStore()
    @ObservationIgnored let personalItems = PersonalItemStore(calendar: .foxCal)
    @ObservationIgnored let events = EventCalendarStore.shared

    @ObservationIgnored private var cachedCalendar: Calendar = .foxCal

    /// Kalender mit dem in den Einstellungen gewählten ersten Wochentag.
    var calendar: Calendar {
        let firstWeekday = settings.firstWeekday.rawValue
        if cachedCalendar.firstWeekday != firstWeekday {
            var calendar = Calendar.foxCal
            calendar.firstWeekday = firstWeekday
            cachedCalendar = calendar
        }
        return cachedCalendar
    }

    /// Alle Datenquellen, deren Einträge im Kalender erscheinen.
    private var sources: [any CalendarItemSource] {
        [holidayProvider, birthdayStore, events, personalItems]
    }

    func holiday(on date: Date) -> Holiday? {
        holidayProvider.holiday(on: date)
    }

    /// Alle Einträge eines Tages aus allen Quellen – nach Art sortiert,
    /// zeitgebundene Einträge innerhalb ihrer Art nach Uhrzeit.
    func items(on date: Date) -> [CalendarItem] {
        sources
            .flatMap { $0.items(on: date, calendar: calendar) }
            .sorted { a, b in
                if a.sortRank != b.sortRank { return a.sortRank < b.sortRank }
                // Termine folgen der Kalender-Reihenfolge aus den Einstellungen.
                if a.sourceOrder != b.sourceOrder { return a.sourceOrder < b.sourceOrder }
                return (a.time ?? .distantPast) < (b.time ?? .distantPast)
            }
    }

    // MARK: - Aufgaben & Notizen

    /// Neue Aufgabe für den ausgewählten Tag bzw. zu einer bestimmten Stunde.
    func newTask(on day: Date? = nil, hour: Int? = nil) {
        let start = calendar.startOfDay(for: day ?? selectedDate)
        if let hour, let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start) {
            editorRequest = .newTask(date: date, hasTime: true)
        } else {
            editorRequest = .newTask(date: start, hasTime: false)
        }
    }

    func newNote(on day: Date? = nil) {
        editorRequest = .newNote(date: calendar.startOfDay(for: day ?? selectedDate))
    }

    /// Neuer Termin für den ausgewählten Tag (09:00–10:00) bzw. zu einer bestimmten Stunde.
    func newEvent(on day: Date? = nil, hour: Int? = nil) {
        let start = calendar.startOfDay(for: day ?? selectedDate)
        let date = calendar.date(bySettingHour: hour ?? 9, minute: 0, second: 0, of: start) ?? start
        editorRequest = .newEvent(date: date, hasTime: true)
    }

    func edit(_ item: CalendarItem) {
        switch item.target {
        case .task(let id): editorRequest = .task(id)
        case .note(let id): editorRequest = .note(id)
        case .event(let reference): editorRequest = .event(reference)
        case nil: break
        }
    }

    /// Termine aus schreibgeschützten Kalendern (z. B. Abos) lassen sich nur ansehen.
    func isEditable(_ item: CalendarItem) -> Bool {
        if case .event(let reference) = item.target {
            return events.isEditable(reference)
        }
        return item.target != nil
    }

    func isRecurring(_ item: CalendarItem) -> Bool {
        if case .event(let reference) = item.target {
            return events.isRecurring(reference)
        }
        return false
    }

    func toggleCompletion(of item: CalendarItem) {
        if case .task(let id) = item.target {
            personalItems.toggleTask(id: id)
        }
    }

    func delete(_ item: CalendarItem) {
        switch item.target {
        case .task(let id): personalItems.deleteTask(id: id)
        case .note(let id): personalItems.deleteNote(id: id)
        // Bei Serien nur dieses Vorkommen – „alle zukünftigen“ gibt es im Editor.
        case .event(let reference): try? events.deleteEvent(reference, span: .thisEvent)
        case nil: break
        }
    }

    /// Blättert je nach Ansicht um einen Monat, eine Woche oder einen Tag.
    func step(by value: Int) {
        let component: Calendar.Component = switch mode {
        case .month: .month
        case .week: .weekOfYear
        case .day: .day
        }
        if let date = calendar.date(byAdding: component, value: value, to: selectedDate) {
            selectedDate = date
        }
    }

    func goToToday() {
        selectedDate = .now
    }

    func open(day: Date) {
        selectedDate = day
        mode = .day
    }

    /// Kalenderwoche nach ISO 8601 – unabhängig vom eingestellten ersten Wochentag.
    func weekNumber(of date: Date) -> Int {
        Calendar.foxCal.component(.weekOfYear, from: date)
    }

    /// Kalenderwoche einer angezeigten Wochenzeile. Beginnt die Woche am Sonntag,
    /// zählt der Montag, damit die Nummer zur ISO-Woche passt.
    func weekNumber(ofWeek days: [Date]) -> Int? {
        let monday = days.first { calendar.component(.weekday, from: $0) == 2 } ?? days.first
        return monday.map(weekNumber(of:))
    }

    var title: String {
        switch mode {
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year().locale(.german))
        case .week:
            let days = calendar.daysOfWeek(containing: selectedDate)
            guard let first = days.first, let last = days.last else { return "" }
            let range = Date.IntervalFormatStyle(date: .long, time: .omitted, locale: .german, calendar: calendar)
            let dates = (first..<last).formatted(range)
            guard settings.showsWeekNumbers, let weekNumber = weekNumber(ofWeek: days) else { return dates }
            return "KW \(weekNumber) · \(dates)"
        case .day:
            return selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(.german))
        }
    }
}
