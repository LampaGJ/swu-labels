import Foundation

/// Turns grouped sections into a fully resolved ``SheetPlan``.
///
/// This is the last stage that knows about cards, and the first that knows
/// about the grid. Everything downstream draws a plan and never sees a `Card`.
public enum SheetPlanner {
    /// Builds the plan for a set of already-grouped, already-ordered sections.
    ///
    /// Ordering is the caller's responsibility and is not re-derived here:
    /// re-sorting at plan time would give the sheet two competing sources of
    /// truth for row position.
    public static func plan(
        sections: [LabelSection],
        config: LabelLayoutConfig
    ) throws -> SheetPlan {
        let template = try TemplateEngine.parse(config.template)
        let planSections = sections.map { section in
            PlanSection(
                key: section.key,
                rows: rows(for: section.slots, config: config, template: template)
            )
        }
        return SheetPlan(config: config, sections: planSections)
    }

    /// Chunks a section's slots into grid rows, padding the final row with empties.
    ///
    /// Rows run continuously past a sheet boundary; the renderer paginates every
    /// ``PlanGeometry/rowsPerSheet`` rows. Chunking here rather than in the
    /// renderer keeps cell assignment in the plan, where the gate can see it.
    static func rows(
        for slots: [LabelSlot],
        config: LabelLayoutConfig,
        template: [ParsedTemplateLine]
    ) -> [PlanRow] {
        let columns = Avery5167.columnsPerSheet
        return stride(from: 0, to: max(slots.count, 0), by: columns).map { start in
            let cells = (0..<columns).map { offset -> PlanCell in
                let index = start + offset
                guard index < slots.count else { return .empty }
                return cell(for: slots[index], config: config, template: template)
            }
            return PlanRow(cells: cells)
        }
    }

    /// Resolves one slot into its cell.
    static func cell(
        for slot: LabelSlot,
        config: LabelLayoutConfig,
        template: [ParsedTemplateLine]
    ) -> PlanCell {
        switch slot {
        case let .card(card):
            let paragraphs = template.compactMap { line -> PlanParagraph? in
                guard let runs = TemplateEngine.resolve(line, card: card, config: config) else {
                    return nil
                }
                return PlanParagraph(style: line.style, runs: runs)
            }
            return PlanCell(kind: .card, rarity: card.rarity, paragraphs: paragraphs)

        case let .divider(lines):
            // A divider is not a card and carries no template. It reuses the
            // three label paragraph styles in order so it reads as visually
            // consistent — bold code, italic name, plain breakdown — without
            // inventing styles that exist nowhere else.
            let styles = dividerStyles(from: config)
            let paragraphs = zip(styles, lines.ordered).map { style, text in
                PlanParagraph(style: style, runs: [.text(text)])
            }
            return PlanCell(kind: .divider, paragraphs: paragraphs)
        }
    }

    /// The three paragraph styles a divider borrows.
    ///
    /// Fixed ids, not derived from `config.template`. Deriving them would be the
    /// better design — a retitled template would not leave dividers pointing at
    /// style ids that no longer exist — but `dividerCell` in `src/render.ts`
    /// hardcodes exactly these three, and the fidelity gate compares this
    /// implementation against that one. Matching the reference beats improving
    /// on it until the reference is retired.
    static func dividerStyles(from config: LabelLayoutConfig) -> [String] {
        ["cardTitle", "cardSubtitle", "cardStats"]
    }
}
