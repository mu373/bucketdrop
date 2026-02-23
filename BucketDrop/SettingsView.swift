//
//  SettingsView.swift
//  BucketDrop
//
//  Created by Fayaz Ahmed Aralikatti on 12/01/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let postUploadActionPasteboardType = NSPasteboard.PasteboardType("com.bucketdrop.postUploadAction")

private struct BucketConfigDraft: Equatable {
    var name: String = ""
    var provider: String = BucketProvider.other.rawValue
    var accessKeyId: String = ""
    var secretAccessKey: String = ""
    var bucket: String = ""
    var region: String = "us-east-1"
    var endpoint: String = ""
    var keyPrefix: String = ""
    var uriScheme: String = "s3"
    var urlTemplates: [URLTemplate] = []
    var renameMode: String = RenameMode.original.rawValue
    var dateTimeFormat: String = DateTimeFormat.unix.rawValue
    var hashAlgorithm: String = HashAlgorithm.sha256.rawValue
    var customRenameTemplate: String = "${original}"
    var copyURLAfterUpload: Bool = true
    var postUploadActions: [PostUploadAction] = []

    init() { }

    init(config: BucketConfig) {
        name = config.name
        provider = BucketProvider(rawValue: config.provider)?.rawValue ?? BucketProvider.other.rawValue
        accessKeyId = config.accessKeyId
        secretAccessKey = config.secretAccessKey
        bucket = config.bucket
        region = config.region
        endpoint = config.endpoint
        keyPrefix = config.keyPrefix
        uriScheme = config.uriScheme
        urlTemplates = config.urlTemplates
        renameMode = config.renameMode
        dateTimeFormat = config.dateTimeFormat
        hashAlgorithm = config.hashAlgorithm
        customRenameTemplate = config.customRenameTemplate
        copyURLAfterUpload = config.copyURLAfterUpload
        postUploadActions = config.postUploadActions
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\BucketConfig.sortOrder), SortDescriptor(\BucketConfig.name)])
    private var configs: [BucketConfig]
    @Query private var uploadedFiles: [UploadedFile]

    @State private var selectedConfigID: UUID?
    @State private var draft = BucketConfigDraft()
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var selectedTemplateID: UUID?
    @State private var editingTemplate: URLTemplate?
    @State private var selectedPostUploadActionID: UUID?
    @State private var editingPostUploadAction: PostUploadAction?
    @State private var renameTextViewRef = TemplateTextViewRef()

    enum TestResult {
        case success
        case failure(String)
    }

    private var selectedConfig: BucketConfig? {
        guard let selectedConfigID else { return nil }
        return configs.first(where: { $0.id == selectedConfigID })
    }

    private var canTest: Bool {
        !trim(draft.accessKeyId).isEmpty && !trim(draft.secretAccessKey).isEmpty && !trim(draft.bucket).isEmpty
    }

    private var selectedProvider: BucketProvider {
        BucketProvider(rawValue: draft.provider) ?? .other
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { selectedProvider.rawValue },
            set: { newValue in
                let provider = BucketProvider(rawValue: newValue) ?? .other
                draft.provider = provider.rawValue
                applyProviderDefaults(provider)
            }
        )
    }

    private var endpointPlaceholder: String {
        switch selectedProvider {
        case .awsS3:
            return "Leave blank for AWS default endpoint"
        case .googleCloud:
            return "https://storage.googleapis.com"
        case .cloudflareR2:
            return "https://<accountid>.r2.cloudflarestorage.com"
        case .other:
            return "https://s3-compatible.example.com"
        }
    }

    private var regionPlaceholder: String {
        switch selectedProvider {
        case .awsS3:
            return "us-east-1"
        case .googleCloud, .cloudflareR2:
            return "auto"
        case .other:
            return "us-east-1"
        }
    }

    private var bucketPathPreview: String {
        let bucket = trim(draft.bucket)
        let scheme = trim(draft.uriScheme)
        let schemeDisplay = scheme.isEmpty ? "s3" : scheme
        guard !bucket.isEmpty else {
            return "\(schemeDisplay)://your-bucket/"
        }

        let prefix = trim(draft.keyPrefix).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if prefix.isEmpty {
            return "\(schemeDisplay)://\(bucket)/"
        }

        return "\(schemeDisplay)://\(bucket)/\(prefix)/"
    }

    private var renamePreviewText: String {
        let replacements: [(String, String)] = [
            ("${original}", "photo.png"),
            ("${basename}", "photo"),
            ("${ext}", "png"),
            ("${year}", "2026"),
            ("${month}", "02"),
            ("${day}", "20"),
            ("${hour}", "14"),
            ("${minute}", "30"),
            ("${second}", "45"),
            ("${timestamp}", "1771588245"),
            ("${hash}", (HashAlgorithm(rawValue: draft.hashAlgorithm) ?? .sha256) == .md5
                ? "d41d8cd98f00b204e9800998ecf8427e"
                : "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("${uuid}", "A1B2C3D4")
        ]
        var result = draft.customRenameTemplate
        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            rightPane
                .frame(minWidth: 400, idealWidth: 580)
        }
        .frame(width: 820, height: 540)
        .onAppear {
            ensureSelection()
            loadDraftForSelection()
        }
        .onChange(of: configs.map(\.id)) { _, _ in
            ensureSelection()
        }
        .onChange(of: selectedConfigID) { _, _ in
            loadDraftForSelection()
        }
        .onChange(of: draft) { _, _ in
            commitDraft()
        }
    }

    // MARK: - Left Pane

    private var leftPane: some View {
        VStack(spacing: 0) {
            List(selection: $selectedConfigID) {
                ForEach(configs) { config in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.name.isEmpty ? "Untitled" : config.name)
                            .lineLimit(1)
                        Text(configSubtitle(config))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(Optional(config.id))
                    .padding(.vertical, 1)
                    .contextMenu {
                        Button {
                            duplicateConfig(config)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 0) {
                Button {
                    addConfig()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.borderless)

                Divider()
                    .frame(height: 16)

                Button {
                    deleteSelectedConfig()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(selectedConfig == nil)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func configSubtitle(_ config: BucketConfig) -> String {
        if config.bucket.isEmpty { return "Not configured" }
        let prefix = config.keyPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.isEmpty {
            return config.bucket
        }
        return "\(config.bucket)/\(prefix)"
    }

    // MARK: - Right Pane

    @ViewBuilder
    private var rightPane: some View {
        if selectedConfig != nil {
            Form {
                Section("General") {
                    TextField("Name", text: $draft.name, prompt: Text("Blog Images"))
                }

                Section("Credentials") {
                    TextField("Access Key ID", text: $draft.accessKeyId)
                    SecureField("Secret Access Key", text: $draft.secretAccessKey)
                }

                Section {
                    Picker("Provider", selection: providerBinding) {
                        ForEach(BucketProvider.allCases) { provider in
                            Text(provider.displayName)
                                .tag(provider.rawValue)
                        }
                    }
                    if selectedProvider != .awsS3 {
                        TextField("Endpoint", text: $draft.endpoint, prompt: Text(endpointPlaceholder))
                    }
                    TextField("URI Scheme", text: $draft.uriScheme, prompt: Text(selectedProvider.defaultScheme ?? "s3"))
                    TextField("Bucket", text: $draft.bucket)
                    TextField("Region", text: $draft.region, prompt: Text(regionPlaceholder))
                    TextField("Key Prefix", text: $draft.keyPrefix, prompt: Text("myfolder/"))
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bucket")
                        Text("Your files will be saved at \(bucketPathPreview)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Rename on Upload") {
                    Picker("Mode", selection: $draft.renameMode) {
                        ForEach(RenameMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    if draft.renameMode == RenameMode.dateTime.rawValue {
                        Picker("Format", selection: $draft.dateTimeFormat) {
                            ForEach(DateTimeFormat.allCases) { fmt in
                                Text("\(fmt.displayName) (\(fmt.example))").tag(fmt.rawValue)
                            }
                        }
                    }
                    if draft.renameMode == RenameMode.hash.rawValue {
                        Picker("Algorithm", selection: $draft.hashAlgorithm) {
                            ForEach(HashAlgorithm.allCases) { algo in
                                Text(algo.displayName).tag(algo.rawValue)
                            }
                        }
                    }
                    if draft.renameMode == RenameMode.custom.rawValue {
                        VStack(alignment: .leading, spacing: 8) {
                            TemplateTokenField(template: $draft.customRenameTemplate, textViewRef: renameTextViewRef)
                                .frame(height: 32)
                            if !draft.customRenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(renamePreviewText)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    renameVariableButton("original", label: "Original filename")
                                    renameVariableButton("basename", label: "Basename")
                                    renameVariableButton("ext", label: "Extension")
                                    renameVariableButton("hash", label: "Hash")
                                    renameVariableButton("uuid", label: "UUID")
                                }
                                HStack(spacing: 4) {
                                    renameVariableButton("year", label: "Year")
                                    renameVariableButton("month", label: "Month")
                                    renameVariableButton("day", label: "Day")
                                    renameVariableButton("hour", label: "Hour")
                                    renameVariableButton("minute", label: "Minute")
                                    renameVariableButton("second", label: "Second")
                                    renameVariableButton("timestamp", label: "Timestamp")
                                }
                            }
                        }
                        Picker("Hash Algorithm", selection: $draft.hashAlgorithm) {
                            ForEach(HashAlgorithm.allCases) { algo in
                                Text(algo.displayName).tag(algo.rawValue)
                            }
                        }
                    }
                }

                Section("Copy Formats") {
                    Toggle("Copy to clipboard after upload", isOn: $draft.copyURLAfterUpload)
                    VStack(spacing: 0) {
                        List(selection: $selectedTemplateID) {
                            ForEach(draft.urlTemplates) { template in
                                HStack(spacing: 6) {
                                    HStack(spacing: 6) {
                                        Text(template.label)
                                            .lineLimit(1)
                                            .frame(width: 120, alignment: .leading)
                                        if template.id == draft.urlTemplates.first?.id {
                                            Text("Default")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(.orange.opacity(0.15), in: .capsule)
                                        }
                                    }

                                    Text(template.template)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .tag(Optional(template.id))
                            }
                            .onMove(perform: moveTemplate)
                        }
                        .listStyle(.bordered(alternatesRowBackgrounds: true))
                        .frame(height: 120)
                        .onDoubleClick {
                            if let selectedTemplateID,
                               let template = draft.urlTemplates.first(where: { $0.id == selectedTemplateID }) {
                                editingTemplate = template
                            }
                        }

                        Divider()

                        HStack(spacing: 0) {
                            Button {
                                addTemplate()
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 24, height: 18)
                            }
                            .buttonStyle(.borderless)

                            Divider()
                                .frame(height: 14)

                            Button {
                                if let selectedTemplateID,
                                   let index = draft.urlTemplates.firstIndex(where: { $0.id == selectedTemplateID }) {
                                    removeTemplate(index)
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 24, height: 18)
                            }
                            .buttonStyle(.borderless)
                            .disabled(selectedTemplateID == nil)

                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                }
                .sheet(item: $editingTemplate) { template in
                    TemplateEditorSheet(
                        template: template,
                        onSave: { label, value in
                            updateTemplate(template.id, label: label, template: value)
                        }
                    )
                }

                Section("Post-Upload Actions") {
                    VStack(spacing: 0) {
                        List(selection: $selectedPostUploadActionID) {
                            ForEach(draft.postUploadActions) { action in
                                HStack(spacing: 8) {
                                    Text(postUploadActionDisplayLabel(action))
                                        .lineLimit(1)

                                    Spacer(minLength: 8)

                                    Text(postUploadActionTypeLabel(action))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: .capsule)

                                    Toggle("", isOn: postUploadActionEnabledBinding(action.id))
                                        .labelsHidden()
                                }
                                .tag(Optional(action.id))
                                .contextMenu {
                                    Button("Copy") {
                                        copyPostUploadAction(action)
                                    }
                                    Button("Paste") {
                                        pastePostUploadAction()
                                    }
                                    .disabled(!canPastePostUploadAction())
                                    Divider()
                                    Button("Duplicate") {
                                        duplicatePostUploadAction(action)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        deletePostUploadAction(action)
                                    }
                                }
                            }
                        }
                        .contextMenu {
                            Button("Paste") {
                                pastePostUploadAction()
                            }
                            .disabled(!canPastePostUploadAction())
                        }
                        .listStyle(.bordered(alternatesRowBackgrounds: true))
                        .frame(height: 120)
                        .onDoubleClick {
                            openSelectedPostUploadActionEditor()
                        }

                        Divider()

                        HStack(spacing: 0) {
                            Menu {
                                Button("DynamoDB") {
                                    addPostUploadAction(type: .dynamoDB(DynamoDBActionConfig()))
                                }
                                Button("HTTP Request") {
                                    addPostUploadAction(type: .http(HTTPActionConfig()))
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 24, height: 18)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()

                            Divider()
                                .frame(height: 14)

                            Button {
                                removeSelectedPostUploadAction()
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 24, height: 18)
                            }
                            .buttonStyle(.borderless)
                            .disabled(selectedPostUploadActionID == nil)

                            Spacer()

                            Button("Edit") {
                                openSelectedPostUploadActionEditor()
                            }
                            .buttonStyle(.link)
                            .disabled(selectedPostUploadActionID == nil)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                }
                .sheet(item: $editingPostUploadAction) { action in
                    PostUploadActionEditorSheet(action: action) { updatedAction in
                        updatePostUploadAction(updatedAction)
                    }
                }

                Section {
                    HStack {
                        Button("Test Connection") {
                            testConnection()
                        }
                        .disabled(isTesting || !canTest)

                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if let result = testResult {
                            switch result {
                            case .success:
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            case .failure(let message):
                                Label(message, systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                Text("No Drop Target Selected")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Select a target from the sidebar, or click + to create one.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Auto-save

    /// Writes draft fields back to the SwiftData model and persists.
    private func commitDraft() {
        guard let config = selectedConfig else { return }

        config.name = trim(draft.name)
        let provider = BucketProvider(rawValue: draft.provider) ?? .other
        config.provider = provider.rawValue
        config.accessKeyId = trim(draft.accessKeyId)
        config.secretAccessKey = trim(draft.secretAccessKey)
        config.bucket = trim(draft.bucket)

        let trimmedRegion = trim(draft.region)
        config.region = trimmedRegion.isEmpty ? (provider.defaultRegion ?? "us-east-1") : trimmedRegion
        config.endpoint = trim(draft.endpoint)
        config.keyPrefix = trim(draft.keyPrefix)
        config.uriScheme = trim(draft.uriScheme)
        config.urlTemplates = sanitizedTemplates(draft.urlTemplates)
        config.renameMode = draft.renameMode
        config.dateTimeFormat = draft.dateTimeFormat
        config.hashAlgorithm = draft.hashAlgorithm
        config.customRenameTemplate = draft.customRenameTemplate
        config.copyURLAfterUpload = draft.copyURLAfterUpload
        config.postUploadActions = draft.postUploadActions

        try? modelContext.save()
    }

    // MARK: - Actions

    private func ensureSelection() {
        guard !configs.isEmpty else {
            selectedConfigID = nil
            draft = BucketConfigDraft()
            return
        }

        if let selectedConfigID,
           configs.contains(where: { $0.id == selectedConfigID }) {
            return
        }

        selectedConfigID = configs.first?.id
    }

    private func loadDraftForSelection() {
        guard let selectedConfig else {
            draft = BucketConfigDraft()
            return
        }

        draft = BucketConfigDraft(config: selectedConfig)
        selectedTemplateID = nil
        selectedPostUploadActionID = nil
        editingTemplate = nil
        editingPostUploadAction = nil
        testResult = nil
    }

    private func addConfig() {
        commitDraft()

        let nextOrder = (configs.map(\.sortOrder).max() ?? -1) + 1
        let newConfig = BucketConfig(
            name: "New Drop Target",
            region: "us-east-1",
            sortOrder: nextOrder,
            urlTemplates: URLTemplate.presets()
        )
        modelContext.insert(newConfig)
        try? modelContext.save()

        selectedConfigID = newConfig.id
        draft = BucketConfigDraft(config: newConfig)
    }

    private func duplicateConfig(_ config: BucketConfig) {
        commitDraft()

        let nextOrder = (configs.map(\.sortOrder).max() ?? -1) + 1
        let duplicatedConfig = BucketConfig(
            name: "\(config.name) Copy",
            provider: config.provider,
            accessKeyId: config.accessKeyId,
            secretAccessKey: config.secretAccessKey,
            bucket: config.bucket,
            region: config.region,
            endpoint: config.endpoint,
            keyPrefix: config.keyPrefix,
            uriScheme: config.uriScheme,
            sortOrder: nextOrder,
            urlTemplates: config.urlTemplates,
            renameMode: config.renameMode,
            dateTimeFormat: config.dateTimeFormat,
            hashAlgorithm: config.hashAlgorithm,
            customRenameTemplate: config.customRenameTemplate,
            copyURLAfterUpload: config.copyURLAfterUpload,
            postUploadActions: config.postUploadActions
        )
        modelContext.insert(duplicatedConfig)
        try? modelContext.save()

        selectedConfigID = duplicatedConfig.id
        draft = BucketConfigDraft(config: duplicatedConfig)
        testResult = nil
    }

    private func deleteSelectedConfig() {
        guard let selectedConfig else { return }

        let nextSelection = configs.first(where: { $0.id != selectedConfig.id })?.id

        for file in uploadedFiles where file.configId == selectedConfig.id {
            modelContext.delete(file)
        }

        modelContext.delete(selectedConfig)
        try? modelContext.save()

        selectedConfigID = nextSelection
        testResult = nil
    }

    private func testConnection() {
        guard canTest, let config = selectedConfig else { return }

        isTesting = true
        testResult = nil

        Task {
            do {
                _ = try await S3Service.shared.listObjects(config: config)
                await MainActor.run {
                    testResult = .success
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }

    private func renameVariableButton(_ token: String, label: String) -> some View {
        Button {
            renameTextViewRef.insertAtCursor("${\(token)}")
        } label: {
            Text(label)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .background(.quaternary, in: .capsule)
        .draggable("${\(token)}")
    }

    private func postUploadActionDisplayLabel(_ action: PostUploadAction) -> String {
        let label = trim(action.label)
        if !label.isEmpty {
            return label
        }

        switch action.actionType {
        case .dynamoDB:
            return "DynamoDB Action"
        case .http:
            return "HTTP Action"
        }
    }

    private func postUploadActionTypeLabel(_ action: PostUploadAction) -> String {
        switch action.actionType {
        case .dynamoDB:
            return "DynamoDB"
        case .http:
            return "HTTP"
        }
    }

    private func postUploadActionEnabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                draft.postUploadActions.first(where: { $0.id == id })?.enabled ?? false
            },
            set: { enabled in
                guard let index = draft.postUploadActions.firstIndex(where: { $0.id == id }) else { return }
                draft.postUploadActions[index].enabled = enabled
            }
        )
    }

    private func addPostUploadAction(type: PostUploadActionType) {
        let defaultLabel: String
        switch type {
        case .dynamoDB: defaultLabel = "DynamoDB Action"
        case .http: defaultLabel = "HTTP Action"
        }
        let action = PostUploadAction(
            enabled: true,
            label: defaultLabel,
            actionType: type
        )
        draft.postUploadActions.append(action)
        selectedPostUploadActionID = action.id
        editingPostUploadAction = action
    }

    private func deletePostUploadAction(_ action: PostUploadAction) {
        draft.postUploadActions.removeAll { $0.id == action.id }
        if selectedPostUploadActionID == action.id {
            selectedPostUploadActionID = nil
        }
    }

    private func removeSelectedPostUploadAction() {
        guard let selectedPostUploadActionID else { return }
        draft.postUploadActions.removeAll { $0.id == selectedPostUploadActionID }
        self.selectedPostUploadActionID = nil
    }

    private func openSelectedPostUploadActionEditor() {
        guard let selectedPostUploadActionID,
              let action = draft.postUploadActions.first(where: { $0.id == selectedPostUploadActionID }) else {
            return
        }
        editingPostUploadAction = action
    }

    private func updatePostUploadAction(_ updatedAction: PostUploadAction) {
        guard let index = draft.postUploadActions.firstIndex(where: { $0.id == updatedAction.id }) else { return }
        draft.postUploadActions[index] = updatedAction
        selectedPostUploadActionID = updatedAction.id
    }

    private func copyPostUploadAction(_ action: PostUploadAction) {
        guard let data = try? JSONEncoder().encode(action) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: postUploadActionPasteboardType)
    }

    private func canPastePostUploadAction() -> Bool {
        NSPasteboard.general.data(forType: postUploadActionPasteboardType) != nil
    }

    private func pastePostUploadAction() {
        guard let data = NSPasteboard.general.data(forType: postUploadActionPasteboardType),
              var action = try? JSONDecoder().decode(PostUploadAction.self, from: data) else { return }
        action.id = UUID()
        draft.postUploadActions.append(action)
        selectedPostUploadActionID = action.id
    }

    private func duplicatePostUploadAction(_ action: PostUploadAction) {
        var copy = action
        copy.id = UUID()
        copy.label = action.label.isEmpty ? "" : "\(action.label) Copy"
        draft.postUploadActions.append(copy)
        selectedPostUploadActionID = copy.id
    }

    private func applyProviderDefaults(_ provider: BucketProvider) {
        if let defaultRegion = provider.defaultRegion {
            draft.region = defaultRegion
        }
        if let defaultEndpoint = provider.defaultEndpoint {
            draft.endpoint = defaultEndpoint
        }
        if let defaultScheme = provider.defaultScheme {
            draft.uriScheme = defaultScheme
        }
    }

    // MARK: - URL Template Helpers

    private func addTemplate() {
        let nextIndex = draft.urlTemplates.count + 1
        draft.urlTemplates.append(URLTemplate(label: "Template \(nextIndex)", template: "https://example.com/${PATH}"))
    }

    private func moveTemplate(from source: IndexSet, to destination: Int) {
        draft.urlTemplates.move(fromOffsets: source, toOffset: destination)
    }

    private func removeTemplate(_ index: Int) {
        guard draft.urlTemplates.indices.contains(index) else { return }
        draft.urlTemplates.remove(at: index)
    }

    private func updateTemplate(_ id: UUID, label: String, template: String) {
        guard let index = draft.urlTemplates.firstIndex(where: { $0.id == id }) else { return }
        draft.urlTemplates[index].label = label
        draft.urlTemplates[index].template = template
    }

    private func sanitizedTemplates(_ templates: [URLTemplate]) -> [URLTemplate] {
        templates.compactMap { template in
            let label = trim(template.label)
            let value = trim(template.template)
            guard !label.isEmpty, !value.isEmpty else {
                return nil
            }
            return URLTemplate(id: template.id, label: label, template: value)
        }
    }

    private func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Double-Click Modifier

private struct DoubleClickListenerView: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DoubleClickNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    class DoubleClickNSView: NSView {
        weak var coordinator: Coordinator?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window == window else { return event }
                if event.clickCount == 2 {
                    let location = self.convert(event.locationInWindow, from: nil)
                    if self.bounds.contains(location) {
                        DispatchQueue.main.async {
                            self.coordinator?.action()
                        }
                    }
                }
                return event
            }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }
    }
}

extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        background { DoubleClickListenerView(action: action) }
    }
}

// MARK: - Template Token Field (NSTextView-backed)

/// Key used to store the variable name inside an NSTextAttachment.
private let kPillVariableKey = "templatePillVariable"

/// Maps variable token names to human-readable pill labels.
private let pillDisplayNames: [String: String] = [
    // URL template variables
    "SCHEME": "Scheme",
    "BUCKET": "Bucket",
    "PATH": "Path",
    "BASENAME": "Basename",
    "KEY": "Key",
    "REGION": "Region",
    "ENDPOINT": "Endpoint",
    // Rename template variables
    "original": "Original filename",
    "basename": "Basename",
    "ext": "Extension",
    "year": "Year",
    "month": "Month",
    "day": "Day",
    "hour": "Hour",
    "minute": "Minute",
    "second": "Second",
    "timestamp": "Timestamp",
    "hash": "Hash",
    "uuid": "UUID",
    // DynamoDB action variables
    "originalFilename": "Original Filename",
    "renamedFilename": "Renamed Filename",
    "path": "Path",
    "bucket": "Bucket",
    "region": "Region",
    "url": "URL",
    "fileSize": "File Size",
    "contentType": "Content Type",
    "contentHash": "Content Hash",
    "hashAlgorithm": "Hash Algorithm",
    "scheme": "Scheme"
]

/// Custom attachment cell that draws a capsule pill for a variable token.
private final class PillAttachmentCell: NSTextAttachmentCell {
    let variableName: String
    let displayName: String

    init(variableName: String) {
        self.variableName = variableName
        self.displayName = pillDisplayNames[variableName] ?? variableName
        super.init()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    // MARK: - Sizing

    nonisolated override func cellSize() -> NSSize {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (displayName as NSString).size(withAttributes: attrs)
        return NSSize(width: textSize.width + 12, height: textSize.height + 4)
    }

    nonisolated override func cellBaselineOffset() -> NSPoint {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return NSPoint(x: 0, y: font.descender)
    }

    // MARK: - Drawing

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let radius = cellFrame.height / 2
        let path = NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius)
        NSColor.controlAccentColor.setFill()
        path.fill()

        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = (displayName as NSString).size(withAttributes: attrs)
        let textRect = NSRect(
            x: cellFrame.minX + (cellFrame.width - textSize.width) / 2,
            y: cellFrame.minY + (cellFrame.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (displayName as NSString).draw(in: textRect, withAttributes: attrs)
    }

    // MARK: - Hit-testing & tracking (makes pills selectable / draggable)

    override func wantsToTrackMouse() -> Bool { true }

    override func trackMouse(with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        return true
    }
}

/// Builds an `NSAttributedString` with pill attachments for each `${VAR}` token.
private func pillAttributedString(from raw: String) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let pattern = try! NSRegularExpression(pattern: #"\$\{([a-zA-Z][a-zA-Z0-9_]*)\}"#)
    let nsString = raw as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)
    let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    var cursor = 0
    for match in pattern.matches(in: raw, range: fullRange) {
        // Append literal text before this match
        if match.range.location > cursor {
            let textRange = NSRange(location: cursor, length: match.range.location - cursor)
            let literal = nsString.substring(with: textRange)
            result.append(NSAttributedString(string: literal, attributes: [.font: bodyFont, .foregroundColor: NSColor.textColor]))
        }

        // Build pill attachment
        let varName = nsString.substring(with: match.range(at: 1))
        let cell = PillAttachmentCell(variableName: varName)
        let attachment = NSTextAttachment()
        attachment.attachmentCell = cell
        let attachStr = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        // Store the variable name so we can reconstruct later
        attachStr.addAttribute(.toolTip, value: "${\(varName)}", range: NSRange(location: 0, length: attachStr.length))
        result.append(attachStr)

        cursor = match.range.location + match.range.length
    }

    // Trailing text
    if cursor < nsString.length {
        let trailing = nsString.substring(from: cursor)
        result.append(NSAttributedString(string: trailing, attributes: [.font: bodyFont, .foregroundColor: NSColor.textColor]))
    } else if cursor == nsString.length {
        // Ensure there's at least a zero-width spot to place the cursor at the end
        result.append(NSAttributedString(string: "", attributes: [.font: bodyFont, .foregroundColor: NSColor.textColor]))
    }

    return result
}

/// Converts an attributed string (with pill attachments) back to a raw template string.
private func rawTemplateString(from attributed: NSAttributedString) -> String {
    var result = ""
    attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
        if let attachment = attrs[.attachment] as? NSTextAttachment,
           let cell = attachment.attachmentCell as? PillAttachmentCell {
            result += "${\(cell.variableName)}"
        } else {
            result += (attributed.string as NSString).substring(with: range)
        }
    }
    return result
}

/// Holds a weak reference to the underlying NSTextView so variable buttons can insert at cursor.
private final class TemplateTextViewRef {
    weak var textView: NSTextView?
    /// Called after content is programmatically inserted so the binding stays in sync.
    var onContentChanged: (() -> Void)?

    func insertAtCursor(_ text: String) {
        guard let textView else { return }
        // Re-acquire first responder so the cursor position is valid
        if textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
        let range = textView.selectedRange()
        // Directly manipulate text storage with pill conversion, bypassing the delegate chain
        let attrStr = pillAttributedString(from: text)
        textView.textStorage?.replaceCharacters(in: range, with: attrStr)
        let newPos = range.location + attrStr.length
        textView.setSelectedRange(NSRange(location: newPos, length: 0))
        // Notify the coordinator so the binding updates
        textView.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: textView))
    }
}

/// NSViewRepresentable wrapping an NSScrollView + PillTextView for inline pill editing.
private struct TemplateTokenField: NSViewRepresentable {
    @Binding var template: String
    var textViewRef: TemplateTextViewRef?
    var onFocus: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(template: $template)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PillTextView()
        textView.onBecomeFirstResponder = onFocus
        context.coordinator.onFocus = onFocus
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isFieldEditor = false
        textView.usesFontPanel = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 2
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.delegate = context.coordinator
        textView.registerForDraggedTypes([.string])
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        // Set initial content
        let attrStr = pillAttributedString(from: template)
        textView.textStorage?.setAttributedString(attrStr)
        context.coordinator.isUpdating = false
        context.coordinator.textView = textView
        textViewRef?.textView = textView

        // Size the textView to fill the scrollView content area
        DispatchQueue.main.async {
            let contentSize = scrollView.contentSize
            let height = max(contentSize.height, 28)
            textView.minSize = NSSize(width: contentSize.width, height: height)
            textView.maxSize = NSSize(width: contentSize.width, height: height)
            textView.frame = NSRect(origin: .zero, size: NSSize(width: contentSize.width, height: height))
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PillTextView else { return }
        textView.onBecomeFirstResponder = onFocus
        context.coordinator.onFocus = onFocus
        // Rebind ref on every update so reused views keep refs valid
        textViewRef?.textView = textView

        // Keep textView size in sync with scrollView
        let contentSize = scrollView.contentSize
        if contentSize.width > 0 {
            let height = max(contentSize.height, 28)
            textView.minSize = NSSize(width: contentSize.width, height: height)
            textView.maxSize = NSSize(width: contentSize.width, height: height)
            if abs(textView.frame.width - contentSize.width) > 1 || abs(textView.frame.height - height) > 1 {
                textView.frame.size = NSSize(width: contentSize.width, height: height)
            }
        }

        // Only push changes when the binding was changed externally
        let current = rawTemplateString(from: textView.attributedString())
        if current != template {
            context.coordinator.isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.textStorage?.setAttributedString(pillAttributedString(from: template))
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdating = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var template: Binding<String>
        var isUpdating = true // suppress feedback during programmatic updates
        weak var textView: NSTextView?
        var onFocus: (() -> Void)?

        init(template: Binding<String>) {
            self.template = template
        }

        func textDidBeginEditing(_ notification: Notification) {
            onFocus?()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating else { return }
            guard let textView = notification.object as? NSTextView else { return }
            let raw = rawTemplateString(from: textView.attributedString())
            if raw != template.wrappedValue {
                template.wrappedValue = raw
            }
        }

        // Re-render pills after paste/drag so raw ${VAR} text becomes pills
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard let text, !isUpdating else { return true }
            let pattern = try! NSRegularExpression(pattern: #"\$\{([a-zA-Z][a-zA-Z0-9_]*)\}"#)
            if pattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil {
                // Contains variable tokens — replace with pill-attributed version
                isUpdating = true
                let attrStr = pillAttributedString(from: text)
                textView.textStorage?.replaceCharacters(in: range, with: attrStr)
                let newPos = range.location + attrStr.length
                textView.setSelectedRange(NSRange(location: newPos, length: 0))
                isUpdating = false
                // Manually fire change
                let raw = rawTemplateString(from: textView.attributedString())
                if raw != template.wrappedValue {
                    template.wrappedValue = raw
                }
                return false
            }
            return true
        }
    }
}

/// NSTextView subclass that accepts dragged strings and converts ${VAR} tokens to pills.
private final class PillTextView: NSTextView {
    var onBecomeFirstResponder: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onBecomeFirstResponder?() }
        return result
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSString.self]) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let str = sender.draggingPasteboard.string(forType: .string) {
            let pattern = try! NSRegularExpression(pattern: #"\$\{([a-zA-Z][a-zA-Z0-9_]*)\}"#)
            if pattern.firstMatch(in: str, range: NSRange(location: 0, length: (str as NSString).length)) != nil {
                let point = convert(sender.draggingLocation, from: nil)
                let insertionIndex = characterIndexForInsertion(at: point)
                let attrStr = pillAttributedString(from: str)
                textStorage?.insert(attrStr, at: insertionIndex)
                setSelectedRange(NSRange(location: insertionIndex + attrStr.length, length: 0))
                // Notify delegate
                delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
                return true
            }
        }
        return super.performDragOperation(sender)
    }
}

// MARK: - Template Editor Sheet

private struct TemplateEditorSheet: View {
    let template: URLTemplate
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""
    @State private var templateValue: String = ""
    private let textViewRef = TemplateTextViewRef()

    private let variables: [(token: String, label: String)] = [
        ("SCHEME", "Scheme"), ("BUCKET", "Bucket"), ("PATH", "Path"),
        ("BASENAME", "Basename"), ("KEY", "Key"), ("REGION", "Region"), ("ENDPOINT", "Endpoint")
    ]

    private var previewText: String {
        let replacements = [
            "${SCHEME}": "s3",
            "${BUCKET}": "my-bucket",
            "${PATH}": "photos/abc12345-image.png",
            "${BASENAME}": "image.png",
            "${KEY}": "abc12345-image.png",
            "${REGION}": "us-east-1",
            "${ENDPOINT}": "https://s3.us-east-1.amazonaws.com"
        ]
        var result = templateValue
        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Template")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Label")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Label", text: $label, prompt: Text("Public URL"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Template")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TemplateTokenField(template: $templateValue, textViewRef: textViewRef)
                    .frame(height: 32)
                if !templateValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(previewText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Variables")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(variables, id: \.token) { variable in
                        Button {
                            textViewRef.insertAtCursor("${\(variable.token)}")
                        } label: {
                            Text(variable.label)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .background(.quaternary, in: .capsule)
                        .draggable("${\(variable.token)}")
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(label, templateValue)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          templateValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            label = template.label
            templateValue = template.template
        }
    }
}

private struct PostUploadActionEditorSheet: View {
    let action: PostUploadAction
    let onSave: (PostUploadAction) -> Void

    @Environment(\.dismiss) private var dismiss

    // Shared state
    @State private var label: String = ""
    @State private var enabled: Bool = true

    // DynamoDB state
    @State private var tableName: String = ""
    @State private var dbRegion: String = ""
    @State private var attributes: [DynamoDBAttribute] = []
    @State private var selectedAttributeID: UUID?
    @State private var attributeRefs: [UUID: TemplateTextViewRef] = [:]
    @State private var showPreview = false

    // HTTP state
    @State private var httpURLTemplate: String = ""
    @State private var httpMethod: String = "POST"
    @State private var httpContentType: HTTPContentType = .json
    @State private var httpHeaders: [HTTPHeader] = []
    @State private var httpBodyTemplate: String = ""
    @State private var selectedHeaderID: UUID?
    @State private var headerRefs: [UUID: TemplateTextViewRef] = [:]
    @State private var httpURLRef = TemplateTextViewRef()
    @State private var httpBodyRef = TemplateTextViewRef()

    // Tracks the last focused TemplateTokenField ref for variable insertion
    @State private var lastFocusedRef: TemplateTextViewRef?

    private var isDynamoDB: Bool {
        if case .dynamoDB = action.actionType { return true }
        return false
    }

    private let variableReferences: [(token: String, label: String)] = [
        ("originalFilename", "Original Filename"),
        ("renamedFilename", "Renamed Filename"),
        ("path", "Path"),
        ("bucket", "Bucket"),
        ("region", "Region"),
        ("scheme", "Scheme"),
        ("url", "URL"),
        ("fileSize", "File Size"),
        ("contentType", "Content Type"),
        ("contentHash", "Content Hash"),
        ("hashAlgorithm", "Hash Algorithm"),
        ("timestamp", "Timestamp")
    ]

    private var canSave: Bool {
        switch action.actionType {
        case .dynamoDB:
            return !trim(tableName).isEmpty
        case .http:
            return !trim(httpURLTemplate).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isDynamoDB ? "Edit DynamoDB Action" : "Edit HTTP Action")
                .font(.headline)

            Toggle("Enabled", isOn: $enabled)

            VStack(alignment: .leading, spacing: 4) {
                Text("Label")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Label", text: $label, prompt: Text(isDynamoDB ? "File metadata table" : "Webhook notification"))
            }

            if isDynamoDB {
                dynamoDBFields
            } else {
                httpFields
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Variables")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 6) {
                    ForEach(variableReferences, id: \.token) { variable in
                        Button {
                            insertVariable(variable.token)
                        } label: {
                            Text(variable.label)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .background(.quaternary, in: .capsule)
                        .help("${\(variable.token)}")
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 680)
        .onAppear {
            loadFromAction()
        }
    }

    // MARK: - DynamoDB Fields

    @ViewBuilder
    private var dynamoDBFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Table Name")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Table Name", text: $tableName, prompt: Text("my-table-name"))
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Region")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Region", text: $dbRegion, prompt: Text("Same as bucket"))
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Attribute Mappings")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Attribute")
                        .frame(width: 100, alignment: .leading)
                    Divider()
                        .frame(height: 14)
                    Text("Type")
                        .frame(width: 70, alignment: .leading)
                    Divider()
                        .frame(height: 14)
                    Text("Value")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .padding(.vertical, 3)
                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($attributes) { $attribute in
                            let ref = refForAttribute(attribute.id)
                            HStack(spacing: 8) {
                                TextField("Attribute", text: $attribute.name)
                                    .frame(width: 100)

                                Picker("", selection: $attribute.type) {
                                    Text("String").tag("S")
                                    Text("Number").tag("N")
                                    Text("Boolean").tag("BOOL")
                                }
                                .labelsHidden()
                                .frame(width: 70)

                                TemplateTokenField(
                                    template: $attribute.valueTemplate,
                                    textViewRef: ref,
                                    onFocus: {
                                        selectedAttributeID = attribute.id
                                        lastFocusedRef = ref
                                    }
                                )
                                .frame(height: 22)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(attribute.id == selectedAttributeID ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                    }
                }
                .frame(height: 120)
                .background(Color(nsColor: .controlBackgroundColor))
                .border(Color(nsColor: .separatorColor))

                HStack(spacing: 0) {
                    Button {
                        addAttribute()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 18)
                    }
                    .buttonStyle(.borderless)

                    Divider()
                        .frame(height: 14)

                    Button {
                        removeSelectedAttribute()
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedAttributeID == nil)

                    Spacer()

                    Button("Preview") {
                        showPreview.toggle()
                    }
                    .buttonStyle(.link)
                    .popover(isPresented: $showPreview, arrowEdge: .bottom) {
                        previewJSON()
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - HTTP Fields

    @ViewBuilder
    private var httpFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("URL")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TemplateTokenField(template: $httpURLTemplate, textViewRef: httpURLRef, onFocus: { lastFocusedRef = httpURLRef })
                .frame(height: 32)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Method")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("", selection: $httpMethod) {
                Text("GET").tag("GET")
                Text("POST").tag("POST")
                Text("PUT").tag("PUT")
                Text("PATCH").tag("PATCH")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
        }

        if httpMethod != "GET" {
            VStack(alignment: .leading, spacing: 4) {
                Text("Content Type")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $httpContentType) {
                    ForEach(HTTPContentType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Headers")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Name")
                        .frame(width: 120, alignment: .leading)
                    Divider()
                        .frame(height: 14)
                    Text("Value")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .padding(.vertical, 3)
                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($httpHeaders) { $header in
                            let ref = refForHeader(header.id)
                            HStack(spacing: 8) {
                                TextField("Header", text: $header.name)
                                    .frame(width: 120)

                                TemplateTokenField(
                                    template: $header.valueTemplate,
                                    textViewRef: ref,
                                    onFocus: {
                                        selectedHeaderID = header.id
                                        lastFocusedRef = ref
                                    }
                                )
                                .frame(height: 22)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(header.id == selectedHeaderID ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                    }
                }
                .frame(height: 80)
                .background(Color(nsColor: .controlBackgroundColor))
                .border(Color(nsColor: .separatorColor))

                HStack(spacing: 0) {
                    Button {
                        addHeader()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 18)
                    }
                    .buttonStyle(.borderless)

                    Divider()
                        .frame(height: 14)

                    Button {
                        removeSelectedHeader()
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedHeaderID == nil)

                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }

        if httpMethod != "GET" {
            VStack(alignment: .leading, spacing: 4) {
                Text("Body")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TemplateTokenField(template: $httpBodyTemplate, textViewRef: httpBodyRef, onFocus: { lastFocusedRef = httpBodyRef })
                    .frame(height: 120)
            }
        }

        HStack {
            Spacer()
            Button("Preview") {
                showPreview.toggle()
            }
            .buttonStyle(.link)
            .popover(isPresented: $showPreview, arrowEdge: .bottom) {
                previewHTTPRequest()
            }
        }
    }

    // MARK: - Load / Save

    private func loadFromAction() {
        label = action.label
        enabled = action.enabled
        switch action.actionType {
        case .dynamoDB(let config):
            tableName = config.tableName
            dbRegion = config.region
            attributes = config.attributes
        case .http(let config):
            httpURLTemplate = config.urlTemplate
            httpMethod = config.method
            httpContentType = config.contentType
            httpHeaders = config.headers
            httpBodyTemplate = config.bodyTemplate
        }
    }

    private func save() {
        let actionType: PostUploadActionType

        switch action.actionType {
        case .dynamoDB:
            var cleanedAttributes: [DynamoDBAttribute] = []
            cleanedAttributes.reserveCapacity(attributes.count)
            for attribute in attributes {
                let name = trim(attribute.name)
                if name.isEmpty { continue }
                cleanedAttributes.append(
                    DynamoDBAttribute(
                        id: attribute.id,
                        name: name,
                        type: trim(attribute.type).uppercased(),
                        valueTemplate: attribute.valueTemplate
                    )
                )
            }
            actionType = .dynamoDB(
                DynamoDBActionConfig(
                    tableName: trim(tableName),
                    region: trim(dbRegion),
                    attributes: cleanedAttributes
                )
            )

        case .http:
            var cleanedHeaders: [HTTPHeader] = []
            for header in httpHeaders {
                let name = trim(header.name)
                if name.isEmpty { continue }
                cleanedHeaders.append(
                    HTTPHeader(id: header.id, name: name, valueTemplate: header.valueTemplate)
                )
            }
            actionType = .http(
                HTTPActionConfig(
                    urlTemplate: trim(httpURLTemplate),
                    method: httpMethod,
                    contentType: httpContentType,
                    headers: cleanedHeaders,
                    bodyTemplate: httpMethod == "GET" ? "" : httpBodyTemplate
                )
            )
        }

        let updatedAction = PostUploadAction(
            id: action.id,
            enabled: enabled,
            label: trim(label),
            actionType: actionType
        )

        onSave(updatedAction)
        dismiss()
    }

    // MARK: - DynamoDB Helpers

    private func addAttribute() {
        let attr = DynamoDBAttribute(name: "", type: "S", valueTemplate: "")
        attributes.append(attr)
        selectedAttributeID = attr.id
    }

    private func removeSelectedAttribute() {
        guard let selectedAttributeID else { return }
        attributeRefs.removeValue(forKey: selectedAttributeID)
        attributes.removeAll { $0.id == selectedAttributeID }
        self.selectedAttributeID = nil
    }

    private func refForAttribute(_ id: UUID) -> TemplateTextViewRef {
        if let ref = attributeRefs[id] { return ref }
        let ref = TemplateTextViewRef()
        attributeRefs[id] = ref
        return ref
    }

    // MARK: - HTTP Helpers

    private func addHeader() {
        let header = HTTPHeader(name: "", valueTemplate: "")
        httpHeaders.append(header)
        selectedHeaderID = header.id
    }

    private func removeSelectedHeader() {
        guard let selectedHeaderID else { return }
        headerRefs.removeValue(forKey: selectedHeaderID)
        httpHeaders.removeAll { $0.id == selectedHeaderID }
        self.selectedHeaderID = nil
    }

    private func refForHeader(_ id: UUID) -> TemplateTextViewRef {
        if let ref = headerRefs[id] { return ref }
        let ref = TemplateTextViewRef()
        headerRefs[id] = ref
        return ref
    }

    // MARK: - Variable Insertion (unified)

    private func insertVariable(_ token: String) {
        // Use the last focused template field (tracked via onFocus callbacks)
        if let lastFocusedRef {
            lastFocusedRef.insertAtCursor("${\(token)}")
            return
        }

        // Fallback: for DynamoDB fall back to selected attribute row, for HTTP fall back to body
        if isDynamoDB {
            if let selectedAttributeID, let ref = attributeRefs[selectedAttributeID] {
                ref.insertAtCursor("${\(token)}")
            }
        } else {
            httpBodyRef.insertAtCursor("${\(token)}")
        }
    }

    // MARK: - DynamoDB Preview

    @ViewBuilder
    private func previewJSON() -> some View {
        let exampleValues: [String: String] = [
            "originalFilename": "photo.png",
            "renamedFilename": "a1b2c3.png",
            "path": "myfolder/a1b2c3.png",
            "bucket": "my-bucket",
            "region": dbRegion.isEmpty ? "us-east-1" : dbRegion,
            "scheme": "s3",
            "url": "https://cdn.example.com/myfolder/a1b2c3.png",
            "fileSize": "284521",
            "contentType": "image/png",
            "contentHash": "a1b2c3d4e5f6...",
            "hashAlgorithm": "sha256",
            "timestamp": "2026-02-22T10:30:00Z"
        ]

        let itemFields = attributes.compactMap { attr -> String? in
            let name = trim(attr.name)
            guard !name.isEmpty else { return nil }
            var resolved = attr.valueTemplate
            for (key, val) in exampleValues {
                resolved = resolved.replacingOccurrences(of: "${\(key)}", with: val)
            }
            let escaped = resolved
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "      \"\(name)\": { \"\(attr.type)\": \"\(escaped)\" }"
        }

        let json = """
        {
          "TableName": "\(trim(tableName).isEmpty ? "my-table" : trim(tableName))",
          "Item": {
        \(itemFields.joined(separator: ",\n"))
          }
        }
        """

        Text(json)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .padding(12)
            .frame(minWidth: 360)
    }

    // MARK: - HTTP Preview

    @ViewBuilder
    private func previewHTTPRequest() -> some View {
        let exampleValues: [String: String] = [
            "originalFilename": "photo.png",
            "renamedFilename": "a1b2c3.png",
            "path": "myfolder/a1b2c3.png",
            "bucket": "my-bucket",
            "region": "us-east-1",
            "scheme": "s3",
            "url": "https://cdn.example.com/myfolder/a1b2c3.png",
            "fileSize": "284521",
            "contentType": "image/png",
            "contentHash": "a1b2c3d4e5f6...",
            "hashAlgorithm": "sha256",
            "timestamp": "2026-02-22T10:30:00Z"
        ]
        let resolved: String = {
            var result = httpBodyTemplate
            for (key, val) in exampleValues {
                result = result.replacingOccurrences(of: "${\(key)}", with: val)
            }
            return result
        }()

        Text(resolved)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .padding(8)
            .frame(minWidth: 300)
    }

    private func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight + (i > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [UploadedFile.self, BucketConfig.self], inMemory: true)
}
