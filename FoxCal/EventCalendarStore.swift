import EventKit
import Foundation
import Observation
import SwiftUI

/// Ein Kalender des Geräts (iCloud, Google, Exchange, lokal …).
struct EventCalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    /// Name des Kontos, z. B. „iCloud“ oder „Google“.
    let accountTitle: String
    let color: Color
    /// `true`, wenn der Nutzer in FoxCal eine eigene Farbe gewählt hat.
    let hasCustomColor: Bool
}

/// Verweist auf ein konkretes Vorkommen eines Termins.
struct EventReference: Hashable {
    let eventID: String
    /// Beginn des Vorkommens – unterscheidet die Termine einer Serie.
    let occurrenceStart: Date
}

/// Bearbeitungsstand eines Termins im Editor – wird erst beim Sichern übernommen.
struct EventDraft {
    var title = ""
    var location = ""
    var notes = ""
    var isAllDay = false
    var start: Date
    var end: Date
    var calendarID: String
    /// Teil einer Serie? Dann wird beim Sichern/Löschen nach dem Umfang gefragt.
    var isRecurring = false
    /// `false` bei schreibgeschützten Kalendern (z. B. Abos).
    var isEditable = true

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && end >= start
    }
}

enum EventEditingError: LocalizedError {
    case notFound
    case noCalendar

    var errorDescription: String? {
        switch self {
        case .notFound: "Der Termin wurde nicht gefunden. Möglicherweise wurde er inzwischen gelöscht."
        case .noCalendar: "Der gewählte Kalender ist nicht mehr verfügbar."
        }
    }
}

/// Liest Termine aus den auf dem Gerät eingerichteten Kalendern (inkl. iCloud)
/// und stellt sie dem Kalender als Quelle bereit.
///
/// Geladen wird immer ein Zeitfenster rund um das gerade angezeigte Datum.
@Observable
final class EventCalendarStore: CalendarItemSource {
    static let shared = EventCalendarStore()

    private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    /// Alle Kalender in der vom Nutzer festgelegten Reihenfolge.
    private(set) var calendars: [EventCalendarInfo] = []
    private var disabledCalendarIDs: Set<String>
    /// Vom Nutzer festgelegte Reihenfolge (Kalender-IDs). Neue Kalender kommen ans Ende.
    @ObservationIgnored private var calendarOrder: [String]
    /// Eigene Farben pro Kalender – überschreiben nur die Darstellung in FoxCal,
    /// nicht die Farbe im Kalenderkonto selbst.
    private var colorOverrides: [String: Color.Resolved]
    private var itemsByDay: [Date: [CalendarItem]] = [:]

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let calendar = Calendar.foxCal
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var loadedRange: DateInterval?
    @ObservationIgnored private var isObservingChanges = false
    /// Zuletzt geladene Termine – erlaubt Farbwechsel ohne erneute Abfrage.
    @ObservationIgnored private var fetchedEvents: [EKEvent] = []

    private static let disabledKey = "disabledEventCalendarIDs"
    private static let colorsKey = "eventCalendarColors"
    private static let orderKey = "eventCalendarOrder"

    init() {
        disabledCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: Self.disabledKey) ?? [])
        calendarOrder = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
        colorOverrides = UserDefaults.standard.data(forKey: Self.colorsKey)
            .flatMap { try? JSONDecoder().decode([String: Color.Resolved].self, from: $0) } ?? [:]
    }

    var hasAccess: Bool {
        authorizationStatus == .fullAccess
    }

    // MARK: - Zugriff & Lebenszyklus

    /// Fragt nach Zugriff auf die Kalender (aus den Einstellungen heraus).
    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        await start()
    }

    /// Lädt Kalender und Termine, wenn bereits Zugriff besteht, und
    /// aktualisiert sie, sobald sich in der Kalender-Datenbank etwas ändert.
    func start() async {
        guard hasAccess, !isObservingChanges else { return }
        isObservingChanges = true

        reloadCalendars()
        if loadedRange == nil {
            loadedRange = loadingRange(around: .now)
        }
        reloadEvents()

        for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
            reloadCalendars()
            reloadEvents()
        }
    }

    /// Stellt sicher, dass die Termine rund um `date` geladen sind.
    func loadIfNeeded(around date: Date) {
        guard hasAccess else { return }
        let needed = visibleRange(around: date)
        if let loadedRange, loadedRange.start <= needed.start, loadedRange.end >= needed.end {
            return
        }
        loadedRange = loadingRange(around: date)
        reloadEvents()
    }

    // MARK: - Termine bearbeiten

    /// Kalender, in die FoxCal schreiben darf (abonnierte Kalender u. Ä. sind schreibgeschützt).
    var writableCalendars: [EventCalendarInfo] {
        let writableIDs = Set(
            store.calendars(for: .event)
                .filter(\.allowsContentModifications)
                .map(\.calendarIdentifier)
        )
        return calendars.filter { writableIDs.contains($0.id) }
    }

    /// Kalender für neue Termine: der Standardkalender des Systems, sonst der erste beschreibbare.
    var defaultCalendarID: String? {
        if let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications {
            return calendar.calendarIdentifier
        }
        return writableCalendars.first?.id
    }

    func draft(for reference: EventReference) -> EventDraft? {
        guard let event = event(for: reference) else { return nil }
        return EventDraft(
            title: event.title ?? "",
            location: event.location ?? "",
            notes: event.notes ?? "",
            isAllDay: event.isAllDay,
            start: event.startDate,
            end: event.endDate,
            calendarID: event.calendar.calendarIdentifier,
            isRecurring: event.hasRecurrenceRules,
            isEditable: event.calendar.allowsContentModifications
        )
    }

    /// Legt einen Termin an (`reference == nil`) oder ändert einen bestehenden.
    /// Gespeichert wird im Kalenderkonto – die Synchronisierung (iCloud, Google …) übernimmt das System.
    func saveEvent(_ draft: EventDraft, reference: EventReference?, span: EKSpan) throws {
        let event: EKEvent
        if let reference {
            guard let existing = self.event(for: reference) else { throw EventEditingError.notFound }
            event = existing
        } else {
            event = EKEvent(eventStore: store)
        }
        guard let calendar = store.calendar(withIdentifier: draft.calendarID) else {
            throw EventEditingError.noCalendar
        }

        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        event.isAllDay = draft.isAllDay
        event.startDate = draft.isAllDay ? self.calendar.startOfDay(for: draft.start) : draft.start
        event.endDate = draft.isAllDay ? self.calendar.startOfDay(for: draft.end) : draft.end
        event.calendar = calendar

        try store.save(event, span: span, commit: true)
        reloadEvents()
    }

    func deleteEvent(_ reference: EventReference, span: EKSpan) throws {
        guard let event = event(for: reference) else { throw EventEditingError.notFound }
        try store.remove(event, span: span, commit: true)
        reloadEvents()
    }

    func isRecurring(_ reference: EventReference) -> Bool {
        event(for: reference)?.hasRecurrenceRules ?? false
    }

    func isEditable(_ reference: EventReference) -> Bool {
        event(for: reference)?.calendar.allowsContentModifications ?? false
    }

    /// Sucht das konkrete Vorkommen – bei Serienterminen teilen sich alle
    /// Vorkommen dieselbe `eventIdentifier`, daher zusätzlich über den Beginn.
    private func event(for reference: EventReference) -> EKEvent? {
        if let loaded = fetchedEvents.first(where: {
            $0.eventIdentifier == reference.eventID && $0.startDate == reference.occurrenceStart
        }) {
            return loaded
        }
        return store.event(withIdentifier: reference.eventID)
    }

    // MARK: - Kalenderauswahl

    func isEnabled(_ calendarID: String) -> Bool {
        !disabledCalendarIDs.contains(calendarID)
    }

    func setEnabled(_ calendarID: String, _ isEnabled: Bool) {
        if isEnabled {
            disabledCalendarIDs.remove(calendarID)
        } else {
            disabledCalendarIDs.insert(calendarID)
        }
        defaults.set(Array(disabledCalendarIDs), forKey: Self.disabledKey)
        reloadEvents()
    }

    // MARK: - Farben

    func setColor(_ color: Color, for calendarID: String) {
        colorOverrides[calendarID] = color.resolve(in: EnvironmentValues())
        colorsDidChange()
    }

    func resetColor(for calendarID: String) {
        colorOverrides[calendarID] = nil
        colorsDidChange()
    }

    private func color(for calendar: EKCalendar) -> Color {
        colorOverrides[calendar.calendarIdentifier].map { Color($0) } ?? Color(cgColor: calendar.cgColor)
    }

    private func colorsDidChange() {
        if let data = try? JSONEncoder().encode(colorOverrides) {
            defaults.set(data, forKey: Self.colorsKey)
        }
        reloadCalendars()
        rebuildIndex()
    }

    // MARK: - Reihenfolge

    /// Übernimmt eine Umsortierung aus der Reihenfolge-Liste (Ziehen).
    func moveCalendars(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = calendars.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        applyOrder(ids)
    }

    /// Verschiebt einen Kalender um eine Position nach oben (`-1`) oder unten (`+1`).
    func moveCalendar(_ calendarID: String, by offset: Int) {
        var ids = calendars.map(\.id)
        guard let index = ids.firstIndex(of: calendarID) else { return }
        let target = index + offset
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        applyOrder(ids)
    }

    private func applyOrder(_ ids: [String]) {
        calendarOrder = ids
        defaults.set(ids, forKey: Self.orderKey)
        reloadCalendars()
        rebuildIndex()
    }

    /// Position eines Kalenders in der Nutzer-Reihenfolge – bestimmt die Reihenfolge der Termine.
    private func orderIndex(of calendarID: String) -> Int {
        calendarOrder.firstIndex(of: calendarID) ?? Int.max
    }

    // MARK: - CalendarItemSource

    func items(on day: Date, calendar: Calendar) -> [CalendarItem] {
        itemsByDay[self.calendar.startOfDay(for: day)] ?? []
    }

    // MARK: - Laden

    private func reloadCalendars() {
        // Erst nach Konto und Name sortieren, damit neue Kalender eine sinnvolle
        // Grundordnung haben – dann gilt die Reihenfolge des Nutzers.
        let sorted = store.calendars(for: .event)
            .sorted {
                let accounts = $0.source.title.localizedStandardCompare($1.source.title)
                if accounts != .orderedSame { return accounts == .orderedAscending }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        let known = sorted.filter { calendarOrder.contains($0.calendarIdentifier) }
            .sorted { orderIndex(of: $0.calendarIdentifier) < orderIndex(of: $1.calendarIdentifier) }
        let new = sorted.filter { !calendarOrder.contains($0.calendarIdentifier) }

        calendars = (known + new).map { calendar in
            EventCalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                accountTitle: calendar.source.title,
                color: color(for: calendar),
                hasCustomColor: colorOverrides[calendar.calendarIdentifier] != nil
            )
        }
        // Neue Kalender in die gespeicherte Reihenfolge aufnehmen.
        let ids = calendars.map(\.id)
        if ids != calendarOrder {
            calendarOrder = ids
            defaults.set(ids, forKey: Self.orderKey)
        }
    }

    private func reloadEvents() {
        let calendars = store.calendars(for: .event).filter { isEnabled($0.calendarIdentifier) }
        if hasAccess, let range = loadedRange, !calendars.isEmpty {
            let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: calendars)
            fetchedEvents = store.events(matching: predicate)
        } else {
            fetchedEvents = []
        }
        rebuildIndex()
    }

    /// Ordnet die geladenen Termine den Kalendertagen zu.
    private func rebuildIndex() {
        var result: [Date: [CalendarItem]] = [:]
        for event in fetchedEvents {
            for (day, item) in dayItems(for: event) {
                result[day, default: []].append(item)
            }
        }
        itemsByDay = result
    }

    /// Zerlegt einen Termin in einen Eintrag pro Kalendertag. Mehrtägige Termine
    /// mit Uhrzeit werden dabei auf den jeweiligen Tag zugeschnitten.
    private func dayItems(for event: EKEvent) -> [(Date, CalendarItem)] {
        guard let start = event.startDate, let end = event.endDate else { return [] }
        let title = event.title ?? ""
        let color = color(for: event.calendar)
        let order = orderIndex(of: event.calendar.calendarIdentifier)
        // Bei Serienterminen ist die eventIdentifier für alle Vorkommen gleich.
        let baseID = "event-\(event.eventIdentifier ?? UUID().uuidString)-\(start.timeIntervalSinceReferenceDate)"
        let target = event.eventIdentifier.map {
            CalendarItem.EditTarget.event(EventReference(eventID: $0, occurrenceStart: start))
        }

        var result: [(Date, CalendarItem)] = []
        var day = calendar.startOfDay(for: start)
        repeat {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let item: CalendarItem
            if event.isAllDay {
                item = CalendarItem(
                    id: "\(baseID)-\(day.timeIntervalSinceReferenceDate)",
                    kind: .event(color: color),
                    title: title,
                    sourceOrder: order,
                    target: target
                )
            } else {
                item = CalendarItem(
                    id: "\(baseID)-\(day.timeIntervalSinceReferenceDate)",
                    kind: .event(color: color),
                    title: title,
                    time: max(start, day),
                    endTime: min(end, nextDay),
                    sourceOrder: order,
                    target: target
                )
            }
            result.append((day, item))
            day = nextDay
        } while day < end

        return result
    }

    /// Bereich, den Monats-, Wochen- und Tagesansicht um `date` herum anzeigen können.
    private func visibleRange(around date: Date) -> DateInterval {
        let month = calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
        let start = calendar.date(byAdding: .day, value: -7, to: month.start) ?? month.start
        let end = calendar.date(byAdding: .day, value: 7, to: month.end) ?? month.end
        return DateInterval(start: start, end: end)
    }

    /// Großzügigeres Fenster, damit beim Blättern nicht ständig neu geladen werden muss.
    private func loadingRange(around date: Date) -> DateInterval {
        let visible = visibleRange(around: date)
        let start = calendar.date(byAdding: .month, value: -1, to: visible.start) ?? visible.start
        let end = calendar.date(byAdding: .month, value: 1, to: visible.end) ?? visible.end
        return DateInterval(start: start, end: end)
    }
}
