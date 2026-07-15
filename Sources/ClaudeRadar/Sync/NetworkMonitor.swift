import Foundation
import Network
import AppKit

protocol NetworkMonitoring: Sendable {
    func start(_ recovered: @escaping @Sendable () -> Void)
    func stop()
}

final class NetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.acfufu.ClaudeRadar.network")
    private let lock = NSLock()
    private var wasSatisfied: Bool?

    func start(_ recovered: @escaping @Sendable () -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.lock()
            let isSatisfied = path.status == .satisfied
            let shouldNotify = isSatisfied && wasSatisfied == false
            wasSatisfied = isSatisfied
            lock.unlock()
            if shouldNotify { recovered() }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}

protocol SleepRecoveryNotifying: Sendable {
    func start(_ recovered: @escaping @Sendable () -> Void)
    func stop()
}

final class SleepRecoveryNotifier: SleepRecoveryNotifying, @unchecked Sendable {
    private let center: NotificationCenter
    private let lock = NSLock()
    private var observer: NSObjectProtocol?

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    func start(_ recovered: @escaping @Sendable () -> Void) {
        lock.lock()
        observer = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { _ in recovered() }
        lock.unlock()
    }

    func stop() {
        lock.lock()
        if let observer { center.removeObserver(observer) }
        observer = nil
        lock.unlock()
    }
}
