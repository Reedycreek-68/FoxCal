import Contacts
import Foundation
import Observation

/// Ein Geburtstag aus der Kontakte-App.
struct Birthday: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let month: Int
    let day: Int
    /// Geburtsjahr, falls im Kontakt hinterlegt.
    let year: Int?
}

/// Lädt Geburtstage aus den Kontakten und hält sie nach Monat/Tag indiziert vor.
@Observable
final class BirthdayStore: CalendarItemSource {
    private(set) var authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    private var birthdaysByDay: [Int: [Birthday]] = [:]

    @ObservationIgnored private let store = CNContactStore()

    /// Fragt bei Bedarf nach Zugriff, lädt die Geburtstage und
    /// lädt sie neu, sobald sich die Kontakte ändern.
    func start() async {
        if authorizationStatus == .notDetermined {
            _ = try? await store.requestAccess(for: .contacts)
            authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        }
        guard hasAccess else { return }

        await reload()
        for await _ in NotificationCenter.default.notifications(named: .CNContactStoreDidChange) {
            await reload()
        }
    }

    private var hasAccess: Bool {
        #if os(macOS)
        authorizationStatus == .authorized
        #else
        // Unter iOS kann auch nur ein Teil der Kontakte freigegeben sein.
        authorizationStatus == .authorized || authorizationStatus == .limited
        #endif
    }

    func items(on date: Date, calendar: Calendar) -> [CalendarItem] {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return []
        }

        var matches = birthdaysByDay[Self.key(month: month, day: day)] ?? []
        // Am 29. Februar Geborene feiern in Nicht-Schaltjahren am 28. Februar.
        if month == 2, day == 28, !Self.isLeapYear(year) {
            matches += birthdaysByDay[Self.key(month: 2, day: 29)] ?? []
        }

        return matches.map { birthday in
            let age = birthday.year.map { year - $0 }.flatMap { $0 > 0 ? $0 : nil }
            return CalendarItem(id: "birthday-\(birthday.id)", kind: .birthday(age: age), title: birthday.name)
        }
    }

    private func reload() async {
        let birthdays = await Self.fetchBirthdays(from: store)
        birthdaysByDay = Dictionary(grouping: birthdays) { Self.key(month: $0.month, day: $0.day) }
            .mapValues { $0.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    }

    /// Liest alle Kontakte mit Geburtstag. Läuft bewusst nicht auf dem Main Actor,
    /// da das Durchlaufen der Kontakte blockierend ist.
    @concurrent
    private nonisolated static func fetchBirthdays(from store: CNContactStore) async -> [Birthday] {
        let keys: [CNKeyDescriptor] = [
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var result: [Birthday] = []

        try? store.enumerateContacts(with: request) { contact, _ in
            guard let birthday = contact.birthday,
                  let month = birthday.month,
                  let day = birthday.day,
                  let name = CNContactFormatter.string(from: contact, style: .fullName),
                  !name.isEmpty
            else { return }

            // Kontakte ohne Jahr speichern teils Platzhalterjahre (z. B. 1604).
            let year = birthday.year.flatMap { $0 > 1700 && $0 != NSDateComponentUndefined ? $0 : nil }
            result.append(Birthday(id: contact.identifier, name: name, month: month, day: day, year: year))
        }
        return result
    }

    private nonisolated static func key(month: Int, day: Int) -> Int {
        month * 100 + day
    }

    private nonisolated static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}
