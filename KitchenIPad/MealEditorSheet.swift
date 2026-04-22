import SwiftUI

struct MealEditorSheet: View {
    let weekday: Int
    let store: DataStore

    @Environment(\.dismiss) private var dismiss

    @State private var name  = ""
    @State private var emoji = ""
    @State private var note  = ""
    @State private var mode: MealMode = .normal

    private var dayName: String { weekdayNamesFull[weekday] ?? "" }

    enum MealMode: String, CaseIterable {
        case normal   = "Middag"
        case borte    = "Borte"
        case takeaway = "Takeaway"
        case rester   = "Rester"

        var emoji: String {
            switch self {
            case .normal:   return "🍽️"
            case .borte:    return "✈️"
            case .takeaway: return "🛵"
            case .rester:   return "♻️"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $mode) {
                        ForEach(MealMode.allCases, id: \.self) { m in
                            Label(m.rawValue, systemImage: "").tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .normal {
                    Section("Middag") {
                        HStack {
                            TextField("Emoji", text: $emoji)
                                .frame(width: 44)
                                .font(.system(size: 24))
                                .multilineTextAlignment(.center)
                                .onChange(of: name) { _, _ in
                                    if emoji.isEmpty {
                                        emoji = mealEmoji(for: name)
                                    }
                                }

                            TextField("Hva er til middag?", text: $name)
                                .font(.system(size: 16))
                        }
                    }
                }
            }
            .navigationTitle(dayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") { save() }
                        .bold()
                }
                if store.dayPlan(for: weekday)?.meal != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Fjern", role: .destructive) {
                            store.updateMeal(nil, for: weekday)
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { loadExisting() }
    }

    private func loadExisting() {
        guard let day = store.dayPlan(for: weekday), let meal = day.meal else { return }
        name  = meal.name
        emoji = meal.emoji
        if let n = meal.note {
            mode = MealMode(rawValue: n) ?? .normal
        }
    }

    private func save() {
        let meal: LocalMeal
        if mode == .normal {
            let resolvedEmoji = emoji.isEmpty ? mealEmoji(for: name) : emoji
            meal = LocalMeal(name: name.isEmpty ? "Middag" : name, emoji: resolvedEmoji)
        } else {
            meal = LocalMeal(name: mode.rawValue, emoji: mode.emoji, note: mode.rawValue)
        }
        store.updateMeal(meal, for: weekday)
        dismiss()
    }
}
