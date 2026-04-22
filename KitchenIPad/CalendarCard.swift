import SwiftUI
import EventKit

// MARK: - Calendar store

@Observable
@MainActor
final class CalendarStore {
    var events: [EKEvent] = []
    var authorized = false
    var denied = false

    private let store = EKEventStore()

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorized = granted
            denied = !granted
            if granted { await fetch() }
        } catch {
            denied = true
        }
    }

    func fetch() async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let fromMon = (weekday + 5) % 7
        let start = cal.date(byAdding: .day, value: -fromMon, to: today)!
        let end = cal.date(byAdding: .day, value: 21, to: today)!
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let fetched = store.events(matching: pred)
        events = fetched.sorted { $0.startDate < $1.startDate }
    }
}

// MARK: - Weekly planning card

struct CalendarCard: View {
    @State private var calStore = CalendarStore()
    @State private var menuStore = RemindersStore(listNames: ["Ukesmeny", "Ukemeny", "Meny", "Middag", "Middager"])
    @State private var now = Date()

    @Environment(\.scenePhase) private var scenePhase
    private let dayTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let rowSpacing: CGFloat = 10
    private let rowTopPadding: CGFloat = 12
    private let rowBottomPadding: CGFloat = 10

    private var weekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: today)
        let fromMon = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -fromMon, to: today)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    private var weekPlanRows: [WeekPlanRowModel] {
        let today = Calendar.current.startOfDay(for: now)
        return weekDays.map { day in
            let hints = eventHints(for: day)
            return WeekPlanRowModel(
                date: day,
                weekday: shortWeekday(for: day),
                dayNumber: dayNumber(for: day),
                dinner: mealFor(date: day),
                events: hints.visible,
                extraEventCount: hints.extra,
                isToday: Calendar.current.isDate(day, inSameDayAs: now),
                isPast: day < today
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if calStore.denied {
                Text("Ingen kalendertilgang")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(Theme.pad)
            } else if !calStore.authorized {
                Text("Ber om tilgang…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dimmed)
                    .padding(Theme.pad)
            } else {
                weekContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await calStore.requestAccess() }
        .task { await menuStore.requestAccess() }
        .remindersAutoRefresh(every: 75, remStore: menuStore)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if calStore.authorized { await calStore.fetch() }
            }
        }
        .onReceive(dayTick) { tick in
            let previous = Calendar.current.startOfDay(for: now)
            let current = Calendar.current.startOfDay(for: tick)
            now = tick

            guard calStore.authorized else { return }
            Task {
                if current != previous { await calStore.fetch() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            now = Date()
            Task {
                if calStore.authorized { await calStore.fetch() }
                await menuStore.refreshNow()
            }
        }
    }

    private var weekContent: some View {
        GeometryReader { geo in
            let rowHeight = computedRowHeight(for: geo.size.height)

            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(weekPlanRows) { row in
                    WeekPlanDayRow(row: row)
                        .frame(height: rowHeight)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Theme.pad - 2)
            .padding(.top, rowTopPadding)
            .padding(.bottom, rowBottomPadding)
        }
    }

    private func computedRowHeight(for availableHeight: CGFloat) -> CGFloat {
        let reserved = rowTopPadding + rowBottomPadding + rowSpacing * 6
        let raw = (availableHeight - reserved) / 7
        return max(raw, 82)
    }

    private func eventHints(for date: Date) -> (visible: [String], extra: Int) {
        let events = eventsOn(date)
        let maxShown = 3
        let visible = events.prefix(maxShown).map {
            eventSummaryText(for: $0, maxTitleLength: 44)
        }
        let extra = max(0, events.count - maxShown)
        return (Array(visible), extra)
    }

    private func eventsOn(_ date: Date) -> [EKEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        return calStore.events
            .filter { event in event.endDate > start && event.startDate < end }
            .sorted { $0.startDate < $1.startDate }
    }

    private func eventSummaryText(for event: EKEvent, maxTitleLength: Int = 52) -> String {
        let rawTitle = event.title ?? "Avtale"
        let title = rawTitle.count > maxTitleLength
            ? String(rawTitle.prefix(maxTitleLength - 1)) + "…"
            : rawTitle
        if event.isAllDay { return title }
        return "\(timeText(event.startDate)) \(title)"
    }

    private func timeText(_ date: Date) -> String {
        CalendarCardFormatters.time.string(from: date)
    }

    private var mealsByWeekday: [Int: String] {
        var meals: [Int: String] = [:]

        for reminder in menuStore.items {
            let rawTitle = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawTitle.isEmpty else { continue }

            let parsed = parseMealTitle(rawTitle)
            let mealTitle = parsed.mealTitle.isEmpty ? rawTitle : parsed.mealTitle

            if let date = normalizedReminderDate(from: reminder.dueDateComponents) {
                let weekday = norwegianWeekdayIndex(for: date)
                if meals[weekday] == nil {
                    meals[weekday] = mealTitle
                    continue
                }
            }

            if let weekday = parsed.weekday, meals[weekday] == nil {
                meals[weekday] = mealTitle
            }
        }

        return meals
    }

    private func mealFor(date: Date) -> String? {
        mealsByWeekday[norwegianWeekdayIndex(for: date)]
    }

    private func normalizedReminderDate(from dueComponents: DateComponents?) -> Date? {
        guard var components = dueComponents else { return nil }
        components.calendar = components.calendar ?? Calendar.current
        components.timeZone = components.timeZone ?? TimeZone.current

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
        if parts.count == 2 {
            let remainder = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (weekday, remainder.isEmpty ? title : remainder)
        }
        return (weekday, title)
    }

    private func shortWeekday(for date: Date) -> String {
        CalendarCardFormatters.weekdayShort.string(from: date).capitalized
    }

    private func dayNumber(for date: Date) -> String {
        CalendarCardFormatters.dayNumber.string(from: date)
    }
}

private struct WeekPlanRowModel: Identifiable {
    let date: Date
    let weekday: String
    let dayNumber: String
    let dinner: String?
    let events: [String]
    let extraEventCount: Int
    let isToday: Bool
    let isPast: Bool

    var id: Date { date }
}

private struct WeekPlanDayRow: View {
    let row: WeekPlanRowModel

    private var dinnerText: String {
        guard let dinner = row.dinner, !dinner.isEmpty else { return "Ikke satt" }
        return "\(mealEmoji(for: dinner)) \(dinner)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(row.weekday)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(row.isPast ? Theme.dimmed : Theme.muted.opacity(0.9))
                    .frame(width: 36, alignment: .leading)

                Text(row.dayNumber)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(row.isPast ? Theme.dimmed : Theme.text.opacity(0.95))
                    .frame(width: 26, alignment: .leading)

                if row.isToday {
                    Text("I DAG")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(1.0)
                        .foregroundStyle(Theme.text.opacity(0.78))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule()
                                .fill(Theme.divider.opacity(0.26))
                                .overlay(
                                    Capsule()
                                        .stroke(Theme.divider.opacity(0.52), lineWidth: 0.7)
                                )
                        )
                }

                Spacer(minLength: 0)

                Text(dinnerText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(
                        row.isPast
                            ? Theme.dimmed
                            : Theme.muted.opacity(0.86)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if !row.events.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(row.events.enumerated()), id: \.offset) { _, text in
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.muted.opacity(0.8))

                            Text(text)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Theme.muted.opacity(0.9))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    if row.extraEventCount > 0 {
                        Text("+ \(row.extraEventCount) til")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dimmed)
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pad - 3)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    row.isToday
                        ? Theme.divider.opacity(0.2)
                        : Theme.divider.opacity(row.isPast ? 0.08 : 0.13)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            row.isToday ? Theme.divider.opacity(0.56) : Color.clear,
                            lineWidth: 0.75
                        )
                )
        )
    }
}

private enum CalendarCardFormatters {
    static let weekdayShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
