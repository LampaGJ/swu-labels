import Foundation
import Testing

@testable import SWULabelsCore

/// Divider labels must name the **set**, whichever position the set occupies.
///
/// A divider exists so someone holding a stack of printed sheets can find where
/// one group ends and the next begins. The set is what identifies a sheet in a
/// binder, so the set belongs on the divider's first line — in the by-set layout
/// where the set is the section, and equally in an aspect-then-set layout where
/// the set is the run *inside* a section.
///
/// The by-set expectations here are the reference generator's exact output,
/// copied from its emitted plan. They are a regression fence: the shipped
/// divider format was validated on printed sheets, so generalizing dividers to
/// other layouts must not disturb it.
@Suite
struct DividerLabels {
    static func rotationCards() throws -> [Card] {
        let store = SnapshotStore(root: RepoPaths.snapshot("v2026-08-14"))
        return try store.loadPool(precedence: SetCatalog.rotationPrecedence).kept
    }

    /// The three lines of every divider in a set of sections.
    static func dividerLines(_ sections: [LabelSection]) -> [(section: String, lines: [String])] {
        sections.flatMap { section in
            section.slots.compactMap { slot -> (section: String, lines: [String])? in
                guard case let .divider(lines) = slot else { return nil }
                return (section: section.key, lines: lines.ordered)
            }
        }
    }

    @Test
    func `the by-set layout's dividers match the reference exactly`() throws {
        let cards = try Self.rotationCards()
        let sections = try Transform.layout(
            cards, order: .setThenAspect, precedence: SetCatalog.rotationPrecedence
        )
        let dividers = Self.dividerLines(sections)

        let first = try #require(dividers.first)
        #expect(first.section == "SOR")
        #expect(first.lines == ["SOR", "Spark of Rebellion", "(Vigilance) 56/254 cards"])

        // Every divider in this layout leads with its section's set code.
        for divider in dividers {
            #expect(divider.lines[0] == divider.section, "divider should lead with the set code")
            #expect(divider.lines[1] == SetCatalog.fullNames[divider.section])
        }
    }

    @Test
    func `an aspect-grouped layout's dividers name the set, not the aspect`() throws {
        let cards = try Self.rotationCards()
        // Sheets grouped by aspect, sets flowing within, dividers on. Here the
        // set is the *run* rather than the section, and it is still the thing a
        // divider has to announce — someone flipping through a colour-sorted
        // binder needs to see where JTL starts.
        var order = SheetOrder.aspectThenSet
        order.showsDividers = true

        let sections = try Transform.layout(
            cards, order: order, precedence: SetCatalog.rotationPrecedence
        )
        let dividers = Self.dividerLines(sections)
        #expect(!dividers.isEmpty, "dividers were requested but none were produced")

        let first = try #require(dividers.first)
        #expect(first.section == "Vigilance")
        // The set code, not the aspect, and its real name rather than a
        // duplicate of the first line.
        #expect(first.lines[0] == "SOR")
        #expect(first.lines[1] == "Spark of Rebellion")
        #expect(first.lines[2].contains("Vigilance"), "the section belongs in the breakdown line")

        for divider in dividers {
            #expect(
                SetCatalog.fullNames[divider.lines[0]] != nil,
                "divider line 1 is \"\(divider.lines[0])\", which is not a set code"
            )
            #expect(
                divider.lines[1] != divider.lines[0],
                "line 2 should be the set's full name, not a repeat of line 1"
            )
        }
    }

    @Test
    func `dividers are absent unless asked for`() throws {
        let cards = try Self.rotationCards()
        let sections = try Transform.layout(
            cards, order: .aspectThenSet, precedence: SetCatalog.rotationPrecedence
        )
        #expect(Self.dividerLines(sections).isEmpty)
    }

    /// Divider labels occupy real label positions, so they must be counted.
    ///
    /// A sheet whose dividers were not accounted for would silently run one
    /// label short per divider, pushing every later card into the wrong cell.
    @Test
    func `divider labels consume label positions`() throws {
        let cards = try Self.rotationCards()
        var order = SheetOrder.aspectThenSet
        order.showsDividers = true

        let withDividers = try Transform.layout(
            cards, order: order, precedence: SetCatalog.rotationPrecedence
        )
        let plan = try SheetPlanner.plan(sections: withDividers, config: .default)

        let dividerCells = plan.sections.reduce(0) { total, section in
            total + section.rows.reduce(0) { rowTotal, row in
                rowTotal + row.cells.count { $0.kind == .divider }
            }
        }
        #expect(dividerCells == Self.dividerLines(withDividers).count)

        let cardCells = plan.sections.reduce(0) { total, section in
            total + section.rows.reduce(0) { rowTotal, row in
                rowTotal + row.cells.count { $0.kind == .card }
            }
        }
        #expect(cardCells == cards.count, "every card must still appear exactly once")
    }
}
