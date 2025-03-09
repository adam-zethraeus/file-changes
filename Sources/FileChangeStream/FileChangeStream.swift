import CoreServices
import Foundation
import os

/// An AsyncSequence which emits when a file or folder is changed.
public final class FileChangeStream: AsyncSequence {
    public func makeAsyncIterator() -> AsyncThrowingStream<Element, any Error>.Iterator {
        builder().makeAsyncIterator()
    }
    
    public typealias AsyncIterator = AsyncThrowingStream<Element, any Error>.Iterator
    

    public typealias Failure = any Error
    public typealias Element = FileChangeEvent
    
    private let builder: () -> AsyncThrowingStream<Element, any Error>
    
    public init(_ urls: [URL]) throws {

        let missingList = urls.filter {
            !FileManager.default.fileExists(atPath: $0.path())
        }
        guard missingList.isEmpty else {
            throw MissingURLsError(urls: missingList)
        }
        
        builder = {
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Element.self)
            let callback: FileWatcher.CallBack = { event in
                continuation.yield(event)
            }
            let fileWatcher: FileWatcher = FileWatcher(urls.map(\.path), callback, DispatchQueue.global())
            do {
                let stop = try fileWatcher.start()
                continuation.onTermination = { _ in
                    stop()
                }
            } catch {
                continuation.finish(throwing: error)
            }
            return stream
        }
    }
}

public struct FileChangeEvent: Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    
    public enum ChangeType: Sendable, CustomStringConvertible {
        case created
        case modified
        case moved
        case removed
        public var description: String {
            switch self {
            case .created: return "created"
            case .modified: return "modified"
            case .moved: return "moved"
            case .removed: return "removed"
            }
        }
    }
    public enum ItemType: Sendable, CustomStringConvertible {
        case directory
        case file
        public var description: String {
            switch self {
            case .directory: return "directory"
            case .file: return "file"
            }
        }
    }
    
    public struct Info: Sendable {
        public let item: ItemType
        public let change: ChangeType
    }
    
    public let id: FSEventStreamEventId
    public let flags: FSEventStreamEventFlags
    public let url: URL
    public let info: Info?
    
    public var debugDescription: String {
        """
        FSEventStreamEvent #\(id), flags: \(flags)
        url: \(url)
        (\(info.map { "\($0.item) \($0.change)" } ?? "unknown"))
        """
    }
    
    public var description: String {
        "\(info.map { "\($0.item) \($0.change)" } ?? "changed"): \(url.standardized)"
    }
    
    init(_ eventId: FSEventStreamEventId, _ path: String, _ flags: FSEventStreamEventFlags) {
        self.id = eventId
        self.flags = flags
        let fileChange: Bool = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile)) != 0
        let dirChange: Bool = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)) != 0
        let created: Bool = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0
        let removed: Bool = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)) != 0
        let moved: Bool = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)) != 0
        let modified: Bool = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)) != 0
        
        let item: ItemType? = if fileChange {
            .file
        } else if dirChange {
            .directory
        } else {
            nil
        }
        let change: ChangeType? = if created {
            .created
        } else if removed {
            .removed
        } else if modified {
            .modified
        } else if moved {
            .moved
        } else {
            nil
        }
        self.info = if let item, let change {
            .init(item: item, change: change)
        } else {
            nil
        }
        self.url = URL(filePath: path)
    }
}

public struct MissingURLsError: Error {
    public let urls: [URL]
}
public struct FSEventStreamSetupFailure: Error {}

private final class FileWatcher: Sendable {
    let callback: CallBack
    let queue: DispatchQueue
    let filePaths: [String]

    init(
            _ paths: [String],
            _ callback: @escaping CallBack,
            _ queue: DispatchQueue
    ) {
        self.filePaths = paths
        self.callback = callback
        self.queue = queue
    }
    /// - Parameters:
    ///   - streamRef: The stream for which event(s) occurred. clientCallBackInfo:
    ///     The info field that was supplied in the context when this stream was created.
    ///   - numEvents:  The number of events being reported in this callback.
    ///     Each of the arrays (eventPaths, eventFlags, eventIds) will have this many elements.
    ///   - eventPaths: An array of paths to the directories in which event(s) occurred
    ///     The type of this parameter depends on the flags
    ///   - eventFlags: An array of flag words corresponding to the paths in the eventPaths parameter.
    ///     If no flags are set, then there was some change in the directory at the specific path supplied in this event.
    ///     See FSEventStreamEventFlags.
    ///   - eventIds: An array of FSEventStreamEventIds corresponding to the paths in the eventPaths parameter.
    ///     Each event ID comes from the most recent event being reported in the corresponding directory named
    ///     in the eventPaths parameter.
    let eventCallback: FSEventStreamCallback = {(
            stream: ConstFSEventStreamRef,
            contextInfo: UnsafeMutableRawPointer?,
            numEvents: Int,
            eventPaths: UnsafeMutableRawPointer,
            eventFlags: UnsafePointer<FSEventStreamEventFlags>,
            eventIds: UnsafePointer<FSEventStreamEventId>
    ) in
        let fileSystemWatcher = Unmanaged<FileWatcher>.fromOpaque(contextInfo!).takeUnretainedValue()
        let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

        (0..<numEvents).indices.forEach { index in
            let event = FileChangeEvent(eventIds[index], paths[index], eventFlags[index])
            fileSystemWatcher.callback(event)
        }

    }

    let retainCallback: CFAllocatorRetainCallBack = {(info: UnsafeRawPointer?) in
        _ = Unmanaged<FileWatcher>.fromOpaque(info!).retain()
        return info
    }

    let releaseCallback: CFAllocatorReleaseCallBack = {(info: UnsafeRawPointer?) in
        Unmanaged<FileWatcher>.fromOpaque(info!).release()
    }
    
    typealias CallBack = @Sendable (_ changeEvent: FileChangeEvent) -> Void
    func start() throws -> @Sendable () -> Void {
        var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: retainCallback,
                release: releaseCallback,
                copyDescription: nil
        )
        let streamRef = try FSEventStreamCreate(
                kCFAllocatorDefault,
                eventCallback,
                &context,
                filePaths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0,
                UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ).tryUnwrap(FSEventStreamSetupFailure())
        FSEventStreamSetDispatchQueue(streamRef, queue)
        FSEventStreamStart(streamRef)
        let locked = OSAllocatedUnfairLock<OpaquePointer?>(uncheckedState: streamRef)
        return {
            guard let streamRef = locked.withLockUnchecked({ ref in
                defer { ref = nil }
                return ref
            }) else { return }
            FSEventStreamStop(streamRef)
            FSEventStreamInvalidate(streamRef)
            FSEventStreamRelease(streamRef)
        }
    }
}

extension Optional {
    func tryUnwrap<E: Error>(_ error: @autoclosure () -> E) throws(E) -> Wrapped {
        guard let value = self else {
            throw error()
        }
        return value
    }
}
