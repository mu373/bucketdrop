//
//  BucketConfig.swift
//  BucketDrop
//
//  Created by Codex on 20/02/26.
//

import Foundation
import SwiftData

struct DynamoDBAttribute: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String = ""
    var type: String = "S" // S, N, BOOL
    var valueTemplate: String = ""
}

struct DynamoDBActionConfig: Codable, Hashable, Sendable {
    var tableName: String = ""
    var region: String = ""
    var attributes: [DynamoDBAttribute] = []
}

struct HTTPHeader: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String = ""
    var valueTemplate: String = ""   // supports ${token} variables
}

enum HTTPContentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case json = "application/json"
    case form = "application/x-www-form-urlencoded"
    case text = "text/plain"
    case none = ""

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .json: return "JSON"
        case .form: return "Form URL-Encoded"
        case .text: return "Plain Text"
        case .none: return "None"
        }
    }
}

struct HTTPActionConfig: Codable, Hashable, Sendable {
    var urlTemplate: String = ""     // supports ${token} variables
    var method: String = "POST"      // POST | PUT | PATCH
    var contentType: HTTPContentType = .json
    var headers: [HTTPHeader] = []
    var bodyTemplate: String = ""    // supports ${token} variables

    init(urlTemplate: String = "", method: String = "POST", contentType: HTTPContentType = .json, headers: [HTTPHeader] = [], bodyTemplate: String = "") {
        self.urlTemplate = urlTemplate
        self.method = method
        self.contentType = contentType
        self.headers = headers
        self.bodyTemplate = bodyTemplate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        urlTemplate = try container.decodeIfPresent(String.self, forKey: .urlTemplate) ?? ""
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? "POST"
        contentType = try container.decodeIfPresent(HTTPContentType.self, forKey: .contentType) ?? .json
        headers = try container.decodeIfPresent([HTTPHeader].self, forKey: .headers) ?? []
        bodyTemplate = try container.decodeIfPresent(String.self, forKey: .bodyTemplate) ?? ""
    }
}

enum PostUploadActionType: Codable, Hashable, Sendable {
    case dynamoDB(DynamoDBActionConfig)
    case http(HTTPActionConfig)
}

struct PostUploadAction: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var enabled: Bool = true
    var label: String = ""
    var actionType: PostUploadActionType
}

struct URLTemplate: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var label: String
    var template: String

    init(id: UUID = UUID(), label: String, template: String) {
        self.id = id
        self.label = label
        self.template = template
    }

    static func presets() -> [URLTemplate] {
        [
            URLTemplate(label: "Public URL", template: "https://example.com/${PATH}"),
            URLTemplate(label: "S3 URI", template: "s3://${BUCKET}/${PATH}"),
            URLTemplate(label: "AWS Direct", template: "https://${BUCKET}.s3.${REGION}.amazonaws.com/${PATH}")
        ]
    }
}

enum RenameMode: String, CaseIterable, Identifiable, Sendable {
    case original
    case dateTime
    case hash
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "Don't Rename"
        case .dateTime: return "Date and Time"
        case .hash: return "Hash"
        case .custom: return "Custom"
        }
    }
}

enum DateTimeFormat: String, CaseIterable, Identifiable, Sendable {
    case unix
    case iso8601
    case compact
    case dateOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unix: return "Unix Timestamp"
        case .iso8601: return "ISO 8601"
        case .compact: return "Compact"
        case .dateOnly: return "Date Only"
        }
    }

    var example: String {
        switch self {
        case .unix: return "1740062445"
        case .iso8601: return "2025-02-20T14:30:45Z"
        case .compact: return "20250220143045"
        case .dateOnly: return "2025-02-20"
        }
    }
}

enum HashAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case sha256
    case md5

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sha256: return "SHA-256"
        case .md5: return "MD5"
        }
    }
}

enum BucketProvider: String, CaseIterable, Identifiable, Sendable {
    case awsS3 = "awsS3"
    case googleCloud = "googleCloud"
    case cloudflareR2 = "cloudflareR2"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .awsS3:
            return "AWS S3"
        case .googleCloud:
            return "Google Cloud Storage"
        case .cloudflareR2:
            return "Cloudflare R2"
        case .other:
            return "Other"
        }
    }

    var defaultRegion: String? {
        switch self {
        case .awsS3:
            return "us-east-1"
        case .googleCloud, .cloudflareR2:
            return "auto"
        case .other:
            return nil
        }
    }

    var defaultEndpoint: String? {
        switch self {
        case .awsS3:
            return ""
        case .googleCloud:
            return "https://storage.googleapis.com"
        case .cloudflareR2:
            return ""
        case .other:
            return nil
        }
    }

    var defaultScheme: String? {
        switch self {
        case .awsS3:
            return "s3"
        case .cloudflareR2:
            return "r2"
        case .googleCloud:
            return "gcs"
        case .other:
            return nil
        }
    }
}

@Model
final class BucketConfig {
    @Attribute(.unique) var id: UUID
    var name: String
    var provider: String = BucketProvider.other.rawValue
    var accessKeyId: String
    var secretAccessKey: String
    var bucket: String
    var region: String
    var endpoint: String
    var keyPrefix: String
    var uriScheme: String = "s3"
    var sortOrder: Int
    var urlTemplates: [URLTemplate]
    var renameMode: String = RenameMode.original.rawValue
    var dateTimeFormat: String = DateTimeFormat.unix.rawValue
    var hashAlgorithm: String = HashAlgorithm.sha256.rawValue
    var customRenameTemplate: String = "${original}"
    var copyURLAfterUpload: Bool = true
    var postUploadActions: [PostUploadAction] = []

    init(
        id: UUID = UUID(),
        name: String,
        provider: String = BucketProvider.other.rawValue,
        accessKeyId: String = "",
        secretAccessKey: String = "",
        bucket: String = "",
        region: String = "us-east-1",
        endpoint: String = "",
        keyPrefix: String = "",
        uriScheme: String = "s3",
        sortOrder: Int = 0,
        urlTemplates: [URLTemplate] = [],
        renameMode: String = RenameMode.original.rawValue,
        dateTimeFormat: String = DateTimeFormat.unix.rawValue,
        hashAlgorithm: String = HashAlgorithm.sha256.rawValue,
        customRenameTemplate: String = "${ORIGINAL}",
        copyURLAfterUpload: Bool = true,
        postUploadActions: [PostUploadAction] = []
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.bucket = bucket
        self.region = region
        self.endpoint = endpoint
        self.keyPrefix = keyPrefix
        self.uriScheme = uriScheme
        self.sortOrder = sortOrder
        self.urlTemplates = urlTemplates
        self.renameMode = renameMode
        self.dateTimeFormat = dateTimeFormat
        self.hashAlgorithm = hashAlgorithm
        self.customRenameTemplate = customRenameTemplate
        self.copyURLAfterUpload = copyURLAfterUpload
        self.postUploadActions = postUploadActions
    }
}
