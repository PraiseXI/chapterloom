import AppKit
import Foundation
import SwiftUI

@main
struct RenderScreenshots {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("Usage: render-screenshots SOURCE_M4A OUTPUT_DIRECTORY")
        }

        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let scenes: [(String, (AppState) -> Void)] = [
            ("source", { state in
                state.status = "Ready to find chapters"
            }),
            ("scan", { state in
                state.isWorking = true
                state.progress = 0.62
                state.status = "Listening · 1 of 1"
            }),
            ("review", { state in
                state.chapters = detectedMarkers()
                state.status = "2 markers ready for review"
            }),
            ("export", { state in
                state.chapters = detectedMarkers()
                state.outputURL = output.appendingPathComponent("Sunrise on the Reaping — 10-minute demo — chaptered.m4b")
                state.progress = 1
                state.status = "Chaptered audiobook ready"
            }),
        ]

        for (name, configure) in scenes {
            let state = AppState()
            state.sourceURL = source
            state.title = "Sunrise on the Reaping — 10-minute test"
            state.author = "Suzanne Collins"
            state.duration = 599.932
            configure(state)

            let view = ChapterloomView()
                .environmentObject(state)
                .frame(width: 1040, height: 900)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 1040, height: 900)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                fatalError("Could not render \(name)")
            }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Could not encode \(name)")
            }
            let destination = output.appendingPathComponent("\(name).png")
            try png.write(to: destination)
            print(destination.path)
        }
    }

    private static func detectedMarkers() -> [ChapterMark] {
        [
            ChapterMark(start: 0, title: "Opening"),
            ChapterMark(start: 91.261, title: "Part I · Chapter 1"),
        ]
    }
}
