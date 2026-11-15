import SwiftUI
import TrainerCore

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showSession = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var weakPractice: [PracticeSequenceView.Entry]?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.loadOrigin == .backup || model.loadOrigin == .corruptSetAside { recoveryNotice }
                    sessionCard
                    statusRow
                    if let lesson = model.nextLesson { nextLessonCard(lesson) }
                    weakTopics
                    backupNudge
                }
                .padding(16)
            }
            .background(Theme.pageBackground)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search and glossary")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings").accessibilityIdentifier("open-settings")
                }
            }
            .fullScreenCover(isPresented: $showSession) { SessionView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showSearch) { SearchView() }
            .sheet(item: Binding(get: { weakPractice.map(EntryList.init) }, set: { weakPractice = $0?.entries })) { list in
                PracticeSequenceView(title: "Weak topics", entries: list.entries)
            }
            .navigationDestination(for: LessonMeta.self) { LessonView(lesson: $0) }
        }
    }

    private var sessionCard: some View {
        let resumable = model.resumableSession
        let due = model.dueConcepts.count
        return Card {
            Text(resumable != nil ? "Session in progress" : model.studiedToday ? "Done for today — or keep going" : "Today's session")
                .font(.title2.weight(.bold))
            Text(sessionDescription(due: due, resumable: resumable)).font(.subheadline).foregroundStyle(.secondary)
            Button(resumable != nil ? "Resume session" : "Start \(model.state.prefs.sessionMinutes)-minute session") {
                if resumable == nil { model.startSession() }
                showSession = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("start-session")
            if resumable == nil {
                HStack(spacing: 8) {
                    ForEach([10, 15, 30], id: \.self) { m in
                        Button("\(m) min") { model.updatePrefs { $0.sessionMinutes = m } }
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(model.state.prefs.sessionMinutes == m ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sessionDescription(due: Int, resumable: SessionProgress?) -> String {
        if let r = resumable { return "Step \(r.index + 1) of \(r.steps.count). Your progress is saved." }
        var parts: [String] = []
        if due > 0 { parts.append("\(due) review\(due == 1 ? "" : "s") due") }
        if let l = model.nextLesson { parts.append("new lesson: \(l.title)") }
        if parts.isEmpty { return "Everything is reviewed and every lesson is complete. Try a cumulative quiz in Assess." }
        return parts.joined(separator: " · ").prefix(1).uppercased() + parts.joined(separator: " · ").dropFirst()
    }

    private var statusRow: some View {
        let all = Mastery.summary(of: model.catalog.orderedConcepts, statuses: model.statuses)
        return HStack(spacing: 12) {
            metric("\(model.dueConcepts.count)", "due now")
            metric("\(all.covered)/\(all.total)", "concepts started")
            metric("\(all.retained)", "retained")
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func nextLessonCard(_ lesson: LessonMeta) -> some View {
        NavigationLink(value: lesson) {
            Card {
                Text("Continue learning").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Text(lesson.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Text(lesson.objective).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading).lineLimit(3)
                Label("\(lesson.minutes) min read", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var weakTopics: some View {
        let weak = Mastery.weakConcepts(statuses: model.statuses, state: model.state, catalog: model.catalog, limit: 5)
        if !weak.isEmpty {
            Card {
                Text("Weak topics").font(.headline)
                ForEach(weak, id: \.self) { id in
                    if let c = model.catalog.concepts[id] {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.subheadline)
                                Text(model.status(id)?.reviewReason?.rawValue ?? "Low recent success rate").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StateBadge(status: model.status(id))
                        }
                    }
                }
                Button("Practise these") {
                    let history = History(state: model.state)
                    weakPractice = weak.compactMap { id in
                        ItemSelector.pick(concept: id, pools: [.practice], catalog: model.catalog, history: history).map { .init(itemId: $0.id, context: .practice) }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder private var backupNudge: some View {
        let last = model.state.lastExportAt
        let stale = last.map { model.clock.now().timeIntervalSince($0) > 30 * 86_400 } ?? (model.state.attempts.count > 50)
        if stale {
            Card {
                Label("Back up your progress", systemImage: "externaldrive").font(.headline)
                Text("Progress lives only on this phone. Export a copy from Settings every so often.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var recoveryNotice: some View {
        Card {
            Label(model.loadOrigin == .backup ? "Restored from the previous save" : "Saved progress could not be read",
                  systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(Theme.warn)
            Text(model.loadOrigin == .backup
                 ? "The latest save file was damaged, so the copy before it was used. At most your last action is missing."
                 : "The unreadable files were kept on the device and a fresh start was made. If you have an export, import it in Settings.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct EntryList: Identifiable {
    let entries: [PracticeSequenceView.Entry]
    var id: String { entries.map(\.itemId).joined(separator: ",") }
}

// MARK: - Daily session

struct SessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let s = model.state.session, !s.isFinished {
                    step(s.steps[s.index], session: s).id(s.index)
                } else if let s = model.state.session {
                    RecapView(session: s) { dismiss() }
                } else {
                    ContentUnavailableView("No session", systemImage: "sun.max")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("close-session")
                }
                ToolbarItem(placement: .principal) {
                    if let s = model.state.session, !s.isFinished {
                        VStack(spacing: 3) {
                            Text(label(for: s.steps[s.index])).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ProgressView(value: Double(s.index), total: Double(s.steps.count)).frame(width: 150)
                        }
                    }
                }
            }
        }
    }

    private func label(for step: SessionStep) -> String {
        switch step {
        case .review(_, _, let ctx): ctx == .delayedCheck ? "RETENTION CHECK" : "REVIEW"
        case .lesson: "NEW LESSON"
        case .practice: "RETRIEVAL PRACTICE"
        case .application: "APPLICATION PROBLEM"
        }
    }

    @ViewBuilder private func step(_ step: SessionStep, session: SessionProgress) -> some View {
        switch step {
        case .lesson(let id):
            if let lesson = model.catalog.lessonById[id] {
                LessonContent(lesson: lesson, footer: AnyView(
                    Button("I've read it — practise now") {
                        model.completeLesson(id)
                        model.advanceSession()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("finish-lesson")
                ))
            }
        case .review(_, let item, let ctx):
            question(item, context: ctx)
        case .practice(let item):
            question(item, context: .practice)
        case .application(let item):
            question(item, context: .application)
        }
    }

    @ViewBuilder private func question(_ id: String, context: AttemptContext) -> some View {
        if let item = model.catalog.items[id] {
            PracticeItemView(item: item, context: context, allowHints: item.pool == .practice) { _ in
                withAnimation { model.advanceSession() }
            }
        } else {
            // Content changed since the session was planned; skip the missing item.
            Color.clear.onAppear { model.advanceSession() }
        }
    }
}

struct RecapView: View {
    @Environment(AppModel.self) private var model
    let session: SessionProgress
    let onDone: () -> Void

    var body: some View {
        let r = SessionComposer.recap(session: session, state: model.state, catalog: model.catalog, clock: model.clock)
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    Text("Session complete").font(.title2.weight(.bold))
                    if r.answered > 0 {
                        HStack(spacing: 18) {
                            stat("\(r.independentCorrect)", "on your own", Theme.good)
                            stat("\(r.hintedOrPartial)", "hinted / partial", Theme.warn)
                            stat("\(r.missed)", "missed", Theme.bad)
                        }
                    }
                }
                .accessibilityIdentifier("session-recap")
                if let id = r.lessonId, let l = model.catalog.lessonById[id] {
                    Card {
                        Text("Learned today").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        Text(l.title).font(.headline)
                        ForEach(l.concepts, id: \.self) { c in
                            if let concept = model.catalog.concepts[c] {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(concept.name).font(.subheadline.weight(.semibold))
                                    MarkdownText(concept.def).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !r.conceptsToRevisit.isEmpty {
                    Card {
                        Text("To revisit").font(.headline)
                        ForEach(r.conceptsToRevisit, id: \.self) { c in
                            Label(model.catalog.concepts[c]?.name ?? c, systemImage: "arrow.uturn.backward").font(.subheadline)
                        }
                        Text("These return tomorrow with different questions.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Card {
                    Text("Next").font(.headline)
                    Label("\(r.dueTomorrow) concept\(r.dueTomorrow == 1 ? "" : "s") due by tomorrow", systemImage: "calendar").font(.subheadline)
                    if let id = r.nextLessonId, let l = model.catalog.lessonById[id] {
                        Label("Next lesson: \(l.title)", systemImage: "book").font(.subheadline)
                    }
                    Text("Today's practice was easy to recall because you just read it. What counts is whether you can recall it tomorrow.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Done") { onDone() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("recap-done")
            }
            .padding(16)
        }
        .background(Theme.pageBackground)
    }

    private func stat(_ n: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
