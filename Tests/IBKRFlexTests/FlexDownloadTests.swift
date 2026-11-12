import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import IBKRFlex

private let fakeToken = "000000000000000000000000"
private func response(_ children: String) -> String {
    "<FlexStatementResponse timestamp=\"12 November, 2026 06:00 PM EST\">\(children)</FlexStatementResponse>"
}
private let sendSuccess = response("""

<Status>Success</Status>
<ReferenceCode>1234567890</ReferenceCode>
<Url>https://statements.example/GetStatement</Url>

""")
private let inProgress = response(
    "<Status>Warn</Status><ErrorCode>1019</ErrorCode><ErrorMessage>Statement generation in progress. Please try again shortly.</ErrorMessage>")
private let inProgressLegacy = response("<code>Statement generation in progress. Please try again shortly.</code>")
private let inProgressCDATA = response("<code><![CDATA[Statement generation in progress. Please try again shortly.]]></code>")

/// Answers each request with the next scripted reply and records the URLs asked for.
private actor FakeFlexService {
    private var replies: [Result<String, FlexError>]
    private(set) var urls: [URL] = []
    init(_ replies: [Result<String, FlexError>]) { self.replies = replies }
    func reply(_ url: URL) throws -> Data {
        urls.append(url)
        return Data(try replies.removeFirst().get().utf8)
    }
    nonisolated var transport: FlexTransport { { try await self.reply($0) } }
}

private func download(_ fake: FakeFlexService, token: String = fakeToken,
                      pollInterval: Duration = .zero) async throws -> FlexReport {
    try await FlexReport.download(token: token, queryID: "123456", pollInterval: pollInterval, transport: fake.transport)
}
private func query(_ url: URL) -> [URLQueryItem] {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
}
/// The task's result, or nil when it has not finished within `limit`. A hung task is left behind, not awaited.
private func result<T: Sendable>(of task: Task<T, any Error>, within limit: Duration) async -> Result<T, any Error>? {
    let results = AsyncStream<Result<T, any Error>?> { continuation in
        Task { _ = continuation.yield(await task.result) }
        Task { try? await Task.sleep(for: limit); _ = continuation.yield(nil) }
    }
    for await first in results { return first }
    return nil
}
private func isMalformed(_ error: any Error) -> Bool {
    if case .malformedXML? = error as? FlexError { true } else { false }
}

@Suite struct FlexDownloadTests {
    @Test func downloadSendsTheTwoSteps() async throws {
        let fake = FakeFlexService([.success(sendSuccess), .success(flexReportXML)])
        let report = try await download(fake)
        #expect(report.extract("Trade").count == 2)
        let urls = await fake.urls
        #expect(urls.count == 2)
        #expect(urls[0].absoluteString.hasPrefix(FlexReport.defaultURL.absoluteString + "?"))
        #expect(query(urls[0]) == [.init(name: "t", value: fakeToken), .init(name: "q", value: "123456"), .init(name: "v", value: "3")])
        #expect(urls[1].absoluteString.hasPrefix("https://statements.example/GetStatement?"))
        #expect(query(urls[1]) == [.init(name: "q", value: "1234567890"), .init(name: "t", value: fakeToken), .init(name: "v", value: "3")])
    }

    @Test func downloadPollsWhileTheStatementIsInProgress() async throws {
        let fake = FakeFlexService([.success(sendSuccess), .success(inProgress), .success(inProgressLegacy),
                                    .success(inProgress), .success(inProgressCDATA), .success(flexReportXML)])
        #expect(try await download(fake).topics.contains("Trade"))
        let urls = await fake.urls
        #expect(urls.count == 6)
        #expect(urls.dropFirst().allSatisfy { $0.absoluteString.hasPrefix("https://statements.example/GetStatement?") })
    }

    @Test func aRefusedRequestThrowsRequestError() async throws {
        let refused = FakeFlexService([.success(response(
            "<Status>Fail</Status><ErrorCode>1015</ErrorCode><ErrorMessage>Token is invalid.</ErrorMessage>"))])
        await #expect(throws: FlexError.request(code: "1015", message: "Token is invalid.")) { try await download(refused) }
        #expect(await refused.urls.count == 1)
        let bare = FakeFlexService([.success(response("<Status>Fail</Status>"))])
        await #expect(throws: FlexError.request(code: "", message: "")) { try await download(bare) }
    }

    @Test func aStatementErrorThrowsStatementError() async throws {
        let v3 = FakeFlexService([.success(sendSuccess), .success(inProgress), .success(response(
            "<Status>Fail</Status><ErrorCode>1003</ErrorCode><ErrorMessage>Statement is not available.</ErrorMessage>"))])
        await #expect(throws: FlexError.statement(code: "1003", message: "Statement is not available.")) { try await download(v3) }
        let legacy = FakeFlexService([.success(sendSuccess), .success(response("<code>Statement could not be generated</code>"))])
        await #expect(throws: FlexError.statement(code: "", message: "Statement could not be generated")) { try await download(legacy) }
        let bare = FakeFlexService([.success(sendSuccess), .success(response("<Status>Fail</Status>"))])
        await #expect(throws: FlexError.statement(code: "", message: "")) { try await download(bare) }
    }

    @Test func anHTTPErrorPropagates() async throws {
        let fake = FakeFlexService([.failure(.http(status: 503))])
        await #expect(throws: FlexError.http(status: 503)) { try await download(fake) }
        #expect(await fake.urls.count == 1)
    }

    @Test func malformedAnswersThrowMalformedXML() async {
        for replies in [[Result<String, FlexError>.success("not xml")],
                        [.success(sendSuccess), .success("<FlexQueryResponse>")],
                        [.success(sendSuccess), .success("")]] {
            do { _ = try await download(FakeFlexService(replies)); Issue.record("downloaded") }
            catch { #expect(isMalformed(error), "\(error)") }
        }
    }

    @Test func successWithoutReferenceCodeOrUrlIsMalformed() async {
        for children in ["<Status>Success</Status><Url>https://statements.example/GetStatement</Url>",
                         "<Status>Success</Status><ReferenceCode>1234567890</ReferenceCode>"] {
            let fake = FakeFlexService([.success(response(children))])
            do { _ = try await download(fake); Issue.record("downloaded") }
            catch { #expect(isMalformed(error), "\(error)") }
            #expect(await fake.urls.count == 1)
        }
    }

    @Test func anAlreadyCancelledCallerSendsNothing() async throws {
        let fake = FakeFlexService([.success(sendSuccess), .success(flexReportXML)])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await download(fake)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await fake.urls.count == 0)
    }

    @Test func cancellingStopsThePolling() async throws {
        let fake = FakeFlexService([.success(sendSuccess)] + Array(repeating: .success(inProgress), count: 10))
        let task = Task { try await download(fake, pollInterval: .seconds(60)) }
        let deadline = ContinuousClock.now + .seconds(10)
        while await fake.urls.isEmpty {
            guard ContinuousClock.now < deadline else { task.cancel(); Issue.record("no SendRequest in 10 s"); return }
            await Task.yield()
        }
        task.cancel()
        guard let outcome = await result(of: task, within: .seconds(10)) else {
            Issue.record("still polling 10 s after the cancel"); return
        }
        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(await fake.urls.count == 1)
    }

    @Test func theTokenIsEscaped() async throws {
        let fake = FakeFlexService([.success(sendSuccess), .success(flexReportXML)])
        _ = try await download(fake, token: "a&b c")
        let urls = await fake.urls
        #expect(query(urls[0]).first == URLQueryItem(name: "t", value: "a&b c"))
        #expect(query(urls[1]).dropFirst().first == URLQueryItem(name: "t", value: "a&b c"))
    }

    @Test func urlSessionAnswersDropTheTokenAndCheckTheStatus() throws {
        let url = URL(string: "https://statements.example/GetStatement?t=\(fakeToken)")!
        let failed = NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue,
                             userInfo: [NSURLErrorFailingURLErrorKey: url])
        #expect(throws: URLError(.timedOut)) { try FlexReport.urlSessionResult(nil, nil, failed).get() }
        guard case .failure(let error) = FlexReport.urlSessionResult(nil, nil, failed) else { Issue.record("succeeded"); return }
        #expect((error as NSError).userInfo.isEmpty)
        #expect(!"\(error)".contains(fakeToken))
        let other = NSError(domain: "other", code: 1)
        #expect(throws: other) { try FlexReport.urlSessionResult(nil, nil, other).get() }

        let ok = Data("<a/>".utf8)
        func http(_ status: Int) -> HTTPURLResponse { HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)! }
        #expect(try FlexReport.urlSessionResult(ok, http(200), nil).get() == ok)
        #expect(throws: FlexError.http(status: 503)) { try FlexReport.urlSessionResult(ok, http(503), nil).get() }
        #expect(throws: FlexError.http(status: 0)) { try FlexReport.urlSessionResult(ok, nil, nil).get() }
        #expect(try FlexReport.urlSessionResult(nil, http(204), nil).get() == Data())
    }
}
