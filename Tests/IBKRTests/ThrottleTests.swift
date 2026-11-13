import Testing
@testable import IBKR

@Test func throttleAllowsTheLimitAtOnce() {
    var th = Throttle()
    let t = ContinuousClock.now
    for _ in 0..<45 { #expect(th.reserve(at: t) == .zero) }
}

@Test func throttleWaitsForTheWindow() {
    var th = Throttle(limit: 2, window: .seconds(1))
    let t = ContinuousClock.now
    #expect(th.reserve(at: t) == .zero)
    #expect(th.reserve(at: t) == .zero)
    #expect(th.reserve(at: t) == .seconds(1))
    #expect(th.reserve(at: t + .seconds(2)) == .zero)
}

@Test func throttleSlidesTheWindow() {
    var th = Throttle(limit: 2, window: .seconds(1))
    let t = ContinuousClock.now
    #expect(th.reserve(at: t) == .zero)
    #expect(th.reserve(at: t + .milliseconds(600)) == .zero)
    #expect(th.reserve(at: t + .milliseconds(800)) == .milliseconds(200))
}

@Test func zeroLimitNeverWaits() {
    var th = Throttle(limit: 0, window: .seconds(1))
    let t = ContinuousClock.now
    for _ in 0..<100 { #expect(th.reserve(at: t) == .zero) }
}
