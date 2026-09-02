import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches the paginated card-list API.
///
/// Mirrors the reference ingest's fragility handling exactly, because the
/// endpoint genuinely is fragile: three pages in flight at once, five attempts
/// per page, and a linear backoff. Raising the concurrency makes the API shed
/// requests, so the low number is a finding rather than a default.
public struct CardListClient: Sendable {
    public static let baseURL = "https://admin.starwarsunlimited.com/api/card-list"
    public static let pageSize = 100
    public static let pageConcurrency = 3
    public static let retryAttempts = 5
    public static let retryDelay = Duration.seconds(3)

    /// Relations the label pipeline consumes.
    ///
    /// Art fields are deliberately absent: labels carry no images beyond the
    /// rarity icon, and requesting art would multiply the payload for nothing.
    static let populateFields = [
        "expansion", "type", "rarity", "aspects", "aspectDuplicates",
        "variantOf", "reprintOf",
    ]

    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Relations the proxy art index needs.
    ///
    /// A separate list because art is a much heavier payload and the label
    /// pipeline must never pay for it. Only the fields identifying a card and
    /// locating its art are requested.
    static let artPopulateFields = ["expansion", "artFront"]

    public static func pageURL(page: Int) -> URL {
        pageURL(page: page, populate: populateFields)
    }

    static func pageURL(page: Int, populate: [String]) -> URL {
        var components = URLComponents(string: baseURL)!
        var items = [
            URLQueryItem(name: "pagination[page]", value: String(page)),
            URLQueryItem(name: "pagination[pageSize]", value: String(pageSize)),
        ]
        for (index, field) in populate.enumerated() {
            items.append(URLQueryItem(name: "populate[\(index)]", value: field))
        }
        components.queryItems = items
        return components.url!
    }

    /// Fetches one page, retrying transient failures.
    ///
    /// A decoding failure is never retried: the same bytes would decode the same
    /// way five times, and the useful signal is that the upstream shape changed,
    /// not that the network is flaky.
    func fetchPage(_ page: Int) async throws -> SWUAPI.PageResponse {
        try await fetchPage(page, populate: Self.populateFields, as: SWUAPI.PageResponse.self)
    }

    /// Fetches one page of any shape this endpoint can return.
    ///
    /// Generic over the response so the art index reuses this retry and backoff
    /// behaviour rather than growing a second, subtly different copy of it.
    func fetchPage<Response: Decodable & Sendable>(
        _ page: Int,
        populate: [String],
        as type: Response.Type
    ) async throws -> Response {
        var attempt = 1
        while true {
            do {
                let (data, response) = try await session.data(
                    from: Self.pageURL(page: page, populate: populate)
                )
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                guard status == 200 else {
                    if status >= 500, attempt < Self.retryAttempts {
                        try await Task.sleep(for: Self.retryDelay * attempt)
                        attempt += 1
                        continue
                    }
                    throw IngestError.httpStatus(page: page, status: status)
                }
                return try JSONDecoder().decode(Response.self, from: data)
            } catch let error as DecodingError {
                throw IngestError.decodingFailed(page: page, underlying: "\(error)")
            } catch let error as IngestError {
                throw error
            } catch {
                guard attempt < Self.retryAttempts else { throw error }
                try await Task.sleep(for: Self.retryDelay * attempt)
                attempt += 1
            }
        }
    }

    /// Fetches every page, reporting progress as pages land.
    ///
    /// Pages are collected into a dictionary keyed by page number and then
    /// re-read in page order, so the concurrent fetch cannot leak arrival order
    /// into the result. The later sort would mask most of that, but not the tie
    /// cases, and "mostly deterministic" is not a property worth having.
    func fetchAllPages(
        progress: @Sendable (_ pagesDone: Int, _ pageCount: Int, _ cardsFetched: Int) -> Void = { _, _, _ in }
    ) async throws -> [SWUAPI.APICard] {
        let first = try await fetchPage(1)
        let pageCount = first.meta.pagination.pageCount
        var pages: [Int: [SWUAPI.APICard]] = [1: first.data]
        var fetched = first.data.count
        progress(1, pageCount, fetched)

        guard pageCount > 1 else { return first.data }

        var nextPage = 2
        var completed = 1

        try await withThrowingTaskGroup(of: (Int, [SWUAPI.APICard]).self) { group in
            // Prime the group to the concurrency limit, then top it up as each
            // page finishes, which keeps exactly `pageConcurrency` requests in
            // flight rather than launching all ninety at once.
            for _ in 0..<min(Self.pageConcurrency, pageCount - 1) {
                let page = nextPage
                nextPage += 1
                group.addTask { (page, try await fetchPage(page).data) }
            }

            while let (page, cards) = try await group.next() {
                pages[page] = cards
                fetched += cards.count
                completed += 1
                progress(completed, pageCount, fetched)

                if nextPage <= pageCount {
                    let page = nextPage
                    nextPage += 1
                    group.addTask { (page, try await fetchPage(page).data) }
                }
            }
        }

        return (1...pageCount).flatMap { pages[$0] ?? [] }
    }
}
