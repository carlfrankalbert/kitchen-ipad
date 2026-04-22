import SwiftUI
import EventKit

struct MealPlanCard: View {
    let emphasizeToday: Bool
    let includeTodayInList: Bool

    @State private var remStore = RemindersStore(listNames: ["Ukesmeny", "Ukemeny", "Meny", "Middag", "Middager"])
    @State private var cachedWeekPlan: [LocalDayPlan] = MealPlanCard.emptyWeekPlan
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase
    private let dayTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var today: Int { norwegianWeekdayIndex(for: now) }

    private static var emptyWeekPlan: [LocalDayPlan] {
        (1...7).map { LocalDayPlan(weekday: $0, meal: nil) }
    }

    init(emphasizeToday: Bool = true, includeTodayInList: Bool = true) {
        self.emphasizeToday = emphasizeToday
        self.includeTodayInList = includeTodayInList
    }

    private var titleText: String {
        includeTodayInList ? "MENY" : "RESTEN AV UKEN"
    }

    private var visibleWeekPlan: [LocalDayPlan] {
        guard !includeTodayInList else { return cachedWeekPlan }
        return cachedWeekPlan.filter { $0.weekday > today }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text(titleText)
                    .font(.system(size: 16, weight: .semibold))
                    .kerning(2.4)
                    .foregroundStyle(Theme.muted.opacity(0.95))

                HStack {
                    Spacer()
                    RemindersRefreshButton(remStore: remStore)
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 9)
            .padding(.bottom, 4)

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
        .onChange(of: remStore.dataVersion) { _, _ in rebuildWeekPlan() }
        .onReceive(dayTick) { now = $0 }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            now = Date()
            Task { await remStore.refreshNow() }
        }
    }

    private var weekSection: some View {
        VStack(spacing: 0) {
            if visibleWeekPlan.isEmpty {
                Text("Ingen flere middager denne uken")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dimmed)
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 14)
            } else {
                ForEach(Array(visibleWeekPlan.enumerated()), id: \.element.weekday) { index, day in
                    MealRow(
                        day:     day,
                        isToday: day.weekday == today,
                        isPast:  day.weekday < today,
                        emphasizeToday: emphasizeToday
                    )

                    if index < visibleWeekPlan.count - 1 {
                        Theme.divider.opacity(0.46)
                            .frame(height: 0.4)
                            .padding(.leading, Theme.pad + 34)
                    }
                }
            }
            Spacer(minLength: 0)
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

            if let dueComponents = reminder.dueDateComponents,
               let weekday = weekdayIndex(for: dueComponents) {
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
        return normalizedDate(from: comps)
    }

    private func weekdayIndex(for dueComponents: DateComponents) -> Int? {
        guard let date = normalizedDate(from: dueComponents) else { return nil }
        return norwegianWeekdayIndex(for: date)
    }

    private func normalizedDate(from dueComponents: DateComponents) -> Date? {
        var components = dueComponents
        components.calendar = components.calendar ?? Calendar.current
        components.timeZone = components.timeZone ?? TimeZone.current

        // Date-only reminders are normalized to midday to avoid DST edge-case drift.
        if components.hour == nil { components.hour = 12 }
        if components.minute == nil { components.minute = 0 }
        if components.second == nil { components.second = 0 }

        return components.date
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
    let emphasizeToday: Bool

    private var todayHighlight: Bool { isToday && emphasizeToday }
    private var calmToday: Bool { isToday && !emphasizeToday }

    var body: some View {
        HStack(spacing: 9) {
            Text(weekdayNames[day.weekday] ?? "")
                .font(.system(size: 12, weight: (isToday ? .semibold : .regular)))
                .foregroundStyle(
                    isToday
                        ? Theme.infoBlue.opacity(todayHighlight ? 0.86 : 0.56)
                        : (isPast ? Theme.dimmed : Theme.muted.opacity(0.85))
                )
                .frame(width: 30, alignment: .leading)

            Group {
                if let meal = day.meal {
                    Text(meal.emoji.isEmpty ? mealEmoji(for: meal.name) : meal.emoji)
                } else {
                    Text("·").foregroundStyle(Theme.dimmed)
                }
            }
            .font(.system(size: calmToday ? 18 : (todayHighlight ? 19 : 17)))
            .frame(width: 18)

            if let meal = day.meal {
                if let note = meal.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 14.5, weight: isToday ? .semibold : .regular).italic())
                        .foregroundStyle(isToday ? Theme.infoBlue.opacity(todayHighlight ? 0.9 : 0.7) : Theme.dimmed)
                        .lineLimit(1)
                } else {
                    Text(meal.name)
                        .font(
                            .system(
                                size: todayHighlight ? 18 : (isToday ? 16 : 15),
                                weight: isToday ? .semibold : .regular
                            )
                        )
                        .foregroundStyle(
                            isToday
                                ? Theme.infoBlue.opacity(todayHighlight ? 0.92 : 0.7)
                                : (isPast ? Theme.dimmed : Theme.text)
                        )
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dimmed)
            }

            Spacer()

            if todayHighlight {
                Text("I DAG")
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.infoBlue, in: Capsule())
            }
        }
        .padding(.vertical, todayHighlight ? 7 : 5)
        .padding(.horizontal, Theme.pad)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.infoBlue.opacity(todayHighlight ? 0.12 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.infoBlue.opacity(todayHighlight ? 0.3 : 0.14), lineWidth: 0.7)
                    )
                    .padding(.horizontal, 8)
            }
        }
    }
}
