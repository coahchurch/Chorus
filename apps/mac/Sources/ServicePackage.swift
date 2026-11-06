import Foundation
import PresenterCore

enum ServicePackage {
    static let format = "chorus-service-package"
    static let version = 2

    struct Manifest: Codable, Sendable {
        var format: String
        var version: Int
    }

    struct Payload: Codable, Sendable {
        var service: Service
        var songs: [SongLyrics]
        var presentations: [Presentation]
        var themes: [Theme]
        var media: [MediaItem]
        var audio: [AudioItem]
        var playlists: [Playlist]
        var outputPresets: [OutputPreset]
    }

    struct Contents: Sendable {
        var payload: Payload
        var root: URL

        var blobFiles: [String: URL] {
            files(in: "blobs")
        }

        var fontFiles: [URL] {
            Array(files(in: "fonts").values).sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        private func files(in name: String) -> [String: URL] {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )) ?? []
            return Dictionary(
                urls.map { ($0.deletingPathExtension().lastPathComponent, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    enum PackageError: LocalizedError {
        case invalidPackage
        case unsupportedVersion(Int)
        case unsafeArchive(String)
        case missingAsset(String)
        case invalidAsset(String)
        case archive(String)

        var errorDescription: String? {
            switch self {
            case .invalidPackage:
                "This file is not a supported Chorus service package."
            case .unsupportedVersion(let version):
                "This service package was created by a newer version of Chorus (format \(version))."
            case .unsafeArchive(let name):
                "The service package contains an unsafe archive entry: \(name)."
            case .missingAsset(let name):
                "The service package is missing the required asset “\(name)”."
            case .invalidAsset(let name):
                "The service package contains an invalid or damaged asset: \(name)."
            case .archive(let detail):
                detail
            }
        }
    }

    static func write(
        _ payload: Payload, blobs: [String: URL], fonts: [URL], to destination: URL
    ) throws {
        let files = FileManager.default
        let holder = files.temporaryDirectory
            .appendingPathComponent("chorus-service-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: holder) }
        let staging = holder.appendingPathComponent("contents", isDirectory: true)
        let blobDirectory = staging.appendingPathComponent("blobs", isDirectory: true)
        let fontDirectory = staging.appendingPathComponent("fonts", isDirectory: true)
        try files.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        try files.createDirectory(at: fontDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Manifest(format: format, version: version))
            .write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        try encoder.encode(payload)
            .write(to: staging.appendingPathComponent("service.json"), options: .atomic)

        for (hash, source) in blobs.sorted(by: { $0.key < $1.key }) {
            guard hash.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil else {
                throw PackageError.invalidAsset(source.lastPathComponent)
            }
            let target = blobDirectory.appendingPathComponent(
                source.pathExtension.isEmpty ? hash : "\(hash).\(source.pathExtension.lowercased())"
            )
            try files.copyItem(at: source, to: target)
        }
        for font in fonts {
            guard let document = FontSharing.document(forFileAt: font) else {
                throw PackageError.invalidAsset(font.lastPathComponent)
            }
            let target = fontDirectory.appendingPathComponent("\(document.id).\(document.ext)")
            if !files.fileExists(atPath: target.path) {
                try files.copyItem(at: font, to: target)
            }
        }

        let archive = holder.appendingPathComponent("package.zip")
        try runDitto(["-c", "-k", "--norsrc", staging.path, archive.path])
        if files.fileExists(atPath: destination.path) {
            _ = try files.replaceItemAt(destination, withItemAt: archive)
        } else {
            try files.moveItem(at: archive, to: destination)
        }
    }

    static func read(_ archive: URL) throws -> Contents {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("chorus-service-import-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            try validateArchiveEntries(archive)
            try runDitto(["-x", "-k", archive.path, root.path])
            try validateTree(root)

            let decoder = JSONDecoder()
            let manifestURL = root.appendingPathComponent("manifest.json")
            guard let manifestData = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(Manifest.self, from: manifestData),
                  manifest.format == format else {
                throw PackageError.invalidPackage
            }
            guard manifest.version <= version else {
                throw PackageError.unsupportedVersion(manifest.version)
            }
            guard manifest.version == version,
                  let payloadData = try? Data(contentsOf: root.appendingPathComponent("service.json")),
                  let payload = try? decoder.decode(Payload.self, from: payloadData) else {
                throw PackageError.invalidPackage
            }

            let blobs = try verifiedBlobs(in: root)
            let requiredHashes = Set(
                payload.media.map(\.fileHash) + payload.audio.map(\.fileHash)
            )
            for item in payload.media where !blobs.keys.contains(item.fileHash) {
                throw PackageError.missingAsset(item.name)
            }
            for item in payload.audio where !blobs.keys.contains(item.fileHash) {
                throw PackageError.missingAsset(item.name)
            }
            guard requiredHashes.count == blobs.count else {
                let extra = blobs.keys.first { !requiredHashes.contains($0) } ?? "unknown"
                throw PackageError.invalidAsset(extra)
            }
            _ = try verifiedFonts(in: root)
            return Contents(payload: payload, root: root)
        } catch {
            try? files.removeItem(at: root)
            throw error
        }
    }

    static func remove(_ contents: Contents) {
        try? FileManager.default.removeItem(at: contents.root)
    }

    private static func verifiedBlobs(in root: URL) throws -> [String: URL] {
        let directory = root.appendingPathComponent("blobs", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []
        var result: [String: URL] = [:]
        for url in urls {
            let hash = url.deletingPathExtension().lastPathComponent.lowercased()
            guard hash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
                  try BlobStore.sha256(of: url) == hash,
                  result[hash] == nil else {
                throw PackageError.invalidAsset(url.lastPathComponent)
            }
            result[hash] = url
        }
        return result
    }

    private static func verifiedFonts(in root: URL) throws -> [URL] {
        let directory = root.appendingPathComponent("fonts", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []
        for url in urls {
            let stem = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            guard stem.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil,
                  try BlobStore.sha256(of: url).caseInsensitiveCompare(stem) == .orderedSame,
                  ext.range(of: #"^[A-Za-z0-9]{1,16}$"#, options: .regularExpression) != nil else {
                throw PackageError.invalidAsset(url.lastPathComponent)
            }
        }
        return urls
    }

    private static func validateTree(_ root: URL) throws {
        let rootPath = root.standardizedFileURL.path + "/"
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        ) else {
            throw PackageError.invalidPackage
        }
        var fileCount = 0
        var totalBytes: Int64 = 0
        for case let url as URL in enumerator {
            let path = url.standardizedFileURL.path
            let values = try url.resourceValues(forKeys: [
                .isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey,
            ])
            guard path.hasPrefix(rootPath), values.isSymbolicLink != true else {
                throw PackageError.unsafeArchive(url.lastPathComponent)
            }
            if values.isRegularFile == true {
                fileCount += 1
                totalBytes += Int64(values.fileSize ?? 0)
                guard fileCount <= 20_000, totalBytes <= 16 * 1024 * 1024 * 1024 else {
                    throw PackageError.unsafeArchive(url.lastPathComponent)
                }
            } else if values.isDirectory != true {
                throw PackageError.unsafeArchive(url.lastPathComponent)
            }
        }
    }

    private static func validateArchiveEntries(_ archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z", "-1", archive.path]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let listing = String(data: data, encoding: .utf8) else {
            let detail = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw PackageError.archive(
                detail.isEmpty ? "Chorus could not read the service package archive." : detail
            )
        }
        let entries = listing.split(whereSeparator: \.isNewline)
        guard !entries.isEmpty, entries.count <= 20_000 else {
            throw PackageError.invalidPackage
        }
        for rawEntry in entries {
            let entry = String(rawEntry).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let components = entry.split(separator: "/")
            guard !entry.hasPrefix("/"), !components.isEmpty,
                  components.allSatisfy({ $0 != "." && $0 != ".." }) else {
                throw PackageError.unsafeArchive(entry)
            }
            if entry == "manifest.json" || entry == "service.json"
                || entry == "blobs" || entry == "fonts" {
                continue
            }
            guard components.count == 2,
                  components[0] == "blobs" || components[0] == "fonts" else {
                throw PackageError.unsafeArchive(entry)
            }
            let filename = String(components[1])
            let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            let ext = URL(fileURLWithPath: filename).pathExtension
            guard stem.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil,
                  ext.isEmpty || ext.range(of: #"^[A-Za-z0-9]{1,16}$"#, options: .regularExpression) != nil else {
                throw PackageError.unsafeArchive(entry)
            }
        }
    }

    private static func runDitto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw PackageError.archive(
                detail.isEmpty ? "Chorus could not read or write the service package." : detail
            )
        }
    }
}
