//
//  S3Service.swift
//  BucketDrop
//
//  Created by Fayaz Ahmed Aralikatti on 12/01/26.
//

import Foundation
import CryptoKit

actor S3Service {
    static let shared = S3Service()

    struct S3Error: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct UploadResult {
        let key: String
        let url: String
        let contentType: String
        let contentHash: String
    }

    private struct BucketConfigValues: Sendable {
        let id: UUID
        let name: String
        let accessKeyId: String
        let secretAccessKey: String
        let bucket: String
        let region: String
        let endpoint: String
        let keyPrefix: String
        let uriScheme: String
        let urlTemplates: [URLTemplate]
        let renameMode: RenameMode
        let dateTimeFormat: DateTimeFormat
        let hashAlgorithm: HashAlgorithm
        let customRenameTemplate: String

        init(config: BucketConfig) {
            self.id = config.id
            self.name = config.name
            self.accessKeyId = config.accessKeyId
            self.secretAccessKey = config.secretAccessKey
            self.bucket = config.bucket
            self.region = config.region
            self.endpoint = config.endpoint
            self.keyPrefix = config.keyPrefix
            self.uriScheme = config.uriScheme
            self.urlTemplates = config.urlTemplates
            self.renameMode = RenameMode(rawValue: config.renameMode) ?? .original
            self.dateTimeFormat = DateTimeFormat(rawValue: config.dateTimeFormat) ?? .unix
            self.hashAlgorithm = HashAlgorithm(rawValue: config.hashAlgorithm) ?? .sha256
            self.customRenameTemplate = config.customRenameTemplate
        }

        var isConfigured: Bool {
            !accessKeyId.isEmpty && !secretAccessKey.isEmpty && !bucket.isEmpty
        }
    }

    // MARK: - Public API

    nonisolated func upload(
        fileURL: URL,
        config: BucketConfig,
        progress: ((Double) -> Void)? = nil
    ) async throws -> UploadResult {
        let values = BucketConfigValues(config: config)
        return try await upload(fileURL: fileURL, config: values, progress: progress)
    }

    nonisolated func listObjects(config: BucketConfig) async throws -> [S3Object] {
        let values = BucketConfigValues(config: config)
        return try await listObjects(config: values)
    }

    @discardableResult
    nonisolated func download(
        key: String,
        to destination: URL,
        config: BucketConfig,
        overwrite: Bool = false,
        progress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let values = BucketConfigValues(config: config)
        return try await download(
            key: key,
            to: destination,
            config: values,
            overwrite: overwrite,
            progress: progress
        )
    }

    nonisolated func deleteObject(key: String, config: BucketConfig) async throws {
        let values = BucketConfigValues(config: config)
        try await deleteObject(key: key, config: values)
    }

    nonisolated func buildURL(
        key: String,
        config: BucketConfig,
        template: URLTemplate? = nil,
        basename: String? = nil
    ) -> String {
        let values = BucketConfigValues(config: config)
        return buildURL(key: key, config: values, template: template, basename: basename)
    }

    // MARK: - Upload

    private func upload(
        fileURL: URL,
        config: BucketConfigValues,
        progress: ((Double) -> Void)? = nil
    ) async throws -> UploadResult {
        guard config.isConfigured else {
            throw S3Error(message: "S3 not configured. Please add credentials in settings.")
        }

        let data = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let ext = fileURL.pathExtension

        let keyWithoutPrefix: String
        let basename: String
        var contentHash = ""
        switch config.renameMode {
        case .original:
            keyWithoutPrefix = filename
            basename = filename
        case .dateTime:
            let now = Date()
            let stem: String
            switch config.dateTimeFormat {
            case .unix:
                stem = "\(Int(now.timeIntervalSince1970))"
            case .iso8601:
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                f.timeZone = TimeZone(identifier: "UTC")
                stem = f.string(from: now)
                    .replacingOccurrences(of: ":", with: "-")
            case .compact:
                let f = DateFormatter()
                f.dateFormat = "yyyyMMddHHmmss"
                f.timeZone = TimeZone(identifier: "UTC")
                stem = f.string(from: now)
            case .dateOnly:
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.timeZone = TimeZone(identifier: "UTC")
                stem = f.string(from: now)
            }
            let renamed = ext.isEmpty ? stem : "\(stem).\(ext)"
            keyWithoutPrefix = renamed
            basename = renamed
        case .hash:
            let hashHex: String
            switch config.hashAlgorithm {
            case .sha256:
                hashHex = SHA256.hash(data: data).hexString
            case .md5:
                hashHex = Insecure.MD5.hash(data: data).hexString
            }
            contentHash = hashHex
            let renamed = ext.isEmpty ? hashHex : "\(hashHex).\(ext)"
            keyWithoutPrefix = renamed
            basename = renamed
        case .custom:
            let now = Date()
            let cal = Calendar.current
            let comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: now)
            let origBasename = (filename as NSString).deletingPathExtension

            let hashHex: String
            switch config.hashAlgorithm {
            case .sha256:
                hashHex = SHA256.hash(data: data).hexString
            case .md5:
                hashHex = Insecure.MD5.hash(data: data).hexString
            }
            contentHash = hashHex

            let replacements: [(String, String)] = [
                ("${original}", filename),
                ("${basename}", origBasename),
                ("${ext}", ext),
                ("${year}", String(format: "%04d", comps.year ?? 0)),
                ("${month}", String(format: "%02d", comps.month ?? 0)),
                ("${day}", String(format: "%02d", comps.day ?? 0)),
                ("${hour}", String(format: "%02d", comps.hour ?? 0)),
                ("${minute}", String(format: "%02d", comps.minute ?? 0)),
                ("${second}", String(format: "%02d", comps.second ?? 0)),
                ("${timestamp}", "\(Int(now.timeIntervalSince1970))"),
                ("${hash}", hashHex),
                ("${uuid}", String(UUID().uuidString.prefix(8)))
            ]

            var resolved = config.customRenameTemplate
            for (token, value) in replacements {
                resolved = resolved.replacingOccurrences(of: token, with: value)
            }
            keyWithoutPrefix = resolved
            basename = resolved
        }

        let key = normalizedPrefix(config.keyPrefix) + keyWithoutPrefix

        let contentType = mimeType(for: ext)

        try await putObject(key: key, data: data, contentType: contentType, config: config, progress: progress)

        let url = buildURL(key: key, config: config, template: config.urlTemplates.first, basename: basename)
        return UploadResult(
            key: key,
            url: url,
            contentType: contentType,
            contentHash: contentHash
        )
    }

    // MARK: - List Objects

    private func listObjects(config: BucketConfigValues) async throws -> [S3Object] {
        guard config.isConfigured else {
            throw S3Error(message: "S3 not configured")
        }

        let host = buildHost(config: config)
        let endpoint = buildEndpoint(config: config)
        let signingPath = buildSigningPath(objectKey: nil, config: config)
        let prefix = normalizedPrefix(config.keyPrefix)

        var queryItems: [String] = ["list-type=2", "max-keys=200"]
        if !prefix.isEmpty {
            queryItems.append("prefix=\(awsURLEncodeQueryValue(prefix))")
        }
        let query = queryItems.joined(separator: "&")

        let urlString = "\(endpoint)/?\(query)"
        guard let url = URL(string: urlString) else {
            throw S3Error(message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let headers = try AWSSigner.signRequest(
            method: "GET",
            path: signingPath,
            query: query,
            headers: ["host": host],
            payload: Data(),
            accessKey: config.accessKeyId,
            secretKey: config.secretAccessKey,
            region: config.region,
            service: "s3"
        )

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw S3Error(message: "Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw S3Error(message: "List failed: \(httpResponse.statusCode) - \(body)")
        }

        return parseListResponse(data)
    }

    // MARK: - Download Object

    @discardableResult
    private func download(
        key: String,
        to destination: URL,
        config: BucketConfigValues,
        overwrite: Bool = false,
        progress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        guard config.isConfigured else {
            throw S3Error(message: "S3 not configured")
        }

        let host = buildHost(config: config)
        let endpoint = buildEndpoint(config: config)
        let encodedKey = awsURLEncodePath(key)
        let signingPath = buildSigningPath(objectKey: key, config: config)

        guard let url = URL(string: "\(endpoint)/\(encodedKey)") else {
            throw S3Error(message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let headers = try AWSSigner.signRequest(
            method: "GET",
            path: signingPath,
            query: "",
            headers: ["host": host],
            payload: Data(),
            accessKey: config.accessKeyId,
            secretKey: config.secretAccessKey,
            region: config.region,
            service: "s3"
        )

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw S3Error(message: "Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw S3Error(message: "Download failed: \(httpResponse.statusCode)")
        }

        let expectedLength = httpResponse.expectedContentLength
        var data = Data()
        if expectedLength > 0 {
            data.reserveCapacity(Int(expectedLength))
        }

        var receivedLength: Int64 = 0
        for try await byte in asyncBytes {
            data.append(byte)
            receivedLength += 1

            if expectedLength > 0 && receivedLength % 65536 == 0 {
                progress?(Double(receivedLength) / Double(expectedLength))
            }
        }

        progress?(1.0)

        let fileManager = FileManager.default
        var finalDestination = destination

        if fileManager.fileExists(atPath: destination.path) {
            if overwrite {
                try fileManager.removeItem(at: destination)
            } else {
                let directory = destination.deletingLastPathComponent()
                let filename = destination.deletingPathExtension().lastPathComponent
                let ext = destination.pathExtension
                var counter = 1

                repeat {
                    let newName = ext.isEmpty ? "\(filename) (\(counter))" : "\(filename) (\(counter)).\(ext)"
                    finalDestination = directory.appendingPathComponent(newName)
                    counter += 1
                } while fileManager.fileExists(atPath: finalDestination.path)
            }
        }

        try data.write(to: finalDestination)
        return finalDestination
    }

    // MARK: - Delete Object

    private func deleteObject(key: String, config: BucketConfigValues) async throws {
        guard config.isConfigured else {
            throw S3Error(message: "S3 not configured")
        }

        let host = buildHost(config: config)
        let endpoint = buildEndpoint(config: config)
        let encodedKey = awsURLEncodePath(key)
        let signingPath = buildSigningPath(objectKey: key, config: config)

        guard let url = URL(string: "\(endpoint)/\(encodedKey)") else {
            throw S3Error(message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let headers = try AWSSigner.signRequest(
            method: "DELETE",
            path: signingPath,
            query: "",
            headers: ["host": host],
            payload: Data(),
            accessKey: config.accessKeyId,
            secretKey: config.secretAccessKey,
            region: config.region,
            service: "s3"
        )

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw S3Error(message: "Invalid response")
        }

        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw S3Error(message: "Delete failed: \(httpResponse.statusCode) - \(body)")
        }
    }

    // MARK: - Private Methods

    private func putObject(
        key: String,
        data: Data,
        contentType: String,
        config: BucketConfigValues,
        progress: ((Double) -> Void)?
    ) async throws {
        let host = buildHost(config: config)
        let endpoint = buildEndpoint(config: config)
        let encodedKey = awsURLEncodePath(key)
        let signingPath = buildSigningPath(objectKey: key, config: config)

        guard let url = URL(string: "\(endpoint)/\(encodedKey)") else {
            throw S3Error(message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data

        let headers = try AWSSigner.signRequest(
            method: "PUT",
            path: signingPath,
            query: "",
            headers: [
                "host": host,
                "content-type": contentType
            ],
            payload: data,
            accessKey: config.accessKeyId,
            secretKey: config.secretAccessKey,
            region: config.region,
            service: "s3"
        )

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw S3Error(message: "Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            print("[S3Service] Upload failed: \(httpResponse.statusCode) - \(body)")
            throw S3Error(message: "Upload failed: \(httpResponse.statusCode) - \(body)")
        }

        print("[S3Service] Upload succeeded for key: \(key)")
        progress?(1)
    }

    nonisolated private func isCustomEndpoint(config: BucketConfigValues) -> Bool {
        !config.endpoint.isEmpty
    }

    nonisolated private func buildHost(config: BucketConfigValues) -> String {
        if isCustomEndpoint(config: config) {
            if let url = URL(string: config.endpoint), let host = url.host {
                return host
            }
        }

        return "\(config.bucket).s3.\(config.region).amazonaws.com"
    }

    nonisolated private func buildEndpoint(config: BucketConfigValues) -> String {
        if isCustomEndpoint(config: config) {
            let base = trimTrailingSlash(config.endpoint)
            return "\(base)/\(config.bucket)"
        }

        return "https://\(config.bucket).s3.\(config.region).amazonaws.com"
    }

    nonisolated private func buildSigningPath(objectKey: String?, config: BucketConfigValues) -> String {
        if isCustomEndpoint(config: config) {
            if let key = objectKey {
                let encodedKey = awsURLEncodePath(key)
                return "/\(config.bucket)/\(encodedKey)"
            }
            return "/\(config.bucket)/"
        }

        if let key = objectKey {
            let encodedKey = awsURLEncodePath(key)
            return "/\(encodedKey)"
        }
        return "/"
    }

    private func mimeType(for ext: String) -> String {
        let mimeTypes: [String: String] = [
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "webp": "image/webp",
            "svg": "image/svg+xml",
            "pdf": "application/pdf",
            "zip": "application/zip",
            "mp4": "video/mp4",
            "mov": "video/quicktime",
            "mp3": "audio/mpeg",
            "txt": "text/plain",
            "html": "text/html",
            "css": "text/css",
            "js": "application/javascript",
            "json": "application/json"
        ]
        return mimeTypes[ext.lowercased()] ?? "application/octet-stream"
    }

    private func parseListResponse(_ data: Data) -> [S3Object] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }

        var objects: [S3Object] = []
        let contents = xml.components(separatedBy: "<Contents>")

        for content in contents.dropFirst() {
            guard let keyEnd = content.range(of: "</Key>"),
                  let keyStart = content.range(of: "<Key>") else {
                continue
            }

            let key = String(content[keyStart.upperBound..<keyEnd.lowerBound])

            var size: Int64 = 0
            if let sizeStart = content.range(of: "<Size>"),
               let sizeEnd = content.range(of: "</Size>") {
                size = Int64(content[sizeStart.upperBound..<sizeEnd.lowerBound]) ?? 0
            }

            var lastModified: Date?
            if let dateStart = content.range(of: "<LastModified>"),
               let dateEnd = content.range(of: "</LastModified>") {
                let dateString = String(content[dateStart.upperBound..<dateEnd.lowerBound])
                lastModified = parseLastModified(dateString)
            }

            objects.append(S3Object(key: key, size: size, lastModified: lastModified ?? Date()))
        }

        return objects.sorted { $0.lastModified > $1.lastModified }
    }

    nonisolated private func parseLastModified(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }

    nonisolated private func normalizedPrefix(_ prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasSuffix("/") ? trimmed : "\(trimmed)/"
    }

    nonisolated private func trimTrailingSlash(_ value: String) -> String {
        value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    nonisolated private func awsURLEncodePath(_ path: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: unreserved) ?? String(segment)
            }
            .joined(separator: "/")
    }

    nonisolated private func awsURLEncodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    nonisolated private func extractBasename(from key: String) -> String {
        (key as NSString).lastPathComponent
    }

    nonisolated private func keyWithoutPrefix(from key: String) -> String {
        (key as NSString).lastPathComponent
    }

    nonisolated private func resolveTemplate(
        _ template: String,
        key: String,
        config: BucketConfigValues,
        basename: String?
    ) -> String {
        let resolvedBasename = basename ?? extractBasename(from: key)
        let resolvedKey = keyWithoutPrefix(from: key)
        let replacements = [
            "${SCHEME}": config.uriScheme,
            "${BUCKET}": config.bucket,
            "${PATH}": awsURLEncodePath(key),
            "${BASENAME}": awsURLEncodePath(resolvedBasename),
            "${KEY}": awsURLEncodePath(resolvedKey),
            "${REGION}": config.region,
            "${ENDPOINT}": trimTrailingSlash(config.endpoint)
        ]

        var result = template
        for (magic, replacement) in replacements {
            result = result.replacingOccurrences(of: magic, with: replacement)
        }
        return result
    }

    nonisolated private func buildURL(
        key: String,
        config: BucketConfigValues,
        template: URLTemplate? = nil,
        basename: String? = nil
    ) -> String {
        let activeTemplate = template ?? config.urlTemplates.first
        if let templateString = activeTemplate?.template.trimmingCharacters(in: .whitespacesAndNewlines),
           !templateString.isEmpty {
            return resolveTemplate(templateString, key: key, config: config, basename: basename)
        }

        return "\(buildEndpoint(config: config))/\(awsURLEncodePath(key))"
    }
}

final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Int64, Int64) -> Void

    init(onProgress: @escaping (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(totalBytesSent, totalBytesExpectedToSend)
    }
}

final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Int64, Int64) -> Void

    init(onProgress: @escaping (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceiveInformationalResponse response: HTTPURLResponse
    ) {
        // Optional: handle informational responses
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        // Optional: handle metrics
    }
}

extension DownloadProgressDelegate: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Required by protocol but handled by async/await
    }
}

struct S3Object: Identifiable {
    let id = UUID()
    let key: String
    let size: Int64
    let lastModified: Date

    var filename: String {
        (key as NSString).lastPathComponent
    }
}
