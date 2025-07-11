import Dispatch
import ErrorHandle

@inlinable
public func asyncResultToSync<T, E>(
    action: @escaping @Sendable () async -> Result<T, E>
) -> T where T: Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, E>! = nil
    Task {
        result = await action()
        semaphore.signal()
    }
    semaphore.wait()
    switch result {
    case .success(let storage): return storage
    case .failure(let error): fatalError(String(reflecting: error))
    case .none: fatalError()
    }
}

@inlinable
public func asyncToSync<T, E>(
    action: @escaping @Sendable () async throws(E) -> T
) -> T where T: Sendable {
    asyncResultToSync {
        await .async { () throws(E) in
            try await action()
        }
    }
}

@inlinable
public func fatalIfFail<T>(
    action: () throws -> T
) -> T {
    do {
        return try action()
    } catch {
        fatalError(String(reflecting: error))
    }
}
