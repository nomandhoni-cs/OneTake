//
//  ReviewView.swift
//  OneTake
//

//  See: docs/ARCHITECTURE.md §6 (Review) + openspec/specs/trim-color-export/spec.md
import AVKit
import Photos
import SwiftData
import SwiftUI

// swiftlint:disable file_length type_body_length
struct ReviewView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @Bindable var take: Take

    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var selectedLUT: LUTPreset = .natural
    @State private var isExporting = false
    @State private var exportProgress = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSaved = false
    @State private var exportedURL: URL?
    @State private var selectedSegment: Int?
    @State private var playheadSeconds: Double?
    @State private var bladeUndoStack: [[Double]?] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                playerSection
                trimSection
                lutSection
                actionsSection
            }
            .padding()
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Adjust") {
                        Button {
                            // Trim handled via scrubber handles
                        } label: {
                            Label("Trim", systemImage: "scissors")
                        }
                        Button {
                            splitAtPlayhead()
                        } label: {
                            Label("Blade Split at Playhead", systemImage: "scissors.badge.ellipsis")
                        }
                        .disabled({
                            if let playhead = playheadSeconds {
                                return playhead <= trimStart + 0.1 || playhead >= trimEnd - 0.1
                            }
                            return (trimEnd - trimStart) < 1.1
                        }())
                        Button(role: .destructive) {
                            deleteSelectedSegment()
                        } label: {
                            Label("Delete Selected Segment", systemImage: "trash")
                        }
                        .disabled(selectedSegment == nil || take.bladeSegments().count <= 1)
                    }
                    Section("Color") {
                        Menu {
                            ForEach(LUTPreset.allCases) { preset in
                                Button {
                                    selectedLUT = preset
                                } label: {
                                    HStack(spacing: 8) {
                                        LUTSwatchView(preset: preset)
                                        Text(preset.displayName)
                                        if selectedLUT == preset {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("LUT", systemImage: "paintpalette")
                        }
                    }
                    Section("Output") {
                        Button {
                            Task { await reexport(saveAsNew: false) }
                        } label: {
                            Label("Save", systemImage: "photo.badge.arrow.down")
                        }
                        .disabled(isExporting)
                        ShareLink(item: exportedURL ?? take.fileURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Edit menu")
            }
        }
        .task { await loadDuration() }
        .task(id: player) {
            guard let player else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                let seconds = player.currentTime().seconds
                await MainActor.run { playheadSeconds = seconds.isFinite ? seconds : nil }
            }
        }
        .onChange(of: take.fileURL) { _, _ in Task { await loadDuration() } }
        .alert("Export Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage) }
        .alert("Saved to Photos", isPresented: $showSaved) {
            Button("OK", role: .cancel) {}
        } message: { Text("Your video was saved to the Photos library.") }
        .overlay {
            if isExporting {
                ProgressView(exportProgress).padding().background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 12)
                ).padding()
            }
        }
    }

    private var playerSection: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onAppear { player.play() }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.85))
                    .frame(height: 360)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "film").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
                            Text("No preview available").foregroundStyle(.white.opacity(0.6)).font(.caption)
                        }
                    }
            }
        }
        .task(id: take.bladeCuts?.description ?? take.fileURL.absoluteString) {
            let url = take.fileURL
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            // Honor blade composition for preview; falls back to plain URL for single segment.
            if let item = await makePlayerItem(for: take) {
                player = AVPlayer(playerItem: item)
            } else {
                player = AVPlayer(url: url)
            }
        }
    }

    private var trimSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trim").font(.headline)
            if duration > 0 {
                TrimScrubberView(
                    duration: duration,
                    startSeconds: $trimStart,
                    endSeconds: $trimEnd,
                    bladeCuts: take.bladeCuts ?? [],
                    selectedSegment: selectedSegment,
                    playheadSeconds: playheadSeconds,
                    onBlade: { splitAtPlayhead() },
                    onDeleteSegment: { deleteSelectedSegment() },
                    onSelectSegment: { idx in selectedSegment = idx }
                )
                .onChange(of: trimStart) { _, _ in pruneBladeCutsToTrim() }
                .onChange(of: trimEnd) { _, _ in pruneBladeCutsToTrim() }
                if !bladeUndoStack.isEmpty {
                    Button {
                        undoLastBlade()
                    } label: {
                        Label("Undo Blade", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                Button("Preview Trim") {
                    guard let player else { return }
                    let t = CMTime(seconds: trimStart, preferredTimescale: 600)
                    player.seek(to: t)
                    player.play()
                    // Stop at trimEnd via boundary observer
                    let end = CMTime(seconds: trimEnd, preferredTimescale: 600)
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: player.currentItem,
                        queue: .main
                    ) { _ in
                        player.pause()
                    }
                    // Simpler: use seek loop; boundary time observer
                    _ = end
                }
                .font(.caption)
            } else {
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var lutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color").font(.headline)
            VStack(spacing: 6) {
                ForEach(LUTPreset.allCases) { preset in
                    Button {
                        selectedLUT = preset
                    } label: {
                        HStack(spacing: 10) {
                            LUTSwatchView(preset: preset)
                            Text(preset.displayName)
                                .font(.subheadline.weight(preset == selectedLUT ? .semibold : .regular))
                                .foregroundStyle(.primary)
                            Spacer()
                            if preset == selectedLUT {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(8)
                        .background(
                            preset == selectedLUT
                                ? Color.accentColor.opacity(0.12)
                                : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(preset == selectedLUT ? [.isSelected] : [])
                }
            }
            if selectedLUT != .natural {
                Text("Applied on export via Metal GPU (CIFilter.colorCube).").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { selectedLUT = LUTPreset(rawValue: take.lutPreset) ?? .natural }
        .onChange(of: selectedLUT) { _, v in take.lutPreset = v.rawValue }
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    Task { await reexport(saveAsNew: true) }
                } label: {
                    Label("Save as New Take", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isExporting)

                Button {
                    Task { await reexport(saveAsNew: false) }
                } label: {
                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
            }

            Button {
                Task { await exportAndSave() }
            } label: {
                Label("Save to Photos", systemImage: "photo.badge.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isExporting)

            if let url = exportedURL ?? take.fileURL as URL? {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Text(exportProgress).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // swiftlint:disable:next function_body_length
    private func reexport(saveAsNew: Bool) async {
        isExporting = true
        exportProgress = "Exporting…"
        defer { isExporting = false }
        let sourceURL = take.fileURL
        let trimRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            duration: CMTime(seconds: max(1, trimEnd - trimStart), preferredTimescale: 600)
        )
        // Blade-aware: prune cuts to the current trim range for export
        let prunedCuts: [Double]? = {
            guard let cuts = take.bladeCuts, !cuts.isEmpty else { return nil }
            let start = trimRange.start.seconds
            let end = start + trimRange.duration.seconds
            let filtered = cuts.filter { $0 > start + 0.1 && $0 < end - 0.1 }.sorted()
            var deduped: [Double] = []
            for value in filtered {
                if let last = deduped.last, abs(last - value) < 0.1 {
                    continue
                }
                deduped.append(value)
            }
            return deduped.isEmpty ? nil : deduped
        }()
        let hasBlades = !(prunedCuts?.isEmpty ?? true)
        let tmpURL = ExportService.tempOutputURL()
        do {
            let outURL: URL
            if hasBlades {
                exportProgress = selectedLUT == .natural
                    ? "Composing blade segments…"
                    : "Composing with \(selectedLUT.displayName)…"
                // Export via composition using a transient Take that carries the pruned cuts
                let tempTake = Take(
                    scriptID: take.scriptID,
                    fileURL: sourceURL,
                    duration: take.duration,
                    trimRange: trimRange,
                    lutPreset: selectedLUT.rawValue,
                    bladeCuts: prunedCuts
                )
                outURL = try await ExportService.shared.exportTake(tempTake, outputURL: tmpURL)
            } else if selectedLUT == .natural {
                exportProgress = "Trimming (passthrough)…"
                outURL = try await ExportService.shared.exportPassthrough(
                    sourceURL: sourceURL, timeRange: trimRange, outputURL: tmpURL
                )
            } else {
                exportProgress = "Applying \(selectedLUT.displayName)…"
                outURL = try await ExportService.shared.exportWithLUT(
                    sourceURL: sourceURL, timeRange: trimRange, lutPreset: selectedLUT, outputURL: tmpURL
                )
            }
            exportedURL = outURL
            if saveAsNew {
                let newDuration = hasBlades
                    ? (prunedCuts.map { _ in trimRange.duration.seconds } ?? trimRange.duration.seconds)
                    : trimRange.duration.seconds
                // For blade, compute effective duration from segments
                let effectiveDuration: Double = {
                    if let cuts = prunedCuts, !cuts.isEmpty {
                        var prev = trimRange.start.seconds
                        var total = 0.0
                        let end = trimRange.start.seconds + trimRange.duration.seconds
                        for cut in cuts.sorted() {
                            total += cut - prev
                            prev = cut
                        }
                        total += end - prev
                        return total
                    }
                    return trimRange.duration.seconds
                }()
                let newTake = Take(
                    scriptID: take.scriptID,
                    fileURL: outURL,
                    duration: effectiveDuration,
                    trimRange: hasBlades ? nil : trimRange,
                    lutPreset: selectedLUT.rawValue,
                    script: take.script,
                    bladeCuts: hasBlades ? nil : nil
                )
                // Blade takes are already composed; store as single segment
                modelContext.insert(newTake)
            } else {
                // Replace: atomically update original and delete old file if different
                let oldURL = take.fileURL
                take.trimStartSeconds = trimRange.start.seconds
                take.trimDurationSeconds = trimRange.duration.seconds
                take.lutPreset = selectedLUT.rawValue
                take.bladeCuts = prunedCuts
                if outURL != oldURL {
                    take.relativeFilePath = Take.relativePath(for: outURL)
                    try? FileManager.default.removeItem(at: oldURL)
                    // Composed blade result is single file; clear cuts after bake
                    if hasBlades {
                        take.bladeCuts = nil; take.trimStartSeconds = nil; take.trimDurationSeconds = nil
                    }
                    take.duration = hasBlades ? take.bladeEffectiveDuration : trimRange.duration.seconds
                } else if hasBlades {
                    // Passthrough replaced in place; keep cuts until next edit
                    take.bladeCuts = prunedCuts
                }
            }
            try? modelContext.save()
            exportProgress = saveAsNew ? "Saved as new take ✓" : "Replaced ✓"
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            exportProgress = ""
        }
    }

    private func loadDuration() async {
        let url = take.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let asset = AVURLAsset(url: url)
        if let d = try? await asset.load(.duration), d.isValid, !d.isIndefinite {
            let seconds = d.seconds
            duration = seconds.isFinite && seconds > 0 ? seconds : take.duration
            if take.trimStartSeconds == nil {
                trimStart = 0
                trimEnd = duration
            } else {
                trimStart = take.trimStartSeconds ?? 0
                trimEnd = (take.trimStartSeconds ?? 0) + (take.trimDurationSeconds ?? duration)
                trimEnd = min(trimEnd, duration)
            }
        } else {
            duration = take.duration > 0 ? take.duration : 10
            trimStart = 0; trimEnd = duration
        }
    }

    private func makePlayerItem(for take: Take) async -> AVPlayerItem? {
        let segments = take.bladeSegments()
        guard segments.count > 1 else { return nil }
        let asset = AVURLAsset(url: take.fileURL)
        let composition = AVMutableComposition()
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let compVideo = composition.addMutableTrack(
                  withMediaType: .video,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else { return nil }
        let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
        let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var cursor = CMTime.zero
        for segment in segments {
            try? compVideo.insertTimeRange(segment, of: videoTrack, at: cursor)
            if let audioTrack, let compAudio {
                let audioDuration = await (try? audioTrack.load(.timeRange).duration) ?? segment.duration
                if segment.start < audioDuration {
                    let audioSlice = CMTimeRange(
                        start: segment.start,
                        duration: min(segment.duration, audioDuration - segment.start)
                    )
                    if audioSlice.duration.seconds > 0 {
                        try? compAudio.insertTimeRange(audioSlice, of: audioTrack, at: cursor)
                    }
                }
            }
            cursor = CMTimeAdd(cursor, segment.duration)
        }
        if let transform = try? await videoTrack.load(.preferredTransform) {
            compVideo.preferredTransform = transform
        }
        return AVPlayerItem(asset: composition)
    }

    // MARK: - Blade helpers

    private func splitAtPlayhead() {
        let time = playheadSeconds ?? (trimStart + trimEnd) / 2
        guard time > trimStart + 0.1, time < trimEnd - 0.1 else { return }
        if let cuts = take.bladeCuts, cuts.contains(where: { abs($0 - time) < 0.1 }) {
            return
        }
        bladeUndoStack.append(take.bladeCuts)
        var cuts = take.bladeCuts ?? []
        cuts.append(time)
        cuts.sort()
        var deduped: [Double] = []
        for value in cuts {
            if let last = deduped.last, abs(last - value) < 0.1 {
                continue
            }
            deduped.append(value)
        }
        take.bladeCuts = deduped
        try? modelContext.save()
        // Auto-select new segment containing the cut
        let segs = take.bladeSegments()
        for (idx, seg) in segs.enumerated() {
            let s = seg.start.seconds
            let e = s + seg.duration.seconds
            if time >= s, time < e {
                selectedSegment = idx
                break
            }
        }
    }

    private func deleteSelectedSegment() {
        guard let idx = selectedSegment else { return }
        let segments = take.bladeSegments()
        guard idx >= 0, idx < segments.count, segments.count > 1 else { return }
        bladeUndoStack.append(take.bladeCuts)
        let seg = segments[idx]
        let segStart = seg.start.seconds
        let segEnd = seg.start.seconds + seg.duration.seconds
        let len = seg.duration.seconds
        let trimStartVal = take.trimRange?.start.seconds ?? 0
        let trimEndVal = (take.trimRange.map { $0.start.seconds + $0.duration.seconds } ?? take.duration)
        var cuts = take.normalizedBladeCuts
        var newCuts: [Double] = []
        for cut in cuts {
            // Remove boundary of deleted segment: keep start for interior, remove end
            if segEnd != trimEndVal, cut == segEnd {
                continue
            }
            if segEnd == trimEndVal, cut == segStart {
                continue
            }
            var newCut = cut
            if cut > segEnd {
                newCut -= len
            }
            newCuts.append(newCut)
        }
        take.bladeCuts = newCuts.isEmpty ? nil : newCuts
        try? modelContext.save()
        selectedSegment = nil
    }

    private func pruneBladeCutsToTrim() {
        let pruned = take.prunedBladeCuts()
        if pruned?.count != take.bladeCuts?.count {
            take.bladeCuts = pruned
            try? modelContext.save()
            if let sel = selectedSegment, sel >= take.bladeSegments().count {
                selectedSegment = nil
            }
        }
    }

    private func undoLastBlade() {
        guard let last = bladeUndoStack.popLast() else { return }
        take.bladeCuts = last
        try? modelContext.save()
        selectedSegment = nil
    }

    private func exportAndSave() async {
        isExporting = true
        exportProgress = "Exporting…"
        defer { isExporting = false }

        let sourceURL = take.fileURL
        let trimRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            duration: CMTime(seconds: max(1, trimEnd - trimStart), preferredTimescale: 600)
        )
        // Blade-aware pruning
        let prunedCuts: [Double]? = {
            guard let cuts = take.bladeCuts, !cuts.isEmpty else { return nil }
            let start = trimRange.start.seconds
            let end = start + trimRange.duration.seconds
            let filtered = cuts.filter { $0 > start + 0.1 && $0 < end - 0.1 }.sorted()
            var deduped: [Double] = []
            for value in filtered {
                if let last = deduped.last, abs(last - value) < 0.1 {
                    continue
                }
                deduped.append(value)
            }
            return deduped.isEmpty ? nil : deduped
        }()
        let hasBlades = !(prunedCuts?.isEmpty ?? true)
        let tmpURL = ExportService.tempOutputURL()

        do {
            let outURL: URL
            if hasBlades {
                exportProgress = selectedLUT == .natural
                    ? "Composing blade segments…"
                    : "Composing with \(selectedLUT.displayName)…"
                let tempTake = Take(
                    scriptID: take.scriptID,
                    fileURL: sourceURL,
                    duration: take.duration,
                    trimRange: trimRange,
                    lutPreset: selectedLUT.rawValue,
                    bladeCuts: prunedCuts
                )
                outURL = try await ExportService.shared.exportTake(tempTake, outputURL: tmpURL)
            } else if selectedLUT == .natural {
                exportProgress = "Trimming (passthrough)…"
                outURL = try await ExportService.shared.exportPassthrough(
                    sourceURL: sourceURL, timeRange: trimRange, outputURL: tmpURL
                )
            } else {
                exportProgress = "Applying \(selectedLUT.displayName)…"
                outURL = try await ExportService.shared.exportWithLUT(
                    sourceURL: sourceURL, timeRange: trimRange, lutPreset: selectedLUT, outputURL: tmpURL
                )
            }
            exportedURL = outURL
            // Update take's trim + blade
            take.trimStartSeconds = trimRange.start.seconds
            take.trimDurationSeconds = trimRange.duration.seconds
            take.lutPreset = selectedLUT.rawValue
            take.bladeCuts = prunedCuts
            try? modelContext.save()

            exportProgress = "Saving to Photos…"
            try await ExportService.shared.saveToPhotos(fileURL: outURL)
            // Sandbox cleanup on success: remove original source if different from output
            if outURL != sourceURL {
                try? FileManager.default.removeItem(at: sourceURL)
                take.relativeFilePath = Take.relativePath(for: outURL)
                // Composed result is baked; clear blade/trim if we baked blades
                if hasBlades {
                    take.bladeCuts = nil
                    take.trimStartSeconds = nil
                    take.trimDurationSeconds = nil
                    take.duration = take.bladeEffectiveDuration
                }
                try? modelContext.save()
            } else if hasBlades {
                // In-place passthrough with blades? keep pruned
                take.bladeCuts = prunedCuts
                try? modelContext.save()
            }
            exportProgress = "Saved ✓"
            showSaved = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            exportProgress = ""
            // Retain original on failure per spec
        }
    }
}

#Preview {
    NavigationStack {
        ReviewView(take: Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/demo.mp4"), duration: 30))
            .modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true)
    }
}
