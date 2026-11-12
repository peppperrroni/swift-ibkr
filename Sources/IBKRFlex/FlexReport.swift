import Foundation

/// A Flex Web Service report, parsed. Load a saved one with `FlexReport(data: Data(contentsOf: url))` and
/// save one with `try report.data.write(to: url)`.
public struct FlexReport: Sendable {
    /// The report's XML as received.
    public let data: Data
    let elements: [FlexElement]

    /// Throws `FlexError.malformedXML` when `data` is not a well-formed XML document.
    public init(data: Data) throws {
        self.data = data
        self.elements = try parseFlexXML(data)
    }

    /// The names of the elements that carry attributes, at any depth.
    public var topics: Set<String> { Set(elements.filter { !$0.attributes.isEmpty }.map(\.name)) }

    /// Every element named `topic`, in document order; an element without attributes gives `[:]`.
    public func extract(_ topic: String) -> [FlexRecord] {
        elements.filter { $0.name == topic }.map { FlexRecord(topic: topic, attributes: $0.attributes) }
    }
}
