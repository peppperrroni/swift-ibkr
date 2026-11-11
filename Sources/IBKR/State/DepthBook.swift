/// A depth book, position-indexed per side as `ib_async` keeps it: insert and update set the position, delete
/// removes it. The published arrays are sorted by position with gaps dropped.
public struct DepthBook: Sendable, Equatable {
    private var bidRows: [Int: DepthLevel] = [:]
    private var askRows: [Int: DepthLevel] = [:]

    public init() {}

    public var bids: [DepthLevel] { bidRows.sorted { $0.key < $1.key }.map(\.value) }
    public var asks: [DepthLevel] { askRows.sorted { $0.key < $1.key }.map(\.value) }

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

    public mutating func reset() { bidRows = [:]; askRows = [:] }
}
