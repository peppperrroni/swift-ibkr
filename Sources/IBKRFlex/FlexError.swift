/// Why a Flex Web Service call or a report failed.
public enum FlexError: Error, Sendable, Equatable {
    /// SendRequest's Status was not Success; IB's error code and message.
    case request(code: String, message: String)
    /// GetStatement answered an error other than "in progress"; `code` is `""` for the legacy form.
    case statement(code: String, message: String)
    /// The report is not well-formed XML (the parser's message), or SendRequest answered Success without a
    /// ReferenceCode or a Url.
    case malformedXML(String)
    /// A non-2xx status from `FlexReport.urlSession`; 0 when the response is not HTTP.
    case http(status: Int)
}
