//
//  DynamoDBService.swift
//  BucketDrop
//
//  Created by Codex on 22/02/26.
//

import Foundation

struct UploadMetadata: Sendable {
    var originalFilename: String
    var renamedFilename: String
    var s3Key: String
    var bucket: String
    var region: String
    var url: String
    var fileSize: Int64
    var contentType: String
    var contentHash: String
    var timestamp: String

    nonisolated func resolveTemplate(_ template: String) -> String {
        let replacements = [
            "${originalFilename}": originalFilename,
            "${renamedFilename}": renamedFilename,
            "${s3Key}": s3Key,
            "${bucket}": bucket,
            "${region}": region,
            "${url}": url,
            "${fileSize}": "\(fileSize)",
            "${contentType}": contentType,
            "${contentHash}": contentHash,
            "${timestamp}": timestamp
        ]

        var resolved = template
        for (token, value) in replacements {
            resolved = resolved.replacingOccurrences(of: token, with: value)
        }
        return resolved
    }
}

actor DynamoDBService {
    static let shared = DynamoDBService()

    struct DynamoDBError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func putItem(
        action: DynamoDBActionConfig,
        metadata: UploadMetadata,
        credentials: (accessKeyId: String, secretAccessKey: String),
        bucketRegion: String
    ) async throws {
        let tableName = action.tableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tableName.isEmpty else {
            throw DynamoDBError(message: "Table name is required")
        }

        let requestedRegion = action.region.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRegion = requestedRegion.isEmpty
            ? bucketRegion.trimmingCharacters(in: .whitespacesAndNewlines)
            : requestedRegion
        guard !resolvedRegion.isEmpty else {
            throw DynamoDBError(message: "Region is required")
        }

        var item: [String: Any] = [:]
        for attribute in action.attributes {
            let name = attribute.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                continue
            }

            let value = metadata.resolveTemplate(attribute.valueTemplate)
            switch attribute.type.uppercased() {
            case "S":
                item[name] = ["S": value]
            case "N":
                item[name] = ["N": value]
            case "BOOL":
                item[name] = ["BOOL": try parseBool(value, attributeName: name)]
            default:
                throw DynamoDBError(message: "Unsupported DynamoDB attribute type '\(attribute.type)' for '\(name)'")
            }
        }

        guard !item.isEmpty else {
            throw DynamoDBError(message: "At least one DynamoDB attribute is required")
        }

        let payloadObject: [String: Any] = [
            "TableName": tableName,
            "Item": item
        ]
        let payload = try JSONSerialization.data(withJSONObject: payloadObject)

        let host = "dynamodb.\(resolvedRegion).amazonaws.com"
        guard let url = URL(string: "https://\(host)/") else {
            throw DynamoDBError(message: "Invalid DynamoDB endpoint for region \(resolvedRegion)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload

        let signedHeaders = try AWSSigner.signRequest(
            method: "POST",
            path: "/",
            query: "",
            headers: [
                "host": host,
                "X-Amz-Target": "DynamoDB_20120810.PutItem",
                "Content-Type": "application/x-amz-json-1.0"
            ],
            payload: payload,
            accessKey: credentials.accessKeyId,
            secretKey: credentials.secretAccessKey,
            region: resolvedRegion,
            service: "dynamodb"
        )
        for (key, value) in signedHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DynamoDBError(message: "Invalid DynamoDB response")
        }

        let responseBody = String(data: responseData, encoding: .utf8) ?? ""
        if httpResponse.statusCode != 200 {
            throw DynamoDBError(message: "PutItem failed: \(httpResponse.statusCode) - \(responseBody)")
        }

        if let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let errorType = object["__type"] as? String {
            let message = object["message"] as? String ?? responseBody
            throw DynamoDBError(message: "PutItem error (\(errorType)): \(message)")
        }
    }

    private func parseBool(_ rawValue: String, attributeName: String) throws -> Bool {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["true", "1", "yes"].contains(normalized) {
            return true
        }
        if ["false", "0", "no"].contains(normalized) {
            return false
        }
        throw DynamoDBError(message: "Invalid BOOL value '\(rawValue)' for '\(attributeName)'")
    }
}
