import SwiftUI
import TrainerCore
import UniformTypeIdentifiers

// MARK: - Search and glossary

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let q = query.trimmingCharacters(in: .whitespaces).lowercased()
                let concepts = model.catalog.orderedConcepts.filter {
                    q.isEmpty || $0.name.lowercased().contains(q) || $0.def.lowercased().contains(q)
                }
                if !q.isEmpty {
                    let lessons = model.catalog.lessons.filter { $0.title.lowercased().contains(q) || $0.objective.lowercased().contains(q) }
                    if !lessons.isEmpty {
                        Section("Lessons") {
                            ForEach(lessons) { l in NavigationLink(value: l) { LessonRow(lesson: l) } }
                        }
                    }
                    let cases = model.catalog.cases.filter { $0.title.lowercased().contains(q) || $0.summary.lowercased().contains(q) }
                    if !cases.isEmpty {
                        Section("Case studies") {
                            ForEach(cases) { c in NavigationLink(value: c) { Text(c.title) } }
                        }
                    }
                }
                Section(q.isEmpty ? "Glossary (\(concepts.count))" : "Glossary") {
                    ForEach(concepts) { c in
                        if let l = model.catalog.lessonById[c.lessonId] {
                            NavigationLink(value: l) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(c.name).font(.subheadline.weight(.semibold))
                                        Spacer()
                                        StateBadge(status: model.status(c.id))
                                    }
                                    MarkdownText(c.def).font(.footnote).foregroundStyle(.secondary)
                                    Text(l.title).font(.caption2).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                if !q.isEmpty && concepts.isEmpty {
                    Text("No matches for “\(query)”").foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Concepts, lessons, cases")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: LessonMeta.self) { LessonView(lesson: $0) }
            .navigationDestination(for: CaseMeta.self) { CaseView(meta: $0) }
        }
    }
}

// MARK: - Settings

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var exportDoc: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var message: String?
    @State private var confirmReset = false
    @State private var pendingImport: Data?

    var body: some View {
        NavigationStack {
            Form {
                reminderSection
                Section("Study") {
                    Picker("Daily session length", selection: Binding(get: { model.state.prefs.sessionMinutes }, set: { v in model.updatePrefs { $0.sessionMinutes = v } })) {
                        Text("10 minutes").tag(10); Text("15 minutes").tag(15); Text("20 minutes").tag(20); Text("30 minutes").tag(30)
                    }
                    Toggle("Ask how sure I am", isOn: Binding(get: { model.state.prefs.askConfidence }, set: { v in model.updatePrefs { $0.askConfidence = v } }))
                }
                Section("Appearance") {
                    Picker("Appearance", selection: Binding(get: { model.state.prefs.appearance }, set: { v in model.updatePrefs { $0.appearance = v } })) {
                        Text("System").tag(Appearance.system); Text("Light").tag(Appearance.light); Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Export progress…") {
                        do { exportDoc = BackupDocument(data: try model.exportData()); showExporter = true }
                        catch { message = "Export failed: \(error.localizedDescription)" }
                    }
                    .accessibilityIdentifier("export")
                    Button("Import progress…") { showImporter = true }.accessibilityIdentifier("import")
                    if let last = model.state.lastExportAt {
                        Text("Last export: \(last.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Backup") } footer: {
                    Text("Progress is stored only on this phone and survives app updates. Deleting the app deletes it, so export a copy now and then (to Files or iCloud Drive). Importing replaces current progress; invalid files are rejected without changing anything.")
                }
                Section {
                    Button("Reset all progress", role: .destructive) { confirmReset = true }
                } footer: { Text("Settings are kept.") }
                Section("About") {
                    LabeledContent("Lessons", value: "\(model.catalog.lessons.count)")
                    LabeledContent("Concepts", value: "\(model.catalog.concepts.count)")
                    LabeledContent("Questions", value: "\(model.catalog.items.count)")
                    LabeledContent("Case studies", value: "\(model.catalog.cases.count)")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    Link("Source code and sources", destination: URL(string: "https://github.com/RonShk/system_design_app")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.reminders.refreshStatus() }
            .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json,
                          defaultFilename: "system-design-progress-\(model.clock.today)") { result in
                if case .failure(let e) = result { message = "Export failed: \(e.localizedDescription)" }
                else { message = "Progress exported." }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        _ = try Backup.importData(data)   // validate before asking
                        pendingImport = data
                    } catch let f as Backup.Failure {
                        message = importMessage(f)
                    } catch {
                        message = "Could not read the file: \(error.localizedDescription)"
                    }
                case .failure(let e): message = "Could not open the file: \(e.localizedDescription)"
                }
            }
            .confirmationDialog("Replace current progress with the imported file?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
                Button("Replace", role: .destructive) {
                    if let d = pendingImport {
                        do { try model.importData(d); message = "Progress imported." } catch { message = "Import failed." }
                    }
                    pendingImport = nil
                }
            }
            .confirmationDialog("Delete all progress? This cannot be undone.", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete progress", role: .destructive) { model.resetProgress(); message = "Progress reset." }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} }
        }
    }

    private var reminderSection: some View {
        let r = model.reminders
        let prefs = model.state.prefs
        return Section {
            Toggle("Daily reminder", isOn: Binding(get: { prefs.remindersEnabled }, set: { on in
                Task {
                    if on, r.permission == .notAsked { await r.requestPermission() }
                    model.updatePrefs { $0.remindersEnabled = on }
                }
            }))
            .accessibilityIdentifier("reminder-toggle")
            if prefs.remindersEnabled {
                DatePicker("Time", selection: Binding(
                    get: { Calendar.current.date(from: DateComponents(hour: prefs.reminderHour, minute: prefs.reminderMinute)) ?? Date() },
                    set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        model.updatePrefs { $0.reminderHour = c.hour ?? 15; $0.reminderMinute = c.minute ?? 0 }
                    }), displayedComponents: .hourAndMinute)
            }
            LabeledContent("Permission", value: r.permission.rawValue)
            if let next = r.nextFire, prefs.remindersEnabled {
                LabeledContent("Next reminder", value: next.formatted(date: .abbreviated, time: .shortened))
            }
            if r.permission == .denied {
                Button("Open iOS Settings to allow notifications") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button("Send a test notification in 5 seconds") {
                Task {
                    let ok = await r.sendTest()
                    message = ok ? "Test scheduled. Lock the phone or go to the Home Screen to see it arrive." : "Notifications are not allowed. Turn them on in iOS Settings."
                }
            }
            .accessibilityIdentifier("test-notification")
        } header: { Text("Reminders") } footer: {
            Text("A local notification scheduled on this phone. It arrives while the app is closed and without internet, and follows the phone's time zone when you travel. Only one is ever scheduled.")
        }
    }

    private func importMessage(_ f: Backup.Failure) -> String {
        switch f {
        case .notJSON: "That file is not a progress export."
        case .wrongFormat: "That JSON file is not a System Design Trainer export."
        case .newerFormat: "That export was made by a newer version of the app. Update the app first."
        case .missingState: "The export is incomplete."
        case .invalid(let why): "The export is damaged (\(why)). Nothing was changed."
        }
    }
}
