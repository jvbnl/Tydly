import Darwin
import Foundation

package final class RootCapabilityProcessLock: @unchecked Sendable {
    private let descriptor: Int32
    private let lock = NSLock()
    private var isClosed = false

    package init(databasePath: String) throws {
        let lockPath = databasePath + ".capability-lock"
        descriptor = Darwin.open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw LedgerStoreError.synchronizationFailed(errno)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let status = errno
            Darwin.close(descriptor)
            if status == EWOULDBLOCK {
                throw LedgerStoreError.rootCapabilityBusy
            }
            throw LedgerStoreError.synchronizationFailed(status)
        }
    }

    package func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        _ = flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }

    deinit {
        close()
    }
}
