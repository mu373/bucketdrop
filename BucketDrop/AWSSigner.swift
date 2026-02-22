//
//  AWSSigner.swift
//  BucketDrop
//
//  Created by Codex on 22/02/26.
//

import Foundation
import CryptoKit

enum AWSSigner {
    nonisolated static func signRequest(
        method: String,
        path: String,
        query: String,
        headers: [String: String],
        payload: Data,
        accessKey: String,
        secretKey: String,
        region: String,
        service: String
    ) throws -> [String: String] {
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let amzDate = dateFormatter.string(from: now)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
        let dateStamp = String(amzDate.prefix(8))

        let payloadHash = SHA256.hash(data: payload).hexString

        var allHeaders = headers
        allHeaders["x-amz-date"] = amzDate
        allHeaders["x-amz-content-sha256"] = payloadHash

        let sortedHeaders = allHeaders.sorted { $0.key.lowercased() < $1.key.lowercased() }
        let canonicalHeaders = sortedHeaders
            .map { "\($0.key.lowercased()):\($0.value.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "\n") + "\n"
        let signedHeaders = sortedHeaders.map { $0.key.lowercased() }.joined(separator: ";")

        let canonicalRequest = [
            method,
            path,
            query,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).hexString
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")

        let kDate = hmacSHA256(key: Data("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        let signature = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8)).hexString

        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var result = allHeaders
        result["authorization"] = authorization
        return result
    }

    nonisolated private static func hmacSHA256(key: Data, data: Data) -> Data {
        let key = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(signature)
    }
}

extension SHA256Digest {
    nonisolated var hexString: String {
        self.map { String(format: "%02x", $0) }.joined()
    }
}

extension Insecure.MD5Digest {
    nonisolated var hexString: String {
        self.map { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    nonisolated var hexString: String {
        self.map { String(format: "%02x", $0) }.joined()
    }
}
