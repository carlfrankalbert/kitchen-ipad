import SwiftUI

struct MealPlanCard: View {
    @State private var store        = DataStore.shared
    @State private var editingWeekday: Int? = nil

    private var today: Int { currentWeekday() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: Binding(
            get: { editingWeekday.map { EditTarget(weekday: $0) } },
            set: { editingWeekday = $0?.weekday }
        )) { target in
            MealEditorSheet(weekday: target.weekday, store: store)
        }
    }

    // MARK: - Week strip (rows expand to fill available height)

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("UKEMENY").label()
                .padding(.horizontal, Theme.pad)
                .padding(.top, Theme.pad)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(store.weekPlan) { day in
                    MealRow(
                        day:     day,
                        isToday: day.weekday == today,
                        isPast:  day.weekday < today
                    )
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { editingWeekday = day.weekday }
                    .hoverEffect()

                    if day.weekday < 7 {
                        HLine()
                            .padding(.leading, Theme.pad + 40)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct EditTarget: Identifiable {
    let weekday: Int
    var id: Int { weekday }
}

private struct MealRow: View {
    let day: LocalDayPlan
    let isToday: Bool
    let isPast: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(weekdayNames[day.weekday] ?? "")
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Theme.accent : (isPast ? Theme.dimmed : Theme.muted))
                .frame(width: 28, alignment: .leading)

            Group {
                if let meal = day.meal {
                    Text(meal.emoji.isEmpty ? mealEmoji(for: meal.name) : meal.emoji)
                } else {
                    Text("·").foregroundStyle(Theme.dimmed)
                }
            }
            .font(.system(size: 15))
            .frame(width: 20)

            if let meal = day.meal {
                if let note = meal.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 13).italic())
                        .foregroundStyle(Theme.dimmed)
                        .lineLimit(1)
                } else {
                    Text(meal.name)
                        .font(.system(size: 13, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? Theme.accent : (isPast ? Theme.dimmed : Theme.text))
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dimmed)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Theme.pad)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}
