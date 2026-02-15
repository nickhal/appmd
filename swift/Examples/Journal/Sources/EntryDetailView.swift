import SwiftUI
import AppMDKit

struct EntryDetailView: View {
    let entry: JournalEntry
    @ObservedObject var store: JournalStore

    @State private var editedBody: String = ""
    @State private var editedMood: String?
    @State private var editedTags: String = ""
    @State private var isEditing: Bool = false
    @State private var hasUnsavedChanges: Bool = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                header

                Divider()

                // Body
                if isEditing {
                    editView
                } else {
                    readView
                }
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isEditing {
                    Button("Done") {
                        saveAndStopEditing()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button {
                        startEditing()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .keyboardShortcut("e", modifiers: .command)
                }
            }
        }
        .onAppear {
            loadFromEntry()
        }
        .onChange(of: entry) { _, newEntry in
            if !isEditing {
                loadFromEntry()
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.displayDate)
                    .font(.title)
                    .fontWeight(.bold)

                if isEditing {
                    HStack(spacing: 12) {
                        Picker("Mood", selection: $editedMood) {
                            Text("No mood").tag(nil as String?)
                            Divider()
                            ForEach(JournalStore.moods, id: \.self) { mood in
                                Text(moodEmoji(mood) + " " + mood.capitalized).tag(mood as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 160)
                        .onChange(of: editedMood) { _, _ in
                            scheduleAutoSave()
                        }

                        TextField("Tags (comma-separated)", text: $editedTags)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                            .onChange(of: editedTags) { _, _ in
                                scheduleAutoSave()
                            }
                    }
                } else {
                    HStack(spacing: 12) {
                        if let mood = entry.mood {
                            HStack(spacing: 4) {
                                Text(moodEmoji(mood))
                                    .font(.title2)
                                Text(mood.capitalized)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !entry.tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(entry.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.callout)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.blue.opacity(0.1))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }

            Spacer()

            if hasUnsavedChanges {
                Text("Saving...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Read View

    @ViewBuilder
    var readView: some View {
        Text(entry.body.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(.body)
            .lineSpacing(6)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Edit View

    @ViewBuilder
    var editView: some View {
        TextEditor(text: $editedBody)
            .font(.body)
            .lineSpacing(6)
            .frame(minHeight: 300)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: editedBody) { _, _ in
                scheduleAutoSave()
            }
    }

    // MARK: - Actions

    private func loadFromEntry() {
        editedBody = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        editedMood = entry.mood
        editedTags = entry.tags.joined(separator: ", ")
    }

    private func startEditing() {
        loadFromEntry()
        isEditing = true
    }

    private func saveAndStopEditing() {
        save()
        isEditing = false
    }

    private func scheduleAutoSave() {
        hasUnsavedChanges = true
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            await MainActor.run {
                save()
            }
        }
    }

    private func save() {
        let tags = editedTags
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var updated = entry
        updated.body = editedBody
        updated.mood = editedMood
        updated.tags = tags

        store.updateEntry(updated)
        hasUnsavedChanges = false
    }
}
