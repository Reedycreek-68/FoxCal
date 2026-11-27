import Foundation
import Observation
import SwiftData

/// Verwaltet eigene Aufgaben und Notizen und stellt sie dem Kalender als Quelle bereit.
@Observable
final class PersonalItemStore: CalendarItemSource {
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private let calendar: Calendar

    private var tasks: [TaskItem] = []
    private var notes: [NoteItem] = []
    private var tasksByDay: [Date: [TaskItem]] = [:]
    private var notesByDay: [Date: [NoteItem]] = [:]

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// Verbindet den Store mit der SwiftData-Datenbank und lädt die Einträge.
    func attach(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        reload()
    }

    // MARK: - CalendarItemSource

    func items(on day: Date, calendar: Calendar) -> [CalendarItem] {
        let key = self.calendar.startOfDay(for: day)

        let taskItems = (tasksByDay[key] ?? []).map { task in
            CalendarItem(
                id: "task-\(task.uuid)",
                kind: .task(isCompleted: task.isCompleted),
                title: task.title,
                time: task.hasTime ? task.date : nil,
                target: .task(task.uuid)
            )
        }
        let noteItems = (notesByDay[key] ?? []).map { note in
            CalendarItem(
                id: "note-\(note.uuid)",
                kind: .note,
                title: note.title.isEmpty ? note.text : note.title,
                target: .note(note.uuid)
            )
        }
        return taskItems + noteItems
    }

    // MARK: - Aufgaben

    func draft(forTask id: UUID) -> TaskDraft? {
        guard let task = task(with: id) else { return nil }
        return TaskDraft(
            title: task.title,
            details: task.details,
            date: task.date,
            hasTime: task.hasTime,
            isCompleted: task.isCompleted
        )
    }

    /// Legt eine neue Aufgabe an (`id == nil`) oder aktualisiert eine bestehende.
    func saveTask(_ draft: TaskDraft, id: UUID?) {
        let date = draft.hasTime ? draft.date : calendar.startOfDay(for: draft.date)
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id, let task = task(with: id) {
            task.title = title
            task.details = draft.details
            task.date = date
            task.hasTime = draft.hasTime
            task.isCompleted = draft.isCompleted
        } else {
            context?.insert(TaskItem(
                title: title,
                details: draft.details,
                date: date,
                hasTime: draft.hasTime,
                isCompleted: draft.isCompleted
            ))
        }
        persist()
    }

    func toggleTask(id: UUID) {
        guard let task = task(with: id) else { return }
        task.isCompleted.toggle()
        persist()
    }

    func deleteTask(id: UUID) {
        guard let task = task(with: id) else { return }
        context?.delete(task)
        persist()
    }

    // MARK: - Notizen

    func draft(forNote id: UUID) -> NoteDraft? {
        guard let note = note(with: id) else { return nil }
        return NoteDraft(title: note.title, text: note.text, date: note.date)
    }

    /// Legt eine neue Notiz an (`id == nil`) oder aktualisiert eine bestehende.
    func saveNote(_ draft: NoteDraft, id: UUID?) {
        let date = calendar.startOfDay(for: draft.date)
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id, let note = note(with: id) {
            note.title = title
            note.text = draft.text
            note.date = date
        } else {
            context?.insert(NoteItem(title: title, text: draft.text, date: date))
        }
        persist()
    }

    func deleteNote(id: UUID) {
        guard let note = note(with: id) else { return }
        context?.delete(note)
        persist()
    }

    // MARK: - Intern

    private func task(with id: UUID) -> TaskItem? {
        tasks.first { $0.uuid == id }
    }

    private func note(with id: UUID) -> NoteItem? {
        notes.first { $0.uuid == id }
    }

    private func persist() {
        do {
            try context?.save()
        } catch {
            print("FoxCal: Speichern fehlgeschlagen – \(error)")
        }
        reload()
    }

    /// Lädt alle Aufgaben und Notizen und indiziert sie nach Tag.
    /// Für einen persönlichen Kalender sind die Datenmengen klein genug, um alles im Speicher zu halten.
    private func reload() {
        guard let context else { return }
        tasks = (try? context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        notes = (try? context.fetch(FetchDescriptor<NoteItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        tasksByDay = Dictionary(grouping: tasks) { calendar.startOfDay(for: $0.date) }
        notesByDay = Dictionary(grouping: notes) { calendar.startOfDay(for: $0.date) }
    }
}
