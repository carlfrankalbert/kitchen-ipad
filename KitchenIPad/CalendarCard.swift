import SwiftUI
import EventKit

// MARK: - Calendar store

@Observable
@MainActor
final class CalendarStore {
    var events:     [EKEvent] = []
    var authorized  = false
    var denied      = false

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
        let cal     = Calendar.current
        let start   = cal.startOfDay(for: Date())
        let end     = cal.date(byAdding: .day, value: 14, to: start)!
        let pred    = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let fetched = store.events(matching: pred)
        events = fetched.sorted { $0.startDate < $1.startDate }
    }
}

// MARK: - CalendarCard

struct CalendarCard: View {
    @State private var calStore = CalendarStore()

    private var weekDays: [Date] {
        let cal      = Calendar.current
        let today    = cal.startOfDay(for: Date())
        let weekday  = cal.component(.weekday, from: today)
        let fromMon  = (weekday + 5) % 7
        let monday   = cal.date(byAdding: .day, value: -fromMon, to: today)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
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
                // Week grid — shows event titles in each day column
                weekGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await calStore.requestAccess() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if calStore.authorized { await calStore.fetch() }
            }
        }
    }

    // MARK: - Week grid (each column shows event titles for that day)

    private var weekGrid: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                WeekDayColumn(date: day, events: eventsOn(day))
                if idx < weekDays.count - 1 {
                    Theme.divider
                        .frame(width: 0.5)
                        .frame(height: 156)
                }
            }
        }
        .frame(height: 170, alignment: .top)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .padding(.horizontal, 2)
    }

    // MARK: - Helpers

    private func eventsOn(_ date: Date) -> [EKEvent] {
        let cal = Calendar.current
        return calStore.events.filter {
            cal.isDate($0.startDate, inSameDayAs: date) ||
            ($0.isAllDay && cal.isDate(date, inSameDayAs: $0.startDate))
        }
    }

}

// MARK: - Week day column (shows event titles)

private struct WeekDayColumn: View {
    let date:   Date
    let events: [EKEvent]

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var isPast:  Bool { date < Calendar.current.startOfDay(for: Date()) }

    private var dayLetter: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "nb_NO")
        df.dateFormat = "EEE"
        return String(df.string(from: date).prefix(1)).uppercased()
    }

    private var dayNum: String {
        let df = DateFormatter()
        df.dateFormat = "d"
        return df.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Day header
            VStack(alignment: .center, spacing: 3) {
                Text(dayLetter)
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(isToday ? Theme.infoBlue : (isPast ? Theme.dimmed : Theme.muted))

                ZStack {
                    if isToday {
                        Circle()
                            .fill(Theme.infoBlue)
                            .frame(width: 34, height: 34)
                    }
                    Text(dayNum)
                        .font(.system(size: isToday ? 19 : 16, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.white : (isPast ? Theme.dimmed : Theme.text))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .padding(.bottom, 5)

            // Event titles
            VStack(alignment: .leading, spacing: 2) {
                ForEach(events.prefix(3), id: \.eventIdentifier) { event in
                    HStack(spacing: 3) {
                        Rectangle()
                            .fill(calColor(event))
                            .frame(width: 3, height: 12)
                        Text(event.title ?? "")
                            .font(.system(size: 13, weight: isToday ? .medium : .regular))
                            .foregroundStyle(
                                isPast ? Theme.dimmed : (isToday ? Theme.infoBlue : Theme.text)
                            )
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 5)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calColor(_ event: EKEvent) -> Color {
        guard let components = event.calendar.cgColor?.components, components.count >= 3 else {
            return Theme.infoBlue
        }
        return Color(red: components[0], green: components[1], blue: components[2])
    }
}
