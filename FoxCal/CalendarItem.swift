import Foundation
import SwiftUI

/// Ein Eintrag, der an einem Kalendertag angezeigt wird –
/// unabhängig davon, aus welcher Quelle er stammt.
struct CalendarItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case holiday
        /// Feiertag eines anderen Bundeslandes oder besonderer Tag (z. B. Heiligabend).
        case observance(isRegionalHoliday: Bool)
        /// `age`: der wievielte Geburtstag, `nil` wenn das Geburtsjahr unbekannt ist.
        case birthday(age: Int?)
        /// Termin aus einem Gerätekalender (iCloud, Google …) in dessen Farbe.
        case event(color: Color)
        case task(isCompleted: Bool)
        case note
    }

    /// Verweis auf den bearbeitbaren Datensatz hinter einem Eintrag.
    enum EditTarget: Hashable {
        case task(UUID)
        case note(UUID)
        /// Termin in einem Gerätekalender – Änderungen werden ins Kalenderkonto geschrieben.
        case event(EventReference)
    }

    /// Muss über alle Quellen hinweg eindeutig sein (z. B. mit Präfix der Quelle).
    let id: String
    let kind: Kind
    let title: String
    /// Zusatzinfo, die nur bei ausreichend Platz erscheint (z. B. Länderkürzel).
    var detail: String? = nil
    /// Uhrzeit für zeitgebundene Einträge; `nil` bei ganztägigen.
    var time: Date? = nil
    /// Ende bei Terminen mit Dauer; `nil` bei Einträgen ohne Dauer (z. B. Aufgaben).
    var endTime: Date? = nil
    /// Reihenfolge innerhalb derselben Art, z. B. die Position des Kalenders in den Einstellungen.
    var sourceOrder: Int = 0
    /// `nil` für Einträge, die in FoxCal nicht bearbeitet werden können (Feiertage, Geburtstage).
    var target: EditTarget? = nil

    var isHoliday: Bool { kind == .holiday }
    var isAllDay: Bool { time == nil }

    var isEvent: Bool {
        if case .event = kind { return true }
        return false
    }

    /// Reihenfolge innerhalb eines Tages: Feiertage und besondere Tage ganz oben,
    /// danach Geburtstage, Termine, Aufgaben und Notizen.
    var sortRank: Int {
        switch kind {
        case .holiday: 0
        case .observance: 1
        case .birthday: 2
        case .event: 3
        case .task: 4
        case .note: 5
        }
    }

    /// Text für VoiceOver.
    var accessibilityDescription: String {
        switch kind {
        case .holiday:
            "Feiertag: \(title)"
        case .observance(true):
            "Feiertag in \(detail ?? "anderen Bundesländern"): \(title)"
        case .observance(false):
            title
        case .birthday(let age?):
            "\(age). Geburtstag von \(title)"
        case .birthday(nil):
            "Geburtstag von \(title)"
        case .event:
            "Termin: \(title)"
        case .task(let isCompleted):
            isCompleted ? "Erledigte Aufgabe: \(title)" : "Aufgabe: \(title)"
        case .note:
            "Notiz: \(title)"
        }
    }
}

/// Eine Datenquelle für Kalendereinträge.
///
/// Neue Quellen (z. B. Aufgaben, Notizen) implementieren dieses Protokoll und
/// werden in `CalendarModel.sources` registriert – die Ansichten zeigen
/// ihre Einträge dann automatisch an.
/// Ist die Quelle `@Observable`, aktualisieren sich die Ansichten bei Änderungen von selbst.
protocol CalendarItemSource: AnyObject {
    func items(on day: Date, calendar: Calendar) -> [CalendarItem]
}
