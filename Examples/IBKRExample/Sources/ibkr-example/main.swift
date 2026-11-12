import Foundation
import IBKR

// Read-only: connects to a paper IB Gateway, prints the server time, accounts, positions and an account summary,
// then disconnects. It never places or cancels an order.
// Usage: ibkr-example [port, default 4002] [clientID, default 7]
let arguments = Array(CommandLine.arguments.dropFirst())
let port = arguments.first.flatMap { Int($0) } ?? 4002
let clientID = arguments.dropFirst().first.flatMap { Int($0) } ?? 7

let client = IBClient()
do {
    try await client.connect(host: "127.0.0.1", port: port, clientID: clientID)
    print("Server time:", try await client.currentTime())
    print("Accounts:", try await client.managedAccounts().joined(separator: ", "))
    for position in await client.positions().snapshot {
        print("Position:", position.account, position.contract.symbol, position.quantity, position.averageCost)
    }
    for try await summary in try await client.accountSummary(tags: ["NetLiquidation", "TotalCashValue", "BuyingPower"]) {
        for value in summary { print("Summary:", value.account, value.tag, value.value, value.currency) }
        break   // the first whole set is enough; leaving the loop cancels the subscription
    }
} catch {
    print("Failed:", error)
    await client.disconnect()
    exit(1)
}
await client.disconnect()
