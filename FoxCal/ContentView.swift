import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var model = CalendarModel()
    @Environment(\.modelContext) private var modelContext
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Ansicht", selection: $model.mode) {
                    ForEach(CalendarViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.bottom, 8)

                Group {
                    switch model.mode {
                    case .month: MonthView(model: model)
                    case .week: WeekView(model: model)
                    case .day: DayView(model: model)
                    }
                }
                // Monat: hoch/runter wischen, Woche und Tag: links/rechts.
                .onSwipeToPage(axis: model.mode == .month ? .vertical : .horizontal) { direction in
                    model.step(by: direction)
                }
            }
            .navigationTitle(model.title)
            .task {
                model.personalItems.attach(modelContext)
                await model.birthdayStore.start()
            }
            .task {
                await model.events.start()
            }
            // Termine rund um das angezeigte Datum nachladen – auch direkt nach erteiltem Zugriff.
            .onChange(of: model.selectedDate, initial: true) {
                model.events.loadIfNeeded(around: model.selectedDate)
            }
            .onChange(of: model.events.hasAccess) {
                model.events.loadIfNeeded(around: model.selectedDate)
            }
            .sheet(item: $model.editorRequest) { request in
                ItemEditorSheet(request: request, store: model.personalItems, events: model.events)
                    .preferredColorScheme(model.settings.appearance.colorScheme)
            }
            #if !os(macOS)
            .sheet(isPresented: $showsSettings) {
                NavigationStack {
                    SettingsView(settings: model.settings, events: model.events)
                        .navigationTitle("Einstellungen")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Fertig") { showsSettings = false }
                            }
                        }
                }
                .preferredColorScheme(model.settings.appearance.colorScheme)
            }
            #endif
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Zurück", systemImage: "chevron.left") {
                        model.step(by: -1)
                    }
                    .keyboardShortcut(.leftArrow, modifiers: .command)

                    Button("Heute") {
                        model.goToToday()
                    }
                    .keyboardShortcut("t", modifiers: .command)

                    Button("Weiter", systemImage: "chevron.right") {
                        model.step(by: 1)
                    }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu("Neu", systemImage: "plus") {
                        Button("Neuer Termin", systemImage: "calendar.badge.plus") {
                            model.newEvent()
                        }
                        .keyboardShortcut("n", modifiers: [.command, .option])
                        .disabled(!model.events.hasAccess)

                        Button("Neue Aufgabe", systemImage: "checkmark.circle") {
                            model.newTask()
                        }
                        .keyboardShortcut("n", modifiers: .command)

                        Button("Neue Notiz", systemImage: "note.text") {
                            model.newNote()
                        }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    #if os(macOS)
                    // Öffnet das Einstellungsfenster (auch über ⌘,).
                    SettingsLink {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
                    #else
                    Button("Einstellungen", systemImage: "gearshape") {
                        showsSettings = true
                    }
                    #endif
                }
            }
        }
        .preferredColorScheme(model.settings.appearance.colorScheme)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TaskItem.self, NoteItem.self], inMemory: true)
}
