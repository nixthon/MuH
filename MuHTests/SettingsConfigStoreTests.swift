import XCTest
@testable import MuH

final class SettingsConfigStoreTests: XCTestCase {
    private var directoryURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuHTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("config")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func testParseAndSerializePreserveCommentsAndUnknownLines() {
        let contents = "# theme\nunknown directive\nfont-size = 14\n"

        let lines = SettingsConfigStore.parse(contents)
        let serialized = SettingsConfigStore.serialize(lines)

        XCTAssertEqual(serialized, contents)
    }

    func testSetUpdatesExistingKeyAndWritesConfig() throws {
        try "# user config\nfont-size = 14\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = SettingsConfigStore(filePath: fileURL.path)

        store.set("font-size", "16")
        store.save()

        let result = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(result, "# user config\nfont-size = 16\n")
    }

    func testSetAppendsNewKeyAfterExistingContent() throws {
        try "# user config\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = SettingsConfigStore(filePath: fileURL.path)

        store.set("background-opacity", "0.8")
        store.save()

        let result = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(result, "# user config\n\nbackground-opacity = 0.8\n")
    }
}
