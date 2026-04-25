import SwiftUI
import EventKit

struct UtilityCornerControls: View {
    @State private var shoppingStore = RemindersStore(listName: "Handleliste")
    @State private var todoStore = RemindersStore(listName: "Gjøremål")
    @State private var activeSheet: UtilityListKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UtilityPanelCard(
                title: "Handleliste",
                icon: "cart",
                accent: Theme.accent,
                onOpen: { activeSheet = .shopping }
            )

            UtilityPanelCard(
                title: "Gjøremål",
                icon: "checklist",
                accent: Theme.green,
                onOpen: { activeSheet = .todo }
            )
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
    let icon: String
    let accent: Color
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 26, alignment: .center)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text.opacity(0.94))

                Spacer(minLength: 0)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(
                corner: 12,
                fill: Theme.divider.opacity(0.16),
                stroke: Theme.divider.opacity(0.34),
                lineWidth: 0.8
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
