import NIO
import Foundation

class EventLoop {
    private var pendingOperations = 0
    private let pendingOperationsLock = NSLock()
    private let group: NIO.EventLoopGroup
    private let eventLoopPromise: EventLoopPromise<Void>?
    private var idleCheckTask: RepeatedTask?

    // Access to the underlying NIO event loop
    var eventLoop: NIO.EventLoop {
        return group.next()
    }

    init() {
        // Create a single-threaded event loop group
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopPromise = nil
    }

    deinit {
        // Cancel any pending idle check task
        idleCheckTask?.cancel()

        // Try to shut down the event loop group gracefully
        try? group.syncShutdownGracefully()
    }

    func incrementPendingOperations() {
        pendingOperationsLock.lock()
        pendingOperations += 1
        pendingOperationsLock.unlock()
    }

    func decrementPendingOperations() {
        pendingOperationsLock.lock()
        pendingOperations -= 1
        let isNowIdle = pendingOperations == 0
        pendingOperationsLock.unlock()

        if isNowIdle {
            notifyIdle()
        }
    }

    func getPendingOperationsCount() -> Int {
        pendingOperationsLock.lock()
        let count = pendingOperations
        pendingOperationsLock.unlock()
        return count
    }

    func waitForPendingOperations(timeout: TimeInterval = 60.0) -> Bool {
        // If already idle, return immediately
        if getPendingOperationsCount() == 0 {
            return true
        }

        // Create a semaphore to wait on
        let semaphore = DispatchSemaphore(value: 0)

        // Create a cancellable task that will signal when idle
        scheduleIdleCheck(semaphore: semaphore)

        // Wait for the semaphore with timeout
        let result = semaphore.wait(timeout: .now() + timeout) == .success

        // If we timed out, cancel the task
        if !result {
            idleCheckTask?.cancel()
        }

        return result
    }

    // Schedule tasks on the event loop
    func schedule<T>(delay: TimeInterval = 0, task: @escaping () -> T) -> EventLoopFuture<T> {
        return eventLoop.scheduleTask(in: .milliseconds(Int64(delay * 1000))) {
            return task()
        }.futureResult
    }

    // Execute a task on the event loop and return a future
    func execute<T>(_ task: @escaping () -> T) -> EventLoopFuture<T> {
        return eventLoop.submit(task)
    }

    // Execute a task that might throw
    func execute<T>(_ task: @escaping () throws -> T) -> EventLoopFuture<T> {
        return eventLoop.submit(task)
    }

    // Private helper methods
    private func scheduleIdleCheck(semaphore: DispatchSemaphore) {
        // Store the task so we can cancel it if needed
        idleCheckTask = eventLoop.scheduleRepeatedTask(initialDelay: .milliseconds(100), delay: .milliseconds(100)) { task in
            if self.getPendingOperationsCount() == 0 {
                semaphore.signal()
                task.cancel()
            }
        }
    }

    private func notifyIdle() {
        // Override point for subclasses or to trigger notifications
    }
}
