public struct ExecutionFilter: Sendable, Equatable {
    public var clientID: Int?
    public var account: String
    public var time: String
    public var symbol: String
    public var secType: String
    public var exchange: String
    public var side: String

    public init(clientID: Int? = nil, account: String = "", time: String = "", symbol: String = "",
                secType: String = "", exchange: String = "", side: String = "") {
        self.clientID = clientID; self.account = account; self.time = time; self.symbol = symbol
        self.secType = secType; self.exchange = exchange; self.side = side
    }
}
