import Foundation
import Observation

@Observable
@MainActor
final class DataStore {
    static let shared = DataStore()

    var weekPlan: [LocalDayPlan] = []

    private let key = "kitchen.weekplan.v1"

    private init() { load() }

    func load() {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([LocalDayPlan].self, from: data)
        else {
            weekPlan = (1...7).map { LocalDayPlan(weekday: $0) }
            return
        }
        // Ensure all 7 weekdays are present (handles first launch or schema changes)
        var plan = decoded
        for day in 1...7 {
            if !plan.contains(where: { $0.weekday == day }) {
                plan.append(LocalDayPlan(weekday: day))
            }
        }
        weekPlan = plan.sorted { $0.weekday < $1.weekday }
    }

    func save() {
        if let data = try? JSONEncoder().encode(weekPlan) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func updateMeal(_ meal: LocalMeal?, for weekday: Int) {
        guard let idx = weekPlan.firstIndex(where: { $0.weekday == weekday }) else { return }
        weekPlan[idx].meal = meal
        save()
    }

    func dayPlan(for weekday: Int) -> LocalDayPlan? {
        weekPlan.first { $0.weekday == weekday }
    }
}
