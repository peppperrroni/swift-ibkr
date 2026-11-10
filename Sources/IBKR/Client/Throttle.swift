/// Sliding-window send limiter: reserves send slots so no window holds more than `limit`.
struct Throttle {
    let limit: Int
    let window: Duration
    private var slots: [ContinuousClock.Instant] = []   // the last `limit` reserved slots

    init(limit: Int = 45, window: Duration = .seconds(1)) {
        self.limit = limit
        self.window = window
    }

    /// Reserves the earliest slot at or after `now`; returns how long to wait for it.
    mutating func reserve(at now: ContinuousClock.Instant) -> Duration {
        var slot = now
        if slots.count >= limit { slot = max(now, slots[slots.count - limit] + window) }
        slots.append(slot)
        if slots.count > limit { slots.removeFirst(slots.count - limit) }
        return slot - now
    }
}
