import Foundation

enum WorkoutClipStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("WorkoutClips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    static func makeFilename(kind: WorkoutClipKind) -> String {
        "\(UUID().uuidString).\(kind.rawValue).mov"
    }

    static func cacheFilename(forClipID id: UUID) -> String {
        "\(id.uuidString).remote.mov"
    }

    static func cachedFileURL(forClipID id: UUID) -> URL {
        fileURL(for: cacheFilename(forClipID: id))
    }

    static func fileExists(_ filename: String?) -> Bool {
        guard let filename else { return false }
        return FileManager.default.fileExists(atPath: fileURL(for: filename).path)
    }

    static func removeAllFiles() {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
