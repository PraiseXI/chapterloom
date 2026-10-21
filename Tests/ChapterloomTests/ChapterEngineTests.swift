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

    func testPreciseTimecodeParsing() {
        XCTAssertEqual(TimeInterval.fromChapterTimecode("01:31.26"), 91.26)
        XCTAssertEqual(TimeInterval.fromChapterTimecode("12:46:26.50"), 45_986.5)
        XCTAssertNil(TimeInterval.fromChapterTimecode("01:70"))
        XCTAssertNil(TimeInterval.fromChapterTimecode("-1"))
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

    func testRealAudiobookExcerptWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let samplePath = environment["CHAPTERLOOM_SAMPLE_PATH"],
              let modelPath = environment["CHAPTERLOOM_MODEL_PATH"] else {
            throw XCTSkip("Set sample and model paths for local audiobook integration test")
        }
        let source = URL(fileURLWithPath: samplePath)
        let engine = ChapterEngine()
        let marks = try engine.scan(
            source: source, duration: 600, limit: nil,
            model: URL(fileURLWithPath: modelPath), progress: { _, _ in }
        )
        XCTAssertTrue(marks.contains { $0.title.contains("Chapter 1") && abs($0.start - 91.26) < 30 },
                      "Expected spoken Chapter 1 near 1:31; found \(marks)")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Chapterloom-real-\(UUID().uuidString).m4b")
        defer { try? FileManager.default.removeItem(at: output) }
        try engine.export(source: source, output: output, chapters: marks, duration: 600)
        XCTAssertEqual(AVURLAsset(url: output).chapterMetadataGroups(
            bestMatchingPreferredLanguages: ["en"]).count, marks.count)
    }
}
