import Foundation
import CoreServices

// MARK: - FSEvents Watcher

/// Watches an AppMD app directory for file changes using macOS FSEvents.
/// Detects external changes and re-indexes files.
public final class FSEventsWatcher: @unchecked Sendable {

    /// The directory being watched.
    public let watchURL: URL

    /// The AppMD index to update on changes.
    private weak var index: AppMDIndex?

    /// Callback invoked when files change.
    public var onChange: (([URL]) -> Void)?

    /// The FSEvents stream reference.
    private var stream: FSEventStreamRef?

    /// Whether the watcher is currently active.
    public private(set) var isWatching: Bool = false

    // Debounce timer
    private var pendingURLs: Set<URL> = []
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.3

    // MARK: - Init

    public init(watchURL: URL, index: AppMDIndex? = nil) {
        self.watchURL = watchURL
        self.index = index
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    /// Start watching for file changes.
    public func start() {
        guard !isWatching else { return }

        let pathString = watchURL.path as CFString
        let pathsToWatch = [pathString] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // latency in seconds
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        isWatching = true
    }

    /// Stop watching for file changes.
    public func stop() {
        guard isWatching, let stream = stream else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        isWatching = false

        debounceTimer?.invalidate()
        debounceTimer = nil
    }

    // MARK: - Internal

    /// Handle an FSEvents event for a set of paths.
    func handleEvents(paths: [String], flags: [UInt32]) {
        var changedURLs: [URL] = []

        for (i, path) in paths.enumerated() {
            let url = URL(fileURLWithPath: path)

            // Only care about .md files
            guard url.pathExtension == "md" else { continue }

            // Skip hidden files and cache
            let components = url.pathComponents
            if components.contains(where: { $0.hasPrefix(".") }) { continue }

            let eventFlags = flags[i]

            // Check if this is a file creation, modification, or removal
            let isModified = (eventFlags & UInt32(kFSEventStreamEventFlagItemModified)) != 0
            let isCreated = (eventFlags & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
            let isRemoved = (eventFlags & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0
            let isRenamed = (eventFlags & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0

            guard isModified || isCreated || isRemoved || isRenamed else { continue }

            // Check if this is our own write (bounce-back prevention)
            if let index = index, !isRemoved {
                if index.isOurWrite(for: url) {
                    continue // Skip — we wrote this
                }
            }

            changedURLs.append(url)

            // Re-index the file
            if isRemoved {
                try? index?.removeFile(at: url)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try? index?.indexFile(at: url)
            }
        }

        if !changedURLs.isEmpty {
            // Debounce the onChange callback
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.pendingURLs.formUnion(changedURLs)
                self.debounceTimer?.invalidate()
                self.debounceTimer = Timer.scheduledTimer(withTimeInterval: self.debounceInterval, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    let urls = Array(self.pendingURLs)
                    self.pendingURLs.removeAll()
                    self.onChange?(urls)
                    self.index?.onIndexUpdated?()
                }
            }
        }
    }
}

// MARK: - FSEvents C Callback

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()

    // Get paths from CFArray
    let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    var paths: [String] = []
    var flags: [UInt32] = []

    for i in 0..<numEvents {
        if let cfPath = CFArrayGetValueAtIndex(cfPaths, i) {
            let path = Unmanaged<CFString>.fromOpaque(cfPath).takeUnretainedValue() as String
            paths.append(path)
            flags.append(eventFlags[i])
        }
    }

    watcher.handleEvents(paths: paths, flags: flags)
}
