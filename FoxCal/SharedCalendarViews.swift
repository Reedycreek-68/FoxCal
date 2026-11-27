import SwiftUI

/// Farbig hinterlegter Eintrag für ganztägige Ereignisse (Feiertage, Geburtstage).
struct AllDayChip: View {
    let text: Text
    let tint: Color
    var font: Font = .caption2.weight(.semibold)

    var body: some View {
        text
            .font(font)
            .foregroundStyle(tint)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Darstellung eines beliebigen Kalendereintrags.
/// Feiertage sind rot hinterlegt, alle anderen Einträge schlicht mit Symbol davor.
struct CalendarItemChip: View {
    let item: CalendarItem
    var font: Font = .caption2.weight(.semibold)
    /// Uhrzeit vor dem Titel anzeigen (nicht nötig im Stundenraster).
    var showsTime = true
    /// Wenn gesetzt, wird das Aufgaben-Symbol zum Abhaken-Button.
    var onToggle: (() -> Void)? = nil
    /// Für schmale Spalten (Monat, Woche): Feiertage anderer Länder und besondere Tage
    /// ohne Symbol und ohne Länderkürzel, damit der Name lesbar bleibt.
    var isCompact = false

    var body: some View {
        if item.isHoliday {
            AllDayChip(text: Text(item.title), tint: .red, font: font)
                .accessibilityLabel(item.accessibilityDescription)
        } else {
            // Innenabstand wie bei den Feiertagen, damit alles bündig ist.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if case .task(let isCompleted) = item.kind, let onToggle {
                    Button(action: onToggle) {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                            // Größere Trefferfläche als das kleine Symbol, ohne das Layout zu verschieben.
                            .padding(6)
                            .contentShape(Rectangle())
                            .padding(-6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCompleted ? "Als offen markieren" : "Als erledigt markieren")
                    titleText
                } else if isCompact, case .observance = item.kind {
                    titleText
                } else {
                    Text("\(iconText) \(titleText)")
                }
            }
            .font(font)
            .foregroundStyle(isSubdued ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.accessibilityDescription)
        }
    }

    private var isCompletedTask: Bool {
        item.kind == .task(isCompleted: true)
    }

    /// Erledigte Aufgaben und besondere Tage treten optisch zurück.
    private var isSubdued: Bool {
        if case .observance = item.kind { return true }
        return isCompletedTask
    }

    private var iconText: Text {
        switch item.kind {
        case .holiday: Text("")
        case .observance(let isRegionalHoliday): Text(Image(systemName: isRegionalHoliday ? "flag" : "star"))
        case .birthday: Text(Image(systemName: "birthday.cake.fill"))
        case .event(let color): Text(Image(systemName: "circle.fill")).foregroundStyle(color)
        case .task(let isCompleted): Text(Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle"))
        case .note: Text(Image(systemName: "note.text"))
        }
    }

    private var titleText: Text {
        var title = item.title
        if case .birthday(let age?) = item.kind {
            title = "\(age). \(title)"
        }
        if !isCompact, let detail = item.detail {
            title += " (\(detail))"
        }
        let text = Text(title).strikethrough(isCompletedTask)
        if showsTime, let time = item.time {
            return Text("\(Text(time.formatted(.foxTime)).monospacedDigit()) \(text)")
        }
        return text
    }
}

extension View {
    /// Tippen öffnet den Editor, Kontextmenü bietet Abhaken und Löschen –
    /// aber nur für Einträge, die in FoxCal bearbeitet werden können.
    func calendarItemActions(_ item: CalendarItem, model: CalendarModel) -> some View {
        modifier(CalendarItemActions(item: item, model: model))
    }
}

private struct CalendarItemActions: ViewModifier {
    let item: CalendarItem
    let model: CalendarModel

    @ViewBuilder
    func body(content: Content) -> some View {
        if item.target != nil {
            content
                .contentShape(Rectangle())
                .onTapGesture { model.edit(item) }
                .contextMenu {
                    let isEditable = model.isEditable(item)
                    Button(
                        isEditable ? "Bearbeiten" : "Ansehen",
                        systemImage: isEditable ? "pencil" : "eye"
                    ) { model.edit(item) }
                    if case .task(let isCompleted) = item.kind {
                        Button(
                            isCompleted ? "Als offen markieren" : "Als erledigt markieren",
                            systemImage: isCompleted ? "circle" : "checkmark.circle"
                        ) {
                            model.toggleCompletion(of: item)
                        }
                    }
                    if isEditable {
                        Divider()
                        Button(
                            model.isRecurring(item) ? "Diesen Termin löschen" : "Löschen",
                            systemImage: "trash",
                            role: .destructive
                        ) { model.delete(item) }
                    }
                }
        } else {
            content
        }
    }
}

/// Kopfzeile eines Tages (Wochentag + Datum) für Wochen- und Tagesansicht.
struct DayHeader: View {
    let day: Date
    let isToday: Bool
    let isSelected: Bool
    let isRedDay: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).locale(.german)))
                .font(.caption)
                .foregroundStyle(isRedDay ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            Text(day.formatted(.dateTime.day().locale(.german)))
                .font(.title3.weight(isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(dayNumberStyle)
                .frame(width: 34, height: 34)
                .background {
                    if isToday {
                        Circle().fill(.red)
                    } else if isSelected {
                        Circle().fill(.primary.opacity(0.12))
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var dayNumberStyle: AnyShapeStyle {
        if isToday { return AnyShapeStyle(.white) }
        if isRedDay { return AnyShapeStyle(.red) }
        return AnyShapeStyle(.primary)
    }
}

/// Scrollbares Stundenraster (0–24 Uhr) mit einer Spalte pro Tag.
/// Doppeltippen auf eine Stunde legt dort eine neue Aufgabe an.
struct HourGrid: View {
    let days: [Date]
    let model: CalendarModel

    static let hourHeight: CGFloat = 56
    static let labelWidth: CGFloat = 52

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    hourLabels
                    ForEach(days, id: \.self) { day in
                        let timedItems = model.items(on: day).filter { !$0.isAllDay }
                        HourGridColumn(
                            day: model.calendar.startOfDay(for: day),
                            isToday: model.calendar.isDateInToday(day),
                            isShaded: model.calendar.isWeekend(day) || model.holiday(on: day) != nil,
                            events: timedItems.filter(\.isEvent),
                            timedItems: timedItems.filter { !$0.isEvent },
                            model: model,
                            onDoubleTapHour: { hour in model.newTask(on: day, hour: hour) }
                        )
                    }
                }
                .padding(.vertical, 10)
            }
            .onAppear {
                proxy.scrollTo(7, anchor: .top)
            }
        }
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hour.formatted(.number.precision(.integerLength(2))) + ":00")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: Self.labelWidth - 8, height: Self.hourHeight, alignment: .topTrailing)
                    .offset(y: -7)
                    .padding(.trailing, 8)
                    .id(hour)
            }
        }
    }
}

private struct HourGridColumn: View {
    let day: Date
    let isToday: Bool
    let isShaded: Bool
    /// Termine mit Dauer – als Blöcke dargestellt.
    let events: [CalendarItem]
    /// Zeitpunkte ohne Dauer (Aufgaben) – als Zeilen dargestellt.
    let timedItems: [CalendarItem]
    let model: CalendarModel
    let onDoubleTapHour: (Int) -> Void

    private static let itemHeight: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Color.clear
                    .frame(height: HourGrid.hourHeight)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onDoubleTapHour(hour) }
                    .overlay(alignment: .top) {
                        Rectangle().fill(.separator).frame(height: 0.5)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .background(isShaded ? Color.secondary.opacity(0.06) : .clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(.separator).frame(width: 0.5)
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                let columnWidth = max(geometry.size.width - 4, 0)
                ForEach(EventLayout.layout(events, day: day)) { layout in
                    let width = columnWidth / CGFloat(layout.columnCount)
                    EventBlock(item: layout.item, height: layout.height)
                        .frame(width: max(width - 2, 0), height: layout.height)
                        .calendarItemActions(layout.item, model: model)
                        .offset(x: 2 + CGFloat(layout.column) * width, y: layout.top)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            ForEach(positionedItems) { positioned in
                CalendarItemChip(item: positioned.item, showsTime: false) {
                    model.toggleCompletion(of: positioned.item)
                }
                .frame(height: Self.itemHeight)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                .calendarItemActions(positioned.item, model: model)
                .padding(.horizontal, 2)
                .offset(y: positioned.y)
            }
        }
        .overlay {
            if isToday {
                CurrentTimeIndicator(calendar: model.calendar)
            }
        }
    }

    private struct PositionedItem: Identifiable {
        let item: CalendarItem
        let y: CGFloat
        var id: String { item.id }
    }

    /// Setzt Einträge auf Höhe ihrer Uhrzeit; Einträge zur gleichen Zeit
    /// werden untereinander gestapelt statt sich zu überdecken.
    private var positionedItems: [PositionedItem] {
        var result: [PositionedItem] = []
        var nextFreeY = -CGFloat.infinity
        for item in timedItems {
            guard let time = item.time else { continue }
            let components = model.calendar.dateComponents([.hour, .minute], from: time)
            let minutes = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
            let y = max(minutes / 60 * HourGrid.hourHeight, nextFreeY)
            result.append(PositionedItem(item: item, y: y))
            nextFreeY = y + Self.itemHeight + 1
        }
        return result
    }
}

/// Position eines Termins im Stundenraster. Überlappende Termine
/// werden nebeneinander in Spalten verteilt.
private struct EventLayout: Identifiable {
    let item: CalendarItem
    let top: CGFloat
    let height: CGFloat
    let column: Int
    let columnCount: Int

    var id: String { item.id }

    private static let minimumHeight: CGFloat = 18

    static func layout(_ events: [CalendarItem], day: Date) -> [EventLayout] {
        func y(_ date: Date) -> CGFloat {
            let hours = min(max(date.timeIntervalSince(day) / 3600, 0), 24)
            return CGFloat(hours) * HourGrid.hourHeight
        }

        var result: [EventLayout] = []
        // Gruppe zusammenhängend überlappender Termine (top, bottom, column).
        var cluster: [(item: CalendarItem, top: CGFloat, bottom: CGFloat, column: Int)] = []
        var columnBottoms: [CGFloat] = []
        var clusterBottom = -CGFloat.infinity

        func flushCluster() {
            for entry in cluster {
                result.append(EventLayout(
                    item: entry.item,
                    top: entry.top,
                    height: entry.bottom - entry.top,
                    column: entry.column,
                    columnCount: max(columnBottoms.count, 1)
                ))
            }
            cluster = []
            columnBottoms = []
        }

        // Nach Beginn; bei gleichem Beginn nach Kalender-Reihenfolge (weiter links = weiter oben in den Einstellungen).
        let sorted = events.sorted {
            let start0 = $0.time ?? .distantPast, start1 = $1.time ?? .distantPast
            return start0 != start1 ? start0 < start1 : $0.sourceOrder < $1.sourceOrder
        }
        for item in sorted {
            guard let start = item.time else { continue }
            let top = y(start)
            let bottom = max(y(item.endTime ?? start), top + minimumHeight)

            if top >= clusterBottom {
                flushCluster()
                clusterBottom = -.infinity
            }
            // Erste Spalte, deren letzter Termin schon zu Ende ist.
            let column = columnBottoms.firstIndex { $0 <= top } ?? columnBottoms.count
            if column == columnBottoms.count {
                columnBottoms.append(bottom)
            } else {
                columnBottoms[column] = bottom
            }
            cluster.append((item, top, bottom, column))
            clusterBottom = max(clusterBottom, bottom)
        }
        flushCluster()
        return result
    }
}

/// Termin-Block im Stundenraster in der Farbe seines Kalenders.
private struct EventBlock: View {
    let item: CalendarItem
    let height: CGFloat

    var body: some View {
        let color: Color = if case .event(let color) = item.kind { color } else { .accentColor }

        VStack(alignment: .leading, spacing: 1) {
            Text(item.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(height > 36 ? 2 : 1)
            if height > 30, let start = item.time {
                Text(timeRange(start: start, end: item.endTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.22))
        .overlay(alignment: .leading) {
            Rectangle().fill(color).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityDescription)
    }

    private func timeRange(start: Date, end: Date?) -> String {
        let style: Date.FormatStyle = .foxTime
        guard let end else { return start.formatted(style) }
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }
}

/// Rote Linie auf Höhe der aktuellen Uhrzeit, minütlich aktualisiert.
private struct CurrentTimeIndicator: View {
    let calendar: Calendar

    var body: some View {
        TimelineView(.everyMinute) { context in
            let components = calendar.dateComponents([.hour, .minute], from: context.date)
            let minutes = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .offset(x: -4, y: minutes / 60 * HourGrid.hourHeight - 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

#Preview("Ganztägige Einträge") {
    VStack(spacing: 4) {
        CalendarItemChip(item: CalendarItem(id: "h", kind: .holiday, title: "1. Weihnachtstag"))
        CalendarItemChip(item: CalendarItem(id: "r", kind: .observance(isRegionalHoliday: true), title: "Allerheiligen (BW, BY, NW, RP, SL)"))
        CalendarItemChip(item: CalendarItem(id: "o", kind: .observance(isRegionalHoliday: false), title: "Heiligabend"))
        CalendarItemChip(item: CalendarItem(id: "e", kind: .event(color: .purple), title: "Kino", time: .now))
        CalendarItemChip(item: CalendarItem(id: "b1", kind: .birthday(age: 40), title: "Anna Schmidt"))
        CalendarItemChip(item: CalendarItem(id: "b2", kind: .birthday(age: nil), title: "Max Müller"))
        CalendarItemChip(item: CalendarItem(id: "t1", kind: .task(isCompleted: false), title: "Geschenke kaufen"))
        CalendarItemChip(item: CalendarItem(id: "t3", kind: .task(isCompleted: false), title: "Zahnarzt", time: .now))
        CalendarItemChip(item: CalendarItem(id: "t2", kind: .task(isCompleted: true), title: "Baum besorgen"))
        CalendarItemChip(item: CalendarItem(id: "n", kind: .note, title: "Rezept Gans"))
    }
    .frame(width: 160)
    .padding()
}
