/// What `qualifyContracts` made of one input contract.
public enum ContractQualification: Sendable, Equatable {
    /// IB's one matching contract, with `SMART` kept as its exchange when the input asked for `SMART`.
    case qualified(Contract)
    /// Several matches: those of the input's secType when it had one (possibly none), else all of them, in IB's order.
    case ambiguous([Contract])
    /// IB knows no such contract (error 200, or an empty answer).
    case notFound
}
