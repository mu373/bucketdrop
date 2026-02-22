//
//  ContentView.swift
//  BucketDrop
//
//  Created by Fayaz Ahmed Aralikatti on 12/01/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit
import Quartz
import Combine

// Model to track individual file upload state
struct UploadTask: Identifiable {
    let id = UUID()
    let filename: String
    let url: URL
    var progress: Double = 0
    var status: UploadStatus = .pending
    var resultURL: String?

    enum UploadStatus {
        case pending
        case uploading
        case completed
        case failed(String)
    }
}

private enum ContentTab: String {
    case drop = "Drop"
    case list = "List"
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettingsAction) private var openSettings

    @Query(sort: [SortDescriptor(\BucketConfig.sortOrder), SortDescriptor(\BucketConfig.name)])
    private var configs: [BucketConfig]

    @State private var selectedTab: ContentTab = .drop
    @State private var targetedConfigIDs: Set<UUID> = []
    @State private var uploadTasksByConfig: [UUID: [UploadTask]] = [:]

    @State private var errorMessage: String?
    @State private var copyToastMessage: String?

    // List tab state - live S3 objects
    @State private var s3ObjectsByConfig: [UUID: [S3Object]] = [:]
    @State private var isLoadingList = false

    // Download/Preview state
    @State private var downloadingToken: String?
    @State private var downloadProgress: Double = 0

    private var configByID: [UUID: BucketConfig] {
        Dictionary(uniqueKeysWithValues: configs.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            Picker(selection: $selectedTab) {
                Text(ContentTab.drop.rawValue).tag(ContentTab.drop)
                Text(ContentTab.list.rawValue).tag(ContentTab.list)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        self.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if selectedTab == .drop {
                dropTabView
            } else {
                listTabView
            }
        }
        .frame(width: 360, height: 500)
        .overlay(alignment: .bottom) {
            if let copyToastMessage {
                Text(copyToastMessage)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(radius: 2)
                    )
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: configs.map(\.id)) { _, ids in
            let validIDs = Set(ids)
            uploadTasksByConfig = uploadTasksByConfig.filter { validIDs.contains($0.key) }
            targetedConfigIDs = targetedConfigIDs.filter { validIDs.contains($0) }
        }
    }

    private var headerView: some View {
        HStack {
            Text("BucketDrop")
                .font(.headline)
            Spacer()
            Button {
                openSettings()
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var dropTabView: some View {
        if configs.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "tray")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("No Drop Targets Configured")
                    .font(.headline)
                Text("Create at least one bucket configuration in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    openSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(configs) { config in
                        ConfigDropZoneView(
                            configName: displayName(for: config),
                            keyPrefix: config.keyPrefix,
                            isTargeted: targetedBinding(for: config.id),
                            uploadTasks: uploadTasksByConfig[config.id] ?? []
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .onTapGesture {
                            if !isUploading(configID: config.id) {
                                openFilePicker(for: config)
                            }
                        }
                        .onDrop(of: [.fileURL], isTargeted: targetedBinding(for: config.id)) { providers in
                            guard !isUploading(configID: config.id) else { return false }
                            NSApp.activate(ignoringOtherApps: true)
                            handleDrop(providers, config: config)
                            return true
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private var allS3Objects: [(object: S3Object, config: BucketConfig)] {
        var result: [(object: S3Object, config: BucketConfig)] = []
        for config in configs {
            if let objects = s3ObjectsByConfig[config.id] {
                result.append(contentsOf: objects.map { (object: $0, config: config) })
            }
        }
        return result.sorted { $0.object.lastModified > $1.object.lastModified }
    }

    @ViewBuilder
    private var listTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoadingList {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await loadAllS3Objects() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            let objects = allS3Objects
            if objects.isEmpty && !isLoadingList {
                VStack(spacing: 8) {
                    Text("No files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(objects, id: \.object.id) { item in
                        S3ObjectRowView(
                            object: item.object,
                            configName: displayName(for: item.config),
                            previewURL: previewURLForObject(item.object, config: item.config),
                            isDownloading: downloadingToken == item.object.key,
                            downloadProgress: downloadingToken == item.object.key ? downloadProgress : 0,
                            templateOptions: item.config.urlTemplates
                        ) {
                            copyObjectDefaultURL(item.object, config: item.config)
                        } onCopyTemplate: { template in
                            copyObjectTemplateURL(item.object, config: item.config, template: template)
                        } onDelete: {
                            await deleteObject(item.object, config: item.config)
                        } onDownload: {
                            await downloadObject(item.object, config: item.config)
                        } onPreview: {
                            previewObject(item.object, config: item.config)
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.never)
            }
        }
        .task(id: selectedTab) {
            if selectedTab == .list && s3ObjectsByConfig.isEmpty {
                await loadAllS3Objects()
            }
        }
    }

    private func loadAllS3Objects() async {
        isLoadingList = true
        var results: [UUID: [S3Object]] = [:]
        for config in configs {
            do {
                let objects = try await S3Service.shared.listObjects(config: config)
                results[config.id] = objects
            } catch {
                errorMessage = "\(displayName(for: config)): \(error.localizedDescription)"
            }
        }
        s3ObjectsByConfig = results
        isLoadingList = false
    }

    private func displayName(for config: BucketConfig) -> String {
        let trimmedName = trim(config.name)
        return trimmedName.isEmpty ? config.bucket : trimmedName
    }

    private func targetedBinding(for configID: UUID) -> Binding<Bool> {
        Binding(
            get: { targetedConfigIDs.contains(configID) },
            set: { isTargeted in
                if isTargeted {
                    targetedConfigIDs.insert(configID)
                } else {
                    targetedConfigIDs.remove(configID)
                }
            }
        )
    }

    private func isUploading(configID: UUID) -> Bool {
        guard let tasks = uploadTasksByConfig[configID], !tasks.isEmpty else {
            return false
        }

        return tasks.contains { task in
            switch task.status {
            case .pending, .uploading:
                return true
            case .completed, .failed:
                return false
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], config: BucketConfig) {
        let lock = NSLock()
        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                defer { group.leave() }
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                lock.lock()
                collectedURLs.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                await uploadFiles(collectedURLs, to: config)
            }
        }
    }

    private func openFilePicker(for config: BucketConfig) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK else { return }
                Task { @MainActor in
                    await uploadFiles(panel.urls, to: config)
                }
            }
        } else {
            let response = panel.runModal()
            guard response == .OK else { return }
            Task { @MainActor in
                await uploadFiles(panel.urls, to: config)
            }
        }
    }

    @MainActor
    private func uploadFiles(_ urls: [URL], to config: BucketConfig) async {
        guard !urls.isEmpty else { return }

        var tasks = urls.map { UploadTask(filename: $0.lastPathComponent, url: $0) }
        uploadTasksByConfig[config.id] = tasks
        errorMessage = nil

        var successfulURLs: [String] = []

        for index in tasks.indices {
            tasks[index].status = .uploading
            uploadTasksByConfig[config.id] = tasks

            do {
                let fileURL = tasks[index].url
                let result = try await S3Service.shared.upload(fileURL: fileURL, config: config) { progress in
                    Task { @MainActor in
                        guard var currentTasks = uploadTasksByConfig[config.id],
                              currentTasks.indices.contains(index) else {
                            return
                        }
                        currentTasks[index].progress = progress
                        uploadTasksByConfig[config.id] = currentTasks
                    }
                }

                let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0

                // Add to live S3 object list
                let newObject = S3Object(key: result.key, size: fileSize, lastModified: Date())
                if s3ObjectsByConfig[config.id] != nil {
                    s3ObjectsByConfig[config.id]?.insert(newObject, at: 0)
                } else {
                    s3ObjectsByConfig[config.id] = [newObject]
                }

                tasks[index].status = .completed
                tasks[index].progress = 1
                tasks[index].resultURL = result.url
                successfulURLs.append(result.url)

                let enabledActions = config.postUploadActions.filter { $0.enabled }
                if !enabledActions.isEmpty {
                    let metadata = UploadMetadata(
                        originalFilename: tasks[index].filename,
                        renamedFilename: (result.key as NSString).lastPathComponent,
                        s3Key: result.key,
                        bucket: config.bucket,
                        region: config.region,
                        url: result.url,
                        fileSize: fileSize,
                        contentType: result.contentType,
                        contentHash: result.contentHash,
                        timestamp: ISO8601DateFormatter().string(from: Date())
                    )

                    for action in enabledActions {
                        switch action.actionType {
                        case .dynamoDB(let dbConfig):
                            do {
                                try await DynamoDBService.shared.putItem(
                                    action: dbConfig,
                                    metadata: metadata,
                                    credentials: (config.accessKeyId, config.secretAccessKey),
                                    bucketRegion: config.region
                                )
                            } catch {
                                print("[BucketDrop] DynamoDB error (\(action.label)): \(error)")
                            }
                        }
                    }
                }
            } catch {
                tasks[index].status = .failed(error.localizedDescription)
                errorMessage = "\(displayName(for: config)): \(error.localizedDescription)"
            }

            uploadTasksByConfig[config.id] = tasks
        }

        if !successfulURLs.isEmpty && config.copyURLAfterUpload {
            NSPasteboard.general.clearContents()
            if successfulURLs.count == 1 {
                NSPasteboard.general.setString(successfulURLs[0], forType: .string)
                showCopyToast("Copied \(defaultTemplateLabel(for: config))")
            } else {
                NSPasteboard.general.setString(successfulURLs.joined(separator: "\n"), forType: .string)
                showCopyToast("Copied \(successfulURLs.count) URLs (\(defaultTemplateLabel(for: config)))")
            }
        }

        try? await Task.sleep(for: .seconds(2))
        uploadTasksByConfig[config.id] = []
    }

    // MARK: - S3 Object Actions (List tab)

    private func copyObjectDefaultURL(_ object: S3Object, config: BucketConfig) {
        let template = defaultTemplate(for: config)
        let url = S3Service.shared.buildURL(
            key: object.key,
            config: config,
            template: template,
            basename: object.filename
        )
        copyToClipboard(url)
        showCopyToast("Copied \(template?.label ?? "URL")")
    }

    private func copyObjectTemplateURL(_ object: S3Object, config: BucketConfig, template: URLTemplate) {
        let url = S3Service.shared.buildURL(
            key: object.key,
            config: config,
            template: template,
            basename: object.filename
        )
        copyToClipboard(url)
        showCopyToast("Copied \(template.label)")
    }

    private func deleteObject(_ object: S3Object, config: BucketConfig) async {
        do {
            try await S3Service.shared.deleteObject(key: object.key, config: config)
            s3ObjectsByConfig[config.id]?.removeAll { $0.key == object.key }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func downloadObject(_ object: S3Object, config: BucketConfig) async {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = object.filename
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        NSApp.activate(ignoringOtherApps: true)
        let response = await savePanel.begin()
        guard response == .OK, let destination = savePanel.url else { return }

        if let cachedURL = getCachedFile(for: object) {
            do {
                try FileManager.default.copyItem(at: cachedURL, to: destination)
                NSWorkspace.shared.selectFile(destination.path, inFileViewerRootedAtPath: "")
                return
            } catch { }
        }

        do {
            downloadingToken = object.key
            downloadProgress = 0

            let cacheURL = cachedFileURL(for: object)
            let savedURL = try await S3Service.shared.download(key: object.key, to: cacheURL, config: config, overwrite: true) { progress in
                Task { @MainActor in
                    downloadProgress = progress
                }
            }

            try FileManager.default.copyItem(at: savedURL, to: destination)
            downloadingToken = nil
            NSWorkspace.shared.selectFile(destination.path, inFileViewerRootedAtPath: "")
        } catch {
            downloadingToken = nil
            errorMessage = error.localizedDescription
        }
    }

    private func previewObject(_ object: S3Object, config: BucketConfig) {
        Task {
            let tempFile = cachedFileURL(for: object)

            if let cachedURL = getCachedFile(for: object) {
                await MainActor.run { showQuickLook(for: cachedURL) }
                return
            }

            do {
                downloadingToken = object.key
                downloadProgress = 0

                let savedURL = try await S3Service.shared.download(key: object.key, to: tempFile, config: config, overwrite: true) { progress in
                    Task { @MainActor in
                        downloadProgress = progress
                    }
                }

                downloadingToken = nil

                await MainActor.run {
                    showQuickLook(for: savedURL)
                }
            } catch {
                downloadingToken = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func showQuickLook(for url: URL) {
        let coordinator = QuickLookCoordinator()
        coordinator.items = [QuickLookItem(url: url)]

        Self.quickLookCoordinator = coordinator

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = coordinator
        panel.delegate = coordinator
        panel.currentPreviewItemIndex = 0

        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Shared Helpers

    private func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func defaultTemplate(for config: BucketConfig) -> URLTemplate? {
        config.urlTemplates.first { !trim($0.template).isEmpty }
    }

    private func defaultTemplateLabel(for config: BucketConfig) -> String {
        guard let template = defaultTemplate(for: config) else { return "URL" }
        let label = trim(template.label)
        return label.isEmpty ? "URL" : label
    }

    private func previewURLForObject(_ object: S3Object, config: BucketConfig) -> URL? {
        guard isImageFile(object.filename) else { return nil }
        let urlString = S3Service.shared.buildURL(key: object.key, config: config, basename: object.filename)
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func isImageFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "svg"].contains(ext)
    }

    // MARK: - Cache

    private func cachedFileURL(for object: S3Object) -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("BucketDrop")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let keyComponent = object.key.replacingOccurrences(of: "/", with: "__")
        return tempDir.appendingPathComponent(keyComponent)
    }

    private func getCachedFile(for object: S3Object) -> URL? {
        let cachedURL = cachedFileURL(for: object)
        return FileManager.default.fileExists(atPath: cachedURL.path) ? cachedURL : nil
    }

    @MainActor
    private func showCopyToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            copyToastMessage = message
        }

        Task {
            try? await Task.sleep(for: .seconds(1.6))
            await MainActor.run {
                guard copyToastMessage == message else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    copyToastMessage = nil
                }
            }
        }
    }

    private func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Static storage for coordinator
    private static var quickLookCoordinator: QuickLookCoordinator?
}

struct ConfigDropZoneView: View {
    let configName: String
    let keyPrefix: String
    @Binding var isTargeted: Bool
    let uploadTasks: [UploadTask]

    private var completedCount: Int {
        uploadTasks.filter {
            if case .completed = $0.status { return true }
            return false
        }.count
    }

    private var totalCount: Int {
        uploadTasks.count
    }

    private var overallProgress: Double {
        guard !uploadTasks.isEmpty else { return 0 }
        return uploadTasks.reduce(0) { $0 + $1.progress } / Double(uploadTasks.count)
    }

    private var currentlyUploading: UploadTask? {
        uploadTasks.first {
            if case .uploading = $0.status { return true }
            return false
        }
    }

    private var allCompleted: Bool {
        completedCount == totalCount && totalCount > 0
    }

    private var hasActiveUploads: Bool {
        !uploadTasks.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(configName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer(minLength: 8)

                let normalizedPrefix = keyPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalizedPrefix.isEmpty {
                    Text(normalizedPrefix)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35)))
                }
            }

            VStack(spacing: 7) {
                if hasActiveUploads {
                    if allCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(nsColor: .systemGreen))
                        if totalCount == 1 {
                            Text("Upload finished")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(totalCount) uploads finished")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView(value: overallProgress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: .infinity)

                        if totalCount == 1 {
                            Text("Uploading \(currentlyUploading?.filename ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Uploading \(completedCount + 1) of \(totalCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let current = currentlyUploading {
                                Text(current.filename)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.up.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    Text(isTargeted ? "Drop to upload" : "Drop files here or click to select")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .quaternaryLabelColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isTargeted ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}

// Custom progress style that doesn't gray out when window loses focus
struct ActiveProgressViewStyle: ProgressViewStyle {
    var height: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            let progress = configuration.fractionCompleted ?? 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.3))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * progress)
                    .animation(.easeOut(duration: 0.15), value: progress)
            }
        }
        .frame(height: height)
    }
}

enum CachedImageState {
    case loading
    case success(Image)
    case failure
}

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

final class ImageLoader: ObservableObject {
    @Published var state: CachedImageState = .loading
    private var task: Task<Void, Never>?

    func load(from url: URL) {
        if let cached = ImageCache.shared.image(for: url) {
            state = .success(Image(nsImage: cached))
            return
        }

        task?.cancel()
        task = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = NSImage(data: data) else {
                    await MainActor.run { self.state = .failure }
                    return
                }
                ImageCache.shared.insert(image, for: url)
                await MainActor.run { self.state = .success(Image(nsImage: image)) }
            } catch {
                await MainActor.run { self.state = .failure }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

struct CachedAsyncImage<Content: View>: View {
    let url: URL
    @ViewBuilder let content: (CachedImageState) -> Content
    @StateObject private var loader = ImageLoader()

    var body: some View {
        content(loader.state)
            .onAppear { loader.load(from: url) }
            .onChange(of: url) { _, newURL in
                loader.load(from: newURL)
            }
            .onDisappear { loader.cancel() }
    }
}

struct S3ObjectRowView: View {
    let object: S3Object
    let configName: String
    let previewURL: URL?
    let isDownloading: Bool
    let downloadProgress: Double
    let templateOptions: [URLTemplate]
    let onCopyDefault: () -> Void
    let onCopyTemplate: (URLTemplate) -> Void
    let onDelete: () async -> Void
    let onDownload: () async -> Void
    let onPreview: () -> Void

    @State private var isHovered = false
    @State private var isDeleting = false
    @State private var isCopied = false

    var body: some View {
        HStack(spacing: 10) {
            if let previewURL {
                CachedAsyncImage(url: previewURL) { state in
                    switch state {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    case .loading:
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .separatorColor).opacity(0.3))
                    Image(systemName: iconForFile(object.filename))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(object.filename)
                    .font(.system(.subheadline).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if isDownloading {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(ActiveProgressViewStyle(height: 6))
                        .padding(.top, 2)
                } else {
                    HStack(spacing: 6) {
                        Text(formatSize(object.size))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(configName)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
                            )
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button {
                    guard !isDeleting && !isDownloading else { return }
                    onCopyDefault()
                    animateCopyFeedback()
                } label: {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "link")
                        .foregroundStyle(isCopied ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy URL")
                .disabled(isDeleting || isDownloading)
                .contextMenu {
                    if templateOptions.isEmpty {
                        Text("No templates")
                    } else {
                        ForEach(templateOptions) { template in
                            Button(template.label) {
                                onCopyTemplate(template)
                                animateCopyFeedback()
                            }
                        }
                    }
                }

                Button {
                    Task { await onDownload() }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.borderless)
                .help("Download")
                .disabled(isDeleting || isDownloading)

                Button {
                    Task {
                        isDeleting = true
                        await onDelete()
                        isDeleting = false
                    }
                } label: {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "trash")
                            .foregroundStyle(Color(nsColor: .systemRed))
                    }
                }
                .buttonStyle(.borderless)
                .help("Delete")
                .disabled(isDeleting || isDownloading)
            }
            .opacity(isHovered || isDeleting || isDownloading ? 1 : 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            if !isDownloading {
                onPreview()
            }
        }
    }

    private func animateCopyFeedback() {
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.15)) {
                isCopied = true
            }
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeInOut(duration: 0.15)) {
                isCopied = false
            }
        }
    }

    private func iconForFile(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "svg":
            return "photo"
        case "mp4", "mov", "avi":
            return "video"
        case "mp3", "wav", "m4a":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "zip", "rar", "7z":
            return "archivebox"
        default:
            return "doc"
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Quick Look Support

class QuickLookItem: NSObject, QLPreviewItem {
    let url: URL

    init(url: URL) {
        self.url = url
        super.init()
    }

    var previewItemURL: URL? { url }
    var previewItemTitle: String? { url.lastPathComponent }
}

class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var items: [QuickLookItem] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index < items.count else { return nil }
        return items[index]
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [UploadedFile.self, BucketConfig.self], inMemory: true)
}
