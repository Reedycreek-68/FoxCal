import Foundation
import SwiftData

/// Eine eigene Aufgabe – ganztägig oder zu einer bestimmten Uhrzeit.
/// Alle Eigenschaften haben Standardwerte, damit später eine iCloud-Synchronisierung
/// (CloudKit) ohne Datenmigration möglich ist.
@Model
final class TaskItem {
    var uuid: UUID = UUID()
    var title: String = ""
    var details: String = ""
    /// Bei ganztägigen Aufgaben der Tagesbeginn, sonst der genaue Zeitpunkt.
    var date: Date = Date.now
    var hasTime: Bool = false
    var isCompleted: Bool = false
    var createdAt: Date = Date.now

    init(uuid: UUID = UUID(), title: String, details: String, date: Date, hasTime: Bool, isCompleted: Bool) {
        self.uuid = uuid
        self.title = title
        self.details = details
        self.date = date
        self.hasTime = hasTime
        self.isCompleted = isCompleted
    }
}

/// Eine eigene Notiz, die einem Kalendertag zugeordnet ist.
@Model
final class NoteItem {
    var uuid: UUID = UUID()
    var title: String = ""
    var text: String = ""
    /// Tagesbeginn des Tages, dem die Notiz zugeordnet ist.
    var date: Date = Date.now
    var createdAt: Date = Date.now

    init(uuid: UUID = UUID(), title: String, text: String, date: Date) {
        self.uuid = uuid
        self.title = title
        self.text = text
        self.date = date
    }
}

/// Bearbeitungsstand einer Aufgabe im Editor – wird erst beim Sichern übernommen.
struct TaskDraft {
    var title = ""
    var details = ""
    var date: Date
    var hasTime = false
    var isCompleted = false

    var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Bearbeitungsstand einer Notiz im Editor.
struct NoteDraft {
    var title = ""
    var text = ""
    var date: Date

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
