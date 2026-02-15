import SwiftUI
import AppMDKit

struct ContentView: View {
    @EnvironmentObject var store: JournalStore

    @State private var selectedEntryID: String?
    @State private var searchText = ""
    @State private var selectedMood: String?
    @State private var selectedTag: String?
    @State private var showingNewEntry = false

    var filteredEntries: [JournalEntry] {
        var result = store.entries

        // Apply mood filter
        if let mood = selectedMood, !mood.isEmpty {
            result = result.filter { $0.mood == mood }
        }

        // Apply tag filter
        if let tag = selectedTag, !tag.isEmpty {
            result = result.filter { $0.tags.contains(tag) }
        }

        // Apply search (simple text match — FTS is used for actual search)
        if !searchText.isEmpty {
            let searchResults = store.search(searchText)
            let searchIDs = Set(searchResults.map { $0.id })
            result = result.filter { searchIDs.contains($0.id) }
        }

        return result
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(isPresented: $showingNewEntry) {
            NewEntrySheet(store: store)
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    var sidebar: some View {
        VStack(spacing: 0) {
            // Filters
            filterBar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            Divider()

            // Entry list
            if store.entries.isEmpty && store.isLoaded {
                ContentUnavailableView {
                    Label("No Entries", systemImage: "book")
                } description: {
                    Text("Create your first journal entry")
                }
            } else {
                List(filteredEntries, selection: $selectedEntryID) { entry in
                    EntryRow(entry: entry)
                        .tag(entry.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.deleteEntry(entry)
                                if selectedEntryID == entry.id {
                                    selectedEntryID = nil
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Journal")
        .searchable(text: $searchText, prompt: "Search entries...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewEntry = true
                } label: {
                    Label("New Entry", systemImage: "plus")
                }
            }
        }
    }

    // MARK: - Filters

    @ViewBuilder
    var filterBar: some View {
        HStack(spacing: 8) {
            // Mood filter
            Picker("Mood", selection: $selectedMood) {
                Text("All Moods").tag(nil as String?)
                Divider()
                ForEach(JournalStore.moods, id: \.self) { mood in
                    Text(moodEmoji(mood) + " " + mood.capitalized).tag(mood as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 140)

            // Tag filter
            if !store.allTags.isEmpty {
                Picker("Tag", selection: $selectedTag) {
                    Text("All Tags").tag(nil as String?)
                    Divider()
                    ForEach(store.allTags, id: \.self) { tag in
                        Text(tag).tag(tag as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 120)
            }

            Spacer()
        }
    }

    // MARK: - Detail

    @ViewBuilder
    var detail: some View {
        if let entryID = selectedEntryID,
           let entry = store.entries.first(where: { $0.id == entryID }) {
            EntryDetailView(entry: entry, store: store)
        } else {
            ContentUnavailableView {
                Label("Select an Entry", systemImage: "doc.text")
            } description: {
                Text("Choose a journal entry from the sidebar, or create a new one.")
            }
        }
    }
}

// MARK: - Entry Row

struct EntryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.shortDate)
                    .font(.headline)

                Spacer()

                if let mood = entry.mood {
                    Text(moodEmoji(mood))
                        .font(.title3)
                }
            }

            if !entry.body.isEmpty {
                Text(entry.body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !entry.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(entry.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Helpers

func moodEmoji(_ mood: String) -> String {
    switch mood.lowercased() {
    case "happy": return "😊"
    case "sad": return "😢"
    case "neutral": return "😐"
    case "focused": return "🎯"
    case "anxious": return "😰"
    case "grateful": return "🙏"
    default: return "📝"
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(JournalStore())
}
