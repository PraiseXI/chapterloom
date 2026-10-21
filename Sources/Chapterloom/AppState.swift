import AppKit
import AVFoundation
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var sourceURL: URL?
    @Published var title = ""
    @Published var author = ""
    @Published var duration: TimeInterval = 0
    @Published var artwork: NSImage?
    @Published var chapters: [ChapterMark] = []
    @Published var progress = 0.0
    @Published var status = "Choose an audiobook to begin"
    @Published var isWorking = false
    @Published var isPlaying = false
    @Published var errorMessage: String?
    @Published var outputURL: URL?
    @Published var scanFirst30Minutes = false

    private var engine: ChapterEngine?
    private var player: AVPlayer?

    var missingTools: [String] {
        ["ffmpeg", "whisper-cli", "mp4track"].filter { (try? Toolchain.path($0)) == nil }
    }

    var scanDuration: TimeInterval { min(duration, scanFirst30Minutes ? 1800 : duration) }

    func chooseSource() {
        let panel = NSOpenPanel()
        panel.title = "Choose an audiobook"
        panel.message = "M4A, M4B, or MP3 audio stays on your Mac."
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.loadSource(url) }
        }
    }

    func loadSource(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["m4a", "m4b", "mp3"].contains(ext) else {
            errorMessage = "Choose an M4A, M4B, or MP3 audiobook."
            return
        }
        player?.pause()
        isPlaying = false
        sourceURL = url
        title = url.deletingPathExtension().lastPathComponent
        author = ""
        duration = 0
        artwork = nil
        chapters = []
        outputURL = nil
        errorMessage = nil
        status = "Reading audiobook details"
        Task {
            do {
                let asset = AVURLAsset(url: url)
                let loadedDuration = try await asset.load(.duration)
                let metadata = try await asset.load(.commonMetadata)
                duration = CMTimeGetSeconds(loadedDuration)
                if let value = metadata.first(where: { $0.commonKey == .commonKeyTitle })?.stringValue,
                   !value.isEmpty { title = value }
                if let value = metadata.first(where: { $0.commonKey == .commonKeyArtist })?.stringValue {
                    author = value
                }
                if let data = metadata.first(where: { $0.commonKey == .commonKeyArtwork })?.dataValue {
                    artwork = NSImage(data: data)
                }
                status = "Ready to find chapters"
            } catch {
                errorMessage = "Could not read this audio file: \(error.localizedDescription)"
                status = "Audio unavailable"
            }
        }
    }

    func scan() {
        guard let sourceURL, duration > 0, !isWorking else { return }
        if !missingTools.isEmpty {
            errorMessage = "Missing tools: \(missingTools.joined(separator: ", ")). Install with: brew install ffmpeg whisper.cpp mp4v2"
            return
        }
        isWorking = true
        progress = 0
        chapters = []
        outputURL = nil
        errorMessage = nil
        status = "Preparing local speech model"
        Task {
            do {
                let model = try await ModelStore.modelURL()
                let engine = ChapterEngine()
                self.engine = engine
                let sourceDuration = duration
                let limit: TimeInterval? = scanFirst30Minutes ? 1800 : nil
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let marks = try engine.scan(source: sourceURL, duration: sourceDuration,
                            limit: limit, model: model) { value, message in
                            DispatchQueue.main.async {
                                self.progress = value
                                self.status = message
                            }
                        }
                        DispatchQueue.main.async {
                            self.chapters = marks
                            self.isWorking = false
                            self.engine = nil
                            self.status = marks.isEmpty ? "No headings found. Add a marker manually." :
                                "\(marks.count) markers ready for review"
                        }
                    } catch is CancellationError {
                        DispatchQueue.main.async {
                            self.isWorking = false
                            self.engine = nil
                            self.status = "Scan cancelled"
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.isWorking = false
                            self.engine = nil
                            self.errorMessage = error.localizedDescription
                            self.status = "Scan failed"
                        }
                    }
                }
            } catch {
                isWorking = false
                errorMessage = "Model setup failed: \(error.localizedDescription)"
                status = "Model unavailable"
            }
        }
    }

    func cancel() {
        engine?.cancel()
        status = "Cancelling scan"
    }

    func addMarker() {
        let time = max(0, min(player?.currentTime().seconds ?? 0, duration - 0.01))
        chapters.append(ChapterMark(start: time, title: "New chapter", needsReview: true))
        chapters.sort { $0.start < $1.start }
    }

    func removeMarker(_ id: UUID) {
        chapters.removeAll { $0.id == id }
    }

    func nudge(_ id: UUID, by delta: TimeInterval) {
        guard let index = chapters.firstIndex(where: { $0.id == id }) else { return }
        chapters[index].start = max(0, min(duration - 0.01, chapters[index].start + delta))
        chapters[index].needsReview = false
        chapters.sort { $0.start < $1.start }
    }

    func preview(_ mark: ChapterMark) {
        guard let sourceURL else { return }
        if isPlaying { player?.pause() }
        let player = self.player ?? AVPlayer(url: sourceURL)
        self.player = player
        let start = max(0, mark.start - 3)
        player.seek(to: CMTime(seconds: start, preferredTimescale: 1000))
        player.play()
        isPlaying = true
    }

    func stopPreview() {
        player?.pause()
        isPlaying = false
    }

    func chooseExport() {
        guard sourceURL != nil, !chapters.isEmpty, !isWorking else { return }
        let panel = NSSavePanel()
        panel.title = "Save chaptered audiobook"
        panel.nameFieldStringValue = "\(title) — chaptered.m4b"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.export(to: url.pathExtension.lowercased() == "m4b" ? url : url.appendingPathExtension("m4b")) }
        }
    }

    private func export(to url: URL) {
        guard let sourceURL else { return }
        isWorking = true
        errorMessage = nil
        status = "Writing chapter track · keeping original audio"
        progress = 0.5
        let engine = ChapterEngine()
        self.engine = engine
        let marks = chapters
        let duration = self.duration
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try engine.export(source: sourceURL, output: url, chapters: marks, duration: duration)
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.engine = nil
                    self.progress = 1
                    self.outputURL = url
                    self.status = "Chaptered audiobook ready"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.engine = nil
                    self.errorMessage = error.localizedDescription
                    self.status = "Export failed"
                }
            }
        }
    }
}

extension TimeInterval {
    var chapterTimecode: String {
        guard isFinite else { return "00:00" }
        let total = Int(max(0, self))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) :
            String(format: "%02d:%02d", minutes, seconds)
    }
}
