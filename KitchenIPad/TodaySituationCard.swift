import SwiftUI
import EventKit

struct TodaySituationCard: View {
    let api: APIClient
    let calStore: CalendarStore

    @State private var menuStore = RemindersStore(listNames: ["Ukesmeny", "Ukemeny", "Meny", "Middag", "Middager"])
    @State private var todoStore = RemindersStore(listName: "Gjøremål")
    @State private var reminderStore = RemindersStore(listNames: ["Påminnelser", "Reminders"])
    @State private var now = Date()

    @Environment(\.scenePhase) private var scenePhase
    private let dayTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var todayDinnerText: String {
        guard let meal = mealFor(date: now) else { return "Ikke satt" }
        return "\(mealEmoji(for: meal)) \(meal)"
    }

    private var keyRememberLines: [String] {
        let merged = (todoStore.items + reminderStore.items).sorted { left, right in
            let leftDate = normalizedReminderDate(from: left.dueDateComponents) ?? .distantFuture
            let rightDate = normalizedReminderDate(from: right.dueDateComponents) ?? .distantFuture
            return leftDate < rightDate
        }

        var lines: [String] = []
        var seen: Set<String> = []

        for reminder in merged {
            let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard shouldShowInRemember(reminder, title: title) else { continue }
            let key = title
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            lines.append(title)
            if lines.count >= 2 { break }
        }

        return Array(lines.prefix(2))
    }

    private func shouldShowInRemember(_ reminder: EKReminder, title: String) -> Bool {
        guard let dueDate = normalizedReminderDate(from: reminder.dueDateComponents),
              Calendar.current.isDate(dueDate, inSameDayAs: now) else {
            return false
        }

        let normalized = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return false }

        return true
    }

    private var nextEventText: String? {
        if let timedEvent = todaysEvents
            .filter({ !$0.isAllDay && $0.endDate > now })
            .min(by: { $0.startDate < $1.startDate }) {
            return eventSummaryText(for: timedEvent, maxTitleLength: 58)
        }

        if let allDayEvent = todaysEvents.first(where: { $0.isAllDay && $0.endDate > now }) {
            return eventSummaryText(for: allDayEvent, maxTitleLength: 58)
        }

        return nil
    }

    private var specialTodayText: String? {
        let keywordTokens = [
            "gym", "trening", "fotball", "dans", "svømm", "barnehage",
            "kindergarten", "sfo", "kor", "øving", "skole"
        ]

        let eventTitles = todaysEvents.compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let eventHit = eventTitles.first(where: { title in
            let normalized = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return keywordTokens.contains(where: { normalized.contains($0) })
        }) {
            return eventHit
        }

        if let reminderHit = keyRememberLines.first(where: { title in
            let normalized = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return keywordTokens.contains(where: { normalized.contains($0) })
        }) {
            return reminderHit
        }

        return nil
    }

    private var practicalGuidanceText: String {
        guard let weather = api.weather else { return "Sjekk igjen om litt" }
        let items = clothingItems(
            temp: weather.current.temperature,
            precipitation: weather.current.precipitation,
            windSpeed: weather.current.windSpeed,
            symbolCode: weather.current.symbolCode
        )
        let labels = items.map(\.label)
        guard !labels.isEmpty else { return "Vanlige klær holder" }
        return labels.prefix(2).joined(separator: " + ")
    }

    private var todayHighLow: (high: Int, low: Int)? {
        guard let weather = api.weather else { return nil }
        let cal = Calendar.current

        let temps: [Double] = weather.hourly.compactMap { hour in
            guard let date = parseWeatherDate(hour.time), cal.isDateInToday(date) else { return nil }
            return hour.temperature
        }

        guard !temps.isEmpty else { return nil }
        return (
            high: Int((temps.max() ?? 0).rounded()),
            low: Int((temps.min() ?? 0).rounded())
        )
    }

    private var dayTrendText: String {
        guard let weather = api.weather else { return "Utover dagen: —" }

        let cal = Calendar.current
        let currentClass = weatherClassKey(weather.current.symbolCode)
        let futureToday = weather.hourly.compactMap { hour -> (Date, WeatherHourly)? in
            guard let date = parseWeatherDate(hour.time),
                  cal.isDateInToday(date),
                  date > now else { return nil }
            return (date, hour)
        }

        if let nextChange = futureToday.first(where: { weatherClassKey($0.1.symbolCode) != currentClass }) {
            return "Utover dagen: \(nextChange.1.symbolCode.weatherDescription) fra \(timeText(nextChange.0))"
        }

        return "Utover dagen: stabilt \(weather.current.symbolCode.weatherDescription.lowercased())"
    }

    private var todaysEvents: [EKEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        return calStore.events
            .filter { event in event.endDate > start && event.startDate < end }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let weather = api.weather {
                HStack(alignment: .center, spacing: 11) {
                    Image(systemName: weather.current.symbolCode.weatherSFSymbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 38))
                        .frame(width: 44, alignment: .leading)

                    Text("\(Int(weather.current.temperature.rounded()))°")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(api.weatherStale ? Theme.dimmed : Theme.text)

                    Spacer(minLength: 0)

                    if let hl = todayHighLow {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("H \(hl.high)°")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.text.opacity(0.74))
                            Text("L \(hl.low)°")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.muted.opacity(0.82))
                        }
                        .frame(minWidth: 52, alignment: .trailing)
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 10)
                .padding(.bottom, 1)

                Text(weather.current.symbolCode.weatherDescription)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(api.weatherStale ? Theme.dimmed : Theme.muted)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 1)

                Text(dayTrendText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(api.weatherStale ? Theme.dimmed : Theme.muted.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 1)

                Text("Praktisk: \(practicalGuidanceText)")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(api.weatherStale ? Theme.dimmed : Theme.muted)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 1)
                    .padding(.bottom, 10)
            } else {
                Text("Laster vær…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dimmed)
                    .padding(.horizontal, Theme.pad)
                    .padding(.vertical, 10)
            }

            HLine()

            VStack(alignment: .leading, spacing: 10) {
                TodaySituationLine(
                    label: "MIDDAG",
                    icon: "fork.knife",
                    value: todayDinnerText,
                    prominent: true
                )
                .padding(.top, 2)

                TodaySituationLine(
                    label: "NESTE",
                    icon: "calendar",
                    value: nextEventText ?? "Ingen flere avtaler i dag"
                )

                if !keyRememberLines.isEmpty {
                    TodaySituationLine(
                        label: "HUSK",
                        icon: "checkmark.circle",
                        value: keyRememberLines.joined(separator: "  ·  ")
                    )
                }

                if let specialTodayText {
                    TodaySituationLine(
                        label: "SPESIELT",
                        icon: "star",
                        value: specialTodayText
                    )
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 11)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await requestAccess() }
        .remindersAutoRefresh(every: 75, remStore: menuStore)
        .remindersAutoRefresh(every: 90, remStore: todoStore)
        .remindersAutoRefresh(every: 90, remStore: reminderStore)
        .onReceive(dayTick) { tick in
            now = tick
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            now = Date()
            Task {
                await menuStore.refreshNow()
                await todoStore.refreshNow()
                await reminderStore.refreshNow()
            }
        }
    }

    private func requestAccess() async {
        await menuStore.requestAccess()
        await todoStore.requestAccess()
        await reminderStore.requestAccess()
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
        TodaySituationFormatters.time.string(from: date)
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

    private func parseWeatherDate(_ raw: String) -> Date? {
        TodaySituationFormatters.isoFull.date(from: raw) ?? TodaySituationFormatters.isoBasic.date(from: raw)
    }

    private func weatherClassKey(_ symbolCode: String) -> String {
        let value = symbolCode.lowercased()
        if value.contains("thunder") { return "thunder" }
        if value.contains("snow") { return "snow" }
        if value.contains("sleet") { return "sleet" }
        if value.contains("rain") { return "rain" }
        if value.contains("fog") { return "fog" }
        if value.contains("cloudy") || value.contains("partlycloudy") { return "cloudy" }
        if value.contains("fair") || value.contains("clearsky") { return "clear" }
        return "other"
    }
}

private struct TodaySituationLine: View {
    let label: String
    let icon: String
    let value: String
    var prominent: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 14 : 12.5, weight: .semibold))
                .foregroundStyle(prominent ? Theme.accent.opacity(0.88) : Theme.muted.opacity(0.84))
                .frame(width: 18, alignment: .center)
                .padding(.top, prominent ? 3 : 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Theme.muted.opacity(0.88))
                    .textCase(.uppercase)

                Text(value)
                    .font(.system(size: prominent ? 23 : 16, weight: prominent ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(prominent ? Theme.text : Theme.text.opacity(0.94))
                    .lineLimit(prominent ? 2 : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: prominent)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, prominent ? 9 : 7)
        .softCard(
            corner: prominent ? 12 : 10,
            fill: prominent ? Theme.accent.opacity(0.08) : Theme.divider.opacity(0.12),
            stroke: prominent ? Theme.accent.opacity(0.22) : Theme.divider.opacity(0.28)
        )
    }
}

private enum TodaySituationFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let isoFull: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let isoBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
