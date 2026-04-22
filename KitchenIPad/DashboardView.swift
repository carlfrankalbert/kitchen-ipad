import SwiftUI
import EventKit

struct DashboardView: View {
    @State private var api        = APIClient.shared
    @State private var nowPlaying = NowPlayingStore()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Status bar ──────────────────────────────────────
                    StatusBarView(api: api)
                    HLine()

                    // ── Main content ────────────────────────────────────
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            TodaySituationCard(api: api)
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            HLine()

                            UtilityCornerControls()
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(.leading, Theme.pad - 1)
                                .padding(.trailing, Theme.pad - 2)
                                .padding(.top, 8)
                                .padding(.bottom, 8)
                                .frame(height: utilityControlsHeight(geo), alignment: .topLeading)
                        }
                        .frame(width: todayColumnWidth(geo), alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .top)

                        VLine()

                        CalendarCard()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxHeight: .infinity)

                    HLine()

                    // ── Footer info strip ───────────────────────────────
                    FooterStrip(
                        weather: api.weather,
                        postalDelivery: api.postalDelivery,
                        postalDeliveryStale: api.postalDeliveryStale,
                        nowPlaying: nowPlaying
                    )
                }
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .task {
            await api.fetchWeather()
            await api.fetchTransport()
            await api.fetchPostalDelivery()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                await api.fetchWeather()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await api.fetchTransport()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(21600))
                await api.fetchPostalDelivery()
            }
        }
        .onAppear { nowPlaying.startObserving() }
    }

    private func todayColumnWidth(_ geo: GeometryProxy) -> CGFloat {
        geo.size.width * 0.58
    }

    private func utilityControlsHeight(_ geo: GeometryProxy) -> CGFloat {
        min(max(112, geo.size.height * 0.14), 148)
    }
}

// MARK: - Footer info strip

private struct FooterStrip: View {
    let weather:    WeatherResponse?
    let postalDelivery: PostalDeliveryResponse?
    let postalDeliveryStale: Bool
    let nowPlaying: NowPlayingStore

    @State private var now = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var solar: (rise: Date?, set: Date?) { solarTimes(date: now) }

    private var sunText: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        guard let rise = solar.rise, let set = solar.set else { return "—" }
        return "\(df.string(from: rise)) – \(df.string(from: set))  ·  \(dayLengthText(rise: rise, set: set))"
    }

    private var postText: String {
        guard let dates = postalDelivery?.deliveryDates, !dates.isEmpty else {
            return postalDeliveryStale ? "Kunne ikke oppdatere" : "Laster…"
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "nb_NO")
        df.dateFormat = "EEE d. MMM"

        let labels = dates.prefix(3).map { date -> String in
            if Calendar.current.isDateInToday(date) { return "I dag" }
            if Calendar.current.isDateInTomorrow(date) { return "I morgen" }
            return df.string(from: date)
        }

        return labels.joined(separator: "  ·  ")
    }

    var body: some View {
        HStack(spacing: 0) {
            FooterCell(label: "POST", value: postText)
            footerDivider
            FooterCell(label: "SOL", value: sunText)
            footerDivider
            FooterCell(label: "POLLENVARSEL", value: "Bjørk  ·  Moderat")

            // Now Playing — only shown when music is active
            if nowPlaying.isPlaying {
                footerDivider
                NowPlayingCell(nowPlaying: nowPlaying)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .onReceive(timer) { now = $0 }
    }

    private var footerDivider: some View {
        Theme.divider
            .opacity(0.9)
            .frame(width: 0.5, height: 18)
            .padding(.horizontal, 14)
    }
}

private struct FooterCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(1.6)
                .foregroundStyle(Theme.muted.opacity(0.9))
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.muted.opacity(0.96))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

private struct NowPlayingCell: View {
    let nowPlaying: NowPlayingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "music.note")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("SPILLES NÅ")
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(1.6)
                    .foregroundStyle(Theme.muted.opacity(0.9))
            }
            HStack(spacing: 4) {
                Text(nowPlaying.title ?? "")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.muted.opacity(0.96))
                    .lineLimit(1)
                if let artist = nowPlaying.artist {
                    Text("·")
                        .foregroundStyle(Theme.dimmed)
                    Text(artist)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, Theme.hpad)
    }
}

// MARK: - Today situation

private struct TodaySituationCard: View {
    let api: APIClient

    @State private var calStore = CalendarStore()
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
                await todoStore.refreshNow()
                await reminderStore.refreshNow()
            }
        }
    }

    private func requestAccess() async {
        await calStore.requestAccess()
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
        .background(
            RoundedRectangle(cornerRadius: prominent ? 12 : 10, style: .continuous)
                .fill(prominent ? Theme.accent.opacity(0.08) : Theme.divider.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: prominent ? 12 : 10, style: .continuous)
                        .stroke(
                            prominent ? Theme.accent.opacity(0.22) : Theme.divider.opacity(0.28),
                            lineWidth: 0.7
                        )
                )
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

// MARK: - Utility controls

private struct UtilityCornerControls: View {
    @State private var shoppingStore = RemindersStore(listName: "Handleliste")
    @State private var todoStore = RemindersStore(listName: "Gjøremål")
    @State private var activeSheet: UtilityListKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                UtilityPanelCard(
                    title: "Handleliste",
                    count: shoppingStore.items.count,
                    itemSingular: "vare",
                    itemPlural: "varer",
                    accent: Theme.accent,
                    onOpen: { activeSheet = .shopping }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                UtilityPanelCard(
                    title: "Gjøremål",
                    count: todoStore.items.count,
                    itemSingular: "oppgave",
                    itemPlural: "oppgaver",
                    accent: Theme.green,
                    onOpen: { activeSheet = .todo }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await shoppingStore.requestAccess()
            await todoStore.requestAccess()
        }
        .remindersAutoRefresh(every: 90, remStore: shoppingStore)
        .remindersAutoRefresh(every: 90, remStore: todoStore)
        .sheet(item: $activeSheet) { kind in
            UtilityListSheet(
                kind: kind,
                remStore: kind == .shopping ? shoppingStore : todoStore
            )
        }
    }
}

private enum UtilityListKind: String, Identifiable {
    case shopping
    case todo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shopping: return "Handleliste"
        case .todo: return "Gjøremål"
        }
    }

    var placeholder: String {
        switch self {
        case .shopping: return "Legg til vare"
        case .todo: return "Legg til gjøremål"
        }
    }

    var accent: Color {
        switch self {
        case .shopping: return Theme.accent
        case .todo: return Theme.green
        }
    }

    var allowsDueDate: Bool {
        self == .todo
    }
}

private struct UtilityPanelCard: View {
    let title: String
    let count: Int
    let itemSingular: String
    let itemPlural: String
    let accent: Color
    let onOpen: () -> Void

    private var summaryText: String {
        guard count > 0 else { return "Tom liste · legg til med +" }
        let noun = count == 1 ? itemSingular : itemPlural
        return "\(count) \(noun) i listen"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .kerning(1.2)
                        .foregroundStyle(Theme.muted.opacity(0.92))

                    Spacer(minLength: 0)

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Text(summaryText)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text.opacity(0.94))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.divider.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.divider.opacity(0.34), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct UtilityListSheet: View {
    let kind: UtilityListKind
    let remStore: RemindersStore

    @Environment(\.dismiss) private var dismiss

    @State private var newTitle = ""
    @State private var includeDueDate = false
    @State private var dueDate = Date()

    private var orderedItems: [EKReminder] {
        remStore.items.sorted { left, right in
            let leftDate = normalizedReminderDate(from: left.dueDateComponents) ?? .distantFuture
            let rightDate = normalizedReminderDate(from: right.dueDateComponents) ?? .distantFuture
            if leftDate != rightDate { return leftDate < rightDate }
            return (left.title ?? "") < (right.title ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                addPanel

                HLine()

                if orderedItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.dimmed)
                        Text("Ingen elementer ennå")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(orderedItems, id: \.calendarItemIdentifier) { reminder in
                                listRow(reminder)
                                HLine().opacity(0.5)
                            }
                        }
                        .padding(.horizontal, Theme.pad)
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await remStore.refreshNow() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await remStore.refreshNow() }
    }

    private var addPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(kind.accent)

                TextField(kind.placeholder, text: $newTitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit(addItem)

                Button("Legg til", action: addItem)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(kind.accent)
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if kind.allowsDueDate {
                HStack(spacing: 10) {
                    Toggle("Sett dato", isOn: $includeDueDate)
                        .toggleStyle(.switch)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.muted)

                    Spacer(minLength: 0)

                    if includeDueDate {
                        DatePicker(
                            "",
                            selection: $dueDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 10)
    }

    private func listRow(_ reminder: EKReminder) -> some View {
        let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 10) {
            Button {
                remStore.complete(reminder)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.muted.opacity(0.8))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text((title?.isEmpty == false ? title! : "Uten navn"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                if let dueText = dueDateText(for: reminder) {
                    Text(dueText)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer(minLength: 0)

            Button {
                remStore.delete(reminder)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private func addItem() {
        let text = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let date = (kind.allowsDueDate && includeDueDate) ? dueDate : nil
        remStore.add(title: text, dueDate: date)
        newTitle = ""
        includeDueDate = false
    }

    private func dueDateText(for reminder: EKReminder) -> String? {
        guard let date = normalizedReminderDate(from: reminder.dueDateComponents) else { return nil }
        return UtilityListFormatters.dueDate.string(from: date)
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
}

private enum UtilityListFormatters {
    static let dueDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "EEE d. MMM"
        return formatter
    }()
}
