import SwiftData
import SwiftUI

struct DayView: View {
    let model: CalendarModel

    var body: some View {
        let calendar = model.calendar
        let day = model.selectedDate

        VStack(spacing: 0) {
            // Wochenleiste zum schnellen Wechseln zwischen den Tagen.
            HStack(spacing: 0) {
                ForEach(calendar.daysOfWeek(containing: day), id: \.self) { weekDay in
                    DayHeader(
                        day: weekDay,
                        isToday: calendar.isDateInToday(weekDay),
                        isSelected: calendar.isDate(weekDay, inSameDayAs: day),
                        isRedDay: model.holiday(on: weekDay) != nil || calendar.component(.weekday, from: weekDay) == 1
                    )
                    .onTapGesture { model.selectedDate = weekDay }
                }
            }
            .padding(.horizontal, 8)

            // Zeitgebundene Einträge stehen im Stundenraster, hier nur die ganztägigen.
            let items = model.items(on: day).filter(\.isAllDay)
            if !items.isEmpty {
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        CalendarItemChip(item: item, font: .subheadline.weight(.semibold)) {
                            model.toggleCompletion(of: item)
                        }
                        .calendarItemActions(item, model: model)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()
            HourGrid(days: [day], model: model)
        }
    }
}

#Preview {
    let model = CalendarModel()
    model.mode = .day
    // Der Container muss so lange leben wie die View – daher unten per `.modelContainer` gehalten.
    let container = try! ModelContainer(
        for: TaskItem.self, NoteItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let store = model.personalItems
    store.attach(container.mainContext)
    let today = Calendar.foxCal.startOfDay(for: .now)
    let at = { (hour: Int, minute: Int) in
        Calendar.foxCal.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
    }
    store.saveTask(TaskDraft(title: "Geschenke kaufen", date: today), id: nil)
    store.saveTask(TaskDraft(title: "Wäsche", date: today, isCompleted: true), id: nil)
    store.saveNote(NoteDraft(title: "Ideen fürs Wochenende", date: today), id: nil)
    store.saveTask(TaskDraft(title: "Zahnarzt", date: at(9, 30), hasTime: true), id: nil)
    store.saveTask(TaskDraft(title: "Anruf Mama", date: at(9, 30), hasTime: true), id: nil)
    store.saveTask(TaskDraft(title: "Team-Call", date: at(11, 0), hasTime: true), id: nil)
    return DayView(model: model)
        .modelContainer(container)
}
