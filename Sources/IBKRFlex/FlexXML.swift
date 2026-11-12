import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct FlexElement: Sendable {
    let name: String
    let attributes: [String: String]
    /// The root is 0.
    let depth: Int
    /// The element's own character data, untrimmed.
    var text: String
}

func parseFlexXML(_ data: Data) throws -> [FlexElement] {
    let collector = FlexElementCollector()
    let parser = XMLParser(data: data)
    parser.delegate = collector
    // An empty document can parse "successfully" on some platforms; a report needs a root.
    // So can a truncated one on corelibs, so every element must also have closed.
    guard parser.parse(), !collector.elements.isEmpty, collector.open.isEmpty else {
        throw FlexError.malformedXML(parser.parserError?.localizedDescription ?? "no XML element, or an unclosed one")
    }
    return collector.elements
}

private final class FlexElementCollector: NSObject, XMLParserDelegate {
    var elements: [FlexElement] = []
    var open: [Int] = []   // indices of the elements still open, innermost last

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        open.append(elements.count)
        elements.append(FlexElement(name: elementName, attributes: attributeDict, depth: open.count - 1, text: ""))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        open.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let index = open.last { elements[index].text += string }
    }

    // Without this, CDATA text is dropped; ElementTree, which ib_async uses, keeps it.
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let index = open.last { elements[index].text += String(decoding: CDATABlock, as: UTF8.self) }
    }
}
