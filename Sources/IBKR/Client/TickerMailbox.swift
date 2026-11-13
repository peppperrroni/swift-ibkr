import Foundation

/// What `tickers` hands its consumer: the newest `Ticker`, carrying the `ticks`, `tickByTicks` and `domTicks` of
/// every update the consumer has not taken yet. `next()` takes it and clears it under one lock, so a slow consumer
/// skips intermediate tickers but never a tick, and never gets one twice. The fold `put`s each update's ticker
/// (holding only that update's lists) and `finish`es; `stop` is the consumer leaving. Either cancels the readers,
/// which stops every inner request stream and so sends its cancel. The stream has one consumer: a second task
/// iterating it while the first waits gets the end at once, which ends the shared stream after the first's element.
final class TickerMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Ticker?
    /// `nil` while open; `.some(nil)` ended; `.some(error)` failed with an error not yet delivered.
    private var end: (any Error)??
    private var waiter: CheckedContinuation<Ticker?, any Error>?
    private var readers: [Task<Void, Never>]

    init(readers: [Task<Void, Never>]) { self.readers = readers }

    func put(_ ticker: Ticker) {
        lock.lock()
        guard end == nil else { lock.unlock(); return }
        if let w = waiter {
            waiter = nil
            lock.unlock()
            w.resume(returning: ticker)
            return
        }
        var merged = ticker
        if var p = pending {
            pending = nil   // p's lists are now unique, so a stalled consumer's backlog grows in place
            p.ticks += ticker.ticks; p.tickByTicks += ticker.tickByTicks; p.domTicks += ticker.domTicks
            (merged.ticks, merged.tickByTicks, merged.domTicks) = (p.ticks, p.tickByTicks, p.domTicks)
        }
        pending = merged
        lock.unlock()
    }

    /// The fold ended: after any pending ticker the consumer gets `error`, or the end.
    func finish(throwing error: (any Error)?) { close(.some(error)) }

    /// The consumer left: it gets the end, and the readers are cancelled.
    func stop() { close(.some(nil)) }

    private func close(_ how: (any Error)??) {
        lock.lock()
        if end == nil { end = how }
        let w = waiter, rs = readers
        waiter = nil; readers = []
        if w != nil { end = .some(nil) }
        lock.unlock()
        rs.forEach { $0.cancel() }
        guard let w else { return }
        if case let .some(.some(error)) = how { w.resume(throwing: error) } else { w.resume(returning: nil) }
    }

    func next() async throws -> Ticker? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Ticker?, any Error>) in
                lock.lock()
                if let p = pending {
                    pending = nil
                    lock.unlock()
                    c.resume(returning: p)
                } else if let e = end {
                    end = .some(nil)   // an error is delivered once; the end after it
                    lock.unlock()
                    if let e { c.resume(throwing: e) } else { c.resume(returning: nil) }
                } else if waiter != nil {
                    lock.unlock()
                    c.resume(returning: nil)   // a second concurrent iterator ends at once; the first keeps its wait
                } else {
                    waiter = c
                    lock.unlock()
                }
            }
        } onCancel: { stop() }
    }

    /// The consumer's stream. Letting go of it (or cancelling its reader) stops the mailbox.
    func stream() -> AsyncThrowingStream<Ticker, any Error> {
        let holder = Holder(self)
        return AsyncThrowingStream(unfolding: { try await holder.box.next() })
    }

    /// Owned by the consumer's stream only, so its end is the consumer letting go.
    private final class Holder: Sendable {
        let box: TickerMailbox
        init(_ box: TickerMailbox) { self.box = box }
        deinit { box.stop() }
    }
}
