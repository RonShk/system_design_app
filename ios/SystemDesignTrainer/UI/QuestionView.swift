import SwiftUI
import TrainerCore

/// What the learner has entered so far for one item.
struct AnswerDraft: Equatable {
    var choice: Int?
    var choices: Set<Int> = []
    var number = ""
    var order: [Int] = []
    var notes = ""
    var rubric: Set<Int> = []

    /// Choice/step display order, shuffled once per presentation so position gives nothing away.
    var shuffle: [Int] = []

    init(item: Item, seed: Int) {
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: item.id.hashValue &+ seed))
        switch item.format {
        case .mcq, .multi:
            shuffle = Array(0..<(item.choices?.count ?? 0)).shuffled(using: &rng)
        case .order:
            let n = item.steps?.count ?? 0
            var o = Array(0..<n).shuffled(using: &rng)
            if o == Array(0..<n), n > 1 { o.swapAt(0, n - 1) }   // never start already solved
            order = o
        default: break
        }
    }

    func response(for item: Item) -> Response? {
        switch item.format {
        case .mcq: choice.map { .choice($0) }
        case .multi: choices.isEmpty ? nil : .choices(choices)
        case .numeric: Checker.parseNumber(number) == nil ? nil : .number(number)
        case .order: .ordering(order)
        case .free: .rubric(rubric)
        }
    }

    /// True when there is enough input to submit (free answers can always be submitted).
    func isReady(for item: Item) -> Bool { item.format == .free || response(for: item) != nil }
}

/// Prompt plus the input control for an item. Read-only once `locked`.
struct AnswerInput: View {
    let item: Item
    @Binding var draft: AnswerDraft
    var locked = false
    /// When set, correct and incorrect choices are marked (used after checking).
    var showSolution = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Tag(text: item.skill.label, color: .accentColor)
                Tag(text: item.format.label)
                Spacer()
            }
            BlocksView(blocks: item.prompt)
            if let a = item.assumptions {
                Label { MarkdownText(a).font(.footnote) } icon: { Image(systemName: "info.circle") }
                    .foregroundStyle(.secondary)
            }
            input
        }
    }

    @ViewBuilder private var input: some View {
        switch item.format {
        case .mcq, .multi:
            VStack(spacing: 9) {
                ForEach(draft.shuffle, id: \.self) { i in choiceRow(i) }
            }
        case .numeric:
            HStack(spacing: 10) {
                TextField("Your answer", text: $draft.number)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .font(.title3.monospacedDigit())
                    .padding(12)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    .focused($focused)
                    .disabled(locked)
                    .accessibilityIdentifier("numeric-input")
                Text(item.unit ?? "").font(.headline).foregroundStyle(.secondary)
            }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
        case .order:
            VStack(spacing: 8) {
                ForEach(Array(draft.order.enumerated()), id: \.element) { pos, step in orderRow(pos: pos, step: step) }
            }
        case .free:
            VStack(alignment: .leading, spacing: 6) {
                Text("Write your answer (or say it out loud) before comparing.").font(.footnote).foregroundStyle(.secondary)
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 110)
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    .focused($focused)
                    .disabled(locked)
                    .accessibilityIdentifier("free-input")
                    .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
            }
        }
    }

    private func choiceRow(_ i: Int) -> some View {
        let multi = item.format == .multi
        let selected = multi ? draft.choices.contains(i) : draft.choice == i
        let isAnswer = multi ? (item.answers ?? []).contains(i) : Int(item.answer ?? -1) == i
        let border: Color = showSolution ? (isAnswer ? Theme.good : (selected ? Theme.bad : Color(.separator))) : (selected ? .accentColor : Color(.separator))
        return Button {
            if multi { if selected { draft.choices.remove(i) } else { draft.choices.insert(i) } }
            else { draft.choice = i }
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: icon(selected: selected, multi: multi, isAnswer: isAnswer))
                    .font(.title3)
                    .foregroundStyle(showSolution ? (isAnswer ? Theme.good : (selected ? Theme.bad : .secondary)) : (selected ? Color.accentColor : .secondary))
                MarkdownText(item.choices?[i] ?? "").font(.body).multilineTextAlignment(.leading)
                    .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(selected && !showSolution ? Color.accentColor.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(border, lineWidth: selected || (showSolution && isAnswer) ? 1.8 : 1))
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(isAnswer ? "choice-correct" : "choice-wrong")
    }

    private func icon(selected: Bool, multi: Bool, isAnswer: Bool) -> String {
        if showSolution { return isAnswer ? "checkmark.circle.fill" : (selected ? "xmark.circle.fill" : (multi ? "square" : "circle")) }
        return multi ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle")
    }

    private func orderRow(pos: Int, step: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(pos + 1)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.secondary).frame(width: 20)
            MarkdownText(item.steps?[step] ?? "").font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if showSolution {
                Image(systemName: step == pos ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(step == pos ? Theme.good : Theme.bad)
            } else if !locked {
                VStack(spacing: 2) {
                    Button { withAnimation(.snappy) { draft.order.swapAt(pos, pos - 1) } } label: { Image(systemName: "chevron.up").frame(width: 40, height: 26) }
                        .disabled(pos == 0).accessibilityLabel("Move up")
                    Button { withAnimation(.snappy) { draft.order.swapAt(pos, pos + 1) } } label: { Image(systemName: "chevron.down").frame(width: 40, height: 26) }
                        .disabled(pos == draft.order.count - 1).accessibilityLabel("Move down")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(11)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ConfidencePicker: View {
    @Binding var value: Confidence?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How sure are you?").font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Confidence.allCases, id: \.self) { c in
                    Button { value = value == c ? nil : c } label: {
                        Text(c == .low ? "Guessing" : c == .medium ? "Fairly sure" : "Certain")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(value == c ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(value == c ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SourcesView: View {
    let sources: [SourceRef]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(sources.enumerated()), id: \.offset) { _, s in
                let text = "\(s.title ?? s.ref) — \(s.section)"
                if let u = s.url, let url = URL(string: u) {
                    Link(destination: url) {
                        Label(text, systemImage: "arrow.up.right.square").font(.footnote).multilineTextAlignment(.leading)
                    }
                } else {
                    Text(text).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The solution to an item: correct answer, model answer, explanation, sources.
struct SolutionView: View {
    let item: Item
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.format == .numeric, let a = item.answer {
                Text("Answer: \(a.formatted(.number.precision(.significantDigits(1...6)))) \(item.unit ?? "")").font(.headline)
            }
            if item.format == .order, let steps = item.steps {
                Text("Correct order").font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .firstTextBaseline) { Text("\(i + 1).").foregroundStyle(.secondary); MarkdownText(s) }.font(.callout)
                    }
                }
            }
            if let model = item.model {
                Text("Model answer").font(.subheadline.weight(.semibold))
                BlocksView(blocks: model)
            }
            Text("Why").font(.subheadline.weight(.semibold))
            BlocksView(blocks: item.explanation)
            Divider()
            SourcesView(sources: item.sources)
        }
    }
}

/// Rubric checklist for self-assessing a written answer.
struct RubricChecklist: View {
    let rubric: [String]
    @Binding var met: Set<Int>
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Check each point your answer actually made").font(.subheadline.weight(.semibold))
            Text("Self-assessed: be strict. This is recorded separately from automatically checked answers.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(rubric.enumerated()), id: \.offset) { i, point in
                Button {
                    if met.contains(i) { met.remove(i) } else { met.insert(i) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: met.contains(i) ? "checkmark.square.fill" : "square")
                            .font(.title3).foregroundStyle(met.contains(i) ? Theme.good : .secondary)
                        MarkdownText(point).font(.callout).multilineTextAlignment(.leading).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rubric-\(i)")
            }
        }
    }
}

/// One item in practice mode: attempt → (hints) → check or reveal → feedback.
struct PracticeItemView: View {
    @Environment(AppModel.self) private var model
    let item: Item
    let context: AttemptContext
    /// Assessment-pool items used as delayed checks give no hints.
    var allowHints = true
    let onDone: (Attempt) -> Void

    @State private var draft: AnswerDraft
    @State private var hintsShown = 0
    @State private var confidence: Confidence?
    @State private var phase: Phase = .answering
    @State private var attempt: Attempt?

    enum Phase { case answering, selfAssess, feedback }

    init(item: Item, context: AttemptContext, allowHints: Bool = true, onDone: @escaping (Attempt) -> Void) {
        self.item = item; self.context = context; self.allowHints = allowHints; self.onDone = onDone
        _draft = State(initialValue: AnswerDraft(item: item, seed: Int(Date().timeIntervalSince1970)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    AnswerInput(item: item, draft: $draft, locked: phase != .answering, showSolution: phase == .feedback && item.format != .free)
                }
                if phase == .answering { answering }
                if phase == .selfAssess { selfAssess }
                if phase == .feedback, let attempt { feedback(attempt) }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.pageBackground)
    }

    @ViewBuilder private var answering: some View {
        if hintsShown > 0 {
            Card {
                ForEach(0..<hintsShown, id: \.self) { i in
                    Label { MarkdownText(item.hints[i]).font(.callout) } icon: { Image(systemName: "lightbulb").foregroundStyle(Theme.warn) }
                }
            }
        }
        if model.state.prefs.askConfidence { ConfidencePicker(value: $confidence) }
        Button(item.format == .free ? "Compare with model answer" : "Check answer") { submit() }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!draft.isReady(for: item))
            .accessibilityIdentifier("submit-answer")
        HStack(spacing: 10) {
            if allowHints, hintsShown < item.hints.count {
                Button("Hint (\(hintsShown + 1) of \(item.hints.count))") { withAnimation { hintsShown += 1 } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button("I don't know — show answer") { reveal() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("reveal-answer")
        }
    }

    private var selfAssess: some View {
        Group {
            Card { SolutionView(item: item) }
            Card { RubricChecklist(rubric: item.rubric ?? [], met: $draft.rubric) }
            Button("Record my assessment") { finish(result: Checker.check(.rubric(draft.rubric), item: item), revealed: false) }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("record-assessment")
        }
    }

    private func feedback(_ a: Attempt) -> some View {
        Group {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: a.assistance == .revealed ? "eye" : a.outcome == .correct ? "checkmark.circle.fill" : a.outcome == .partial ? "circle.lefthalf.filled" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(a.assistance == .revealed ? Theme.warn : a.outcome == .correct ? Theme.good : a.outcome == .partial ? Theme.warn : Theme.bad)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline(a)).font(.headline)
                        Text(detail(a)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("feedback-banner")
            }
            Card { SolutionView(item: item) }
            Button("Continue") { onDone(a) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("continue")
        }
    }

    private func headline(_ a: Attempt) -> String {
        if a.assistance == .revealed { return "Answer shown" }
        switch a.outcome {
        case .correct: return a.assistance == .hinted ? "Correct, with a hint" : "Correct"
        case .partial: return "Partly there"
        case .incorrect: return "Not yet"
        }
    }

    private func detail(_ a: Attempt) -> String {
        if a.assistance == .revealed { return "Counted as not known. It will come back tomorrow with a different question." }
        if a.isIndependentSuccess {
            return a.grading == .selfAssessed ? "Self-assessed against the rubric." : "Checked automatically."
        }
        if a.outcome == .correct { return "Hinted answers don't count as independent evidence." }
        if a.confidence == .high { return "You were certain — flagged as a misconception to revisit soon." }
        return "This concept is scheduled again for tomorrow."
    }

    private func submit() {
        if item.format == .free { withAnimation { phase = .selfAssess }; return }
        guard let r = draft.response(for: item) else { return }
        finish(result: Checker.check(r, item: item), revealed: false)
    }

    private func reveal() { finish(result: nil, revealed: true) }

    private func finish(result: CheckResult?, revealed: Bool) {
        let a = model.record(item: item, result: result, hintsUsed: hintsShown, revealed: revealed, confidence: confidence, context: context)
        attempt = a
        withAnimation { phase = .feedback }
    }
}

/// Runs a list of items one after another in practice mode, then shows a short summary.
struct PracticeSequenceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    struct Entry: Hashable { let itemId: String; let context: AttemptContext }
    let title: String
    let entries: [Entry]

    @State private var index = 0
    @State private var attempts: [Attempt] = []

    var body: some View {
        NavigationStack {
            Group {
                if index < entries.count, let item = model.catalog.items[entries[index].itemId] {
                    PracticeItemView(item: item, context: entries[index].context, allowHints: item.pool == .practice) { a in
                        attempts.append(a)
                        withAnimation { index += 1 }
                    }
                    .id(index)
                } else {
                    summary
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    if index < entries.count {
                        ProgressView(value: Double(index), total: Double(entries.count)).frame(width: 140)
                    }
                }
            }
        }
    }

    private var summary: some View {
        ScrollView {
            VStack(spacing: 16) {
                AttemptSummaryCard(attempts: attempts)
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("sequence-done")
            }
            .padding(16)
        }
        .background(Theme.pageBackground)
    }
}

struct AttemptSummaryCard: View {
    @Environment(AppModel.self) private var model
    let attempts: [Attempt]
    var body: some View {
        let solo = attempts.filter(\.isIndependentSuccess).count
        let missed = attempts.filter(\.isFailure).count
        Card {
            Text(attempts.isEmpty ? "Nothing to practise right now" : "Practice complete").font(.title3.weight(.semibold))
            if !attempts.isEmpty {
                HStack(spacing: 18) {
                    stat("\(solo)", "on your own", Theme.good)
                    stat("\(attempts.count - solo - missed)", "hinted / partial", Theme.warn)
                    stat("\(missed)", "missed", Theme.bad)
                }
                let revisit = Array(Set(attempts.filter(\.isFailure).map(\.primaryConcept))).compactMap { model.catalog.concepts[$0]?.name }.sorted()
                if !revisit.isEmpty {
                    Text("Coming back tomorrow: " + revisit.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func stat(_ n: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
