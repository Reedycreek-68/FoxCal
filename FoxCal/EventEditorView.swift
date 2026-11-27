import EventKit
import SwiftUI

/// Formular zum Anlegen und Bearbeiten von Terminen in den Gerätekalendern.
/// Gespeichert wird direkt im Kalenderkonto (iCloud, Google, Exchange …),
/// von dort synchronisiert das System auf alle anderen Geräte.
struct EventEditorView: View {
    let events: EventCalendarStore
    /// `nil` beim Anlegen eines neuen Termins.
    let reference: EventReference?
    @State var draft: EventDraft

    /// Bei Serienterminen: Rückfrage, ob nur dieses oder auch zukünftige Vorkommen betroffen sind.
    @State private var pendingRecurringAction: RecurringAction?
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    private enum RecurringAction: Identifiable {
        case save
        case delete

        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $draft.title)
                    TextField("Ort", text: $draft.location)
                }

                Section {
                    Toggle("Ganztägig", isOn: $draft.isAllDay.animation())
                    DatePicker(
                        "Beginn",
                        selection: $draft.start,
                        displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "Ende",
                        selection: $draft.end,
                        in: draft.start...,
                        displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                }

                Section {
                    Picker("Kalender", selection: $draft.calendarID) {
                        ForEach(calendarChoices) { calendar in
                            Label {
                                Text(calendar.title)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(calendar.color)
                            }
                            .tag(calendar.id)
                        }
                    }
                }

                Section("Notizen") {
                    TextField("Notizen", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                        .labelsHidden()
                }

                if reference != nil, draft.isEditable {
                    Section {
                        Button("Termin löschen", role: .destructive) {
                            if draft.isRecurring {
                                pendingRecurringAction = .delete
                            } else {
                                delete(span: .thisEvent)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(!draft.isEditable)
            .safeAreaInset(edge: .top) {
                if !draft.isEditable {
                    Label("Dieser Kalender ist schreibgeschützt – der Termin kann nur angesehen werden.", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
            }
            .navigationTitle(reference == nil ? "Neuer Termin" : "Termin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(draft.isEditable ? "Abbrechen" : "Schließen") { dismiss() }
                }
                if draft.isEditable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern") {
                            if draft.isRecurring {
                                pendingRecurringAction = .save
                            } else {
                                save(span: .thisEvent)
                            }
                        }
                        .disabled(!draft.isValid)
                    }
                }
            }
            .onChange(of: draft.start) { oldStart, newStart in
                // Beim Verschieben des Beginns die Dauer beibehalten.
                draft.end = draft.end.addingTimeInterval(newStart.timeIntervalSince(oldStart))
            }
            .confirmationDialog(
                "Dies ist ein Serientermin.",
                isPresented: Binding(
                    get: { pendingRecurringAction != nil },
                    set: { if !$0 { pendingRecurringAction = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingRecurringAction
            ) { action in
                switch action {
                case .save:
                    Button("Nur diesen Termin sichern") { save(span: .thisEvent) }
                    Button("Alle zukünftigen sichern") { save(span: .futureEvents) }
                case .delete:
                    Button("Nur diesen Termin löschen", role: .destructive) { delete(span: .thisEvent) }
                    Button("Alle zukünftigen löschen", role: .destructive) { delete(span: .futureEvents) }
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .alert(
                "Termin konnte nicht gespeichert werden",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .environment(\.locale, .german)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }

    /// Beschreibbare Kalender; bei schreibgeschützten Terminen zusätzlich dessen eigener Kalender,
    /// damit der Picker etwas anzeigen kann.
    private var calendarChoices: [EventCalendarInfo] {
        let writable = events.writableCalendars
        if writable.contains(where: { $0.id == draft.calendarID }) {
            return writable
        }
        return events.calendars.filter { $0.id == draft.calendarID } + writable
    }

    private func save(span: EKSpan) {
        do {
            try events.saveEvent(draft, reference: reference, span: span)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(span: EKSpan) {
        guard let reference else { return }
        do {
            try events.deleteEvent(reference, span: span)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
