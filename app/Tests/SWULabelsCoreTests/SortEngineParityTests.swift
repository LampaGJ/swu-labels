import Foundation
import Testing

@testable import SWULabelsCore

/// Proves the general sort engine reproduces the shipped layouts exactly.
///
/// The five fixed layouts are what the printed reference sheets validate, and
/// ``PlanParity`` ties them to the reference generator card for card. This suite
/// extends that trust to the flexible ordering: if the engine puts every one of
/// the ~2,800 cards in the same section and the same position as the fixed
/// function does, then a custom order is built on machinery already known to
/// agree with the reference, rather than on a second implementation nobody
/// checked.
@Suite
struct SortEngineParity {
    static func premierCards() throws -> [Card] {
        let store = SnapshotStore(root: RepoPaths.snapshot("v2026-08-23"))
        return try store.loadPool(precedence: SetCatalog.premierPrecedence).kept
    }

    static func rotationCards() throws -> [Card] {
        let store = SnapshotStore(root: RepoPaths.snapshot("v2026-08-14"))
        return try store.loadPool(precedence: SetCatalog.rotationPrecedence).kept
    }

    /// Section keys paired with their card titles, which is what "same sheet,
    /// same position" means in practice.
    static func shape(_ sections: [LabelSection]) -> [(key: String, titles: [String])] {
        sections.map { section in
            (
                key: section.key,
                titles: section.slots.compactMap { slot in
                    if case let .card(card) = slot { return card.title }
                    return nil
                }
            )
        }
    }

    static func expectSameShape(
        _ actual: [LabelSection],
        _ expected: [LabelSection],
        label: String
    ) {
        let actualShape = shape(actual)
        let expectedShape = shape(expected)

        #expect(actualShape.count == expectedShape.count, "\(label): section count")
        for (index, pair) in zip(actualShape, expectedShape).enumerated() {
            #expect(pair.0.key == pair.1.key, "\(label): section \(index) key")
            if pair.0.titles != pair.1.titles {
                let firstDifference = zip(pair.0.titles, pair.1.titles)
                    .enumerated()
                    .first { $0.element.0 != $0.element.1 }
                let detail = firstDifference.map {
                    "position \($0.offset): \"\($0.element.0)\" vs \"\($0.element.1)\""
                } ?? "lengths differ: \(pair.0.titles.count) vs \(pair.1.titles.count)"
                Issue.record("\(label): section \"\(pair.0.key)\" differs at \(detail)")
            }
        }
    }

    @Test
    func `the engine reproduces the aspect-then-set layout`() throws {
        let cards = try Self.premierCards()
        let engine = try Transform.layout(cards, order: .aspectThenSet)
        let fixed = try Transform.layoutAspectThenSet(cards, config: .default)
        Self.expectSameShape(engine, fixed, label: "aspect-set")
    }

    @Test
    func `the engine reproduces the aspect-only layout`() throws {
        let cards = try Self.premierCards()
        let engine = try Transform.layout(cards, order: .aspectOnly)
        let fixed = Transform.layoutAspectOnly(cards)
        Self.expectSameShape(engine, fixed, label: "aspect")
    }

    @Test
    func `the engine reproduces the alphabetical layout`() throws {
        let cards = try Self.premierCards()
        let engine = try Transform.layout(cards, order: .alphabetical)
        let fixed = Transform.layoutAlphabetical(cards)
        Self.expectSameShape(engine, fixed, label: "alphabetical")
    }

    @Test
    func `the engine reproduces the by-set layout's card order`() throws {
        let cards = try Self.rotationCards()
        let engine = try Transform.layout(
            cards, order: .setThenAspect, precedence: SetCatalog.rotationPrecedence
        )
        let fixed = try Transform.layoutBySetWithDividers(
            cards, config: .default, precedence: SetCatalog.rotationPrecedence
        )
        // Card order and sectioning only. The fixed layout also interleaves
        // divider labels, which are a presentation feature of that mode rather
        // than an ordering decision, so they are outside what this compares.
        Self.expectSameShape(engine, fixed, label: "set")
    }

    @Test
    func `the engine reproduces the full-rotation aspect-then-set layout`() throws {
        let cards = try Self.rotationCards()
        let engine = try Transform.layout(
            cards, order: .aspectThenSet, precedence: SetCatalog.rotationPrecedence
        )
        let fixed = try Transform.layoutAspectThenSet(
            cards, config: .default, precedence: SetCatalog.rotationPrecedence
        )
        Self.expectSameShape(engine, fixed, label: "rotation-aspect-set")
    }

    @Test
    func `every card survives an arbitrary custom order`() throws {
        let cards = try Self.premierCards()
        // Grouping by rarity and ordering by cost then power is a combination no
        // fixed layout offers, which is the point of the engine. Whatever the
        // order, no card may be dropped or duplicated.
        let order = SheetOrder(
            groupBy: [SortCriterion(key: .rarity)],
            thenBy: [
                SortCriterion(key: .cost, direction: .descending),
                SortCriterion(key: .power),
                SortCriterion(key: .title),
            ]
        )
        let sections = try Transform.layout(cards, order: order)
        let placed = sections.flatMap { section in
            section.slots.compactMap { slot -> Card? in
                if case let .card(card) = slot { return card }
                return nil
            }
        }
        #expect(placed.count == cards.count, "a custom order dropped or duplicated cards")
        #expect(Set(placed) == Set(cards), "a custom order changed which cards are present")
    }

    @Test
    func `ordering is stable across repeated runs`() throws {
        let cards = try Self.premierCards()
        let order = SheetOrder(
            groupBy: [SortCriterion(key: .aspect)],
            thenBy: [SortCriterion(key: .cost), SortCriterion(key: .title)]
        )
        // Run twice in one process. Swift seeds its hasher per process, so any
        // accidental dependence on `Dictionary` iteration order inside the
        // engine would show up as two different answers here.
        let first = Self.shape(try Transform.layout(cards, order: order))
        let second = Self.shape(try Transform.layout(cards, order: order))
        #expect(first.map(\.key) == second.map(\.key))
        #expect(first.map(\.titles) == second.map(\.titles))
    }
}
