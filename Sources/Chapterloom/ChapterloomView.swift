import SwiftUI
import UniformTypeIdentifiers

private enum Palette {
    static let canvas = Color(red: 0.970, green: 0.977, blue: 0.990)
    static let surface = Color.white
    static let ink = Color(red: 0.106, green: 0.145, blue: 0.227)
    static let muted = Color(red: 0.370, green: 0.415, blue: 0.502)
    static let line = Color(red: 0.860, green: 0.884, blue: 0.930)
    static let primary = Color(red: 0.179, green: 0.321, blue: 0.738)
    static let primaryDeep = Color(red: 0.098, green: 0.160, blue: 0.392)
    static let primaryPale = Color(red: 0.906, green: 0.930, blue: 0.993)
    static let amber = Color(red: 0.745, green: 0.388, blue: 0.102)
    static let amberPale = Color(red: 0.999, green: 0.947, blue: 0.877)
}

struct ChapterloomView: View {
    @EnvironmentObject private var state: AppState
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 24) {
                sourceColumn
                    .frame(width: 336)
                reviewColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(28)
            footer
        }
        .background(Palette.canvas)
        .preferredColorScheme(.light)
        .alert("Chapterloom", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in state.loadSource(url) }
            }
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Palette.primary, style: StrokeStyle(lineWidth: 4, dash: [9, 7]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Palette.primary)
                    .frame(width: 39, height: 39)
                Image(systemName: "waveform.badge.bookmark")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Chapterloom")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .tracking(-0.3)
                    .foregroundStyle(Palette.ink)
                Text("A quiet place to shape audiobook chapters")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(Color(red: 0.23, green: 0.65, blue: 0.46)).frame(width: 6, height: 6)
                Text("LOCAL WORKFLOW")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Palette.canvas, in: Capsule())
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 17)
        .background(Palette.surface)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }

    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                sectionLabel("01  SOURCE AUDIO")
                cover
                    .frame(maxWidth: .infinity)
                    .frame(height: 222)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.sourceURL == nil ? "Start with a book" : state.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    Text(state.sourceURL == nil ? "Choose an M4A, M4B, or MP3 file" :
                            "\(state.author.isEmpty ? "Audiobook" : state.author)  ·  \(state.duration.chapterTimecode)")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Button(action: state.chooseSource) {
                    Label(state.sourceURL == nil ? "Choose audiobook" : "Change audiobook", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                Text("You can also drop an audio file anywhere in this window.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.line))

            VStack(alignment: .leading, spacing: 16) {
                sectionLabel("02  FIND CHAPTERS")
                Text("Listen for narrated chapter numbers and map each one to a pause in the audio.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    scopeButton("Entire book", sample: false)
                    scopeButton("First 30 min", sample: true)
                }
                .padding(4)
                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 9))

                if state.isWorking {
                    ProgressView(value: state.progress)
                        .tint(Palette.primary)
                    Button("Cancel scan", action: state.cancel)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                } else {
                    Button(action: state.scan) {
                        HStack {
                            Image(systemName: "waveform")
                            Text("Find chapters")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(state.sourceURL == nil || state.duration <= 0)
                }
                if !state.missingTools.isEmpty {
                    Text("Needs: \(state.missingTools.joined(separator: ", "))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.amber)
                }
            }
            .padding(18)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.line))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let artwork = state.artwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.primaryDeep)
        } else {
            ZStack {
                LinearGradient(colors: [Palette.primaryDeep, Palette.primary],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(alignment: .center, spacing: 5) {
                    ForEach([22.0, 44, 71, 39, 89, 59, 30, 65, 38, 79, 48, 24], id: \.self) { height in
                        Capsule()
                            .fill(.white.opacity(0.65))
                            .frame(width: 5, height: height)
                    }
                }
                .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
            }
        }
    }

    private var reviewColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("03  REVIEW & EXPORT")
                    Text("Chapters")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .tracking(-0.8)
                        .foregroundStyle(Palette.ink)
                    Text("Check markers, adjust timing, then save a BookPlayer-ready M4B.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                if !state.chapters.isEmpty {
                    Text("\(state.chapters.count) MARKERS")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(Palette.primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Palette.primaryPale, in: Capsule())
                }
            }
            .padding(23)

            Rectangle().fill(Palette.line).frame(height: 1)

            if state.chapters.isEmpty { emptyState } else { chaptersList }

            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(spacing: 12) {
                Button(action: state.addMarker) {
                    Label("Add marker", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(state.sourceURL == nil || state.isWorking)
                if state.isPlaying {
                    Button(action: state.stopPreview) {
                        Label("Stop preview", systemImage: "stop.fill")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.primary)
                }
                Spacer()
                Button(action: state.chooseExport) {
                    Label("Export M4B", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(state.chapters.isEmpty || state.isWorking)
            }
            .padding(18)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.line))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Palette.primaryPale).frame(width: 86, height: 86)
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Palette.primary)
            }
            Text(state.sourceURL == nil ? "Every story has its rhythm." : "Ready when you are.")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text(state.sourceURL == nil ?
                 "Choose an audiobook. Chapterloom will listen for spoken headings and give you a chapter list to refine." :
                 "Find spoken chapters, or add your own marker to begin shaping the book.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var chaptersList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(state.chapters.enumerated()), id: \.element.id) { index, chapter in
                    chapterRow(index: index, chapter: chapter)
                    if index < state.chapters.count - 1 {
                        Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 72)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chapterRow(index: Int, chapter: ChapterMark) -> some View {
        HStack(spacing: 14) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.primary)
                .frame(width: 32, height: 32)
                .background(Palette.primaryPale, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                TextField("Chapter name", text: chapterTitleBinding(chapter.id))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                if chapter.needsReview {
                    Text("CHECK TIMING")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(Palette.amber)
                }
            }
            Spacer(minLength: 8)
            Text(chapter.start.chapterTimecode)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.muted)
                .frame(minWidth: 65, alignment: .trailing)
            Button { state.nudge(chapter.id, by: -0.5) } label: {
                Image(systemName: "minus").frame(width: 20, height: 20)
            }
            .help("Move marker back 0.5 seconds")
            Button { state.nudge(chapter.id, by: 0.5) } label: {
                Image(systemName: "plus").frame(width: 20, height: 20)
            }
            .help("Move marker forward 0.5 seconds")
            Button { state.preview(chapter) } label: {
                Image(systemName: "play.fill").frame(width: 20, height: 20)
            }
            .help("Preview around marker")
            Button { state.removeMarker(chapter.id) } label: {
                Image(systemName: "xmark").frame(width: 20, height: 20)
            }
            .help("Remove marker")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
    }

    private func chapterTitleBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { state.chapters.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let index = state.chapters.firstIndex(where: { $0.id == id }) {
                    state.chapters[index].title = newValue
                }
            }
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: state.outputURL == nil ? "waveform" : "checkmark.circle.fill")
                .foregroundStyle(state.outputURL == nil ? Palette.primary : Color.green)
            Text(state.status)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
            Spacer()
            if let url = state.outputURL {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.primary)
            } else {
                Text("Audio stays on this Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 42)
        .background(Palette.surface)
        .overlay(alignment: .top) { Palette.line.frame(height: 1) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(Palette.primary)
    }

    private func scopeButton(_ title: String, sample: Bool) -> some View {
        Button {
            state.scanFirst30Minutes = sample
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state.scanFirst30Minutes == sample ? Palette.ink : Palette.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(state.scanFirst30Minutes == sample ? Palette.surface : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .frame(height: 36)
            .background(Palette.primary.opacity(configuration.isPressed ? 0.83 : 1),
                in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Palette.surface.opacity(configuration.isPressed ? 0.66 : 1),
                in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line))
    }
}
