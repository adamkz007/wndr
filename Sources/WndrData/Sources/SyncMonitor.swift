import CoreData
import CryptoKit
import Dispatch
import Foundation

public actor SyncMonitor {
    private struct VisibleFileInfo {
        let fileURL: URL
        let collectionName: String?
        let title: String
        let documentType: String
        let finderTags: [String]
    }

    private let persistenceController: PersistenceController
    private let libraryStore: LibraryRootStore
    private let importService: ImportService
    private let logger: WndrLogger
    private let fileManager: FileManager
    private let onDidSync: (@Sendable () async -> Void)?

    private var monitoredLibraryURL: URL?
    private var rootFileDescriptor: CInt = -1
    private var eventSource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private var pendingDebounceTask: Task<Void, Never>?
    private var isReconciling = false
    private var needsAnotherPass = false
    private var lastVisibleStateFingerprint: String?

    public init(
        persistenceController: PersistenceController,
        libraryStore: LibraryRootStore,
        importService: ImportService,
        logger: WndrLogger = WndrLogger(category: "sync-monitor"),
        fileManager: FileManager = .default,
        onDidSync: (@Sendable () async -> Void)? = nil
    ) {
        self.persistenceController = persistenceController
        self.libraryStore = libraryStore
        self.importService = importService
        self.logger = logger
        self.fileManager = fileManager
        self.onDidSync = onDidSync
    }

    deinit {
        pendingDebounceTask?.cancel()
        eventSource?.cancel()
        pollTimer?.cancel()
        if rootFileDescriptor >= 0 {
            close(rootFileDescriptor)
        }
    }

    public func startMonitoring(libraryURL: URL) {
        let standardizedURL = libraryURL.standardizedFileURL
        if monitoredLibraryURL == standardizedURL {
            scheduleReconcile(reason: "restart-existing-library")
            return
        }

        stopMonitoring()
        monitoredLibraryURL = standardizedURL

        let fd = open(standardizedURL.path, O_EVTONLY)
        if fd >= 0 {
            rootFileDescriptor = fd
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .attrib, .extend],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                Task {
                    await self?.scheduleReconcile(reason: "filesystem-event")
                }
            }
            source.setCancelHandler { [fd] in
                close(fd)
            }
            source.resume()
            eventSource = source
        } else {
            logger.error("Failed to open library root for filesystem monitoring: \(standardizedURL.path)")
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5))
        timer.setEventHandler { [weak self] in
            Task {
                await self?.scheduleReconcile(reason: "poll")
            }
        }
        timer.resume()
        pollTimer = timer

        scheduleReconcile(reason: "initial-start")
        logger.info("Started sync monitor for \(standardizedURL.path)")
    }

    public func stopMonitoring() {
        pendingDebounceTask?.cancel()
        pendingDebounceTask = nil

        eventSource?.cancel()
        eventSource = nil

        pollTimer?.cancel()
        pollTimer = nil

        if rootFileDescriptor >= 0 {
            rootFileDescriptor = -1
        }

        monitoredLibraryURL = nil
        isReconciling = false
        needsAnotherPass = false
        lastVisibleStateFingerprint = nil
    }

    public func scheduleReconcile(reason: String) {
        guard monitoredLibraryURL != nil else { return }
        pendingDebounceTask?.cancel()
        pendingDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await reconcileLibrary(reason: reason)
        }
    }

    public func reconcileLibrary(reason: String = "manual") async {
        guard let libraryURL = monitoredLibraryURL else { return }
        if isReconciling {
            needsAnotherPass = true
            return
        }

        isReconciling = true
        defer {
            isReconciling = false
        }

        logger.info("Reconciling library state (\(reason))")

        let forceReconcileReasons: Set<String> = ["initial-start", "manual", "restart-existing-library"]
        let shouldForceReconcile = forceReconcileReasons.contains(reason)
        if !shouldForceReconcile {
            let fingerprint = await computeVisibleStateFingerprint(in: libraryURL)
            if fingerprint == lastVisibleStateFingerprint {
                logger.debug("Skipping reconcile because visible library state is unchanged")
                return
            }
            lastVisibleStateFingerprint = fingerprint
        }

        var shouldNotify = false
        do {
            let visibleFiles = await enumerateVisibleFiles(in: libraryURL)
            let didChange = try await reconcileExistingDocuments(with: visibleFiles, in: libraryURL)
            let didImport = await importNewFiles(from: visibleFiles, in: libraryURL)
            shouldNotify = didChange || didImport
            if shouldForceReconcile {
                lastVisibleStateFingerprint = await computeVisibleStateFingerprint(in: libraryURL)
            }
        } catch {
            logger.error("Library reconciliation failed: \(error.localizedDescription)")
        }

        if shouldNotify {
            await onDidSync?()
        }

        if needsAnotherPass {
            needsAnotherPass = false
            await reconcileLibrary(reason: "follow-up")
        }
    }

    private func computeVisibleStateFingerprint(in libraryURL: URL) async -> String {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .attributeModificationDateKey
        ]

        var entries: [String] = []

        if let rootEntries = try? fileManager.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) {
            for entry in rootEntries {
                guard let values = try? entry.resourceValues(forKeys: resourceKeys) else {
                    continue
                }

                if values.isRegularFile == true, isSupportedDocumentFile(entry) {
                    entries.append(snapshotEntry(for: entry, values: values, relativeTo: libraryURL))
                    continue
                }

                guard values.isDirectory == true else { continue }
                if libraryStore.isReservedTopLevelDirectoryName(entry.lastPathComponent) {
                    continue
                }

                entries.append(snapshotEntry(for: entry, values: values, relativeTo: libraryURL))

                if let enumerator = fileManager.enumerator(
                    at: entry,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let fileURL as URL in enumerator where isSupportedDocumentFile(fileURL) {
                        guard let fileValues = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                            continue
                        }
                        entries.append(snapshotEntry(for: fileURL, values: fileValues, relativeTo: libraryURL))
                    }
                }
            }
        }

        let inboxURL = await libraryStore.url(for: .inbox, in: libraryURL)
        if let inboxFiles = try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in inboxFiles where isSupportedDocumentFile(fileURL) {
                guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                    continue
                }
                entries.append(snapshotEntry(for: fileURL, values: values, relativeTo: libraryURL))
            }
        }

        return entries.sorted().joined(separator: "\n")
    }

    private func snapshotEntry(for url: URL, values: URLResourceValues, relativeTo libraryURL: URL) -> String {
        let relativePath = url.path.replacingOccurrences(of: libraryURL.path + "/", with: "")
        let fileSize = values.fileSize ?? 0
        let contentDate = values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let attributeDate = values.attributeModificationDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(relativePath)|\(fileSize)|\(contentDate)|\(attributeDate)"
    }

    private func enumerateVisibleFiles(in libraryURL: URL) async -> [VisibleFileInfo] {
        var files: [VisibleFileInfo] = []

        if let rootEntries = try? fileManager.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in rootEntries {
                guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
                    continue
                }

                if values.isRegularFile == true, isSupportedDocumentFile(entry) {
                    files.append(await visibleFileInfo(for: entry, collectionName: nil))
                    continue
                }

                guard values.isDirectory == true else { continue }
                if libraryStore.isReservedTopLevelDirectoryName(entry.lastPathComponent) {
                    continue
                }

                if let enumerator = fileManager.enumerator(
                    at: entry,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let fileURL as URL in enumerator where isSupportedDocumentFile(fileURL) {
                        files.append(await visibleFileInfo(for: fileURL, collectionName: entry.lastPathComponent))
                    }
                }
            }
        }

        let inboxURL = await libraryStore.url(for: .inbox, in: libraryURL)
        if let inboxFiles = try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in inboxFiles where isSupportedDocumentFile(fileURL) {
                if !files.contains(where: { $0.fileURL.standardizedFileURL == fileURL.standardizedFileURL }) {
                    files.append(await visibleFileInfo(for: fileURL, collectionName: nil))
                }
            }
        }

        return files.sorted { $0.fileURL.path.localizedStandardCompare($1.fileURL.path) == .orderedAscending }
    }

    private func visibleFileInfo(for fileURL: URL, collectionName: String?) async -> VisibleFileInfo {
        VisibleFileInfo(
            fileURL: fileURL,
            collectionName: collectionName,
            title: fileURL.deletingPathExtension().lastPathComponent,
            documentType: fileURL.pathExtension.lowercased(),
            finderTags: await libraryStore.readFinderTags(from: fileURL)
        )
    }

    private func reconcileExistingDocuments(with visibleFiles: [VisibleFileInfo], in libraryURL: URL) async throws -> Bool {
        let context = persistenceController.newBackgroundContext()
        let request = Document.fetchRequest()
        let documents = try context.fetch(request)

        let visiblePaths = Dictionary(uniqueKeysWithValues: visibleFiles.map { ($0.fileURL.standardizedFileURL.path, $0) })
        var documentsByChecksum: [String: [Document]] = [:]
        for document in documents {
            if let checksum = document.checksum {
                documentsByChecksum[checksum, default: []].append(document)
            }
        }

        var matchedDocumentIDs = Set<UUID>()
        var changed = false
        var unmatchedFiles: [VisibleFileInfo] = []

        for info in visibleFiles {
            if let document = documents.first(where: { $0.fileURL?.standardizedFileURL.path == info.fileURL.standardizedFileURL.path }) {
                changed = try reconcile(document: document, with: info, in: context) || changed
                if let id = document.id {
                    matchedDocumentIDs.insert(id)
                }
                continue
            }

            let checksum = try calculateChecksum(for: info.fileURL)
            if let candidate = documentsByChecksum[checksum]?.first(where: { document in
                guard let id = document.id else { return false }
                return !matchedDocumentIDs.contains(id)
            }) {
                changed = try reconcile(document: candidate, with: info, in: context) || changed
                if let id = candidate.id {
                    matchedDocumentIDs.insert(id)
                }
            } else {
                unmatchedFiles.append(info)
            }
        }

        for document in documents {
            guard let id = document.id, !matchedDocumentIDs.contains(id) else { continue }
            guard let fileURL = document.fileURL else {
                context.delete(document)
                changed = true
                continue
            }

            let standardizedPath = fileURL.standardizedFileURL.path
            if visiblePaths[standardizedPath] != nil {
                continue
            }

            if !fileManager.fileExists(atPath: fileURL.path) {
                context.delete(document)
                changed = true
            }
        }

        changed = try reconcileCollectionFolders(in: context, visibleFiles: visibleFiles) || changed

        if context.hasChanges {
            try context.save()
        }

        pendingImports = unmatchedFiles
        return changed
    }

    private var pendingImports: [VisibleFileInfo] {
        get { _pendingImports }
        set { _pendingImports = newValue }
    }

    private var _pendingImports: [VisibleFileInfo] = []

    private func importNewFiles(from visibleFiles: [VisibleFileInfo], in libraryURL: URL) async -> Bool {
        guard !_pendingImports.isEmpty else { return false }

        var importedAny = false
        for info in _pendingImports {
            do {
                _ = try await importService.importDocument(from: info.fileURL, in: libraryURL, copyFile: false)
                importedAny = true
            } catch ImportService.ImportError.duplicateDocument {
                continue
            } catch {
                logger.error("Failed to import externally added file \(info.fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        _pendingImports = []
        return importedAny
    }

    private func reconcile(document: Document, with info: VisibleFileInfo, in context: NSManagedObjectContext) throws -> Bool {
        var changed = false

        if document.fileURL?.standardizedFileURL != info.fileURL.standardizedFileURL {
            document.fileURL = info.fileURL
            changed = true
        }

        if document.title != info.title {
            document.title = info.title
            changed = true
        }

        if document.documentType?.lowercased() != info.documentType {
            document.documentType = info.documentType
            changed = true
        }

        changed = try reconcileCollection(for: document, collectionName: info.collectionName, in: context) || changed
        changed = try reconcileTags(for: document, tagNames: info.finderTags, in: context) || changed

        if changed {
            document.updatedAt = Date()
        }

        return changed
    }

    private func reconcileCollection(
        for document: Document,
        collectionName: String?,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let existingCollections = (document.collections as? Set<DocumentCollection>) ?? []
        let existingName = existingCollections.first?.name

        if existingName == collectionName {
            return false
        }

        for collection in existingCollections {
            collection.removeFromDocuments(document)
        }

        if let collectionName {
            let collection = try findOrCreateCollection(named: collectionName, in: context)
            collection.addToDocuments(document)
        }

        return true
    }

    private func reconcileTags(for document: Document, tagNames: [String], in context: NSManagedObjectContext) throws -> Bool {
        let normalizedNames = Set(tagNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let existingTags = (document.tags as? Set<Tag>) ?? []
        let existingNames = Set(existingTags.compactMap(\.name))

        guard normalizedNames != existingNames else {
            return false
        }

        for tag in existingTags {
            tag.removeFromDocuments(document)
        }

        for tagName in normalizedNames.sorted() {
            let tag = try findOrCreateTag(named: tagName, in: context)
            tag.addToDocuments(document)
        }

        return true
    }

    private func reconcileCollectionFolders(in context: NSManagedObjectContext, visibleFiles: [VisibleFileInfo]) throws -> Bool {
        let visibleCollectionNames = Set(visibleFiles.compactMap(\.collectionName))
        let request = DocumentCollection.fetchRequest()
        let collections = try context.fetch(request)
        var changed = false

        for collectionName in visibleCollectionNames {
            _ = try findOrCreateCollection(named: collectionName, in: context)
        }

        for collection in collections {
            guard collection.kind == CollectionKind.manual.rawValue,
                  let name = collection.name else { continue }

            let docCount = (collection.documents as? Set<Document>)?.count ?? 0
            let noteCount = (collection.notes as? Set<Note>)?.count ?? 0
            if !visibleCollectionNames.contains(name), docCount == 0, noteCount == 0 {
                context.delete(collection)
                changed = true
            }
        }

        return changed
    }

    private func findOrCreateCollection(named name: String, in context: NSManagedObjectContext) throws -> DocumentCollection {
        let request = DocumentCollection.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1

        if let existing = try context.fetch(request).first {
            return existing
        }

        let countRequest = DocumentCollection.fetchRequest()
        let count = (try? context.count(for: countRequest)) ?? 0

        let collection = DocumentCollection(context: context)
        collection.id = UUID()
        collection.name = name
        collection.kind = CollectionKind.manual.rawValue
        collection.sortOrder = Int32(count)
        collection.createdAt = Date()
        return collection
    }

    private func findOrCreateTag(named name: String, in context: NSManagedObjectContext) throws -> Tag {
        let request = Tag.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1

        if let existing = try context.fetch(request).first {
            return existing
        }

        let tag = Tag(context: context)
        tag.id = UUID()
        tag.name = name
        tag.createdAt = Date()
        return tag
    }

    private func calculateChecksum(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func isSupportedDocumentFile(_ fileURL: URL) -> Bool {
        guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else {
            return false
        }
        return ["pdf", "epub"].contains(fileURL.pathExtension.lowercased())
    }
}
