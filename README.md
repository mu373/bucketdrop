# BucketDrop

A macOS menubar app for uploading files to S3-compatible storage (AWS S3, Cloudflare R2, Google Cloud Storage, MinIO, etc.).

Forked from [fayazara/bucketdrop](https://github.com/fayazara/bucketdrop) with multi-bucket support and configurable rename-on-upload.

## Features

- **Multiple bucket configs** — add as many S3-compatible drop targets as you need, each with its own credentials, provider, key prefix, rename mode, and URL copy formats
- **Rename on upload** — per-bucket rename mode: keep original filename, timestamp (Unix / ISO 8601 / compact / date-only), content hash (SHA-256 / MD5), or a custom template with variables like `${basename}`, `${timestamp}`, `${hash}`, `${uuid}`, etc.
- **Customizable URL copy formats** — define URL templates per bucket (e.g. public URL, S3 URI, AWS direct link); the default template is auto-copied to clipboard on upload, and all templates are available via right-click
- **Provider presets** — built-in defaults for AWS S3, Google Cloud Storage, Cloudflare R2, and a generic "Other" option
- **Drag & drop or click to upload** — drop files onto any configured drop zone, or click to select from Finder
- **Unified file list** — browse all objects across every configured bucket in a single date-sorted list
- **Quick Look, download, delete** — double-click to preview, hover for action buttons
- **No AWS SDK** — all S3 API calls and AWS Signature V4 signing are implemented in pure Swift using CryptoKit

## Requirements

- macOS 14.0 (Sonoma) or later

## Installation

1. Download the latest release
2. Move `BucketDrop.app` to your Applications folder
3. Open the app — it will appear in your menubar

## Setup

1. Click the BucketDrop icon in the menubar
2. Click the gear icon to open **Settings**
3. Click **+** in the sidebar to add a new drop target
4. Configure the bucket:
   - **Name** — a label shown on the drop zone
   - **Provider** — choose AWS S3, Google Cloud Storage, Cloudflare R2, or Other (sets sensible defaults for endpoint, region, and URI scheme)
   - **Access Key ID** / **Secret Access Key**
   - **Bucket** name
   - **Region** (e.g. `us-east-1`, or `auto` for R2/GCS)
   - **Endpoint** — custom S3-compatible endpoint (hidden for AWS S3)
   - **Key Prefix** — optional path prefix (e.g. `uploads/`)
5. Optionally configure **Rename on Upload** (original, dateTime, hash, or custom template)
6. Optionally configure **Copy Formats** — add, remove, or reorder URL templates; the first one is the default
7. Click **Test Connection** to verify
8. Changes are saved automatically — there is no Save button

Add more buckets by clicking **+** again. You can also right-click a config to duplicate it.

## Usage

### Uploading

- Open the popover by clicking the menubar icon
- On the **Drop** tab, each configured bucket appears as a separate drop zone
- **Drag & drop** files onto a zone, or **click** it to select files from Finder
- Upload progress is shown inline; when finished, the URL is automatically copied to your clipboard using the bucket's default URL template

### Browsing files

- Switch to the **List** tab to see all objects across every bucket, sorted by most recent
- Each row shows the filename, size, and a badge indicating which bucket it belongs to
- **Hover** a row to reveal action buttons: copy URL, download, delete
- **Right-click** the copy button to choose an alternate URL template
- **Double-click** a row to preview the file with Quick Look

## License

MIT
