/// Which executions reqExecutions (out 7) asks for; `ib_async`'s `ExecutionFilter`.
public struct ExecutionFilter: Sendable, Equatable, Encodable {
    /// `nil` goes out as `0`, `ib_async`'s default; live, that returned another client's fill (see KNOWN-GAPS).
    public var clientID: Int?
    /// Only this account; empty sends an empty field.
    public var account: String
    /// Only executions from this time on, in IB's text; empty sends an empty field.
    public var time: String
    /// Only this symbol; empty sends an empty field.
    public var symbol: String
    /// Only this security type; empty sends an empty field.
    public var secType: String
    /// Only this exchange; empty sends an empty field.
    public var exchange: String
    /// Only this side (`BOT` or `SLD`); empty sends an empty field.
    public var side: String

    /// Creates a filter with every field given.
    public init(clientID: Int? = nil, account: String = "", time: String = "", symbol: String = "",
                secType: String = "", exchange: String = "", side: String = "") {
        self.clientID = clientID; self.account = account; self.time = time; self.symbol = symbol
        self.secType = secType; self.exchange = exchange; self.side = side
    }
}
