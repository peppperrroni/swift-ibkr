/// How much detail IB Gateway writes to its own log (`setServerLogLevel`).
public enum ServerLogLevel: Int, Sendable { case system = 1, error, warning, information, detail }
