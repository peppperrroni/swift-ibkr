import Foundation

/// One element of a Flex report: IB's attribute strings, untouched.
public struct FlexRecord: Sendable, Equatable {
    public let topic: String
    public let attributes: [String: String]

    public init(topic: String, attributes: [String: String]) {
        self.topic = topic
        self.attributes = attributes
    }

    public subscript(_ key: String) -> String? { attributes[key] }

    /// The attribute as a number, only when the whole value is one (`-1.0025`, `1E-4`); `nil` for a missing,
    /// empty or partly numeric value such as `12abc` or `1,000`.
    public func decimal(_ key: String) -> Decimal? {
        guard let value = attributes[key], value.wholeMatch(of: /-?\d+(\.\d+)?([eE][-+]?\d+)?/) != nil else { return nil }
        return Decimal(string: value)
    }
}
