#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation

/// Fetches one URL with a GET and returns the body; `FlexReport.urlSession` is the default.
/// The URL carries the Flex token in its query: a custom transport must not log it or put it in an error.
public typealias FlexTransport = @Sendable (URL) async throws -> Data

extension FlexReport {
    /// IB's documented SendRequest endpoint (the `ndcdyn` region); another region, such as `gdcdyn`, goes in
    /// `download`'s `url:`.
    public static let defaultURL = URL(string: "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/SendRequest")!

    /// A GET through `URLSession.shared`; a non-2xx status throws `FlexError.http(status:)`.
    /// A network failure throws a `URLError` with only its code: URLSession's own error carries the failing URL,
    /// token included, in its `userInfo`, which must not reach a log.
    public static let urlSession: FlexTransport = { url in
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: url) { data, response, error in
                continuation.resume(with: urlSessionResult(data, response, error))
            }.resume()
        }
    }

    static func urlSessionResult(_ data: Data?, _ response: URLResponse?, _ error: (any Error)?) -> Result<Data, any Error> {
        if let error {
            // corelibs reports an NSError that does not bridge to URLError; either way the code is all that is kept.
            let ns = error as NSError
            guard ns.domain == NSURLErrorDomain else { return .failure(error) }
            let code: URLError.Code? = URLError.Code(rawValue: ns.code)   // failable on corelibs, not on Darwin
            return .failure(URLError(code ?? .unknown))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { return .failure(FlexError.http(status: status)) }
        return .success(data ?? Data())
    }

    /// Downloads a Flex query's report through the two steps of IB's Flex Web Service: SendRequest, then
    /// GetStatement until the statement is ready. It polls without a bound, sleeping `pollInterval` before every
    /// GetStatement. An already-cancelled caller sends nothing; cancelling the calling task later throws
    /// `CancellationError` at the next sleep, and a request already in flight is waited for (the transport is
    /// not cancelled).
    public static func download(token: String, queryID: String, url: URL = FlexReport.defaultURL,
                                pollInterval: Duration = .seconds(1),
                                transport: FlexTransport = FlexReport.urlSession) async throws -> FlexReport {
        try Task.checkCancellation()   // SendRequest starts generation at IB and counts against the token's rate limit
        let sent = try FlexReport(data: await transport(requestURL(url, [
            URLQueryItem(name: "t", value: token), URLQueryItem(name: "q", value: queryID), URLQueryItem(name: "v", value: "3"),
        ])))
        guard sent.value("Status") == "Success" else {
            throw FlexError.request(code: sent.value("ErrorCode") ?? "", message: sent.value("ErrorMessage") ?? "")
        }
        guard let reference = sent.value("ReferenceCode"), let statement = sent.value("Url").flatMap(URL.init(string:)) else {
            throw FlexError.malformedXML("SendRequest answered Success without a ReferenceCode or a Url")
        }
        let statementURL = try requestURL(statement, [
            URLQueryItem(name: "q", value: reference), URLQueryItem(name: "t", value: token), URLQueryItem(name: "v", value: "3"),
        ])
        while true {
            try await Task.sleep(for: pollInterval)   // ib_async sleeps before every GetStatement, the first included
            let answer = try FlexReport(data: await transport(statementURL))
            // The legacy form may sit under a FlexStatementResponse root, so it is checked first.
            if answer.elements.first(where: { $0.depth == 1 })?.name == "code" {   // ib_async's legacy form
                let text = answer.value("code") ?? ""
                if text.hasPrefix("Statement generation in progress") { continue }
                throw FlexError.statement(code: "", message: text)
            }
            if answer.elements.first?.name == "FlexStatementResponse" {            // the v3 form
                let code = answer.value("ErrorCode")
                if code == "1019" { continue }
                if code != nil || answer.value("Status") != "Success" {
                    throw FlexError.statement(code: code ?? "", message: answer.value("ErrorMessage") ?? "")
                }
            }
            return answer
        }
    }

    /// The text, trimmed, of the first element at depth 1 named `tag`.
    func value(_ tag: String) -> String? {
        elements.first { $0.depth == 1 && $0.name == tag }?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func requestURL(_ base: URL, _ items: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        components.queryItems = (components.queryItems ?? []) + items
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }
}
