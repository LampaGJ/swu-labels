@preconcurrency import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SWULabelsCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Downloads card art once and keeps it on disk.
///
/// A proxy run of a few hundred cards would otherwise refetch several hundred
/// images every time a setting changed. The cache is keyed by a digest of the
/// art URL, so a card whose art is replaced upstream gets a new key rather than
/// silently serving a stale picture from the old one.
///
/// `ImageIO` decodes rather than `NSImage`/`UIImage`: it is the same API on
/// every Apple platform, which keeps this target free of a UI framework.
public actor ArtImageStore {
    public enum StoreError: Error, CustomStringConvertible {
        case downloadFailed(url: String, status: Int)
        case notAnImage(url: String)

        public var description: String {
            switch self {
            case let .downloadFailed(url, status):
                "could not download art (HTTP \(status)): \(url)"
            case let .notAnImage(url):
                "downloaded art could not be decoded as an image: \(url)"
            }
        }
    }

    public let cacheDirectory: URL
    private let session: URLSession
    /// Decoded images, so one card printed nine times decodes once.
    private var decoded: [String: CGImage] = [:]

    public init(cacheDirectory: URL, session: URLSession = .shared) {
        self.cacheDirectory = cacheDirectory
        self.session = session
    }

    /// The default cache location: beside the content, not in the bundle.
    ///
    /// Art is fetched at run time and can be re-fetched, so it does not belong
    /// in a signed app bundle — writing there would break the signature.
    public static func defaultCacheDirectory(contentRoot: URL) -> URL {
        contentRoot.appending(path: "data/art-cache")
    }

    /// Where one art URL is cached.
    ///
    /// The digest, not the filename: two sets can ship art with the same
    /// basename, and a URL can contain characters a filesystem will not take.
    nonisolated func cacheURL(for artURL: String) -> URL {
        let digest = SHA256.hash(data: Data(artURL.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let ext = URL(string: artURL)?.pathExtension.isEmpty == false
            ? URL(string: artURL)!.pathExtension
            : "png"
        return cacheDirectory.appending(path: "\(digest).\(ext)")
    }

    /// Whether this art is already on disk.
    public nonisolated func isCached(_ artURL: String) -> Bool {
        FileManager.default.fileExists(atPath: cacheURL(for: artURL).path(percentEncoded: false))
    }

    /// Downloads art if it is not cached, and returns its local file URL.
    public func fetch(_ artURL: String) async throws -> URL {
        let destination = cacheURL(for: artURL)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            return destination
        }
        try FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true
        )
        guard let url = URL(string: artURL) else {
            throw StoreError.downloadFailed(url: artURL, status: -1)
        }
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard status == 200 else {
            throw StoreError.downloadFailed(url: artURL, status: status)
        }
        // Written to a temporary neighbour and moved into place, so an
        // interrupted download cannot leave a truncated file that later looks
        // cached and decodes to a broken image.
        let staging = destination.appendingPathExtension("partial")
        try data.write(to: staging)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination
    }

    /// Downloads every URL that is missing, reporting progress.
    ///
    /// Bounded concurrency for the same reason the card ingest bounds it: the
    /// origin sheds requests under a burst, and a failed art fetch means a blank
    /// card on a printed sheet.
    public func prefetch(
        _ artURLs: [String],
        concurrency: Int = 4,
        progress: @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws {
        let missing = artURLs.filter { !isCached($0) }
        guard !missing.isEmpty else {
            progress(artURLs.count, artURLs.count)
            return
        }
        var completed = 0
        var next = 0

        try await withThrowingTaskGroup(of: Void.self) { group in
            func addNext() {
                guard next < missing.count else { return }
                let url = missing[next]
                next += 1
                group.addTask { _ = try await self.fetch(url) }
            }
            for _ in 0..<min(concurrency, missing.count) { addNext() }
            while try await group.next() != nil {
                completed += 1
                progress(completed, missing.count)
                addNext()
            }
        }
    }

    /// The decoded image for one art URL, downloading it if needed.
    public func image(for artURL: String) async throws -> CGImage {
        if let cached = decoded[artURL] { return cached }
        let file = try await fetch(artURL)
        guard
            let source = CGImageSourceCreateWithURL(file as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw StoreError.notAnImage(url: artURL)
        }
        decoded[artURL] = image
        return image
    }
}
