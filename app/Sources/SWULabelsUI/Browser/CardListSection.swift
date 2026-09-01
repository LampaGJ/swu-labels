import Foundation
import SWULabelsCore

/// One section of the browser list: the sheet's section key and its cards.
///
/// `Identifiable` so `ForEach` needs no `id:` key path, per the project's data
/// conventions.
struct CardListSection: Identifiable {
    let key: String
    let cards: [Card]

    var id: String { key }
}
