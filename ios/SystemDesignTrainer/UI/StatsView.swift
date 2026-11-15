import SwiftUI
import TrainerCore

/// Progress: coverage (what has been started) and retention (what has held up over time) shown separately.
struct StatsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overall
                    legend
                    ForEach(model.catalog.modules) { m in moduleCard(m) }
                    forecast
                    calibration
                    evidence
                }
                .padding(16)
            }
            .background(Theme.pageBackground)
            .navigationTitle("Progress")
            .navigationDestination(for: Module.self) { ModuleConceptsView(module: $0) }
        }
    }

    private var overall: some View {
        let s = Mastery.summary(of: model.catalog.orderedConcepts, statuses: model.statuses)
        return Card {
            Text("\(s.total) concepts").font(.title2.weight(.bold))
            HStack(spacing: 12) {
                big("\(pct(s.covered, s.total))", "Coverage", "Concepts at least introduced")
                big("\(pct(s.demonstrated, s.total))", "Demonstrated", "Answered on your own, varied questions")
                big("\(pct(s.retained, s.total))", "Retained", "Still known after a week or more")
            }
            StateBar(summary: s)
            if s.needsReview > 0 {
                Label("\(s.needsReview) need review", systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.needsReview)
            }
        }
    }

    private func big(_ v: String, _ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.title3.weight(.bold).monospacedDigit())
            Text(title).font(.caption.weight(.semibold))
            Text(sub).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pct(_ n: Int, _ total: Int) -> String {
        total == 0 ? "0%" : "\(Int((Double(n) / Double(total) * 100).rounded()))%"
    }

    private var legend: some View {
        Card {
            Text("What the states mean").font(.headline)
            ForEach(ConceptState.allCases, id: \.self) { st in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Theme.color(for: st)).frame(width: 10, height: 10).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(st.label).font(.subheadline.weight(.semibold))
                        Text(explanation(st)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Theme.needsReview).frame(width: 10, height: 10).padding(.top, 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Needs review").font(.subheadline.weight(.semibold))
                    Text("Last answer was wrong or revealed, a confident answer was wrong, or the review is long overdue. Clears after the next success.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func explanation(_ st: ConceptState) -> String {
        switch st {
        case .notStarted: "Not read or practised yet."
        case .introduced: "Lesson read. Reading alone is not evidence of learning."
        case .practiced: "At least one question answered."
        case .demonstrated: "Correct without help on two different questions, at least one not multiple choice."
        case .retained: "Correct without help on a different question at least 7 days after the previous one."
        }
    }

    private func moduleCard(_ m: Module) -> some View {
        let s = Mastery.summary(of: model.catalog.concepts(in: m.id), statuses: model.statuses)
        return NavigationLink(value: m) {
            Card {
                HStack {
                    Text(m.title).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                StateBar(summary: s, height: 8)
                HStack(spacing: 14) {
                    Text("Coverage \(pct(s.covered, s.total))")
                    Text("Retained \(pct(s.retained, s.total))")
                    if s.needsReview > 0 { Text("\(s.needsReview) to review").foregroundStyle(Theme.needsReview) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var forecast: some View {
        let f = Scheduler.forecast(state: model.state, clock: model.clock, days: 14)
        let maxV = max(1, f.max() ?? 1)
        return Card {
            Text("Reviews over the next two weeks").font(.headline)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(f.enumerated()), id: \.offset) { i, n in
                    VStack(spacing: 3) {
                        Text(n > 0 ? "\(n)" : "").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i == 0 ? Color.accentColor : Color.accentColor.opacity(0.45))
                            .frame(height: max(2, 70 * CGFloat(n) / CGFloat(maxV)))
                        Text(i == 0 ? "Now" : i % 7 == 0 ? "+\(i)d" : "").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
            .accessibilityElement()
            .accessibilityLabel("Reviews due: " + f.enumerated().filter { $0.element > 0 }.map { "\($0.element) in \($0.offset) days" }.joined(separator: ", "))
        }
    }

    @ViewBuilder private var calibration: some View {
        let cal = Mastery.calibration(state: model.state)
        if !cal.isEmpty {
            Card {
                Text("Confidence vs. results").font(.headline)
                Text("Confidence is context, not evidence. Well calibrated means \"Certain\" answers are nearly always right.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach([Confidence.high, .medium, .low], id: \.self) { c in
                    if let v = cal[c], let rate = v.rate {
                        HStack {
                            Text(c == .high ? "Certain" : c == .medium ? "Fairly sure" : "Guessing").font(.subheadline)
                            Spacer()
                            Text("\(Int((rate * 100).rounded()))% right of \(v.total)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var evidence: some View {
        let a = model.state.attempts
        let auto = a.filter { $0.grading == .auto }, own = a.filter { $0.grading == .selfAssessed }
        return Card {
            Text("Evidence").font(.headline)
            row("Questions answered", "\(a.count)")
            row("Auto-checked, correct on your own", "\(auto.filter(\.isIndependentSuccess).count) of \(auto.count)")
            row("Self-assessed, all rubric points met", "\(own.filter(\.isIndependentSuccess).count) of \(own.count)")
            row("Used a hint", "\(a.filter { $0.assistance == .hinted }.count)")
            row("Revealed the answer", "\(a.filter { $0.assistance == .revealed }.count)")
            row("Lessons read", "\(model.state.lessonsCompleted.count) of \(model.catalog.lessons.count)")
            row("Case studies attempted", "\(Set(model.state.caseResults.map(\.caseId)).count) of \(model.catalog.cases.count)")
            row("Labs built", "\(model.state.labsDone.count) of \(model.catalog.labs.count)")
            row("Study days", "\(Engine.studyDays(state: model.state, clock: model.clock).count)")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.subheadline); Spacer(); Text(v).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
    }
}

struct ModuleConceptsView: View {
    @Environment(AppModel.self) private var model
    let module: Module

    var body: some View {
        List {
            ForEach(model.catalog.lessons(in: module.id)) { l in
                Section(l.title) {
                    ForEach(l.concepts, id: \.self) { id in
                        if let c = model.catalog.concepts[id] { ConceptRow(concept: c) }
                    }
                }
            }
        }
        .navigationTitle(module.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConceptRow: View {
    @Environment(AppModel.self) private var model
    let concept: Concept

    var body: some View {
        let st = model.status(concept.id)
        let rec = model.state.concepts[concept.id]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(concept.name).font(.subheadline.weight(.semibold))
                Spacer()
                StateBadge(status: st)
            }
            if let st, st.attempts > 0 {
                Text("\(st.attempts) answered · \(st.autoSuccesses) auto-checked + \(st.selfSuccesses) self-assessed on your own")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let due = rec?.dueDay {
                let days = due.days(since: model.clock.today)
                Text(days <= 0 ? "Review due now" : "Next review in \(days) day\(days == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            if let reason = st?.reviewReason { Text(reason.rawValue).font(.caption).foregroundStyle(Theme.needsReview) }
        }
        .padding(.vertical, 2)
    }
}
