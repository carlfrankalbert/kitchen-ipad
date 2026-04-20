import SwiftUI
import EventKit

// MARK: - Reminders store (shared between shopping + todo)

@Observable
@MainActor
final class RemindersStore {
    var items:       [EKReminder] = []
    var authorized   = false
    var denied       = false
    var listNotFound = false
    let listName:    String

    private let store = EKEventStore()

    init(listName: String) {
        self.listName = listName
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToReminders()
            authorized = granted
            denied = !granted
            if granted { await fetch() }
        } catch {
            denied = true
        }
    }

    func fetch() async {
        guard let cal = reminderCalendar() else {
            listNotFound = true
            return
        }
        listNotFound = false
        let pred = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [cal]
        )
        await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { [weak self] fetched in
                Task { @MainActor in
                    self?.items = fetched ?? []
                    cont.resume()
                }
            }
        }
    }

    var availableLists: [String] {
        store.calendars(for: .reminder).map { $0.title }
    }

    func complete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        items.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
    }

    func add(title: String) {
        guard let cal = reminderCalendar() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title    = title
        reminder.calendar = cal
        try? store.save(reminder, commit: true)
        items.append(reminder)
    }

    func delete(_ reminder: EKReminder) {
        try? store.remove(reminder, commit: true)
        items.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
    }

    private func reminderCalendar() -> EKCalendar? {
        store.calendars(for: .reminder).first { $0.title == listName }
    }
}

// MARK: - ShoppingCard

struct ShoppingCard: View {
    @State private var remStore = RemindersStore(listName: "Handleliste")
    @State private var newItem  = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("HANDLELISTE").label()
                if !remStore.items.isEmpty {
                    Text("\(remStore.items.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.accent, in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, Theme.pad)
            .padding(.bottom, 8)

            HLine()

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
                    Text("Finner ikke «\(remStore.listName)»")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.red)
                    Text(remStore.availableLists.joined(separator: ", "))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dimmed)
                }
                .padding(Theme.pad)
            } else {
                itemList
                HLine()
                addField
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await remStore.requestAccess() }
    }

    @ViewBuilder
    private var itemList: some View {
        if remStore.items.isEmpty {
            Text("Listen er tom")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dimmed)
                .padding(.horizontal, Theme.pad)
                .padding(.vertical, 10)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(remStore.items, id: \.calendarItemIdentifier) { item in
                        CheckRow(title: item.title ?? "") {
                            remStore.complete(item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { remStore.delete(item) } label: {
                                Label("Slett", systemImage: "trash")
                            }
                        }
                        HLine().padding(.leading, Theme.pad + 28)
                    }
                }
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dimmed)

            TextField("Legg til vare…", text: $newItem)
                .font(.system(size: 13))
                .focused($fieldFocused)
                .onSubmit { addItem() }

            if !newItem.isEmpty {
                Button(action: addItem) {
                    Image(systemName: "return")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 10)
    }

    private func addItem() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        remStore.add(title: t)
        newItem = ""
    }
}

// MARK: - Shared check row

struct CheckRow: View {
    let title:      String
    let onComplete: () -> Void

    var body: some View {
        Button(action: onComplete) {
            HStack(spacing: 10) {
                Image(systemName: "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.dimmed)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, Theme.pad)
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }
}
