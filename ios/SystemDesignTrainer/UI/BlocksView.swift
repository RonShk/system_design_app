import SwiftUI
import TrainerCore

/// Text with inline Markdown (**bold**, *italic*, `code`, links).
struct MarkdownText: View {
    let md: String
    init(_ md: String) { self.md = md }

    var body: some View { Text(Self.attributed(md)) }

    static func attributed(_ md: String) -> AttributedString {
        guard var s = try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(md)
        }
        for run in s.runs where run.inlinePresentationIntent?.contains(.code) == true {
            s[run.range].font = .system(.callout, design: .monospaced)
            s[run.range].backgroundColor = Color(.tertiarySystemFill)
        }
        return s
    }
}

/// Renders compiled lesson content natively.
struct BlocksView: View {
    let blocks: [Block]
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlockView: View {
    let block: Block
    var body: some View {
        switch block {
        case .paragraph(let md):
            MarkdownText(md).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        case .heading(let md):
            MarkdownText(md).font(.headline).padding(.top, 4)
        case .quote(let md):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3)
                MarkdownText(md).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let text, _):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).font(.system(.footnote, design: .monospaced)).padding(12)
            }
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker(ordered: ordered, index: i, items: items))
                            .font(.body.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(minWidth: 16, alignment: .trailing)
                        MarkdownText(entry.md).font(.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(entry.level) * 20)
                }
            }
        case .table(let head, let rows):
            TableBlock(head: head, rows: rows)
        case .diagram(let d):
            DiagramView(diagram: d)
        }
    }

    private func marker(ordered: Bool, index: Int, items: [ListEntry]) -> String {
        guard ordered, items[index].level == 0 else { return "•" }
        return "\(items[...index].filter { $0.level == 0 }.count)."
    }
}

private struct TableBlock: View {
    let head: [String]
    let rows: [[String]]
    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(head.enumerated()), id: \.offset) { _, h in
                    MarkdownText(h).font(.footnote.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider()
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        MarkdownText(cell).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 7)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .background(Color(.tertiarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Diagrams

struct DiagramView: View {
    let diagram: Diagram
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                switch diagram {
                case .flow(let rows, let edges): drawFlow(&ctx, size: size, rows: rows, edges: edges)
                case .seq(let actors, let steps): drawSeq(&ctx, size: size, actors: actors, steps: steps)
                }
            }
            .frame(width: geo.size.width, height: height)
        }
        .frame(height: height)
        .padding(10)
        .background(Color(.tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 11))
        .accessibilityElement()
        .accessibilityLabel(description)
    }

    private let boxH: CGFloat = 42, gapY: CGFloat = 46, seqTop: CGFloat = 40, seqRow: CGFloat = 38

    private var height: CGFloat {
        switch diagram {
        case .flow(let rows, _): CGFloat(rows.count) * boxH + CGFloat(max(0, rows.count - 1)) * gapY
        case .seq(_, let steps): seqTop + CGFloat(steps.count) * seqRow + 8
        }
    }

    private var description: String {
        switch diagram {
        case .flow(_, let edges):
            "Diagram. " + edges.map { "\($0.from) to \($0.to)\($0.label.isEmpty ? "" : ", \($0.label)")" }.joined(separator: "; ")
        case .seq(_, let steps):
            "Sequence diagram. " + steps.map { s in
                s.kind == "note" ? "\(s.from): \(s.label)" : "\(s.from) \(s.kind == "lost" ? "sends, lost before reaching" : "to") \(s.to): \(s.label)"
            }.joined(separator: "; ")
        }
    }

    private var ink: Color { .primary }
    private var boxFill: Color { scheme == .dark ? Color(white: 0.22) : .white }
    private var lineColor: Color { scheme == .dark ? Color(white: 0.72) : Color(white: 0.32) }
    private var lostColor: Color { Theme.bad }

    private func text(_ s: String, size: CGFloat = 12, weight: Font.Weight = .medium, color: Color? = nil) -> Text {
        Text(s).font(.system(size: size, weight: weight)).foregroundColor(color ?? ink)
    }

    private func arrow(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, kind: String, head: Bool = true) {
        var path = Path()
        path.move(to: a); path.addLine(to: b)
        let color = kind == "lost" ? lostColor : lineColor
        let style = StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: kind == "solid" ? [] : [5, 4])
        ctx.stroke(path, with: .color(color), style: style)
        guard head else { return }
        let angle = atan2(b.y - a.y, b.x - a.x), len: CGFloat = 8, spread: CGFloat = 0.45
        var h = Path()
        h.move(to: b)
        h.addLine(to: CGPoint(x: b.x - len * cos(angle - spread), y: b.y - len * sin(angle - spread)))
        h.addLine(to: CGPoint(x: b.x - len * cos(angle + spread), y: b.y - len * sin(angle + spread)))
        h.closeSubpath()
        ctx.fill(h, with: .color(color))
    }

    private func label(_ ctx: inout GraphicsContext, _ s: String, at p: CGPoint, maxWidth: CGFloat, background: Bool) {
        let resolved = ctx.resolve(text(s, size: 10.5, weight: .regular, color: .secondary))
        let sz = resolved.measure(in: CGSize(width: maxWidth, height: 40))
        if background {
            let r = CGRect(x: p.x - sz.width / 2 - 3, y: p.y - sz.height / 2 - 1, width: sz.width + 6, height: sz.height + 2)
            ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color(.systemBackground).opacity(0.92)))
        }
        ctx.draw(resolved, in: CGRect(x: p.x - sz.width / 2, y: p.y - sz.height / 2, width: sz.width, height: sz.height))
    }

    private func box(_ ctx: inout GraphicsContext, _ name: String, rect: CGRect) {
        let p = Path(roundedRect: rect, cornerRadius: 8)
        ctx.fill(p, with: .color(boxFill))
        ctx.stroke(p, with: .color(lineColor.opacity(0.7)), lineWidth: 1)
        let resolved = ctx.resolve(text(name))
        let inner = rect.insetBy(dx: 5, dy: 3)
        let sz = resolved.measure(in: inner.size)
        ctx.draw(resolved, in: CGRect(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2, width: sz.width, height: sz.height))
    }

    private func drawFlow(_ ctx: inout GraphicsContext, size: CGSize, rows: [[String]], edges: [DiagramEdge]) {
        var frames: [String: CGRect] = [:]
        for (r, row) in rows.enumerated() {
            let gap: CGFloat = 12
            let w = min(150, (size.width - gap * CGFloat(row.count - 1)) / CGFloat(row.count))
            let total = w * CGFloat(row.count) + gap * CGFloat(row.count - 1)
            for (i, name) in row.enumerated() {
                frames[name] = CGRect(x: (size.width - total) / 2 + CGFloat(i) * (w + gap), y: CGFloat(r) * (boxH + gapY), width: w, height: boxH)
            }
        }
        var labels: [(String, CGPoint)] = []
        for e in edges {
            guard let a = frames[e.from], let b = frames[e.to] else { continue }
            var p1: CGPoint, p2: CGPoint
            if b.minY > a.maxY { p1 = CGPoint(x: a.midX, y: a.maxY); p2 = CGPoint(x: b.midX, y: b.minY) }
            else if b.maxY < a.minY { p1 = CGPoint(x: a.midX + 12, y: a.minY); p2 = CGPoint(x: b.midX + 12, y: b.maxY) }
            else if b.minX > a.minX { p1 = CGPoint(x: a.maxX, y: a.midY); p2 = CGPoint(x: b.minX, y: b.midY) }
            else { p1 = CGPoint(x: a.minX, y: a.midY); p2 = CGPoint(x: b.maxX, y: b.midY) }
            // keep a steep diagonal from starting at the far corner of a wide box
            if abs(p1.x - p2.x) > 4, p1.y != p2.y {
                p1.x += (p2.x - p1.x) * 0.25
                p1.x = min(max(p1.x, a.minX + 8), a.maxX - 8)
            }
            arrow(&ctx, from: p1, to: p2, kind: e.kind)
            if !e.label.isEmpty { labels.append((e.label, CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2))) }
        }
        for (name, rect) in frames { box(&ctx, name, rect: rect) }
        for (s, p) in labels { label(&ctx, s, at: p, maxWidth: size.width / 2.2, background: true) }
    }

    private func drawSeq(_ ctx: inout GraphicsContext, size: CGSize, actors: [String], steps: [DiagramEdge]) {
        let colW = size.width / CGFloat(actors.count)
        func cx(_ name: String) -> CGFloat { colW * (CGFloat(actors.firstIndex(of: name) ?? 0) + 0.5) }
        for a in actors {
            let w = min(colW - 8, 104)
            var life = Path()
            life.move(to: CGPoint(x: cx(a), y: 28)); life.addLine(to: CGPoint(x: cx(a), y: size.height))
            ctx.stroke(life, with: .color(lineColor.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            box(&ctx, a, rect: CGRect(x: cx(a) - w / 2, y: 0, width: w, height: 28))
        }
        for (i, s) in steps.enumerated() {
            let y = seqTop + CGFloat(i) * seqRow + 24
            if s.kind == "note" {
                let resolved = ctx.resolve(text(s.label, size: 10.5, weight: .regular))
                let sz = resolved.measure(in: CGSize(width: size.width - 12, height: 30))
                let x = min(max(4, cx(s.from) - sz.width / 2 - 6), size.width - sz.width - 16)
                let r = CGRect(x: x, y: y - 16, width: sz.width + 12, height: sz.height + 8)
                ctx.fill(Path(roundedRect: r, cornerRadius: 5), with: .color(Color.yellow.opacity(scheme == .dark ? 0.25 : 0.35)))
                ctx.draw(resolved, in: CGRect(x: r.minX + 6, y: r.minY + 4, width: sz.width, height: sz.height))
                continue
            }
            let x1 = cx(s.from)
            var x2 = cx(s.to)
            let lost = s.kind == "lost"
            if lost { x2 = x1 + (x2 - x1) * 0.6 }
            arrow(&ctx, from: CGPoint(x: x1, y: y), to: CGPoint(x: x2, y: y), kind: s.kind, head: !lost)
            if lost {
                ctx.draw(ctx.resolve(text("✕", size: 13, weight: .bold, color: lostColor)), at: CGPoint(x: x2 + (x2 > x1 ? 7 : -7), y: y))
            }
            if !s.label.isEmpty {
                label(&ctx, s.label, at: CGPoint(x: (x1 + cx(s.to)) / 2, y: y - 9), maxWidth: size.width - 8, background: false)
            }
        }
    }
}
