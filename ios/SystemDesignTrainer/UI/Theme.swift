import SwiftUI
import TrainerCore

enum Theme {
    static let cardRadius: CGFloat = 14
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let pageBackground = Color(.systemGroupedBackground)
    static let good = Color(red: 0.13, green: 0.55, blue: 0.33)
    static let warn = Color(red: 0.80, green: 0.47, blue: 0.05)
    static let bad = Color(red: 0.78, green: 0.22, blue: 0.20)

    static func color(for state: ConceptState) -> Color {
        switch state {
        case .notStarted: Color(.systemGray4)
        case .introduced: Color(red: 0.55, green: 0.62, blue: 0.75)
        case .practiced: Color(red: 0.90, green: 0.68, blue: 0.20)
        case .demonstrated: Color(red: 0.25, green: 0.62, blue: 0.80)
        case .retained: Color(red: 0.16, green: 0.60, blue: 0.38)
        }
    }
    static let needsReview = Color(red: 0.84, green: 0.33, blue: 0.25)
}

extension ConceptStatus {
    var displayLabel: String { needsReview ? "Needs review" : state.label }
    var displayColor: Color { needsReview ? Theme.needsReview : Theme.color(for: state) }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white)
            .background(Color.accentColor.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .environment(\.colorScheme, .light)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.22 : 0.12),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

/// Small coloured pill showing a concept's state.
struct StateBadge: View {
    let status: ConceptStatus?
    var body: some View {
        let label = status?.displayLabel ?? ConceptState.notStarted.label
        let color = status?.displayColor ?? Theme.color(for: .notStarted)
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Tag: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.13), in: Capsule())
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
    }
}

/// Horizontal bar split by concept state.
struct StateBar: View {
    let summary: Mastery.Summary
    var height: CGFloat = 10
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(ConceptState.allCases.reversed(), id: \.self) { st in
                    let n = summary.counts[st] ?? 0
                    if n > 0 {
                        Theme.color(for: st).frame(width: max(2, geo.size.width * CGFloat(n) / CGFloat(max(1, summary.total)) - 1.5))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityLabel("\(summary.covered) of \(summary.total) concepts started, \(summary.demonstrated) demonstrated, \(summary.retained) retained")
    }
}

extension ItemSkill {
    var label: String {
        switch self {
        case .recall: "Recall"; case .explain: "Explain"; case .predict: "Predict"; case .compare: "Compare"
        case .estimate: "Estimate"; case .diagnose: "Diagnose"; case .design: "Design"; case .implement: "Implementation"
        }
    }
}

extension ItemFormat {
    var label: String {
        switch self {
        case .mcq: "Multiple choice"; case .multi: "Select all that apply"; case .numeric: "Calculation"
        case .order: "Put in order"; case .free: "Written answer"
        }
    }
}
