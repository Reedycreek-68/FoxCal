import SwiftUI

/// Öffnet den passenden Editor für eine `EditorRequest`.
struct ItemEditorSheet: View {
    let request: EditorRequest
    let store: PersonalItemStore
    let events: EventCalendarStore

    var body: some View {
        switch request {
        case .newEvent(let date, let hasTime):
            if let calendarID = events.defaultCalendarID {
                let end = date.addingTimeInterval(3600)
                EventEditorView(
                    events: events,
                    reference: nil,
                    draft: EventDraft(isAllDay: !hasTime, start: date, end: end, calendarID: calendarID)
                )
            } else {
                ContentUnavailableView(
                    "Kein Kalender verfügbar",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Verbinde in den Einstellungen deine Kalender, um Termine anzulegen.")
                )
            }
        case .event(let reference):
            if let draft = events.draft(for: reference) {
                EventEditorView(events: events, reference: reference, draft: draft)
            }
        case .newTask(let date, let hasTime):
            TaskEditorView(store: store, taskID: nil, draft: TaskDraft(date: date, hasTime: hasTime))
        case .task(let id):
            if let draft = store.draft(forTask: id) {
                TaskEditorView(store: store, taskID: id, draft: draft)
            }
        case .newNote(let date):
            NoteEditorView(store: store, noteID: nil, draft: NoteDraft(date: date))
        case .note(let id):
            if let draft = store.draft(forNote: id) {
                NoteEditorView(store: store, noteID: id, draft: draft)
            }
        }
    }
}

struct TaskEditorView: View {
    let store: PersonalItemStore
    /// `nil` beim Anlegen einer neuen Aufgabe.
    let taskID: UUID?
    @State var draft: TaskDraft

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $draft.title)
                    Toggle("Erledigt", isOn: $draft.isCompleted)
                }

                Section {
                    Toggle("Uhrzeit", isOn: $draft.hasTime.animation())
                    DatePicker(
                        draft.hasTime ? "Datum & Uhrzeit" : "Datum",
                        selection: $draft.date,
                        displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date]
                    )
                }

                Section("Details") {
                    TextField("Details", text: $draft.details, axis: .vertical)
                        .lineLimit(3...8)
                        .labelsHidden()
                }

                if let taskID {
                    Section {
                        Button("Aufgabe löschen", role: .destructive) {
                            store.deleteTask(id: taskID)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(taskID == nil ? "Neue Aufgabe" : "Aufgabe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        store.saveTask(draft, id: taskID)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
            .onChange(of: draft.hasTime) { _, hasTime in
                // Beim Einschalten der Uhrzeit nicht mit 00:00 starten.
                guard hasTime else { return }
                let components = Calendar.foxCal.dateComponents([.hour, .minute], from: draft.date)
                if components.hour == 0, components.minute == 0,
                   let nineOClock = Calendar.foxCal.date(bySettingHour: 9, minute: 0, second: 0, of: draft.date) {
                    draft.date = nineOClock
                }
            }
        }
        .environment(\.locale, .german)
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 380)
        #endif
    }
}

struct NoteEditorView: View {
    let store: PersonalItemStore
    /// `nil` beim Anlegen einer neuen Notiz.
    let noteID: UUID?
    @State var draft: NoteDraft

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $draft.title)
                    DatePicker("Tag", selection: $draft.date, displayedComponents: .date)
                }

                Section("Notiz") {
                    TextEditor(text: $draft.text)
                        .frame(minHeight: 180)
                }

                if let noteID {
                    Section {
                        Button("Notiz löschen", role: .destructive) {
                            store.deleteNote(id: noteID)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(noteID == nil ? "Neue Notiz" : "Notiz")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        store.saveNote(draft, id: noteID)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .environment(\.locale, .german)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
    }
}
