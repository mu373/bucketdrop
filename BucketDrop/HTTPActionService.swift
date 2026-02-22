//
//  HTTPActionService.swift
//  BucketDrop
//
//  Created by Codex on 22/02/26.
//

import Foundation

actor HTTPActionService {
    static let shared = HTTPActionService()

    struct HTTPActionError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func perform(action: PostUploadAction, metadata: UploadMetadata) async throws {
        guard case .http(let config) = action.actionType else {
            throw HTTPActionError(message: "Post-upload action is not an HTTP action")
        }

        let resolvedURLTemplate = metadata.resolveTemplate(config.urlTemplate)
        let resolvedURLString = resolvedURLTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedURLString.isEmpty else {
            throw HTTPActionError(message: "HTTP URL is required")
        }
        guard let url = URL(string: resolvedURLString) else {
            throw HTTPActionError(message: "Invalid HTTP URL '\(resolvedURLString)'")
        }

        let method = config.method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard ["GET", "POST", "PUT", "PATCH"].contains(method) else {
            throw HTTPActionError(message: "Unsupported HTTP method '\(config.method)'. Use GET, POST, PUT, or PATCH.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if method != "GET" {
            let resolvedBody = metadata.resolveTemplate(config.bodyTemplate)
            request.httpBody = Data(resolvedBody.utf8)
        }

        if config.contentType != .none {
            request.setValue(config.contentType.rawValue, forHTTPHeaderField: "Content-Type")
        }

        for header in config.headers {
            let name = metadata.resolveTemplate(header.name).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                continue
            }
            let value = metadata.resolveTemplate(header.valueTemplate)
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPActionError(message: "Invalid HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: responseData, encoding: .utf8) ?? ""
            throw HTTPActionError(message: "HTTP action failed: \(httpResponse.statusCode) - \(responseBody)")
        }
    }
}
