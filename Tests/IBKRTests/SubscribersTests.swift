import Testing
@testable import IBKR

private func firstTwo(_ s: AsyncStream<Int>) async -> [Int] {
    var out: [Int] = []
    for await x in s { out.append(x); if out.count == 2 { break } }
    return out
}

@Test func subscribersFanOut() async {
    var subs = Subscribers<Int>()
    let a = subs.stream { _ in }
    let b = subs.stream { _ in }
    subs.yield(1)
    subs.yield(2)
    #expect(await firstTwo(a) == [1, 2])
    #expect(await firstTwo(b) == [1, 2])
}

@Test func removedSubscriberGetsNothing() async {
    var subs = Subscribers<Int>()
    _ = subs.stream { _ in }
    let b = subs.stream { _ in }
    subs.remove(0) // the first stream has id 0
    subs.yield(1)
    #expect(subs.count == 1)
    var it = b.makeAsyncIterator()
    #expect(await it.next() == 1)
}
