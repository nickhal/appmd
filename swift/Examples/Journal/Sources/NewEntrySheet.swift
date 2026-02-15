import SwiftUI
import AppMDKit

struct NewEntrySheet: View {
    @ObservedObject var store: JournalStore
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var mood: String?
    @State private var tagsText: String = ""
    @State private var entryBody: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("New Journal Entry")
                    .font(.headline)

                Spacer()

                Button("Create") {
                    createEntry()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entryBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            // Form
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)

                Picker("Mood", selection: $mood) {
                    Text("None").tag(nil as String?)
                    Divider()
                    ForEach(JournalStore.moods, id: \.self) { mood in
                        Text(moodEmoji(mood) + " " + mood.capitalized).tag(mood as String?)
                    }
                }

                TextField("Tags (comma-separated)", text: $tagsText)

                Section("Entry") {
                    TextEditor(text: $entryBody)
                        .frame(minHeight: 200)
                        .font(.body)
                        .lineSpacing(4)
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 500, height: 450)
    }

    private func createEntry() {
        let tags = tagsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        store.createEntry(
            date: date,
            mood: mood,
            tags: tags,
            body: entryBody
        )

        dismiss()
    }
}
