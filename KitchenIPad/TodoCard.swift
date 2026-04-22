import SwiftUI
import EventKit

struct TodoCard: View {
    @State private var remStore = RemindersStore(listName: "Gjøremål")
    @State private var newItem  = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("GJØREMÅL").label()
                if !remStore.items.isEmpty {
                    Text("\(remStore.items.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(minWidth: 18)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.green, in: Capsule())
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
            Text("Ingen gjøremål")
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
                prompt: Text("Legg til gjøremål…")
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
                        .foregroundStyle(Theme.green)
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

struct TodoCompactCard: View {
    @State private var remStore = RemindersStore(listName: "Gjøremål")
    @State private var newItem  = ""
    @FocusState private var fieldFocused: Bool

    private var firstItem: EKReminder? {
        remStore.items.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("GJØREMÅL").label()
                if !remStore.items.isEmpty {
                    Text("\(remStore.items.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(minWidth: 18)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.green, in: Capsule())
                        .offset(y: -0.5)
                }
                RemindersRefreshButton(remStore: remStore)
                Spacer()
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 10)
            .padding(.bottom, 6)

            HLine()

            if remStore.denied {
                Text("Ingen tilgang til Påminnelser")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.pad)
                    .padding(.vertical, 8)
            } else if !remStore.authorized {
                Text("Ber om tilgang…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dimmed)
                    .padding(.horizontal, Theme.pad)
                    .padding(.vertical, 8)
            } else if remStore.listNotFound {
                Text("Finner ikke «\(remStore.listName)»")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.red)
                    .padding(.horizontal, Theme.pad)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted.opacity(0.9))

                    Text(firstItem?.title ?? "Ingen åpne gjøremål")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(firstItem == nil ? Theme.dimmed : Theme.text.opacity(0.95))
                        .lineLimit(1)

                    Spacer()

                    if remStore.items.count > 1 {
                        Text("+\(remStore.items.count - 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 7)
                .padding(.bottom, 7)

                HLine()

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted.opacity(0.88))

                    TextField(
                        "",
                        text: $newItem,
                        prompt: Text("Legg til gjøremål…")
                            .foregroundStyle(Theme.muted.opacity(0.8))
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text.opacity(0.96))
                    .focused($fieldFocused)
                    .onSubmit { addItem() }

                    if !newItem.isEmpty {
                        Button(action: addItem) {
                            Image(systemName: "return")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.green)
                        }
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await remStore.requestAccess() }
        .remindersAutoRefresh(every: 45, remStore: remStore)
    }

    private func addItem() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        remStore.add(title: t)
        newItem = ""
    }
}
