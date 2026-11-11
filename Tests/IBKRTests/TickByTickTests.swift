import Foundation
import Testing
@testable import IBKR

private let aapl = ["0", "AAPL", "STK", "", "0.0", "", "", "SMART", "", "USD", "", ""]

@Suite struct TickByTickCodecTests {
    @Test func tradeTickDecodes() {
        guard case .tickByTick(8, let t) = IBDecoder.decode(
            body("99", "8", "2", "1794321000", "351.5", "100", "2", "NASDAQ", "@ I")) else { Issue.record("not 99"); return }
        #expect(t == .trade(time: Date(timeIntervalSince1970: 1794321000), price: d("351.5"), size: d("100"),
                            exchange: "NASDAQ", conditions: "@ I", pastLimit: false, unreported: true))
    }

    @Test func bidAskTickDecodes() {
        guard case .tickByTick(8, let t) = IBDecoder.decode(
            body("99", "8", "3", "1794321000", "351.4", "351.6", "300", "200", "3")) else { Issue.record("not 99"); return }
        #expect(t == .bidAsk(time: Date(timeIntervalSince1970: 1794321000), bidPrice: d("351.4"), askPrice: d("351.6"),
                             bidSize: d("300"), askSize: d("200")))
    }

    @Test func midPointTickDecodes() {
        guard case .tickByTick(8, let t) = IBDecoder.decode(body("99", "8", "4", "1794321000", "351.5")) else {
            Issue.record("not 99"); return
        }
        #expect(t == .midPoint(time: Date(timeIntervalSince1970: 1794321000), price: d("351.5")))
    }

    @Test func unknownTypeOrBadTimeIsMalformed() {
        for f in [["99", "8", "5", "1794321000", "1"], ["99", "8", "4", "noon", "351.5"], ["99", "8", "3", "1", "1"]] {
            guard case .malformed = IBDecoder.decode(body(f)) else { Issue.record("not malformed: \(f)"); return }
        }
    }

    @Test func requestsEncode() throws {
        let c = Contract(symbol: "AAPL")
        #expect(try IBRequest.tickByTick(requestID: 4, contract: c, type: .allLast).body()
            == body(["97", "4"] + aapl + ["AllLast", "0", "0"]))
        #expect(try IBRequest.cancelTickByTick(requestID: 4).body() == body("98", "4"))
    }
}

@Test func tickByTickStreamsAndCancels() async throws {
    let gateway = FakeGateway()
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    let stream = try await client.tickByTick(Contract(symbol: "AAPL"), .allLast)
    let sent = try await gateway.waitForSent(6)[5]
    #expect(sent == ["97", sent[1]] + aapl + ["AllLast", "0", "0"])
    let id = sent[1]
    gateway.feed(["99", id, "2", "1794321000", "351.5", "100", "0", "NASDAQ", ""])
    gateway.feed(["99", id, "4", "1794321001", "351.55"])
    let (reader, result) = take(2, stream)
    let ticks = try await within2s { try await result.value }
    #expect(ticks[1] == .midPoint(time: Date(timeIntervalSince1970: 1794321001), price: d("351.55")))
    reader.cancel()
    #expect(try await gateway.waitForSent(7)[6] == ["98", id])
}
