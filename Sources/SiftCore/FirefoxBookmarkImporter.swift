import Foundation
import SQLite3

public struct FirefoxBookmarkImporter {
    public static func load() -> [Bookmark] {
        guard let placesURL = locatePlacesSQLite() else { return [] }

        if let direct = readBookmarks(from: placesURL, immutable: true) {
            return direct
        }

        guard let copyURL = copyDatabase(from: placesURL) else { return [] }
        defer { try? FileManager.default.removeItem(at: copyURL.deletingLastPathComponent()) }
        return readBookmarks(from: copyURL, immutable: false) ?? []
    }

    public static func modificationTime() -> Date? {
        guard let url = locatePlacesSQLite() else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    private static var firefoxRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Firefox")
    }

    private static func locatePlacesSQLite() -> URL? {
        let profilesDir = firefoxRoot.appendingPathComponent("Profiles")
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: profilesDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        let withPlaces: [(URL, Date)] = candidates.compactMap { dir in
            let places = dir.appendingPathComponent("places.sqlite")
            guard FileManager.default.fileExists(atPath: places.path) else { return nil }
            let date = (try? places.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return (places, date)
        }
        return withPlaces.max(by: { $0.1 < $1.1 })?.0
    }

    private static func copyDatabase(from source: URL) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-firefox-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch { return nil }

        let dst = tempDir.appendingPathComponent("places.sqlite")
        do {
            try FileManager.default.copyItem(at: source, to: dst)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            return nil
        }

        let sourceDir = source.deletingLastPathComponent()
        for suffix in ["-wal", "-shm"] {
            let auxSrc = sourceDir.appendingPathComponent("places.sqlite\(suffix)")
            if FileManager.default.fileExists(atPath: auxSrc.path) {
                try? FileManager.default.copyItem(
                    at: auxSrc,
                    to: tempDir.appendingPathComponent("places.sqlite\(suffix)")
                )
            }
        }
        return dst
    }

    private static func readBookmarks(from url: URL, immutable: Bool) -> [Bookmark]? {
        var db: OpaquePointer?
        let connection: String
        var flags = SQLITE_OPEN_READONLY
        if immutable {
            connection = "\(url.absoluteString)?immutable=1"
            flags |= SQLITE_OPEN_URI
        } else {
            connection = url.path
        }

        guard sqlite3_open_v2(connection, &db, flags, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT b.title, p.url
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        WHERE b.type = 1
          AND b.title IS NOT NULL
          AND b.title != ''
          AND b.parent NOT IN (
            SELECT id FROM moz_bookmarks WHERE guid = 'tags________'
          )
          AND b.parent NOT IN (
            SELECT id FROM moz_bookmarks
            WHERE parent = (SELECT id FROM moz_bookmarks WHERE guid = 'tags________')
          );
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        var results: [Bookmark] = []
        results.reserveCapacity(512)
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let titleC = sqlite3_column_text(stmt, 0),
                  let urlC = sqlite3_column_text(stmt, 1) else { continue }
            let title = String(cString: titleC)
            let urlString = String(cString: urlC)
            guard !urlString.hasPrefix("place:") else { continue }
            results.append(Bookmark(
                id: "firefox:\(urlString)",
                name: title,
                url: urlString,
                source: .firefox
            ))
        }
        return results
    }
}
