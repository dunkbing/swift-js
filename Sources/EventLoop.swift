import Foundation
import JavaScriptCore

class EventLoop {
    private var pendingOperations = 0
    private let pendingOperationsLock = NSLock()

    static let idleNotification = NSNotification.Name("EventLoopIdle")

    func incrementPendingOperations() {
        pendingOperationsLock.lock()
        pendingOperations += 1
        pendingOperationsLock.unlock()
    }

    func decrementPendingOperations() {
        pendingOperationsLock.lock()
        pendingOperations -= 1
        let remaining = pendingOperations
        pendingOperationsLock.unlock()

        if remaining == 0 {
            NotificationCenter.default.post(name: EventLoop.idleNotification, object: nil)
        }
    }

    func getPendingOperationsCount() -> Int {
        pendingOperationsLock.lock()
        let count = pendingOperations
        pendingOperationsLock.unlock()
        return count
    }

    func waitForPendingOperations(timeout: TimeInterval = 60.0) -> Bool {
        if getPendingOperationsCount() == 0 {
            return true
        }

        let semaphore = DispatchSemaphore(value: 0)

        let observer = NotificationCenter.default.addObserver(
            forName: EventLoop.idleNotification,
            object: nil,
            queue: nil
        ) { _ in
            semaphore.signal()
        }

        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        return semaphore.wait(timeout: .now() + timeout) == .success
    }
}
