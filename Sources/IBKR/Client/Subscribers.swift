/// Fan-out of one event source to any number of `AsyncStream` consumers.
/// Termination does not remove: `onTermination` gets the id so the owner can call `remove`.
struct Subscribers<Element: Sendable> {
    private var continuations: [Int: AsyncStream<Element>.Continuation] = [:]
    private var nextID = 0

    init() {}

    var count: Int { continuations.count }

    /// `first`, when given, goes to this stream only, ahead of everything yielded later.
    mutating func stream(first: Element? = nil, onTermination: @escaping @Sendable (Int) -> Void) -> AsyncStream<Element> {
        let id = nextID
        nextID += 1
        let (stream, continuation) = AsyncStream.makeStream(of: Element.self, bufferingPolicy: .unbounded)
        if let first { continuation.yield(first) }
        continuation.onTermination = { _ in onTermination(id) }
        continuations[id] = continuation
        return stream
    }

    mutating func remove(_ id: Int) { continuations[id] = nil }

    func yield(_ element: Element) {
        for c in continuations.values { c.yield(element) }
    }
}
