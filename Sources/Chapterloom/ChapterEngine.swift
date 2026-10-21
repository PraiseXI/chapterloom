import AVFoundation
import Foundation

struct ChapterMark: Identifiable, Equatable {
    let id: UUID
    var start: TimeInterval
    var title: String
    var needsReview: Bool

    init(id: UUID = UUID(), start: TimeInterval, title: String, needsReview: Bool = false) {
        self.id = id
        self.start = start
        self.title = title
        self.needsReview = needsReview
    }
}

enum ChapterloomError: LocalizedError {
    case missingTool(String)
    case commandFailed(String)
    case noHeadings
    case invalidChapters
    case verificationFailed(Int, Int)

    var errorDescription: String? {
        switch self {
        case .missingTool(let tool): "Missing \(tool). Install ffmpeg, whisper.cpp, and mp4v2 with Homebrew."
        case .commandFailed(let detail): detail
        case .noHeadings: "No spoken chapter headings found. Add markers manually, then export."
        case .invalidChapters: "Chapter times must be unique, ordered, and within audio duration."
        case .verificationFailed(let expected, let actual): "Apple media framework found \(actual) chapters; expected \(expected)."
        }
    }
}

enum Toolchain {
    static func path(_ name: String) throws -> String {
        let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in envPaths + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        throw ChapterloomError.missingTool(name)
    }
}

final class CommandRunner {
    private let lock = NSLock()
    private var running: Process?
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        let process = running
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }

    func run(_ tool: String, _ arguments: [String], quiet: Bool = true) throws -> String {
        lock.lock()
        let isCancelled = cancelled
        lock.unlock()
        if isCancelled { throw CancellationError() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: try Toolchain.path(tool))
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = quiet ? FileHandle.nullDevice : output
        process.standardError = error
        lock.lock()
        running = process
        lock.unlock()
        try process.run()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        let stdout = quiet ? Data() : output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        lock.lock()
        running = nil
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ChapterloomError.commandFailed("\(tool) failed: \(message.suffix(500))")
        }
        return String(data: quiet ? stderr : stdout, encoding: .utf8) ?? ""
    }
}

enum ModelStore {
    static func modelURL() async throws -> URL {
        if let override = ProcessInfo.processInfo.environment["CHAPTERLOOM_MODEL_PATH"] {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chapterloom/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let destination = support.appendingPathComponent("ggml-base.en.bin")
        if let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 100_000_000 {
            return destination
        }
        let remote = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!
        let (temporary, _) = try await URLSession.shared.download(from: remote)
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 100_000_000 else { throw ChapterloomError.commandFailed("Model download incomplete.") }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}

private struct WhisperResult: Decodable {
    struct Segment: Decodable {
        struct Offsets: Decodable {
            let from: Int
            let to: Int
        }
        let offsets: Offsets
        let text: String
    }
    let transcription: [Segment]
}

private struct Heading {
    let number: Int?
    let title: String
    let time: TimeInterval
    let segmentStartsWithHeading: Bool
}

enum HeadingParser {
    private static let chapter = try! NSRegularExpression(
        pattern: #"(?i)\bchapter\s+(\d{1,3}|[ivxlcdm]+|twenty[ -]?(?:one|two|three|four|five|six|seven|eight|nine)|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)\b"#
    )
    private static let part = try! NSRegularExpression(pattern: #"(?i)\bpart\s+(i{1,3}|[1-3]|one|two|three)\b"#)
    private static let epilogue = try! NSRegularExpression(pattern: #"(?i)\bepilogue\b"#)

    static func chapterNumber(in text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = chapter.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        let value = String(text[valueRange]).lowercased().replacingOccurrences(of: "-", with: " ")
        if let number = Int(value), (1...999).contains(number) { return number }
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                     "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
                     "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
                     "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20]
        if let number = words[value] { return number }
        if value.hasPrefix("twenty "), let suffix = words[String(value.dropFirst(7))] { return 20 + suffix }
        let roman = ["i": 1, "ii": 2, "iii": 3, "iv": 4, "v": 5, "vi": 6, "vii": 7, "viii": 8,
                     "ix": 9, "x": 10, "xi": 11, "xii": 12, "xiii": 13, "xiv": 14, "xv": 15,
                     "xvi": 16, "xvii": 17, "xviii": 18, "xix": 19, "xx": 20]
        return roman[value]
    }

    static func hasPart(_ text: String) -> Bool {
        part.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func hasEpilogue(_ text: String) -> Bool {
        epilogue.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

final class ChapterEngine {
    let runner = CommandRunner()

    func cancel() { runner.cancel() }

    func scan(source: URL, duration: TimeInterval, limit: TimeInterval?, model: URL,
              progress: (Double, String) -> Void) throws -> [ChapterMark] {
        let target = min(duration, limit ?? duration)
        let stride = 870.0
        let starts = Swift.stride(from: 0.0, to: target, by: stride).map { $0 }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("Chapterloom-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        var headings: [Heading] = []
        var parts: [TimeInterval] = []

        for (index, start) in starts.enumerated() {
            let stem = work.appendingPathComponent("chunk-\(index)")
            let wav = stem.appendingPathExtension("wav")
            let length = min(900, target - start)
            progress(Double(index) / Double(starts.count), "Listening · \(index + 1) of \(starts.count)")
            _ = try runner.run("ffmpeg", ["-nostdin", "-hide_banner", "-loglevel", "error",
                "-ss", String(start), "-t", String(length), "-i", source.path,
                "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", "-y", wav.path])
            let whisperArguments = ["-m", model.path, "-f", wav.path,
                "-oj", "-of", stem.path, "-np"]
            do {
                _ = try runner.run("whisper-cli", whisperArguments)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                progress(Double(index) / Double(starts.count), "GPU unavailable · using CPU")
                _ = try runner.run("whisper-cli", whisperArguments + ["-ng"])
            }
            try? FileManager.default.removeItem(at: wav)
            let transcript = try JSONDecoder().decode(WhisperResult.self,
                from: Data(contentsOf: stem.appendingPathExtension("json")))
            for segment in transcript.transcription {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let time = start + Double(segment.offsets.from) / 1000
                if HeadingParser.hasPart(text) { parts.append(time) }
                if let number = HeadingParser.chapterNumber(in: text) {
                    headings.append(Heading(number: number, title: "Chapter \(number)", time: time,
                        segmentStartsWithHeading: text.lowercased().hasPrefix("chapter")))
                }
                if HeadingParser.hasEpilogue(text) {
                    headings.append(Heading(number: nil, title: "Epilogue", time: time,
                        segmentStartsWithHeading: text.lowercased().hasPrefix("epilogue")))
                }
            }
        }

        let sorted = headings.sorted { $0.time < $1.time }
        var unique: [Heading] = []
        for heading in sorted {
            if unique.contains(where: { $0.number == heading.number && abs($0.time - heading.time) < 45 }) { continue }
            unique.append(heading)
        }
        var marks = try unique.map { heading -> ChapterMark in
            let relatedPart = parts.filter { $0 <= heading.time + 3 && heading.time - $0 < 30 }.max()
            let anchor = relatedPart ?? heading.time
            let (adjusted, strong) = try refinedStart(source: source, near: anchor,
                headingAtSegmentStart: relatedPart != nil || heading.segmentStartsWithHeading)
            let title = relatedPart == nil ? heading.title : "Part · \(heading.title)"
            return ChapterMark(start: max(0, adjusted), title: title, needsReview: !strong)
        }
        marks.sort { $0.start < $1.start }
        if let first = marks.first, first.start > 15 {
            marks.insert(ChapterMark(start: 0, title: "Opening"), at: 0)
        }
        progress(1, "Ready for review")
        return marks
    }

    private func refinedStart(source: URL, near time: TimeInterval,
                              headingAtSegmentStart: Bool) throws -> (TimeInterval, Bool) {
        let offset = max(0, time - 12)
        let log = try runner.run("ffmpeg", ["-nostdin", "-nostats", "-hide_banner", "-v", "info",
            "-ss", String(offset), "-t", "25", "-i", source.path, "-map", "0:a:0",
            "-af", "silencedetect=noise=-35dB:d=0.5", "-f", "null", "-"])
        let regex = try! NSRegularExpression(pattern: #"silence_end: ([\d.]+) \| silence_duration: ([\d.]+)"#)
        let matches = regex.matches(in: log, range: NSRange(log.startIndex..., in: log))
        let gaps: [(TimeInterval, TimeInterval)] = matches.compactMap { match in
            guard let endRange = Range(match.range(at: 1), in: log),
                  let durationRange = Range(match.range(at: 2), in: log),
                  let end = Double(log[endRange]), let length = Double(log[durationRange]) else { return nil }
            return (offset + end, length)
        }
        let window = headingAtSegmentStart ? (time - 1.0)...(time + 1.8) : (time - 0.5)...(time + 8)
        if let best = gaps.filter({ window.contains($0.0) && $0.1 >= 1.8 })
            .min(by: { abs($0.0 - time) < abs($1.0 - time) }) {
            return (best.0, true)
        }
        return (time, false)
    }

    static func ffmetadata(chapters: [ChapterMark], duration: TimeInterval) throws -> String {
        let ordered = chapters.sorted { $0.start < $1.start }
        guard !ordered.isEmpty, ordered[0].start >= 0, ordered.last!.start < duration,
              zip(ordered, ordered.dropFirst()).allSatisfy({ $0.start < $1.start }) else {
            throw ChapterloomError.invalidChapters
        }
        var lines = [";FFMETADATA1"]
        for index in ordered.indices {
            let end = index + 1 < ordered.count ? ordered[index + 1].start : duration
            let title = ordered[index].title.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "=", with: "\\=")
                .replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: "#", with: "\\#")
                .replacingOccurrences(of: "\n", with: " ")
            lines += ["[CHAPTER]", "TIMEBASE=1/1000", "START=\(Int((ordered[index].start * 1000).rounded()))",
                "END=\(Int((end * 1000).rounded()))", "title=\(title)"]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func export(source: URL, output: URL, chapters: [ChapterMark], duration: TimeInterval) throws {
        let metadata = try Self.ffmetadata(chapters: chapters, duration: duration)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Chapterloom-\(UUID().uuidString).ffmeta")
        try metadata.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let mp3 = source.pathExtension.lowercased() == "mp3"
        var arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", source.path,
            "-f", "ffmetadata", "-i", file.path, "-map", "0:a:0", "-map", "0:v?",
            "-map_metadata", "0", "-map_chapters", "1"]
        arguments += mp3 ? ["-c:a", "aac", "-b:a", "64k", "-c:v", "copy"] : ["-c", "copy"]
        arguments += ["-y", output.path]
        _ = try runner.run("ffmpeg", arguments)
        let tracks = try runner.run("mp4track", ["--list", output.path], quiet: false)
        let idRegex = try! NSRegularExpression(pattern: #"track\[\d+\] id=(\d+)\s+type\s+= text"#)
        guard let match = idRegex.firstMatch(in: tracks, range: NSRange(tracks.startIndex..., in: tracks)),
              let range = Range(match.range(at: 1), in: tracks) else {
            throw ChapterloomError.commandFailed("Could not identify chapter track.")
        }
        _ = try runner.run("mp4track", ["--track-id", String(tracks[range]), "--language", "eng", output.path])
        let asset = AVURLAsset(url: output)
        let actual = asset.chapterMetadataGroups(bestMatchingPreferredLanguages: ["en"]).count
        guard actual == chapters.count else { throw ChapterloomError.verificationFailed(chapters.count, actual) }
    }
}
