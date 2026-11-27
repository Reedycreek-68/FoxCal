import SwiftData
import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [TaskItem.self, NoteItem.self])

        #if os(macOS)
        Settings {
            MacSettingsWindow()
        }
        #endif
    }
}

#if os(macOS)
/// Inhalt des Einstellungsfensters (⌘,) unter macOS.
private struct MacSettingsWindow: View {
    private let settings = AppSettings.shared

    var body: some View {
        SettingsView(settings: settings, events: .shared)
            .frame(width: 460)
            .frame(minHeight: 420)
            .preferredColorScheme(settings.appearance.colorScheme)
    }
}
#endif
