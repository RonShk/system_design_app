import SwiftUI
import TrainerCore

struct LearnView: View {
    @Environment(AppModel.self) private var model
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            List {
                Section("Curriculum") {
                    ForEach(model.catalog.modules) { m in
                        NavigationLink(value: m) { moduleRow(m) }.accessibilityIdentifier("module-\(m.id)")
                    }
                }
                Section {
                    ForEach(model.catalog.cases) { c in
                        NavigationLink(value: c) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.title).font(.body)
                                Text(caseSubtitle(c)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Applied design: case studies") } footer: {
                    Text("Each case asks you to attempt a stage before showing a reference design. Best taken after the lessons they build on.")
                }
                Section {
                    ForEach(model.catalog.labs) { lab in
                        NavigationLink(value: lab) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(lab.title).font(.body)
                                    if model.state.labsDone[lab.id] != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good) }
                                }
                                Label("Needs a computer", systemImage: "laptopcomputer").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Implementation labs") } footer: {
                    Text("Optional build exercises. The reasoning questions inside each lab work on the phone.")
                }
            }
            .navigationTitle("Learn")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search and glossary")
                }
            }
            .sheet(isPresented: $showSearch) { SearchView() }
            .navigationDestination(for: Module.self) { ModuleView(module: $0) }
            .navigationDestination(for: LessonMeta.self) { LessonView(lesson: $0) }
            .navigationDestination(for: CaseMeta.self) { CaseView(meta: $0) }
            .navigationDestination(for: LabMeta.self) { LabView(meta: $0) }
        }
    }

    private func moduleRow(_ m: Module) -> some View {
        let lessons = model.catalog.lessons(in: m.id)
        let done = lessons.filter(model.isCompleted).count
        let summary = Mastery.summary(of: model.catalog.concepts(in: m.id), statuses: model.statuses)
        return VStack(alignment: .leading, spacing: 6) {
            Text(m.title).font(.headline)
            Text(m.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            StateBar(summary: summary, height: 7)
            Text("\(done) of \(lessons.count) lessons read").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func caseSubtitle(_ c: CaseMeta) -> String {
        let done = model.state.caseResults.filter { $0.caseId == c.id }
        let ready = c.prereqs.filter { model.state.lessonsCompleted[$0] != nil }.count
        if !done.isEmpty { return "Attempted \(done.count)× · \(c.minutes) min" }
        return "\(c.minutes) min · \(ready)/\(c.prereqs.count) prerequisite lessons read"
    }
}

struct ModuleView: View {
    @Environment(AppModel.self) private var model
    let module: Module

    var body: some View {
        List {
            Section { Text(module.summary).font(.subheadline).foregroundStyle(.secondary) }
            Section("Lessons") {
                ForEach(model.catalog.lessons(in: module.id)) { l in
                    NavigationLink(value: l) { LessonRow(lesson: l) }.accessibilityIdentifier("lesson-\(l.id)")
                }
            }
        }
        .navigationTitle(module.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LessonRow: View {
    @Environment(AppModel.self) private var model
    let lesson: LessonMeta

    var body: some View {
        let missing = lesson.prereqs.filter { model.state.lessonsCompleted[$0] == nil }
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.isCompleted(lesson) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(model.isCompleted(lesson) ? Theme.good : Color(.systemGray3))
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.title).font(.body)
                HStack(spacing: 8) {
                    Text("\(lesson.minutes) min").font(.caption).foregroundStyle(.secondary)
                    if !missing.isEmpty && !model.isCompleted(lesson) {
                        Label("\(missing.count) prerequisite\(missing.count == 1 ? "" : "s") unread", systemImage: "arrow.turn.down.right")
                            .font(.caption).foregroundStyle(Theme.warn)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(lesson.concepts, id: \.self) { c in StateBadge(status: model.status(c)) }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Lesson

/// The scrollable body of a lesson; the footer differs between browsing and a daily session.
struct LessonContent: View {
    @Environment(AppModel.self) private var model
    let lesson: LessonMeta
    let footer: AnyView

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.catalog.modules.first { $0.id == lesson.module }?.title ?? "")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor).textCase(.uppercase)
                    Text(lesson.title).font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    Label("\(lesson.minutes) min read", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                }
                Card {
                    Text("After this lesson you can").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    Text(lesson.objective).font(.callout)
                }
                if !lesson.prereqs.isEmpty { prerequisites }
                if let body = model.catalog.lessonBodies[lesson.id] {
                    ForEach(Array(body.sections.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(s.title).font(.title2.weight(.semibold))
                            BlocksView(blocks: s.blocks)
                        }
                    }
                    Card {
                        Text("Key terms").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        ForEach(lesson.concepts, id: \.self) { c in
                            if let concept = model.catalog.concepts[c] {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(concept.name).font(.subheadline.weight(.semibold))
                                    MarkdownText(concept.def).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Card { SourcesView(sources: body.sources) }
                }
                footer
            }
            .padding(16)
        }
        .background(Theme.pageBackground)
    }

    private var prerequisites: some View {
        Card {
            Text("Builds on").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            ForEach(lesson.prereqs, id: \.self) { id in
                if let p = model.catalog.lessonById[id] {
                    NavigationLink(value: p) {
                        HStack {
                            Image(systemName: model.isCompleted(p) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.isCompleted(p) ? Theme.good : Theme.warn)
                            Text(p.title).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 36)
                    }
                }
            }
            if lesson.prereqs.contains(where: { model.state.lessonsCompleted[$0] == nil }) {
                Text("You can read this now, but it assumes the unread lessons above.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct LessonView: View {
    @Environment(AppModel.self) private var model
    let lesson: LessonMeta
    @State private var practice: EntryList?

    var body: some View {
        LessonContent(lesson: lesson, footer: AnyView(footer))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $practice) { PracticeSequenceView(title: "Practice", entries: $0.entries) }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(model.isCompleted(lesson) ? "Practise this lesson" : "Mark as read and practise") {
                model.completeLesson(lesson.id)
                let ids = SessionComposer.practiceItems(for: lesson, catalog: model.catalog, history: History(state: model.state), count: 4)
                practice = EntryList(entries: ids.map { .init(itemId: $0, context: .practice) })
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("lesson-practise")
            if !model.isCompleted(lesson) {
                Text("Reading alone only marks the concepts as introduced. Evidence comes from answering questions, and retention from answering them again on later days.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Case studies

struct CaseView: View {
    @Environment(AppModel.self) private var model
    let meta: CaseMeta
    @State private var unguided: CaseMode?

    var body: some View {
        List {
            Section {
                Text(meta.summary).font(.subheadline)
                Label("About \(meta.minutes) minutes", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            }
            if !meta.prereqs.isEmpty {
                Section("Builds on") {
                    ForEach(meta.prereqs, id: \.self) { id in
                        if let l = model.catalog.lessonById[id] {
                            NavigationLink(value: l) {
                                Label(l.title, systemImage: model.isCompleted(l) ? "checkmark.circle.fill" : "circle").font(.subheadline)
                            }
                        }
                    }
                }
            }
            Section {
                NavigationLink { GuidedCaseView(meta: meta) } label: {
                    Label("Guided walkthrough", systemImage: "list.number").frame(minHeight: 40)
                }
                .accessibilityIdentifier("case-guided")
                if model.catalog.caseBodies[meta.id]?.unguided != nil {
                    Button { unguided = .unguided } label: { Label("Unguided exercise (new constraints)", systemImage: "pencil.and.outline").frame(minHeight: 40) }
                    Button { unguided = .timed } label: { Label("Timed interview", systemImage: "timer").frame(minHeight: 40) }
                }
            } header: { Text("Work on it") } footer: {
                Text("Guided: attempt each stage, then compare. Unguided and timed: design alone, then grade yourself against a rubric. More than one design can satisfy it.")
            }
            let results = model.state.caseResults.filter { $0.caseId == meta.id }.sorted { $0.date > $1.date }
            if !results.isEmpty {
                Section("History (self-assessed)") {
                    ForEach(results) { r in
                        HStack {
                            Text(r.mode == .guided ? "Guided" : r.mode == .timed ? "Timed" : "Unguided")
                            Spacer()
                            Text("\(r.rubricMet)/\(r.rubricTotal) · \(r.durationSec / 60) min").foregroundStyle(.secondary)
                            Text(r.date, style: .date).foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    }
                }
            }
        }
        .navigationTitle(meta.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $unguided) { mode in UnguidedCaseView(meta: meta, mode: mode) }
    }
}

extension CaseMode: Identifiable { public var id: String { rawValue } }

/// Stage by stage: read the prompt, attempt it, then reveal the reference discussion.
struct GuidedCaseView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let meta: CaseMeta
    @State private var stage = 0
    @State private var revealed = false
    @State private var notes = ""
    @State private var attempted = 0
    @State private var started = Date()
    @FocusState private var focused: Bool

    var body: some View {
        let body = model.catalog.caseBodies[meta.id]
        let stages = body?.stages ?? []
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if stage < stages.count {
                        let s = stages[stage]
                        Text("Stage \(stage + 1) of \(stages.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase).id("top")
                        Text(s.title).font(.title2.weight(.bold))
                        Card {
                            Label("Your turn", systemImage: "pencil").font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                            MarkdownText(s.prompt).font(.callout).fixedSize(horizontal: false, vertical: true)
                            if !revealed {
                                TextEditor(text: $notes)
                                    .frame(minHeight: 100).padding(6).scrollContentBackground(.hidden)
                                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                                    .focused($focused)
                                    .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
                            } else if !notes.isEmpty {
                                Text(notes).font(.footnote).foregroundStyle(.secondary).padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        if !revealed {
                            Button("Show reference discussion") {
                                if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { attempted += 1 }
                                focused = false
                                withAnimation { revealed = true }
                            }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("case-reveal")
                        } else {
                            Card { BlocksView(blocks: s.blocks) }
                            Button(stage + 1 < stages.count ? "Next stage" : "Finish") {
                                revealed = false; notes = ""; stage += 1
                                proxy.scrollTo("top", anchor: .top)
                                if stage == stages.count {
                                    model.addCaseResult(CaseResult(caseId: meta.id, date: model.clock.now(), mode: .guided, rubricMet: attempted,
                                                                   rubricTotal: stages.count, durationSec: Int(Date().timeIntervalSince(started))))
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("case-next")
                        }
                    } else {
                        Card {
                            Text("Walkthrough complete").font(.title3.weight(.semibold))
                            Text("You wrote an attempt for \(attempted) of \(stages.count) stages before looking. Come back in a week or two for the unguided exercise: same kind of problem, different constraints, no prompts.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let b = body { Card { SourcesView(sources: b.sources) } }
                        Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(16)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.pageBackground)
        .navigationTitle(meta.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Unguided or timed design exercise, self-assessed against the case's rubric.
struct UnguidedCaseView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let meta: CaseMeta
    let mode: CaseMode
    @State private var notes = ""
    @State private var started = Date()
    @State private var finishedAt: Date?
    @State private var met: Set<Int> = []
    @FocusState private var focused: Bool

    var body: some View {
        let ex = model.catalog.caseBodies[meta.id]?.unguided
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let ex {
                        if finishedAt == nil {
                            TimelineView(.periodic(from: started, by: 1)) { ctx in
                                let elapsed = Int(ctx.date.timeIntervalSince(started))
                                let limit = ex.minutes * 60
                                HStack {
                                    Image(systemName: "timer")
                                    Text(mode == .timed ? timeString(max(0, limit - elapsed)) + " left" : timeString(elapsed))
                                        .font(.headline.monospacedDigit())
                                    Spacer()
                                    if mode == .timed && elapsed >= limit { Text("Time is up — wrap up").font(.footnote).foregroundStyle(Theme.bad) }
                                }
                                .foregroundStyle(mode == .timed && elapsed >= limit ? Theme.bad : .primary)
                            }
                        }
                        Card { BlocksView(blocks: ex.prompt) }
                        if finishedAt == nil {
                            Text("Work as you would at a whiteboard: requirements, estimates, API and data model, architecture, bottlenecks, failures. Notes here are for you and are not saved.")
                                .font(.footnote).foregroundStyle(.secondary)
                            TextEditor(text: $notes)
                                .frame(minHeight: 220).padding(6).scrollContentBackground(.hidden)
                                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                                .focused($focused)
                                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
                            Button("I'm done — grade against the rubric") { focused = false; withAnimation { finishedAt = Date() } }
                                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("unguided-finish")
                        } else {
                            if !notes.isEmpty { Card { Text("Your notes").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(notes).font(.footnote) } }
                            Card { RubricChecklist(rubric: ex.rubric, met: $met) }
                            Text("The guided walkthrough of this case discusses one reference design; yours can differ and still meet the rubric.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Save result") {
                                model.addCaseResult(CaseResult(caseId: meta.id, date: model.clock.now(), mode: mode, rubricMet: met.count, rubricTotal: ex.rubric.count,
                                                               durationSec: Int((finishedAt ?? Date()).timeIntervalSince(started))))
                                dismiss()
                            }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("unguided-save")
                        }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.pageBackground)
            .navigationTitle(mode == .timed ? "Timed interview" : "Unguided exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}

// MARK: - Labs

struct LabView: View {
    @Environment(AppModel.self) private var model
    let meta: LabMeta
    @State private var practice: EntryList?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(meta.title).font(.title.weight(.bold))
                Card {
                    Label("Needs a development environment", systemImage: "laptopcomputer").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.warn)
                    Text(meta.summary).font(.subheadline)
                    if let h = meta.hours { Text("Roughly \(h.formatted()) hours").font(.caption).foregroundStyle(.secondary) }
                }
                if !meta.lessons.isEmpty {
                    Card {
                        Text("Reinforces").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        ForEach(meta.lessons, id: \.self) { id in
                            if let l = model.catalog.lessonById[id] {
                                NavigationLink(value: l) { Text(l.title).font(.subheadline).frame(maxWidth: .infinity, minHeight: 32, alignment: .leading) }
                            }
                        }
                    }
                }
                if let body = model.catalog.labBodies[meta.id] {
                    ForEach(Array(body.sections.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(s.title).font(.title2.weight(.semibold))
                            BlocksView(blocks: s.blocks)
                        }
                    }
                    Card { SourcesView(sources: body.sources) }
                }
                let questions = labQuestions
                if !questions.isEmpty {
                    Button("Phone-only questions (\(questions.count))") {
                        practice = EntryList(entries: questions.map { .init(itemId: $0, context: .practice) })
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Toggle("I built this", isOn: Binding(get: { model.state.labsDone[meta.id] != nil }, set: { model.setLabDone(meta.id, done: $0) }))
                    .padding(14).background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
            .padding(16)
        }
        .background(Theme.pageBackground)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $practice) { PracticeSequenceView(title: "Lab questions", entries: $0.entries) }
    }

    /// Lab items are identified by the lab id prefix in their own id.
    private var labQuestions: [String] {
        model.catalog.itemMetas.filter { $0.id.hasPrefix(meta.id + "-") && $0.pool == .practice }.map(\.id)
    }
}
