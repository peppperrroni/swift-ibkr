import Foundation

/// One element of a Flex report: IB's attribute strings, untouched.
public struct FlexRecord: Sendable, Equatable {
    /// The element's tag name.
    public let topic: String
    /// The element's attributes, as IB wrote them.
    public let attributes: [String: String]

    /// A record of these values.
    public init(topic: String, attributes: [String: String]) {
        self.topic = topic
        self.attributes = attributes
    }

    /// The attribute named `key`, or `nil`.
    public subscript(_ key: String) -> String? { attributes[key] }

    /// The attribute as a number, only when the whole value is one (`-1.0025`, `1E-4`); `nil` for a missing,
    /// empty or partly numeric value such as `12abc` or `1,000`.
    public func decimal(_ key: String) -> Decimal? {
        // ASCII digits only (`\d` takes any script's); NaN is refused whatever the platform's `Decimal(string:)` does.
        guard let value = attributes[key], value.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?/) != nil,
              let number = Decimal(string: value), !number.isNaN else { return nil }
        return number
    }
}
