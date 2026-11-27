import Foundation
import Observation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    /// `nil` folgt der Systemeinstellung.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Werte entsprechen `Calendar.firstWeekday` (1 = Sonntag, 2 = Montag).
enum FirstWeekday: Int, CaseIterable, Identifiable {
    case monday = 2
    case sunday = 1

    var id: Self { self }

    var title: String {
        switch self {
        case .monday: "Montag"
        case .sunday: "Sonntag"
        }
    }
}

/// App-weite Einstellungen, dauerhaft in den UserDefaults gespeichert.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let appearance = "appearance"
        static let firstWeekday = "firstWeekday"
        static let showsWeekNumbers = "showsWeekNumbers"
        static let showsRegionalHolidays = "showsRegionalHolidays"
        static let showsObservances = "showsObservances"
        static let homeState = "homeState"
    }

    /// Bundesland, dessen gesetzliche Feiertage rot (arbeitsfrei) angezeigt werden.
    var homeState: GermanState {
        didSet { defaults.set(homeState.rawValue, forKey: Keys.homeState) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var firstWeekday: FirstWeekday {
        didSet { defaults.set(firstWeekday.rawValue, forKey: Keys.firstWeekday) }
    }

    var showsWeekNumbers: Bool {
        didSet { defaults.set(showsWeekNumbers, forKey: Keys.showsWeekNumbers) }
    }

    /// Feiertage, die nur in anderen Bundesländern gelten.
    var showsRegionalHolidays: Bool {
        didSet { defaults.set(showsRegionalHolidays, forKey: Keys.showsRegionalHolidays) }
    }

    /// Besondere Tage ohne Feiertagsstatus (Heiligabend, Muttertag, Advent …).
    var showsObservances: Bool {
        didSet { defaults.set(showsObservances, forKey: Keys.showsObservances) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init) ?? .system
        firstWeekday = FirstWeekday(rawValue: defaults.integer(forKey: Keys.firstWeekday)) ?? .monday
        showsWeekNumbers = defaults.object(forKey: Keys.showsWeekNumbers) as? Bool ?? true
        showsRegionalHolidays = defaults.object(forKey: Keys.showsRegionalHolidays) as? Bool ?? true
        showsObservances = defaults.object(forKey: Keys.showsObservances) as? Bool ?? true
        homeState = defaults.string(forKey: Keys.homeState).flatMap(GermanState.init) ?? .berlin
    }
}
