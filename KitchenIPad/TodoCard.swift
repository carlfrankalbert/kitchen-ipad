import SwiftUI
import EventKit

struct TodoCard: View {
    @State private var remStore = RemindersStore(listName: "Gjøremål")
    @State private var newItem  = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("GJØREMÅL").label()
                if !remStore.items.isEmpty {
                    Text("\(remStore.items.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.green, in: Capsule())
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
            Text("Ingen gjøremål")
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

            TextField("Legg til gjøremål…", text: $newItem)
                .font(.system(size: 13))
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
        .padding(.vertical, 10)
    }

    private func addItem() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        remStore.add(title: t)
        newItem = ""
    }
}
