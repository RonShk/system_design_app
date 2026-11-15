import SwiftUI
import TrainerCore

// MARK: - Practice tab

struct PracticeView: View {
    @Environment(AppModel.self) private var model
    @State private var run: EntryList?
    @State private var runTitle = "Practice"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let due = model.dueConcepts
                    Button { start("Due reviews", reviewEntries(due.prefix(12))) } label: {
                        row("Due reviews", "\(due.count) concept\(due.count == 1 ? "" : "s") due", "calendar.badge.clock", count: due.count)
                    }
                    .disabled(due.isEmpty).accessibilityIdentifier("practice-due")
                    let weak = Mastery.weakConcepts(statuses: model.statuses, state: model.state, catalog: model.catalog, limit: 8)
                    Button { start("Weak topics", practiceEntries(weak)) } label: {
                        row("Weak topics", "Concepts you missed or answered with confidence but wrongly", "exclamationmark.triangle", count: weak.count)
                    }
                    .disabled(weak.isEmpty)
                    let studied = model.catalog.orderedConcepts.filter { model.state.concepts[$0.id]?.introducedAt != nil }.map(\.id)
                    Button { start("Mixed practice", practiceEntries(Array(studied.shuffled().prefix(8)))) } label: {
                        row("Mixed practice", "8 questions across everything you have studied", "shuffle", count: min(8, studied.count))
                    }
                    .disabled(studied.isEmpty)
                } header: { Text("Review") } footer: {
                    Text("Practice is low-stakes: hints are available and nothing is graded. Reviewing a concept before it is due is fine but doesn't move its schedule forward.")
                }
                ForEach(model.catalog.modules) { m in
                    let lessons = model.catalog.lessons(in: m.id).filter(model.isCompleted)
                    if !lessons.isEmpty {
                        Section(m.title) {
                            ForEach(lessons) { l in
                                Button {
                                    let ids = SessionComposer.practiceItems(for: l, catalog: model.catalog, history: History(state: model.state), count: 5)
                                    start(l.title, ids.map { .init(itemId: $0, context: .practice) })
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(l.title).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                            HStack(spacing: 10) { ForEach(l.concepts, id: \.self) { StateBadge(status: model.status($0)) } }
                                        }
                                        Spacer()
                                        Image(systemName: "play.circle").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
                if model.state.lessonsCompleted.isEmpty {
                    Section { Text("Read your first lesson in Today or Learn, then come back here to practise it.").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Practice")
            .sheet(item: $run) { PracticeSequenceView(title: runTitle, entries: $0.entries) }
        }
    }

    private func start(_ title: String, _ entries: [PracticeSequenceView.Entry]) {
        runTitle = title
        run = EntryList(entries: entries)
    }

    private func reviewEntries<S: Sequence>(_ concepts: S) -> [PracticeSequenceView.Entry] where S.Element == String {
        let history = History(state: model.state)
        var used = Set<String>()
        return concepts.compactMap { c in
            guard let pick = ItemSelector.reviewItem(concept: c, state: model.state, catalog: model.catalog, history: history, clock: model.clock, exclude: used) else { return nil }
            used.insert(pick.item.id)
            return .init(itemId: pick.item.id, context: pick.context)
        }
    }

    private func practiceEntries(_ concepts: [String]) -> [PracticeSequenceView.Entry] {
        let history = History(state: model.state)
        var used = Set<String>()
        return concepts.compactMap { c in
            guard let it = ItemSelector.pick(concept: c, pools: [.practice], catalog: model.catalog, history: history, exclude: used) else { return nil }
            used.insert(it.id)
            return .init(itemId: it.id, context: .practice)
        }
    }

    private func row(_ title: String, _ subtitle: String, _ icon: String, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Spacer()
            if count > 0 { Text("\(count)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary) }
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Assess tab

struct PlanBox: Identifiable {
    let plan: AssessmentComposer.Plan
    let title: String
    var id: String { title + plan.itemIds.joined() }
}

struct AssessView: View {
    @Environment(AppModel.self) private var model
    @State private var run: PlanBox?
    @State private var interview: CaseMeta?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.catalog.modules) { m in
                        let plan = AssessmentComposer.quiz(module: m.id, state: model.state, catalog: model.catalog, seed: seed)
                        let read = model.catalog.lessons(in: m.id).filter(model.isCompleted).count
                        Button { run = PlanBox(plan: plan, title: "\(m.title) quiz") } label: {
                            row(m.title, read == 0 ? "No lessons read yet" : "\(plan.itemIds.count) questions from \(read) lesson\(read == 1 ? "" : "s") read", "list.bullet.clipboard")
                        }
                        .disabled(plan.itemIds.isEmpty)
                        .accessibilityIdentifier("quiz-\(m.id)")
                    }
                } header: { Text("Topic quizzes") } footer: {
                    Text("Questions come from a pool that practice never shows. A quiz taken the day you read a lesson shows what you understood, not what you retained.")
                }
                Section {
                    let delayed = AssessmentComposer.delayedCheck(state: model.state, catalog: model.catalog, clock: model.clock, seed: seed)
                    Button { run = PlanBox(plan: delayed, title: "Retention check") } label: {
                        row("Retention check", delayed.itemIds.isEmpty ? "Nothing has been left alone for a week yet" : "\(delayed.itemIds.count) concepts not touched for 7+ days", "clock.arrow.circlepath")
                    }
                    .disabled(delayed.itemIds.isEmpty)
                    let cum = AssessmentComposer.cumulative(state: model.state, catalog: model.catalog, seed: seed)
                    let span = AssessmentComposer.modulesSpanned(by: cum, catalog: model.catalog).count
                    Button { run = PlanBox(plan: cum, title: "Cumulative quiz") } label: {
                        row("Cumulative quiz", cum.itemIds.isEmpty ? "Read some lessons first" : "\(cum.itemIds.count) mixed questions across \(span) module\(span == 1 ? "" : "s")", "square.stack.3d.up")
                    }
                    .disabled(cum.itemIds.isEmpty)
                    .accessibilityIdentifier("quiz-cumulative")
                    let fin = AssessmentComposer.final(catalog: model.catalog)
                    Button { run = PlanBox(plan: fin, title: "Final assessment") } label: {
                        row("Final assessment", "\(fin.itemIds.count) unfamiliar scenarios with rubrics. Best taken after finishing the course.", "flag.checkered")
                    }
                    .disabled(fin.itemIds.isEmpty)
                } header: { Text("Retention and synthesis") }
                Section {
                    ForEach(model.catalog.cases) { c in
                        Button { interview = c } label: { row(c.title, "Timed design exercise, self-graded against a rubric", "timer") }
                    }
                } header: { Text("Timed interview practice") } footer: {
                    Text("Optional. The clock is only there to practise pacing.")
                }
                if !model.state.assessments.isEmpty {
                    Section("History") {
                        ForEach(model.state.assessments.sorted { $0.date > $1.date }.prefix(20)) { r in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(title(for: r)).font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text(r.date, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                                ScoreLine(result: r)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Assess")
            .fullScreenCover(item: $run) { AssessmentRunView(box: $0) }
            .fullScreenCover(item: $interview) { UnguidedCaseView(meta: $0, mode: .timed) }
        }
    }

    /// Changes once per day so a quiz's question order is stable while you look at the list.
    private var seed: UInt64 { UInt64(model.clock.today.days(since: LocalDay(year: 2020, month: 1, day: 1))) }

    private func title(for r: AssessmentResult) -> String {
        switch r.kind {
        case .quiz: (model.catalog.modules.first { $0.id == r.moduleId }?.title ?? "Topic") + " quiz"
        case .delayedCheck: "Retention check"
        case .cumulative: "Cumulative quiz"
        case .final: "Final assessment"
        }
    }

    private func row(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
        }
        .frame(minHeight: 44)
    }
}

/// Automatic and self-assessed scores, always shown as two separate numbers.
struct ScoreLine: View {
    let result: AssessmentResult
    var body: some View {
        HStack(spacing: 14) {
            if result.autoTotal > 0 {
                Label("\(result.autoCorrect)/\(result.autoTotal) auto-checked", systemImage: "checkmark.circle").foregroundStyle(.primary)
            }
            if result.selfTotal > 0 {
                Label("\(result.selfPoints.formatted(.number.precision(.fractionLength(0...1))))/\(result.selfTotal) rubric points (self-assessed)", systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

/// Runs an assessment: answer everything with no feedback, then self-grade written answers, then see results.
struct AssessmentRunView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let box: PlanBox

    enum Phase { case answering, grading, results }
    @State private var phase: Phase = .answering
    @State private var index = 0
    @State private var drafts: [String: AnswerDraft] = [:]
    @State private var confidence: [String: Confidence] = [:]
    @State private var gradeIndex = 0
    @State private var attempts: [Attempt] = []
    @State private var result: AssessmentResult?
    @State private var confirmQuit = false

    private var items: [Item] { box.plan.itemIds.compactMap { model.catalog.items[$0] } }
    private var freeItems: [Item] { items.filter { $0.format == .free } }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .answering: answering
                case .grading: grading
                case .results: results
                }
            }
            .background(Theme.pageBackground)
            .navigationTitle(box.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .results ? "Done" : "Quit") { if phase == .results { dismiss() } else { confirmQuit = true } }
                }
            }
            .confirmationDialog("Quit without recording this assessment?", isPresented: $confirmQuit, titleVisibility: .visible) {
                Button("Quit", role: .destructive) { dismiss() }
            }
        }
    }

    private func draft(for item: Item) -> Binding<AnswerDraft> {
        Binding(get: { drafts[item.id] ?? AnswerDraft(item: item, seed: Int(box.plan.itemIds.count)) }, set: { drafts[item.id] = $0 })
    }

    @ViewBuilder private var answering: some View {
        let list = items
        if index < list.count {
            let item = list[index]
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Question \(index + 1) of \(list.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("No hints or feedback until the end").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(index), total: Double(list.count))
                    Card { AnswerInput(item: item, draft: draft(for: item)) }
                    if model.state.prefs.askConfidence {
                        ConfidencePicker(value: Binding(get: { confidence[item.id] }, set: { confidence[item.id] = $0 }))
                    }
                    Button(index + 1 < list.count ? "Next question" : "Finish") {
                        if drafts[item.id] == nil { drafts[item.id] = AnswerDraft(item: item, seed: Int(box.plan.itemIds.count)) }
                        if index + 1 < list.count { withAnimation { index += 1 } } else { finishAnswering() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("assess-next")
                    if index > 0 {
                        Button("Previous") { withAnimation { index -= 1 } }.buttonStyle(SecondaryButtonStyle())
                    }
                    Text("Leaving a question blank counts as not known.").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .id(index)
        }
    }

    @ViewBuilder private var grading: some View {
        let free = freeItems
        if gradeIndex < free.count {
            let item = free[gradeIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Grade your written answers · \(gradeIndex + 1) of \(free.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Card {
                        BlocksView(blocks: item.prompt)
                        let mine = drafts[item.id]?.notes ?? ""
                        Text("Your answer").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(mine.isEmpty ? "(left blank)" : mine).font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Card { SolutionView(item: item) }
                    Card {
                        RubricChecklist(rubric: item.rubric ?? [], met: Binding(get: { drafts[item.id]?.rubric ?? [] }, set: { drafts[item.id]?.rubric = $0 }))
                    }
                    Button(gradeIndex + 1 < free.count ? "Next answer" : "See results") {
                        if gradeIndex + 1 < free.count { withAnimation { gradeIndex += 1 } } else { record() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("grade-next")
                }
                .padding(16)
            }
            .id(gradeIndex)
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let result {
                    Card {
                        Text("Results").font(.title2.weight(.bold))
                        ScoreLine(result: result)
                        Text("Automatically checked and self-assessed scores are kept apart because self-grading is only as strict as you are.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("assessment-results")
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let a = attempts.first { $0.itemId == item.id }
                    Card {
                        HStack(alignment: .top) {
                            Image(systemName: a?.outcome == .correct ? "checkmark.circle.fill" : a?.outcome == .partial ? "circle.lefthalf.filled" : "xmark.circle.fill")
                                .foregroundStyle(a?.outcome == .correct ? Theme.good : a?.outcome == .partial ? Theme.warn : Theme.bad)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Question \(i + 1) · \(model.catalog.concepts[item.primaryConcept]?.name ?? "")").font(.subheadline.weight(.semibold))
                                Text(a?.grading == .selfAssessed ? "Self-assessed: \(Int(((a?.score ?? 0) * Double(item.rubric?.count ?? 0)).rounded())) of \(item.rubric?.count ?? 0) rubric points" : "Auto-checked")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        DisclosureGroup("Question and explanation") {
                            VStack(alignment: .leading, spacing: 12) {
                                AnswerInput(item: item, draft: .constant(drafts[item.id] ?? AnswerDraft(item: item, seed: 0)), locked: true, showSolution: item.format != .free)
                                SolutionView(item: item)
                            }
                            .padding(.top, 8)
                        }
                        .font(.subheadline)
                    }
                }
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("assessment-done")
            }
            .padding(16)
        }
    }

    private func finishAnswering() {
        if freeItems.isEmpty { record() } else { withAnimation { phase = .grading } }
    }

    private func record() {
        let context: AttemptContext = switch box.plan.kind {
        case .quiz: .quiz
        case .delayedCheck: .delayedCheck
        case .cumulative: .cumulative
        case .final: .final
        }
        var recorded: [Attempt] = []
        for item in items {
            let d = drafts[item.id] ?? AnswerDraft(item: item, seed: 0)
            // A blank answer is recorded as incorrect, not as a reveal: nothing was shown to the learner first.
            let response = d.response(for: item)
            var check = response.flatMap { Checker.check($0, item: item) }
            if check == nil { check = CheckResult(outcome: .incorrect, score: 0, grading: item.format.isAutoChecked ? .auto : .selfAssessed) }
            recorded.append(model.record(item: item, result: check, hintsUsed: 0, revealed: false, confidence: confidence[item.id], context: context))
        }
        attempts = recorded
        let sizes = Dictionary(uniqueKeysWithValues: items.filter { $0.format == .free }.map { ($0.id, $0.rubric?.count ?? 1) })
        let r = AssessmentComposer.summarise(plan: box.plan, attempts: recorded, rubricSizes: sizes, date: model.clock.now())
        model.addAssessment(r)
        result = r
        withAnimation { phase = .results }
    }
}
