import AVFoundation
import XCTest
@testable import Chapterloom

final class ChapterEngineTests: XCTestCase {
    func testSpokenChapterNumbers() {
        XCTAssertEqual(HeadingParser.chapterNumber(in: "Chapter 12."), 12)
        XCTAssertEqual(HeadingParser.chapterNumber(in: "CHAPTER XIII."), 13)
        XCTAssertEqual(HeadingParser.chapterNumber(in: "Chapter twenty six."), 26)
        XCTAssertNil(HeadingParser.chapterNumber(in: "This is part of my chapter."))
    }

    func testFFMetadataProducesContiguousBoundaries() throws {
        let text = try ChapterEngine.ffmetadata(chapters: [
            ChapterMark(start: 0, title: "Opening"),
            ChapterMark(start: 91.26, title: "Chapter 1"),
        ], duration: 1800)
        XCTAssertTrue(text.contains("START=0\nEND=91260\ntitle=Opening"))
        XCTAssertTrue(text.contains("START=91260\nEND=1800000\ntitle=Chapter 1"))
    }

    func testFFMetadataRejectsDuplicateTimes() {
        XCTAssertThrowsError(try ChapterEngine.ffmetadata(chapters: [
            ChapterMark(start: 12, title: "A"), ChapterMark(start: 12, title: "B")
        ], duration: 30))
    }

    func testExportEmbedsReadableChaptersAndKeepsAudio() throws {
        guard (try? Toolchain.path("ffmpeg")) != nil,
              (try? Toolchain.path("mp4track")) != nil else {
            throw XCTSkip("ffmpeg and mp4track required")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Chapterloom-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.m4a")
        let output = directory.appendingPathComponent("chaptered.m4b")
        _ = try CommandRunner().run("ffmpeg", ["-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=12", "-c:a", "aac",
            "-b:a", "64k", "-metadata", "title=Test Book", "-y", source.path])
        try ChapterEngine().export(source: source, output: output, chapters: [
            ChapterMark(start: 0, title: "Opening"),
            ChapterMark(start: 6, title: "Chapter 1")
        ], duration: 12)
        let asset = AVURLAsset(url: output)
        XCTAssertEqual(asset.chapterMetadataGroups(bestMatchingPreferredLanguages: ["en"]).count, 2)
        XCTAssertEqual(asset.commonMetadata.first(where: { $0.commonKey == .commonKeyTitle })?.stringValue,
                       "Test Book")
        XCTAssertGreaterThan(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 50_000)
    }
}
