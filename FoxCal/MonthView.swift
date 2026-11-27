import SwiftUI

struct MonthView: View {
    let model: CalendarModel

    private static let weekNumberWidth: CGFloat = 30

    var body: some View {
        let calendar = model.calendar
        let days = calendar.monthGridDays(for: model.selectedDate)
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }

        VStack(spacing: 0) {
            weekdayHeader
            Divider()
            ForEach(weeks, id: \.self) { week in
                HStack(spacing: 0) {
                    if model.settings.showsWeekNumbers {
                        let weekNumber = model.weekNumber(ofWeek: week)
                        Text(weekNumber.map { "\($0)" } ?? "")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: Self.weekNumberWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, 8)
                            .accessibilityLabel(weekNumber.map { "Kalenderwoche \($0)" } ?? "")
                    }

                    ForEach(week, id: \.self) { day in
                        MonthDayCell(
                            day: day,
                            isInMonth: calendar.isDate(day, equalTo: model.selectedDate, toGranularity: .month),
                            isToday: calendar.isDateInToday(day),
                            isSelected: calendar.isDate(day, inSameDayAs: model.selectedDate),
                            isWeekend: calendar.isWeekend(day),
                            isSunday: calendar.component(.weekday, from: day) == 1,
                            items: model.items(on: day),
                            model: model
                        )
                        .onTapGesture {
                            // Erster Tipp wählt den Tag aus, zweiter Tipp öffnet die Tagesansicht.
                            if calendar.isDate(day, inSameDayAs: model.selectedDate) {
                                model.open(day: day)
                            } else {
                                model.selectedDate = day
                            }
                        }
                    }
                }
                Divider()
            }
        }
    }

    private var weekdayHeader: some View {
        let calendar = model.calendar
        let symbols = calendar.shortStandaloneWeekdaySymbols
        // Symbole beginnen bei Sonntag – auf Montag als ersten Wochentag rotieren.
        let shift = calendar.firstWeekday - 1
        let ordered = Array(symbols[shift...] + symbols[..<shift])

        return HStack(spacing: 0) {
            if model.settings.showsWeekNumbers {
                Text("KW")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.weekNumberWidth)
            }
            ForEach(Array(ordered.enumerated()), id: \.offset) { index, symbol in
                // Wochentag nach Calendar-Zählung: 1 = Sonntag … 7 = Samstag.
                let weekday = (shift + index) % 7 + 1
                let isWeekend = weekday == 1 || weekday == 7
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isWeekend ? AnyShapeStyle(.red.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MonthDayCell: View {
    let day: Date
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isWeekend: Bool
    let isSunday: Bool
    let items: [CalendarItem]
    let model: CalendarModel

    /// Mehr Einträge passen nicht sinnvoll in eine Zelle.
    private static let maxVisibleItems = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.formatted(.dateTime.day().locale(.german)))
                .font(.callout.weight(isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(numberStyle)
                .frame(minWidth: 28, minHeight: 28)
                .background {
                    if isToday {
                        Circle().fill(.red)
                    } else if isSelected {
                        Circle().fill(.primary.opacity(0.12))
                    }
                }

            ForEach(items.prefix(Self.maxVisibleItems)) { item in
                // Aufgaben und Notizen: Tippen öffnet den Editor statt den Tag auszuwählen.
                CalendarItemChip(item: item, onToggle: { model.toggleCompletion(of: item) }, isCompact: true)
                    .calendarItemActions(item, model: model)
            }
            if items.count > Self.maxVisibleItems {
                Text("+\(items.count - Self.maxVisibleItems) weitere")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isWeekend ? Color.secondary.opacity(0.06) : .clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(.separator).frame(width: 0.5)
        }
        .opacity(isInMonth ? 1 : 0.4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityActions {
            ForEach(items.filter { $0.target != nil }) { item in
                Button("\(item.title) bearbeiten") { model.edit(item) }
            }
        }
    }

    private var numberStyle: AnyShapeStyle {
        if isToday { return AnyShapeStyle(.white) }
        if isSunday || items.contains(where: \.isHoliday) { return AnyShapeStyle(.red) }
        return AnyShapeStyle(.primary)
    }

    private var accessibilityText: String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.german))
        return ([date] + items.map(\.accessibilityDescription)).joined(separator: ", ")
    }
}
