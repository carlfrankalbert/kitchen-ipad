import EventKit
import Foundation

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
