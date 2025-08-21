//
//  NotesApp.swift
//  MarkdownNotes
//
//  Created by Faeez Ahmed on 21/08/25.
//

import Foundation
import SwiftUI
import CoreData

@main
struct NotesApp: App {
    private let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\._persistence, persistenceController)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Persistence.swift (Core Data + optional CloudKit)
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    let cloudEnabled: Bool = false // Toggle to true to try CloudKit (requires capabilities & container id)

    private init(inMemory: Bool = false) {
        let model = Self.makeModel()

        if cloudEnabled {
            // Replace identifier with your own iCloud container
            let desc = NSPersistentStoreDescription()
            desc.type = NSSQLiteStoreType
            desc.url = Self.storeURL()
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.example.MarkdownNotes")
            desc.cloudKitContainerOptions = options
            let ckContainer = NSPersistentCloudKitContainer(name: "NotesModel", managedObjectModel: model)
            ckContainer.persistentStoreDescriptions = [desc]
            container = ckContainer
        } else {
            container = NSPersistentContainer(name: "NotesModel", managedObjectModel: model)
            container.persistentStoreDescriptions = [
                {
                    let d = NSPersistentStoreDescription()
                    d.type = NSSQLiteStoreType
                    d.url = Self.storeURL()
                    d.shouldMigrateStoreAutomatically = true
                    d.shouldInferMappingModelAutomatically = true
                    return d
                }()
            ]
        }

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error: \(error), \(error.userInfo)")
            }
            self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            self.container.viewContext.automaticallyMergesChangesFromParent = true
        }
    }

    private static func storeURL() -> URL {
        let storeName = "Notes.sqlite"
        let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
        return storeURL.appendingPathComponent(storeName)
    }

    // Programmatic Core Data model so this project is code-only
    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // Entity: Note
        let noteEntity = NSEntityDescription()
        noteEntity.name = "Note"
        noteEntity.managedObjectClassName = NSStringFromClass(Note.self)

        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .UUIDAttributeType
        idAttr.isOptional = false

        let titleAttr = NSAttributeDescription()
        titleAttr.name = "title"
        titleAttr.attributeType = .stringAttributeType
        titleAttr.isOptional = false
        titleAttr.defaultValue = "Untitled"

        let contentAttr = NSAttributeDescription()
        contentAttr.name = "content"
        contentAttr.attributeType = .stringAttributeType
        contentAttr.isOptional = true

        let tagsAttr = NSAttributeDescription()
        tagsAttr.name = "tags"
        tagsAttr.attributeType = .transformableAttributeType
        tagsAttr.isOptional = true
        tagsAttr.valueTransformerName = "NSSecureUnarchiveFromData"
        tagsAttr.attributeValueClassName = NSStringFromClass(NSArray.self)

        let createdAtAttr = NSAttributeDescription()
        createdAtAttr.name = "createdAt"
        createdAtAttr.attributeType = .dateAttributeType
        createdAtAttr.isOptional = false

        let updatedAtAttr = NSAttributeDescription()
        updatedAtAttr.name = "updatedAt"
        updatedAtAttr.attributeType = .dateAttributeType
        updatedAtAttr.isOptional = false

        let pinnedAttr = NSAttributeDescription()
        pinnedAttr.name = "isPinned"
        pinnedAttr.attributeType = .booleanAttributeType
        pinnedAttr.isOptional = false
        pinnedAttr.defaultValue = false

        noteEntity.properties = [idAttr, titleAttr, contentAttr, tagsAttr, createdAtAttr, updatedAtAttr, pinnedAttr]
        model.entities = [noteEntity]
        return model
    }
}

// MARK: - Note Managed Object
@objc(Note)
final class Note: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var content: String?
    @NSManaged var tags: [String]?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var isPinned: Bool
}

extension Note {
    @nonobjc class func fetchRequestAll() -> NSFetchRequest<Note> {
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(Note.isPinned), ascending: false),
            NSSortDescriptor(key: #keyPath(Note.updatedAt), ascending: false)
        ]
        return request
    }
}

// MARK: - Environment key to access PersistenceController
private struct PersistenceKey: EnvironmentKey { static let defaultValue: PersistenceController = .shared }
extension EnvironmentValues { var _persistence: PersistenceController { get { self[PersistenceKey.self] } set { self[PersistenceKey.self] = newValue } } }

// MARK: - ContentView (List + Search + Tags)
struct ContentView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\._persistence) private var persistence

    @FetchRequest(fetchRequest: Note.fetchRequestAll()) private var allNotes: FetchedResults<Note>

    @State private var searchText: String = ""
    @State private var selectedTag: String? = nil
    @State private var showOnlyPinned = false

    var body: some View {
        NavigationSplitView {
            masterView
        } detail: {
            PlaceholderDetail()
                .background(GradientBackground())
        }
    }

    // MARK: - Split out to reduce type-checking load
    @ViewBuilder
    private var masterView: some View {
        VStack(spacing: 0) {
            TagScroller(tags: uniqueTags(), selected: $selectedTag)
                .padding(.horizontal)
                .padding(.top, 8)

            Toggle(isOn: $showOnlyPinned.animation()) {
                Label("Pinned", systemImage: "pin.fill")
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)

            List {
                ForEach(filteredNotes(), id: \.objectID) { note in
                    NavigationLink {
                        NoteEditorView(note: note)
                    } label: {
                        NoteRow(note: note)
                    }
                    .listRowBackground(Color.black.opacity(0.1))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(note) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { togglePin(note) } label: {
                            Label(note.isPinned ? "Unpin" : "Pin",
                                  systemImage: note.isPinned ? "pin.slash" : "pin")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search notes"))
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: addSampleData) { Label("Add Sample", systemImage: "sparkles") }
                        Button(action: wipeAll)       { Label("Delete All", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addNote) { Label("New", systemImage: "plus.circle.fill") }
                }
            }
        }
        .background(GradientBackground())
    }

    private func filteredNotes() -> [Note] {
        allNotes.filter { n in
            var ok = true
            if showOnlyPinned { ok = ok && n.isPinned }
            if let selectedTag { ok = ok && (n.tags ?? []).contains(selectedTag) }
            if !searchText.isEmpty {
                let hay = (n.title + "\n" + (n.content ?? "")).lowercased()
                ok = ok && hay.contains(searchText.lowercased())
            }
            return ok
        }
    }

    private func uniqueTags() -> [String] {
        Array(Set(allNotes.flatMap { $0.tags ?? [] })).sorted()
    }

    private func addNote() {
        let n = Note(context: ctx)
        n.id = UUID()
        n.title = "Untitled"
        n.content = ""
        n.tags = []
        n.createdAt = Date()
        n.updatedAt = Date()
        n.isPinned = false
        save()
    }

    private func togglePin(_ n: Note) { n.isPinned.toggle(); n.updatedAt = Date(); save() }
    private func delete(_ n: Note)    { ctx.delete(n); save() }
    private func addSampleData() {
        let samples: [(String, String, [String])] = [
            ("SwiftUI Tips", "# SwiftUI\n\n- Use `@State`\n- Prefer `NavigationStack`", ["swift","ui"]),
            ("Groceries", "- Apples\n- Milk\n- Oats", ["life"]),
            ("Daily Journal", "## 2025-08-21\nFelt productive.", ["journal"])
        ]
        for s in samples {
            let n = Note(context: ctx)
            n.id = UUID(); n.title = s.0; n.content = s.1; n.tags = s.2
            n.createdAt = Date(); n.updatedAt = Date(); n.isPinned = false
        }
        save()
    }
    private func wipeAll() { allNotes.forEach(ctx.delete); save() }
    private func save() { try? ctx.save() }
}


// MARK: - Gradient Background (subtle, elegant)
struct GradientBackground: View {
    var body: some View {
        LinearGradient(gradient: Gradient(colors: [Color.black, Color(white: 0.08)]), startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

// MARK: - Placeholder Detail
struct PlaceholderDetail: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 48, weight: .thin))
            Text("Select or create a note")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Note Row (elegant cell)
struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if note.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }
                Text(snippet())
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    ForEach((note.tags ?? []).prefix(4), id: \.self) { tag in TagChip(text: tag) }
                    Spacer()
                    Text(note.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func snippet() -> String {
        (note.content ?? "").split(separator: "\n").first.map(String.init) ?? ""
    }
}

// MARK: - Tag Chip & Scroller
struct TagChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }
}

struct TagScroller: View {
    let tags: [String]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TagSelectable(label: "All", selected: selected == nil) { selected = nil }
                ForEach(tags, id: \.self) { t in
                    TagSelectable(label: "#\(t)", selected: selected == t) { selected = t }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct TagSelectable: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color.white.opacity(0.15) : Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Note Editor (Split: TextKit editor + Markdown preview)
struct NoteEditorView: View {
    @Environment(\.managedObjectContext) private var ctx
    @ObservedObject var note: Note

    @State private var titleText: String = ""
    @State private var bodyText: String = ""
    @State private var tagField: String = ""
    @State private var showPreviewOnlyOnPhone = 0 // 0 edit, 1 preview

    var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.width < 720
            VStack(spacing: 12) {
                // Title + Tags
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: $titleText, axis: .vertical)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .textFieldStyle(.plain)
                        .padding(.horizontal)
                        .padding(.top)
                        .onChange(of: titleText) { _ in commit() }

                    HStack(spacing: 8) {
                        TextField("Comma separated tags (e.g. swift, journal)", text: $tagField)
                            .textFieldStyle(.plain)
                            .font(.callout)
                        Button {
                            note.tags = tagField.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                            commit()
                        } label: { Label("Apply", systemImage: "checkmark.circle") }
                            .buttonStyle(.borderedProminent)
                            .tint(.white.opacity(0.12))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }

                if isCompact {
                    Picker("Mode", selection: $showPreviewOnlyOnPhone) {
                        Text("Edit").tag(0)
                        Text("Preview").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    Group {
                        if showPreviewOnlyOnPhone == 0 { editor } else { preview }
                    }
                    .background(.black.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .padding(.bottom)
                } else {
                    HStack(spacing: 12) {
                        editor
                        preview
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .background(GradientBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: togglePin) { Image(systemName: note.isPinned ? "pin.fill" : "pin") }
                Menu {
                    Button(action: insertTemplate) { Label("Insert Markdown Template", systemImage: "doc.append") }
                    Button(role: .destructive, action: deleteNote) { Label("Delete", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear { load() }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            MarkdownTextView(text: $bodyText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06)))
                .padding(12)
        }
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MarkdownPreview(text: bodyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06)))
    }

    private func load() {
        titleText = note.title
        bodyText = note.content ?? ""
        tagField = (note.tags ?? []).joined(separator: ", ")
    }

    private func commit() {
        note.title = titleText.isEmpty ? "Untitled" : titleText
        note.content = bodyText
        note.updatedAt = Date()
        try? ctx.save()
    }

    private func insertTemplate() {
        let template = """
        # Heading 1

        **Bold**, *Italic*, `code`

        - Bullet 1
        - Bullet 2

        ```swift
        print("Hello, Markdown!")
        ```
        """

        bodyText = (bodyText + (bodyText.isEmpty ? "" : "\n\n") + template)
        commit()
    }


    private func togglePin() { note.isPinned.toggle(); commit() }

    private func deleteNote() {
        let ctx = note.managedObjectContext!
        ctx.delete(note)
        try? ctx.save()
    }
}

// MARK: - UIKit TextKit Editor Wrapper (simple, elegant)
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.textColor = UIColor(white: 0.92, alpha: 1.0)
        tv.tintColor = .systemTeal
        tv.isEditable = true
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        tv.autocorrectionType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.delegate = context.coordinator
        tv.text = text
        tv.keyboardDismissMode = .interactive
        tv.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        // Subtle border
        tv.layer.cornerRadius = 16
        tv.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        tv.layer.borderWidth = 1
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        // Optional: very light syntax cue for headings
        context.coordinator.applyMinimalHighlighting(in: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextView
        init(_ parent: MarkdownTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        /// Minimal markdown highlighting (headings & inline code) to keep things elegant
        func applyMinimalHighlighting(in tv: UITextView) {
            let text = tv.text as NSString? ?? ""
            let attr = NSMutableAttributedString(string: text as String, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor(white: 0.92, alpha: 1)
            ])

            let fullRange = NSRange(location: 0, length: attr.length)

            // Headings: lines starting with '#'
            let headingRegex = try! NSRegularExpression(pattern: "(?m)^(#{1,6})\\s+(.*)$")
            headingRegex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, _ in
                guard let m = match else { return }
                let hashesRange = m.range(at: 1)
                let contentRange = m.range(at: 2)
                attr.addAttributes([
                    .font: UIFont.systemFont(ofSize: 20, weight: .semibold)
                ], range: contentRange)
                attr.addAttributes([
                    .foregroundColor: UIColor.systemTeal
                ], range: hashesRange)
            }

            // Inline code: `code`
            let codeRegex = try! NSRegularExpression(pattern: "`([^`]+)`")
            codeRegex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, _ in
                guard let m = match else { return }
                attr.addAttributes([
                    .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium),
                    .foregroundColor: UIColor.systemYellow
                ], range: m.range)
            }

            let selected = tv.selectedRange
            tv.attributedText = attr
            tv.selectedRange = selected
        }
    }
}

// MARK: - Markdown Preview using AttributedString(markdown:)
struct MarkdownPreview: View {
    let text: String
    var body: some View {
        Group {
            if let parsed = try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)) {
                Text(parsed)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            } else {
                Text(text)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
