import SwiftUI

struct WeekView: View {
    let model: CalendarModel

    var body: some View {
        let calendar = model.calendar
        let days = calendar.daysOfWeek(containing: model.selectedDate)
        // Zeitgebundene Einträge stehen im Stundenraster, hier nur die ganztägigen.
        let allDayItems = Dictionary(uniqueKeysWithValues: days.map { day in
            (day, model.items(on: day).filter(\.isAllDay))
        })
        let hasAllDayItems = allDayItems.values.contains { !$0.isEmpty }

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: HourGrid.labelWidth, height: 1)
                ForEach(days, id: \.self) { day in
                    WeekColumnHeader(
                        day: day,
                        isToday: calendar.isDateInToday(day),
                        isRedDay: model.holiday(on: day) != nil || calendar.component(.weekday, from: day) == 1
                    )
                }
            }
            .padding(.vertical, 6)

            if hasAllDayItems {
                HStack(alignment: .top, spacing: 0) {
                    Text("ganztägig")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: HourGrid.labelWidth)
                    ForEach(days, id: \.self) { day in
                        VStack(spacing: 2) {
                            ForEach(allDayItems[day] ?? []) { item in
                                CalendarItemChip(item: item, onToggle: { model.toggleCompletion(of: item) }, isCompact: true)
                                    .calendarItemActions(item, model: model)
                            }
                            Color.clear.frame(height: 1)
                        }
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 6)
            }

            Divider()
            HourGrid(days: days, model: model)
        }
    }
}

/// Reine Spaltenüberschrift (Wochentag + Datum) – keine Auswahl, nur Beschriftung.
private struct WeekColumnHeader: View {
    let day: Date
    let isToday: Bool
    let isRedDay: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).locale(.german)))
                .font(.caption)
                .foregroundStyle(isToday || isRedDay ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            Text(day.formatted(.dateTime.day().locale(.german)))
                .font(.headline.weight(isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(dayNumberStyle)
                .frame(minWidth: 30, minHeight: 30)
                .background {
                    if isToday {
                        Circle().fill(.red)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var dayNumberStyle: AnyShapeStyle {
        if isToday { return AnyShapeStyle(.white) }
        if isRedDay { return AnyShapeStyle(.red) }
        return AnyShapeStyle(.primary)
    }
}

#Preview {
    let model = CalendarModel()
    model.mode = .week
    return WeekView(model: model)
}
