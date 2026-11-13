#if os(macOS) || os(Linux) || os(Windows)
import Foundation

/// What a `Watchdog` reports on `events()`, as `ib_async`'s six Watchdog events.
public enum WatchdogEvent: Sendable, Equatable, Encodable {
    /// `start()` was called; a restart does not emit it again.
    case starting
    /// The client connected to the app the Watchdog started.
    case started
    /// `stop()` was called.
    case stopping
    /// A round ended: the client is disconnected and the app terminated.
    case stopped
    /// The connection was silent for `appTimeout`; the probe went out.
    case softTimeout
    /// The probe got no answer within `probeTimeout`; the app is restarted.
    case hardTimeout
}

/// Starts TWS or IB Gateway through an `IBC`, connects `client` to it and keeps it up, as `ib_async`'s `Watchdog`:
/// after `appTimeout` of silence it probes the app, and restarts the app (terminate, wait `retryDelay`, start,
/// wait `appStartupTime`, connect) when the probe gets no answer, on IB's error 100 or 1100, or when the
/// connection drops. macOS, Linux and Windows only. The client must not be connected, and is not to be connected
/// or disconnected by anyone else while the Watchdog runs. Its log lines go to `client`'s log handler.
public actor Watchdog {
    /// Starts and terminates the app.
    public nonisolated let controller: IBC
    /// The client the Watchdog connects on every round.
    public nonisolated let client: IBClient
    /// Where the app listens.
    public nonisolated let host: String
    /// The app's API port.
    public nonisolated let port: Int
    /// The client id to connect with.
    public nonisolated let clientID: Int
    /// How long each connect may take.
    public nonisolated let connectTimeout: Duration
    /// What each connect is given (`ib_async`'s `readonly`, `account` and `raiseSyncErrors` among them).
    public nonisolated let options: ConnectOptions
    /// The pause after starting the app before connecting to it.
    public nonisolated let appStartupTime: Duration
    /// The silence after which the app is probed.
    public nonisolated let appTimeout: Duration
    /// The pause after the app is terminated before it is started again.
    public nonisolated let retryDelay: Duration
    /// `nil` probes with `currentTime()`; a contract probes with `ib_async`'s history request instead (30 S of
    /// 5-second MIDPOINT bars outside regular hours), whose first batch must hold a bar.
    public nonisolated let probeContract: Contract?
    /// How long the probe may take.
    public nonisolated let probeTimeout: Duration

    private var runner: Task<Void, Never>?
    private var subscribers = Subscribers<WatchdogEvent>()

    /// Keeps the settings; nothing starts until `start()`.
    public init(controller: IBC, client: IBClient, host: String = "127.0.0.1", port: Int = 7497, clientID: Int = 1,
                connectTimeout: Duration = .seconds(2), options: ConnectOptions = .init(),
                appStartupTime: Duration = .seconds(30), appTimeout: Duration = .seconds(20),
                retryDelay: Duration = .seconds(2), probeContract: Contract? = nil, probeTimeout: Duration = .seconds(4)) {
        (self.controller, self.client, self.host, self.port, self.clientID) = (controller, client, host, port, clientID)
        (self.connectTimeout, self.options, self.appStartupTime) = (connectTimeout, options, appStartupTime)
        (self.appTimeout, self.retryDelay, self.probeContract) = (appTimeout, retryDelay, probeContract)
        self.probeTimeout = probeTimeout
    }

    /// A fresh stream on every call, of the events from now on.
    public func events() -> AsyncStream<WatchdogEvent> {
        subscribers.stream { [weak self] id in Task { await self?.unsubscribe(id) } }
    }

    private func unsubscribe(_ id: Int) { subscribers.remove(id) }

    /// Emits `.starting` and starts the loop. Throws `.alreadyConnected` while it runs or unless the client is
    /// disconnected.
    public func start() async throws(IBClientError) {
        guard case .disconnected = await client.state, runner == nil else { throw .alreadyConnected }
        subscribers.yield(.starting)
        runner = Task { await run() }
    }

    /// Emits `.stopping`, disconnects the client and ends the loop, which terminates the app and emits `.stopped`;
    /// returns once it has.
    public func stop() async {
        subscribers.yield(.stopping)
        let runner = self.runner
        self.runner = nil
        runner?.cancel()   // first: the disconnect must not look like a drop to restart from
        await client.disconnect()
        await runner?.value
    }

    /// The rounds, until cancelled. Each round ends the same way, once: disconnect, terminate, `.stopped`.
    private func run() async {
        repeat {
            do {
                try Task.checkCancellation()
                try await controller.start(logTo: client)
                try await Task.sleep(for: appStartupTime)
                try await client.connect(host: host, port: port, clientID: clientID, timeout: connectTimeout,
                                         options: options)
                subscribers.yield(.started)
                try await watch()
            } catch {
                if !Task.isCancelled { client.log(.warning, "Watchdog: \(error)") }
            }
            await client.disconnect()
            await controller.terminate()
            subscribers.yield(.stopped)
            try? await Task.sleep(for: retryDelay)
        } while !Task.isCancelled
    }

    private enum Signal { case idle, restart(String) }
    private struct Restart: Error, CustomStringConvertible { let description: String }

    /// Returns only when cancelled; throws `Restart` when the app is to be restarted.
    private func watch() async throws {
        let (signals, out) = AsyncStream.makeStream(of: Signal.self)
        let (idle, messages, states) = (await client.idleTimeouts(after: appTimeout), await client.messages(),
                                        await client.states())
        // Each feeder's stream ends with its task, which unsubscribes it.
        let feeders = [
            Task { for await _ in idle { out.yield(.idle) } },
            Task {
                for await case .error(let e) in messages where e.code == 100 || e.code == 1100 {
                    out.yield(.restart("Error \(e.code)"))
                }
            },
            Task { for await case .disconnected in states { out.yield(.restart("Disconnected")) } },
        ]
        defer { feeders.forEach { $0.cancel() } }
        for await signal in signals {   // ends when cancelled
            if case .restart(let why) = signal { throw Restart(description: why) }
            subscribers.yield(.softTimeout)
            let answered = await probe()
            if Task.isCancelled { return }   // stop() cut the probe short
            guard answered else {
                subscribers.yield(.hardTimeout)
                throw Restart(description: "Hard timeout")
            }
        }
    }

    /// Whether the app answers the probe within `probeTimeout`.
    private func probe() async -> Bool {
        let (client, contract, timeout) = (client, probeContract, probeTimeout)
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                guard let contract else { return (try? await client.currentTime()) != nil }
                guard let bars = try? await client.historicalBars(contract, duration: "30 S", barSize: "5 secs",
                                                                  whatToShow: "MIDPOINT", rth: false) else { return false }
                do { for try await case .history(let batch) in bars { return !batch.isEmpty } } catch {}
                return false
            }
            group.addTask { try? await Task.sleep(for: timeout); return false }
            let answered = await group.next() ?? false
            group.cancelAll()
            return answered
        }
    }
}
#endif
