import XCTest
@testable import ClaudeHub

final class RateLimitTests: XCTestCase {
    private let account = Account(label: "account1", configDirectory: "/tmp/rate-test")

    func testRetryAfterSecondsDatesAndMalformedValues() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(RateLimitPolicy.retryDate(header: " 120 ", now: now), now.addingTimeInterval(120))
        XCTAssertEqual(RateLimitPolicy.retryDate(header: "Thu, 01 Jan 1970 00:02:00 GMT", now: now), now.addingTimeInterval(120))
        XCTAssertEqual(RateLimitPolicy.retryDate(header: "0", now: now), now)
        for header in [nil, "", "oops", "-1", "NaN", "Infinity", "1.5"] as [String?] {
            XCTAssertNil(RateLimitPolicy.retryDate(header: header, now: now))
        }
        XCTAssertEqual(RateLimitPolicy.delay(failures: 1, jitter: 0), 60)
        XCTAssertEqual(RateLimitPolicy.delay(failures: 2, jitter: 0), 120)
        XCTAssertEqual(RateLimitPolicy.delay(failures: 20, jitter: 0.2), 1_800)
    }

    func testCooldownBlocksManualRefreshAndPreservesServerDeadline() async throws {
        let clock = RateTestClock()
        let requests = UsageRequestCoordinator(now: { clock.now }, jitter: { 0 })
        await requests.configure([account])
        let counter = RateTestCounter()
        let deadline = clock.now.addingTimeInterval(3_600)
        for _ in 0..<4 {
            do {
                _ = try await requests.snapshot(for: account) {
                    await counter.increment()
                    throw AnthropicClientError.rateLimitResponse(endpoint: .usage, retryAt: deadline)
                }
                XCTFail("Expected rate limit")
            } catch AnthropicClientError.rateLimited(let date) { XCTAssertEqual(date, deadline) }
        }
        let count = await counter.value
        XCTAssertEqual(count, 1)
        await requests.pause(account)
        await requests.resume(account)
        do { _ = try await requests.snapshot(for: account) { XCTFail("Reconnect must not bypass cooldown"); return try Self.snapshot() } }
        catch AnthropicClientError.rateLimited(let date) { XCTAssertEqual(date, deadline) }
        clock.advance(3_600)
        _ = try await requests.snapshot(for: account) { try Self.snapshot() }
    }

    func testFallbackBackoffGrowsAndSuccessResetsIt() async throws {
        let clock = RateTestClock()
        let requests = UsageRequestCoordinator(now: { clock.now }, jitter: { 0 })
        await requests.configure([account])
        for delay in [60.0, 120.0, 240.0] {
            let expected = clock.now.addingTimeInterval(delay)
            do { _ = try await requests.snapshot(for: account) { throw AnthropicClientError.http(429) } }
            catch AnthropicClientError.rateLimited(let date) { XCTAssertEqual(date, expected) }
            clock.advance(delay)
        }
        _ = try await requests.snapshot(for: account) { try Self.snapshot() }
        clock.advance(30)
        let expected = clock.now.addingTimeInterval(60)
        do { _ = try await requests.snapshot(for: account) { throw AnthropicClientError.http(429) } }
        catch AnthropicClientError.rateLimited(let date) { XCTAssertEqual(date, expected) }
    }

    func testConcurrentAndRapidRefreshesShareWorkWithoutChangingSampleTime() async throws {
        let clock = RateTestClock()
        let requests = UsageRequestCoordinator(now: { clock.now })
        await requests.configure([account])
        let counter = RateTestCounter()
        let sample = try Self.snapshot()
        try await withThrowingTaskGroup(of: AccountSnapshot.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await requests.snapshot(for: self.account) {
                        await counter.increment()
                        try await Task.sleep(nanoseconds: 30_000_000)
                        return sample
                    }
                }
            }
            for try await result in group { XCTAssertEqual(result.fetchedAt, sample.fetchedAt) }
        }
        clock.advance(29)
        let cached = try await requests.snapshot(for: account) { XCTFail("Too soon"); return sample }
        XCTAssertEqual(cached.fetchedAt, sample.fetchedAt)
        let count = await counter.value
        XCTAssertEqual(count, 1)
        clock.advance(1)
        _ = try await requests.snapshot(for: account) { await counter.increment(); return sample }
        let nextCount = await counter.value
        XCTAssertEqual(nextCount, 2)
    }

    func testCancelledUIWaiterDoesNotCancelSharedRequest() async throws {
        let requests = UsageRequestCoordinator()
        await requests.configure([account])
        let started = expectation(description: "Request started")
        let first = Task {
            try await requests.snapshot(for: account) {
                started.fulfill()
                try await Task.sleep(nanoseconds: 100_000_000)
                return try Self.snapshot()
            }
        }
        await fulfillment(of: [started], timeout: 2)
        first.cancel()
        _ = try await requests.snapshot(for: account) { XCTFail("Must share existing request"); return try Self.snapshot() }
        do { _ = try await first.value; XCTFail("Cancelled waiter") } catch is CancellationError { }
    }

    func testRateLimitedAccountDoesNotBlockOtherAccount() async throws {
        let requests = UsageRequestCoordinator()
        let other = Account(label: "account2", configDirectory: "/tmp/rate-test-2")
        await requests.configure([account, other])
        do { _ = try await requests.snapshot(for: account) { throw AnthropicClientError.http(429) } }
        catch AnthropicClientError.rateLimited { }
        _ = try await requests.snapshot(for: other) { try Self.snapshot() }
        await requests.configure([other])
        do { _ = try await requests.snapshot(for: account) { XCTFail("Removed account"); return try Self.snapshot() } }
        catch is CancellationError { }
    }

    func testProfileCacheExpiresAndInvalidatesWithoutTokenCoupling() async throws {
        let clock = RateTestClock()
        let server = RateTestServer()
        let transport = AnthropicTransport(send: { try await server.send($0) }, now: { clock.now })
        let first = OAuthCredential(accessToken: "one", refreshToken: nil, expiresAt: 1)
        let rotated = OAuthCredential(accessToken: "two", refreshToken: nil, expiresAt: 2)
        _ = try await transport.snapshot(for: account, credential: first)
        clock.advance(300)
        _ = try await transport.snapshot(for: account, credential: rotated)
        var paths = await server.paths
        XCTAssertEqual(paths, ["/api/oauth/usage", "/api/oauth/profile", "/api/oauth/usage"])
        clock.advance(21_300)
        _ = try await transport.snapshot(for: account, credential: rotated)
        await transport.invalidate(account.id)
        _ = try await transport.snapshot(for: account, credential: rotated)
        paths = await server.paths
        XCTAssertEqual(paths.filter { $0 == "/api/oauth/profile" }.count, 3)
    }

    func test429OnEitherEndpointPreservesHeaderAndStopsFurtherRequests() async throws {
        for endpoint in [AnthropicEndpoint.usage, .profile] {
            let clock = RateTestClock()
            let server = RateTestServer(limitedPath: endpoint.rawValue)
            let transport = AnthropicTransport(send: { try await server.send($0) }, now: { clock.now })
            do {
                _ = try await transport.snapshot(for: account, credential: OAuthCredential(accessToken: "test", refreshToken: nil, expiresAt: 1))
                XCTFail("Expected 429")
            } catch AnthropicClientError.rateLimitResponse(let path, let retry) {
                XCTAssertEqual(path, endpoint)
                XCTAssertEqual(retry, clock.now.addingTimeInterval(120))
            }
            let paths = await server.paths
            XCTAssertEqual(paths.count, endpoint == .usage ? 1 : 2)
        }
    }

    func testUsageCooldownDoesNotStopScheduledTokenRenewal() async throws {
        let renewed = expectation(description: "Renewal remains independent")
        let expired = OAuthCredential(accessToken: "test", refreshToken: "test", expiresAt: 1, scopes: ["user:profile"])
        let sessions = SessionCoordinator(cache: CredentialCache(loader: { _ in expired })) { _, _ in
            try await Task.sleep(nanoseconds: 50_000_000)
            renewed.fulfill()
        }
        let client = AnthropicClient(sessions: sessions) { _ in throw AnthropicClientError.http(429) }
        await client.configure(accounts: [account])
        do { _ = try await client.snapshot(for: account) } catch AnthropicClientError.rateLimited { }
        await fulfillment(of: [renewed], timeout: 2)
        await client.configure(accounts: [])
    }

    private static func snapshot() throws -> AccountSnapshot {
        AccountSnapshot(email: nil, organizationID: nil,
            usage: try JSONDecoder().decode(UsagePayload.self, from: Data("{}".utf8)), fetchedAt: Date())
    }
}

private final class RateTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}

private actor RateTestCounter {
    var value = 0
    func increment() { value += 1 }
}

private actor RateTestServer {
    var paths: [String] = []
    let limitedPath: String?
    init(limitedPath: String? = nil) { self.limitedPath = limitedPath }
    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        let url = try XCTUnwrap(request.url)
        paths.append(url.path)
        let limited = url.path == limitedPath
        let body = url.path == "/api/oauth/profile" ? "{\"account\":{},\"organization\":{}}" : "{}"
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: limited ? 429 : 200,
            httpVersion: nil, headerFields: limited ? ["Retry-After": "120"] : [:]))
        return (Data(body.utf8), response)
    }
}
