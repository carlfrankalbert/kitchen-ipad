import SwiftUI
import EventKit

struct MealPlanCard: View {
    @State private var remStore = RemindersStore(listNames: ["Ukesmeny", "Ukemeny", "Meny", "Middag", "Middager"])
    @State private var cachedWeekPlan: [LocalDayPlan] = MealPlanCard.emptyWeekPlan

    private var today: Int { currentWeekday() }

    private static var emptyWeekPlan: [LocalDayPlan] {
        (1...7).map { LocalDayPlan(weekday: $0, meal: nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text("MENY")
                    .font(.system(size: 15, weight: .bold))
                    .kerning(2.2)
                    .foregroundStyle(Theme.muted)

                HStack {
                    Spacer()
                    RemindersRefreshButton(remStore: remStore)
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if remStore.denied {
                Text("Ingen tilgang til Påminnelser")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(Theme.pad)
            } else if !remStore.authorized {
                Text("Ber om tilgang…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dimmed)
                    .padding(Theme.pad)
            } else if remStore.listNotFound {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Finner ikke meny-liste i Påminnelser")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.red)
                    Text(remStore.availableLists.joined(separator: ", "))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dimmed)
                }
                .padding(Theme.pad)
            } else {
                weekSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await remStore.requestAccess() }
        .remindersAutoRefresh(every: 60, remStore: remStore)
        .onAppear { rebuildWeekPlan() }
        .onChange(of: remStore.dataVersion) { rebuildWeekPlan() }
    }

    private var weekSection: some View {
        VStack(spacing: 0) {
            ForEach(cachedWeekPlan, id: \.weekday) { day in
                MealRow(
                    day:     day,
                    isToday: day.weekday == today,
                    isPast:  day.weekday < today
                )
                .frame(maxHeight: .infinity)

                if day.weekday < 7 {
                    HLine()
                        .padding(.leading, Theme.pad + 40)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func rebuildWeekPlan() {
        cachedWeekPlan = weekPlanFromReminders(remStore.items)
    }

    private func weekPlanFromReminders(_ reminders: [EKReminder]) -> [LocalDayPlan] {
        var mealsByWeekday: [Int: LocalMeal] = [:]
        var unassignedMeals: [LocalMeal] = []

        let sorted = reminders.sorted { lhs, rhs in
            let lhsDate = dueDate(for: lhs) ?? .distantFuture
            let rhsDate = dueDate(for: rhs) ?? .distantFuture
            return lhsDate < rhsDate
        }

        for reminder in sorted {
            let rawTitle = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawTitle.isEmpty else { continue }

            let parsed = parseMealTitle(rawTitle)
            let mealName = parsed.mealTitle.isEmpty ? rawTitle : parsed.mealTitle

            let meal = LocalMeal(name: mealName, emoji: mealEmoji(for: mealName))

            if let date = dueDate(for: reminder) {
                let weekday = weekdayIndex(for: date)
                if mealsByWeekday[weekday] == nil {
                    mealsByWeekday[weekday] = meal
                    continue
                }
            }

            if let weekday = parsed.weekday, mealsByWeekday[weekday] == nil {
                mealsByWeekday[weekday] = meal
                continue
            }

            unassignedMeals.append(meal)
        }

        if !unassignedMeals.isEmpty {
            var iterator = unassignedMeals.makeIterator()
            for weekday in 1...7 where mealsByWeekday[weekday] == nil {
                if let meal = iterator.next() {
                    mealsByWeekday[weekday] = meal
                } else {
                    break
                }
            }
        }

        return (1...7).map { weekday in
            LocalDayPlan(weekday: weekday, meal: mealsByWeekday[weekday])
        }
    }

    private func dueDate(for reminder: EKReminder) -> Date? {
        guard let comps = reminder.dueDateComponents else { return nil }
        return Calendar.current.date(from: comps)
    }

    private func weekdayIndex(for date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private func parseMealTitle(_ title: String) -> (weekday: Int?, mealTitle: String) {
        let normalized = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let token = normalized
            .split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "-" || $0 == "–" || $0 == "—" })
            .first?
            .lowercased() ?? ""

        let weekday: Int? = {
            switch token {
            case "man", "mandag": return 1
            case "tir", "tirsdag": return 2
            case "ons", "onsdag": return 3
            case "tor", "torsdag": return 4
            case "fre", "fredag": return 5
            case "lor", "lordag", "lør", "lørdag": return 6
            case "son", "sondag", "søn", "søndag": return 7
            default: return nil
            }
        }()

        guard weekday != nil else { return (nil, title) }

        let parts = title.split(
            maxSplits: 1,
            whereSeparator: { $0 == " " || $0 == ":" || $0 == "-" || $0 == "–" || $0 == "—" }
        )
        let mealTitle: String
        if parts.count == 2 {
            let remainder = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            mealTitle = remainder.isEmpty ? title : remainder
        } else {
            mealTitle = title
        }

        return (weekday, mealTitle)
    }
}

private struct MealRow: View {
    let day: LocalDayPlan
    let isToday: Bool
    let isPast: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(weekdayNames[day.weekday] ?? "")
                .font(.system(size: isToday ? 15 : 14, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Theme.infoBlue : (isPast ? Theme.dimmed : Theme.muted))
                .frame(width: 34, alignment: .leading)

            Group {
                if let meal = day.meal {
                    Text(meal.emoji.isEmpty ? mealEmoji(for: meal.name) : meal.emoji)
                } else {
                    Text("·").foregroundStyle(Theme.dimmed)
                }
            }
            .font(.system(size: 20))
            .frame(width: 24)

            if let meal = day.meal {
                if let note = meal.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: isToday ? 17 : 15, weight: isToday ? .semibold : .regular).italic())
                        .foregroundStyle(isToday ? Theme.infoBlue : Theme.dimmed)
                        .lineLimit(1)
                } else {
                    Text(meal.name)
                        .font(.system(size: isToday ? 22 : 17, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Theme.infoBlue : (isPast ? Theme.dimmed : Theme.text))
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dimmed)
            }

            Spacer()

            if isToday {
                Text("I DAG")
                    .font(.system(size: 12, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.infoBlue, in: Capsule())
            }
        }
        .padding(.vertical, isToday ? 12 : 9)
        .padding(.horizontal, Theme.pad)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.infoBlue.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.infoBlue.opacity(0.35), lineWidth: 0.8)
                    )
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}
