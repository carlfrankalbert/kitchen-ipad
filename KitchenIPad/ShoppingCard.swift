import SwiftUI
import EventKit
import UIKit

// MARK: - Reminders store (shared between shopping + todo)

@Observable
@MainActor
final class RemindersStore {
    var items:       [EKReminder] = []
    var authorized   = false
    var denied       = false
    var listNotFound = false
    var isRefreshing = false
    var dataVersion  = 0
    var listName: String { resolvedListName ?? listNames.first ?? "" }

    private let store = EKEventStore()
    private let listNames: [String]
    private let normalizedListNames: [String]
    private var resolvedListName: String?
    private var resolvedCalendarIdentifier: String?
    private var itemsSignature: Int?
    private var storeChangedObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?

    init(listName: String) {
        let names = [listName]
        self.listNames = names
        self.normalizedListNames = names.map(Self.normalizedListName)
    }

    init(listNames: [String]) {
        let names = listNames.isEmpty ? [""] : listNames
        self.listNames = names
        self.normalizedListNames = names.map(Self.normalizedListName)
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToReminders()
            authorized = granted
            denied = !granted
            if granted {
                startObservingChangesIfNeeded()
                await refreshNow()
            }
        } catch {
            denied = true
        }
    }

    func refreshNow() async {
        guard authorized else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch()
    }

    func fetch() async {
        guard let cal = reminderCalendar() else {
            listNotFound = true
            resolvedListName = nil
            resolvedCalendarIdentifier = nil
            applyItems([])
            return
        }
        listNotFound = false
        resolvedListName = cal.title
        resolvedCalendarIdentifier = cal.calendarIdentifier
        let pred = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [cal]
        )
        await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { [weak self] fetched in
                Task { @MainActor in
                    self?.applyItems(fetched ?? [])
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
        applyItems(items.filter { $0.calendarItemIdentifier != reminder.calendarItemIdentifier })
        scheduleRefresh()
    }

    func add(title: String, dueDate: Date? = nil) {
        guard let cal = reminderCalendar() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title    = title
        reminder.calendar = cal

        if let dueDate {
            var due = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
            due.calendar = Calendar.current
            due.timeZone = TimeZone.current
            due.hour = 12
            due.minute = 0
            due.second = 0
            reminder.dueDateComponents = due
        }

        try? store.save(reminder, commit: true)
        var updated = items
        updated.append(reminder)
        applyItems(updated)
        scheduleRefresh()
    }

    func delete(_ reminder: EKReminder) {
        try? store.remove(reminder, commit: true)
        applyItems(items.filter { $0.calendarItemIdentifier != reminder.calendarItemIdentifier })
        scheduleRefresh()
    }

    private func reminderCalendar() -> EKCalendar? {
        if let id = resolvedCalendarIdentifier,
           let cached = store.calendar(withIdentifier: id) {
            return cached
        }

        let calendars = store.calendars(for: .reminder)
        let normalizedCalendars = calendars.map { ($0, Self.normalizedListName($0.title)) }

        if let exact = normalizedCalendars.first(where: { normalizedListNames.contains($0.1) })?.0 {
            return exact
        }

        // Fallback: tolerate prefixes/suffixes (e.g. emoji or extra context in title)
        if let fuzzy = normalizedCalendars.first(where: { title in
            normalizedListNames.contains(where: { wanted in
                title.1.contains(wanted) || wanted.contains(title.1)
            })
        })?.0 {
            return fuzzy
        }

        return nil
    }

    private func startObservingChangesIfNeeded() {
        guard storeChangedObserver == nil else { return }

        storeChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
    }

    private func scheduleRefresh() {
        guard authorized else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else { return }
            await self.refreshNow()
        }
    }

    private func applyItems(_ newItems: [EKReminder]) {
        let newSignature = Self.signature(for: newItems)
        let changed = (itemsSignature != newSignature)
        items = newItems
        if changed {
            itemsSignature = newSignature
            dataVersion &+= 1
        }
    }

    private static func signature(for reminders: [EKReminder]) -> Int {
        var hasher = Hasher()
        hasher.combine(reminders.count)
        for reminder in reminders {
            hasher.combine(reminder.calendarItemIdentifier)
            hasher.combine(reminder.title ?? "")
            let c = reminder.dueDateComponents
            hasher.combine(c?.calendar?.identifier)
            hasher.combine(c?.era)
            hasher.combine(c?.year)
            hasher.combine(c?.month)
            hasher.combine(c?.day)
            hasher.combine(c?.hour)
            hasher.combine(c?.minute)
            hasher.combine(c?.second)
        }
        return hasher.finalize()
    }

    private static func normalizedListName(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct RemindersRefreshButton: View {
    let remStore: RemindersStore

    var body: some View {
        Button {
            Task { await remStore.refreshNow() }
        } label: {
            if remStore.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.muted)
        .disabled(!remStore.authorized || remStore.isRefreshing)
        .padding(.leading, 6)
    }
}

extension View {
    func remindersAutoRefresh(every seconds: Double, remStore: RemindersStore) -> some View {
        task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                await remStore.refreshNow()
            }
        }
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("HANDLELISTE").label()
                if !remStore.items.isEmpty {
                    Text("\(remStore.items.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(minWidth: 18)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                        .offset(y: -0.5)
                }
                RemindersRefreshButton(remStore: remStore)
                Spacer()
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, Theme.pad)
            .padding(.bottom, 7)

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
        .remindersAutoRefresh(every: 45, remStore: remStore)
    }

    @ViewBuilder
    private var itemList: some View {
        if remStore.items.isEmpty {
            Text("Listen er tom")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dimmed)
                .padding(.horizontal, Theme.pad)
                .padding(.top, 12)
                .padding(.bottom, 10)
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
                .padding(.top, 4)
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted.opacity(0.88))

            TextField(
                "",
                text: $newItem,
                prompt: Text("Legg til vare…")
                    .foregroundStyle(Theme.muted.opacity(0.82))
            )
                .font(.system(size: 14))
                .foregroundStyle(Theme.text.opacity(0.96))
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
        .padding(.vertical, 11)
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
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.muted.opacity(0.9))

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text.opacity(0.97))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.vertical, 9)
            .padding(.horizontal, Theme.pad)
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }
}
