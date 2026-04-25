import SwiftUI
import EventKit

// MARK: - Weekly planning card

struct CalendarCard: View {
    let calStore: CalendarStore
    @State private var menuStore = RemindersStore(listNames: ["Ukesmeny", "Ukemeny", "Meny", "Middag", "Middager"])
    @State private var now = Date()

    @Environment(\.scenePhase) private var scenePhase
    private let dayTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let rowTopPadding: CGFloat = 8
    private let rowBottomPadding: CGFloat = 8
    private let dividerThickness: CGFloat = 0.6

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
        .task { await menuStore.requestAccess() }
        .remindersAutoRefresh(every: 75, remStore: menuStore)
        .onReceive(dayTick) { tick in
            now = tick
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            now = Date()
            Task { await menuStore.refreshNow() }
        }
    }

    private var weekContent: some View {
        GeometryReader { geo in
            let rowHeight = computedRowHeight(for: geo.size.height)
            let rows = weekPlanRows

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    WeekPlanDayRow(row: row)
                        .frame(height: rowHeight)

                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(Theme.divider.opacity(0.36))
                            .frame(height: dividerThickness)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Theme.pad - 4)
            .padding(.top, rowTopPadding)
            .padding(.bottom, rowBottomPadding)
        }
    }

    private func computedRowHeight(for availableHeight: CGFloat) -> CGFloat {
        let reserved = rowTopPadding + rowBottomPadding + dividerThickness * 6
        let raw = (availableHeight - reserved) / 7
        return max(raw, 82)
    }

    private func eventHints(for date: Date) -> (visible: [String], extra: Int) {
        let events = eventsOn(date)
        let maxShown = 4
        let visible = events.prefix(maxShown).map {
            eventSummaryText(for: $0, maxTitleLength: 60)
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.weekday)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(row.isPast ? Theme.dimmed : Theme.muted.opacity(0.9))

                Text(row.dayNumber)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(row.isPast ? Theme.dimmed : Theme.text.opacity(0.95))

                if row.isToday {
                    Text("I DAG")
                        .font(.system(size: 8.5, weight: .semibold))
                        .kerning(1.0)
                        .foregroundStyle(Theme.text.opacity(0.78))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Theme.divider.opacity(0.32))
                        )
                        .padding(.top, 1)
                }
            }
            .frame(width: 50, alignment: .leading)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2.5) {
                if !row.events.isEmpty {
                    ForEach(Array(row.events.enumerated()), id: \.offset) { _, text in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Theme.muted.opacity(0.8))

                            Text(text)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(
                                    row.isPast ? Theme.dimmed : Theme.text.opacity(0.92)
                                )
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    if row.extraEventCount > 0 {
                        Text("+ \(row.extraEventCount) til")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.dimmed)
                            .padding(.leading, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)

            Text(dinnerText)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(
                    row.isPast ? Theme.dimmed : Theme.muted.opacity(0.88)
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 180, alignment: .trailing)
                .padding(.top, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            row.isToday
                ? Theme.divider.opacity(0.18)
                : Color.clear
        )
        .clipped()
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
