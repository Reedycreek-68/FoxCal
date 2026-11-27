import EventKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let events: EventCalendarStore

    var body: some View {
        Form {
            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
            }

            Section("Woche") {
                Picker("Erster Tag der Woche", selection: $settings.firstWeekday) {
                    ForEach(FirstWeekday.allCases) { weekday in
                        Text(weekday.title).tag(weekday)
                    }
                }
                Toggle("Kalenderwochen anzeigen", isOn: $settings.showsWeekNumbers)
            }

            Section {
                Picker("Bundesland", selection: $settings.homeState) {
                    ForEach(GermanState.allCases.sorted { $0.name < $1.name }) { state in
                        Text(state.name).tag(state)
                    }
                }
                Toggle("Feiertage anderer Bundesländer", isOn: $settings.showsRegionalHolidays)
                Toggle("Besondere Tage", isOn: $settings.showsObservances)
            } header: {
                Text("Feiertage")
            } footer: {
                Text("Gesetzliche Feiertage in \(settings.homeState.name) werden immer rot angezeigt. Besondere Tage sind z. B. Heiligabend, Silvester, Rosenmontag, St. Martin, Muttertag, die Adventssonntage und die Zeitumstellung.")
            }

            calendarSections
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsCalendarOrder) {
            CalendarOrderView(events: events)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }

    @State private var showsCalendarOrder = false

    @ViewBuilder
    private var calendarSections: some View {
        switch events.authorizationStatus {
        case .fullAccess:
            Section {
                if events.calendars.isEmpty {
                    Text("Auf diesem Gerät sind keine Kalender eingerichtet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(events.calendars) { calendar in
                    calendarRow(calendar)
                }
                if events.calendars.count > 1 {
                    Button("Reihenfolge ändern …", systemImage: "arrow.up.arrow.down") {
                        showsCalendarOrder = true
                    }
                }
            } header: {
                Text("Kalender")
            } footer: {
                Text("Termine eines Tages erscheinen in der Reihenfolge dieser Liste.\n\n\(iCloudHint)")
            }

        case .notDetermined:
            Section("Kalender") {
                Text("Zeige Termine aus deinen iCloud-Kalendern und allen anderen auf diesem Gerät eingerichteten Kalendern (z. B. Google, Exchange) in FoxCal an.")
                    .foregroundStyle(.secondary)
                Button("Kalender verbinden") {
                    Task { await events.requestAccess() }
                }
            }

        default:
            Section("Kalender") {
                Text(deniedHint)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func calendarRow(_ calendar: EventCalendarInfo) -> some View {
        HStack {
            ColorPicker(
                "Farbe für \(calendar.title)",
                selection: Binding(
                    get: { calendar.color },
                    set: { events.setColor($0, for: calendar.id) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()

            Toggle(isOn: Binding(
                get: { events.isEnabled(calendar.id) },
                set: { events.setEnabled(calendar.id, $0) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(calendar.title)
                    Text(calendar.accountTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            let index = events.calendars.firstIndex(of: calendar)
            Button("Nach oben", systemImage: "arrow.up") {
                events.moveCalendar(calendar.id, by: -1)
            }
            .disabled(index == 0)
            Button("Nach unten", systemImage: "arrow.down") {
                events.moveCalendar(calendar.id, by: 1)
            }
            .disabled(index == events.calendars.count - 1)
            if calendar.hasCustomColor {
                Divider()
                Button("Originalfarbe wiederherstellen", systemImage: "arrow.uturn.backward") {
                    events.resetColor(for: calendar.id)
                }
            }
        }
    }

    private var iCloudHint: String {
        #if os(macOS)
        "iCloud-Kalender erscheinen hier, wenn du in den Systemeinstellungen bei iCloud angemeldet bist und „Kalender“ für iCloud aktiviert ist. Weitere Konten fügst du unter Systemeinstellungen > Internetaccounts hinzu."
        #else
        "iCloud-Kalender erscheinen hier, wenn du in den Einstellungen bei iCloud angemeldet bist und „Kalender“ für iCloud aktiviert ist. Weitere Konten fügst du unter Einstellungen > Apps > Kalender > Kalenderaccounts hinzu."
        #endif
    }

    private var deniedHint: String {
        #if os(macOS)
        "FoxCal hat keinen Zugriff auf deine Kalender. Du kannst ihn unter Systemeinstellungen > Datenschutz & Sicherheit > Kalender erlauben."
        #else
        "FoxCal hat keinen Zugriff auf deine Kalender. Du kannst ihn unter Einstellungen > Apps > FoxCal > Kalender erlauben."
        #endif
    }
}

/// Liste zum Umsortieren der Kalender per Ziehen an den Griffen.
private struct CalendarOrderView: View {
    let events: EventCalendarStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(events.calendars) { calendar in
                    HStack(spacing: 10) {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(calendar.color)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(calendar.title)
                            Text(calendar.accountTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        #if os(macOS)
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                        #endif
                    }
                }
                .onMove { source, destination in
                    events.moveCalendars(fromOffsets: source, toOffset: destination)
                }
            }
            #if !os(macOS)
            // Griffe zum Ziehen dauerhaft einblenden.
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Reihenfolge")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 400)
        #endif
    }
}

#Preview {
    SettingsView(settings: AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard), events: .shared)
}
