import Foundation
import Testing
@testable import IBKR

private let aapl = ["0", "AAPL", "STK", "", "0.0", "", "", "SMART", "", "USD", "", ""]

private func connected(_ gateway: FakeGateway) async throws -> IBClient {
    let client = IBClient(connector: gateway.connector)
    try await within2s { try await client.connect(clientID: 7) }
    return client
}

private func upd(_ pos: Int, _ op: DepthUpdate.Operation, _ side: DepthUpdate.Side, _ price: String, _ size: String,
                 mm: String = "") -> DepthUpdate {
    DepthUpdate(position: pos, marketMaker: mm, operation: op, side: side, price: d(price), size: d(size))
}

@Suite struct DepthCodecTests {
    @Test func depthFramesDecode() {
        guard case .depth(4, let a) = IBDecoder.decode(body("12", "1", "4", "0", "0", "1", "351.5", "100")) else {
            Issue.record("not 12"); return
        }
        #expect(a == upd(0, .insert, .bid, "351.5", "100"))
        guard case .depth(4, let b) = IBDecoder.decode(body("13", "1", "4", "1", "NSDQ", "1", "0", "351.6", "50", "1")) else {
            Issue.record("not 13"); return
        }
        #expect(b == upd(1, .update, .ask, "351.6", "50", mm: "NSDQ"))
    }

    @Test func badOperationOrSideIsMalformed() {
        for f in [["12", "1", "4", "0", "3", "1", "1", "1"], ["12", "1", "4", "0", "0", "2", "1", "1"]] {
            guard case .malformed = IBDecoder.decode(body(f)) else { Issue.record("not malformed: \(f)"); return }
        }
    }

    @Test func depthRequestEncodes() throws {
        let c = Contract(symbol: "AAPL")
        #expect(try IBRequest.marketDepth(requestID: 4, contract: c, rows: 10, smart: true).body()
            == body(["10", "5", "4"] + aapl + ["10", "1", ""]))
        #expect(try IBRequest.cancelMarketDepth(requestID: 4, smart: false).body() == body("11", "1", "4", "0"))
    }
}

@Test func bookInsertUpdateDelete() {
    var book = DepthBook()
    book.apply(upd(0, .insert, .bid, "351.5", "100"))
    book.apply(upd(1, .insert, .bid, "351.4", "200"))
    book.apply(upd(0, .update, .bid, "351.6", "150"))
    book.apply(upd(1, .delete, .bid, "351.4", "200"))
    #expect(book.bids == [DepthLevel(price: d("351.6"), size: d("150"), marketMaker: "")])
    #expect(book.asks.isEmpty)
    book.apply(upd(5, .delete, .ask, "1", "1"))    // missing position: no-op
    book.apply(upd(-1, .insert, .ask, "1", "1"))   // negative position: ignored
    #expect(book.asks.isEmpty)
    book.reset()
    #expect(book.bids.isEmpty)
}

@Test func depthStreamYieldsWholeBooks() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketDepth(Contract(symbol: "AAPL"), rows: 10)
    let id = try await gateway.waitForSent(6)[5][2]
    gateway.feed(["12", "1", id, "0", "0", "1", "351.5", "100"])
    gateway.feed(["13", "1", id, "0", "NSDQ", "0", "0", "351.6", "50", "1"])
    let (reader, result) = take(2, stream)
    let books = try await within2s { try await result.value }
    #expect(books[0].bids.count == 1 && books[0].asks.isEmpty)
    #expect(books[1].bids.count == 1 && books[1].asks == [DepthLevel(price: d("351.6"), size: d("50"), marketMaker: "NSDQ")])
    reader.cancel()
    #expect(try await gateway.waitForSent(7)[6] == ["11", "1", id, "1"])
}

@Test func depthResetEmptiesTheBookAndGoesOn() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketDepth(Contract(symbol: "AAPL"), rows: 10)
    let id = try await gateway.waitForSent(6)[5][2]
    gateway.feed(["12", "1", id, "0", "0", "1", "351.5", "100"])
    gateway.feed(["12", "1", id, "1", "0", "1", "351.4", "100"])
    gateway.feed(["4", "2", id, "317", "Market depth data has been RESET. Please empty deep book contents", ""])
    gateway.feed(["12", "1", id, "0", "0", "1", "351.0", "10"])
    let (reader, result) = take(4, stream)
    let books = try await within2s { try await result.value }
    #expect(books[1].bids.count == 2)
    #expect(books[2].bids.isEmpty && books[2].asks.isEmpty)
    #expect(books[3].bids.count == 1)
    reader.cancel()
}

@Test func slowDepthConsumerGetsOnlyTheNewestBook() async throws {
    let gateway = FakeGateway()
    let client = try await connected(gateway)
    let stream = try await client.marketDepth(Contract(symbol: "AAPL"), rows: 10)
    let id = try await gateway.waitForSent(6)[5][2]
    gateway.feed(["12", "1", id, "0", "0", "1", "351.5", "100"])
    gateway.feed(["12", "1", id, "1", "0", "1", "351.4", "100"])
    gateway.feed(["12", "1", id, "2", "0", "1", "351.3", "100"])
    try await Task.sleep(for: .milliseconds(100))   // the route has applied all three before the first read
    let first = try await within2s { try await stream.first { _ in true } }
    #expect(first?.bids.count == 3)
}
