//
//  UploadedFile.swift
//  BucketDrop
//
//  Created by Fayaz Ahmed Aralikatti on 12/01/26.
//

import Foundation
import SwiftData

@Model
final class UploadedFile {
    var filename: String
    var key: String
    var url: String
    var size: Int64
    var uploadedAt: Date
    
    init(filename: String, key: String, url: String, size: Int64, uploadedAt: Date = Date()) {
        self.filename = filename
        self.key = key
        self.url = url
        self.size = size
        self.uploadedAt = uploadedAt
    }
}
