import Foundation

/// An insertion-ordered multi-map: the reproducible stand-in for `Dictionary`.
///
/// **This exists because Swift's `Dictionary` iteration order is randomized per
/// process.** Swift seeds its hasher differently on every launch, so iterating a
/// `Dictionary` yields a different order each run. The TypeScript generator
/// leans on JavaScript `Map`'s guaranteed insertion order in `groupByAspect`,
/// `groupBySet` and `buildDocument`, where iteration order decides which section
/// prints first and which card lands in which cell. Porting any of those to a
/// Swift `Dictionary` would produce a generator that reshuffles the sheet
/// between runs while every test still passed.
///
/// Lookup stays O(1) through a private index; iteration follows first-insertion
/// order, exactly like `Map`.
public struct OrderedBuckets<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private var order: [Key] = []
    private var storage: [Key: [Value]] = [:]

    public init() {}

    /// Appends `value` to `key`'s bucket, creating the bucket at the end of the
    /// iteration order the first time `key` is seen.
    public mutating func append(_ value: Value, to key: Key) {
        if storage[key] == nil {
            order.append(key)
            storage[key] = []
        }
        storage[key]?.append(value)
    }

    /// The bucket for `key`, or `nil` when the key was never inserted.
    public subscript(key: Key) -> [Value]? {
        storage[key]
    }

    /// Keys in first-insertion order.
    public var keys: [Key] { order }

    /// Whether `key` has a bucket.
    public func contains(_ key: Key) -> Bool {
        storage[key] != nil
    }

    /// Key/bucket pairs in first-insertion order.
    public var entries: [(key: Key, values: [Value])] {
        order.compactMap { key in
            guard let values = storage[key] else { return nil }
            return (key: key, values: values)
        }
    }

    /// Rebuilds the collection with `keyOrder` as the new iteration order.
    ///
    /// Keys absent from `keyOrder` are dropped, so callers that must not lose a
    /// bucket check `keys` against `keyOrder` before calling this. The grouping
    /// functions do exactly that and throw ``LabelError/unaccountedSetCodes(_:order:)``
    /// rather than shipping a sheet with a set silently missing.
    public func reordered(by keyOrder: [Key]) -> OrderedBuckets<Key, Value> {
        var result = OrderedBuckets<Key, Value>()
        for key in keyOrder {
            guard let values = storage[key] else { continue }
            result.order.append(key)
            result.storage[key] = values
        }
        return result
    }

    /// Applies `transform` to every bucket, preserving iteration order.
    public func mapValues<T: Sendable>(
        _ transform: ([Value]) throws -> [T]
    ) rethrows -> OrderedBuckets<Key, T> {
        var result = OrderedBuckets<Key, T>()
        for key in order {
            guard let values = storage[key] else { continue }
            result.order.append(key)
            result.storage[key] = try transform(values)
        }
        return result
    }

    /// Drops every bucket that is empty, preserving iteration order.
    public func removingEmptyBuckets() -> OrderedBuckets<Key, Value> {
        var result = OrderedBuckets<Key, Value>()
        for key in order {
            guard let values = storage[key], !values.isEmpty else { continue }
            result.order.append(key)
            result.storage[key] = values
        }
        return result
    }
}
