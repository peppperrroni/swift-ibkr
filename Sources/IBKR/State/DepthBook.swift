/// A depth book, position-indexed per side as `ib_async` keeps it: insert and update set the position, delete
/// removes it. The published arrays are sorted by position with gaps dropped.
public struct DepthBook: Sendable, Equatable, Encodable {
    private var bidRows: [Int: DepthLevel] = [:]
    private var askRows: [Int: DepthLevel] = [:]

    /// Creates an empty book.
    public init() {}

    /// The bid rows, sorted by position.
    public var bids: [DepthLevel] { bidRows.sorted { $0.key < $1.key }.map(\.value) }
    /// The ask rows, sorted by position.
    public var asks: [DepthLevel] { askRows.sorted { $0.key < $1.key }.map(\.value) }

    /// Applies one update: insert and update set the row at its position, delete removes it, and a negative position
    /// is ignored.
    public mutating func apply(_ u: DepthUpdate) {
        guard u.position >= 0 else { return }
        let level = DepthLevel(price: u.price, size: u.size, marketMaker: u.marketMaker)
        switch (u.side, u.operation) {
        case (.bid, .delete): bidRows[u.position] = nil
        case (.ask, .delete): askRows[u.position] = nil
        case (.bid, _): bidRows[u.position] = level
        case (.ask, _): askRows[u.position] = level
        }
    }

    /// Empties both sides, as IB's depth reset (error 317) asks.
    public mutating func reset() { bidRows = [:]; askRows = [:] }
}
