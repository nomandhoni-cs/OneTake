//
//  ReactionStudioView.swift
//  OneTake
//
//  Owns: Reaction capture screen — BG canvas + framing preview, layout/audio
//  controls, transport, optional script overlay, export flow, Take saving.
//  Why: Capture-first sibling of `StudioView` — recording is a plain
//  movie-file capture (reliable, pausable) while the cutout is computed after
//  Stop by `ReactionExportJob`; the preview shows honest framing geometry so
//  placement choices match the export.
//  See: docs/ARCHITECTURE.md §6 + openspec/changes/capture-first-reaction-pipeline/specs/reaction-post-processing/spec.md
//
import SwiftData
import SwiftUI

struct ReactionStudioView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.dismiss)
    private var dismiss

    @Query(sort: \Script.updatedAt, order: .reverse)
    private var scripts: [Script]

    @State private var capture = ReactionCaptureService()
    @State private var haptics = HapticsService()
    @State private var activityService = RecordingActivityService()

    @AppStorage("studioIsRecording")
    private var studioIsRecordingFlag = false
    @AppStorage("reaction.presenter.cx")
    private var presenterCX = ReactionPresenterDefaults.centerX
    @AppStorage("reaction.presenter.cy")
    private var presenterCY = ReactionPresenterDefaults.centerY
    @AppStorage("reaction.presenter.w")
    private var presenterW = ReactionPresenterDefaults.width
    @AppStorage("reaction.presenter.h")
    private var presenterH = ReactionPresenterDefaults.height

    @State private var selectedScriptID: Script.ID?
    @State private var speed: Double = 2.0
    @State private var fontSize: Double = 24
    @State private var backdropOpacity: Double = 0.35
    @State private var countdownEnabled = true
    @State private var mirrorMode = true

    // Unused by the reaction pipeline (fixed 1080p30 SDR) — placeholders for
    // the shared settings sheet, which hides them when `isReaction`.
    @State private var resolution: Resolution = .hd1080p
    @State private var frameRate: FrameRate = .standard
    @State private var aspect: AspectRatio = .vertical
    @State private var enableHDR = false

    @State private var elapsedSeconds = 0
    @State private var isCountdown = false
    @State private var countdownValue = 3
    @State private var showSettingsSheet = false
    @State private var showBGPicker = false
    @State private var showDiscardConfirmation = false
    @State private var showProcessing = false
    @State private var prompterExpanded = false
    @State private var recordingStartDate: Date?
    @State private var pausedDuration: TimeInterval = 0
    @State private var pauseStartDate: Date?
    @State private var pendingDuration: TimeInterval = 0

    private var currentScript: Script? {
        guard let id = selectedScriptID else { return nil }
        return scripts.first(where: { $0.id == id })
    }

    private var prompterText: String {
        currentScript?.body ?? "Reaction notes appear here.\n\nPick an optional script above, or freestyle."
    }

    /// Title for the collapsed notes pill — script title when picked,
    /// otherwise an explicit optional affordance.
    private var collapsedNotesTitle: String {
        if let title = currentScript?.title.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            return title
        }
        return "Notes (optional)"
    }

    private var presenterBinding: Binding<CGRect> {
        Binding(
            get: { CGRect(x: presenterCX, y: presenterCY, width: presenterW, height: presenterH) },
            set: { rect in
                presenterCX = rect.origin.x
                presenterCY = rect.origin.y
                presenterW = rect.width
                presenterH = rect.height
                capture.style.presenterUnitRect = rect
            }
        )
    }

    var body: some View {
        // System NavigationStack chrome: close + script + settings live in
        // the nav bar, which the OS always places below the status bar.
        // Plain glyphs, zero custom styling — any pill rendering is iOS 26's
        // own native toolbar treatment, identical to Apple's apps.
        NavigationStack {
            ZStack {
                // Fullscreen measure + paint: only this reader ignores the safe
                // area, so the preview stays edge-to-edge and the presenter-rect
                // mapping matches export geometry.
                GeometryReader { geo in
                    ZStack {
                        framingPreview(size: geo.size)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .overlay {
                                PresenterGestureLayer(rect: presenterBinding, enabled: !capture.isRecording || !capture.isPaused)
                            }
                    }
                }
                .ignoresSafeArea()

                if !capture.background.hasMedia, !capture.isRecording {
                    BackgroundEmptyState {
                        showBGPicker = true
                    }
                }

                if capture.isPaused {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    PausedBadge()
                }

                VStack(spacing: 0) {
                    if prompterExpanded {
                        ZStack(alignment: .topTrailing) {
                            PrompterView(
                                text: prompterText,
                                speedMultiplier: speed,
                                fontSize: fontSize,
                                opacity: backdropOpacity,
                                isScrolling: capture.isRecording && !capture.isPaused && !isCountdown
                            )
                            Button {
                                prompterExpanded = false
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black.opacity(0.55), in: Circle())
                            }
                            .padding(8)
                            .accessibilityLabel("Hide script notes")
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    } else {
                        // Slim pill instead of the 220pt prompter — freestyle
                        // stays compact until the user picks a script or expands.
                        HStack {
                            Spacer()
                            Button {
                                prompterExpanded = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text")
                                    Text(collapsedNotesTitle)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up")
                                        .font(.caption2)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.black.opacity(0.55), in: Capsule())
                            }
                            .accessibilityLabel("Show script notes")
                            .accessibilityHint("Expands the scrolling prompter")
                            Spacer()
                        }
                        .padding(.top, 8)
                    }

                    Spacer()

                    if capture.pendingExport != nil, !showProcessing {
                        PendingExportBanner(
                            onProcess: { Task { await runPendingExport() } },
                            onDiscard: { capture.discardRaw() }
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                    }

                    ReactionTransportBar(
                        isRecording: capture.isRecording,
                        isPaused: capture.isPaused,
                        elapsedSeconds: elapsedSeconds,
                        hasBackground: capture.background.hasMedia,
                        bgLocked: capture.isRecording,
                        onRestartBG: { capture.background.restart() },
                        onRecord: { Task { await startRecordingFlow() } },
                        onPause: { capture.pauseRecording(); pauseStartDate = Date() },
                        onResume: { resumeRecording() },
                        onStop: { Task { await stopRecording() } }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 12)

                    if capture.isRecording {
                        Text(capture.isPaused ? "Paused • \(format(seconds: elapsedSeconds))" : "● REC \(format(seconds: elapsedSeconds))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(capture.isPaused ? Color.white : Color.appSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .padding(.bottom, 8)
                    }
                }

                if isCountdown {
                    CountdownView(count: countdownValue).transition(.opacity)
                }

                if showProcessing {
                    ProcessingView(progress: capture.exportProgress) {
                        capture.cancelExport()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: requestDismiss) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close reaction studio")
                }
                ToolbarItem(placement: .principal) {
                    ScriptSelectorView(selectedID: $selectedScriptID)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(
                        action: { showSettingsSheet = true },
                        label: {
                            Image(systemName: "gearshape.fill")
                        }
                    )
                    .accessibilityLabel("Reaction settings")
                }
            }
        }
        .task {
            capture.style.presenterUnitRect = CGRect(x: presenterCX, y: presenterCY, width: presenterW, height: presenterH)
            await capture.configure()
            haptics.prewarm()
        }
        .onDisappear {
            capture.cancelExport()
            capture.discardRaw()
            capture.stopSession()
            activityService.endSync()
            studioIsRecordingFlag = false
        }
        .onChange(of: capture.isRecording) { _, recording in
            studioIsRecordingFlag = recording
        }
        .onChange(of: selectedScriptID) { _, new in
            // Freestyle collapses to the slim pill; picking a script reveals notes.
            prompterExpanded = new != nil
        }
        .onChange(of: mirrorMode) { _, enabled in
            capture.setMirroring(enabled: enabled)
        }
        .onChange(of: capture.audioMeter.level) { _, level in
            capture.mixer.setMicMeter(level)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, capture.isRecording {
                Task { await stopRecording() }
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            StudioSettingsSheet(
                resolution: $resolution,
                frameRate: $frameRate,
                enableHDR: $enableHDR,
                mirrorMode: $mirrorMode,
                countdownEnabled: $countdownEnabled,
                aspect: $aspect,
                speed: $speed,
                fontSize: $fontSize,
                opacity: $backdropOpacity,
                isRecordingOrPaused: capture.isRecording || capture.isPaused,
                supportedCombos: [],
                isReaction: true,
                reaction: ReactionSheetBindings(
                    layout: Binding(
                        get: { capture.style.layout },
                        set: { capture.style.layout = $0 }
                    ),
                    outline: Binding(
                        get: { capture.style.outline },
                        set: { capture.style.outline = $0 }
                    ),
                    rect: presenterBinding,
                    mixer: capture.mixer
                )
            )
        }
        .sheet(isPresented: $showBGPicker) {
            BackgroundPickerView(
                onPick: { result in
                    showBGPicker = false
                    switch result {
                    case let .success(picked):
                        capture.applyPickedBackground(picked)
                    case let .failure(error):
                        capture.setError(error.localizedDescription)
                    }
                },
                onCancel: { showBGPicker = false }
            )
        }
        .alert("Background", isPresented: errorAlertBinding) {
            Button("Pick Background") { showBGPicker = true }
            Button("OK", role: .cancel) { capture.clearError() }
        } message: {
            Text(errorAlertMessage)
        }
        .alert("Export failed", isPresented: exportFailedBinding) {
            Button("Retry") { Task { await runPendingExport() } }
            Button("Discard", role: .destructive) { capture.discardRaw() }
            Button("Later", role: .cancel) {}
        } message: {
            Text(capture.exportError ?? "Processing failed.")
        }
        .alert("Camera & Microphone Required", isPresented: permissionAlertBinding) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera and microphone access in Settings to record reactions.")
        }
        .confirmationDialog("Discard this reaction?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard Take", role: .destructive) {
                capture.discardRecording()
                dismiss()
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("You're still recording. Leaving now discards this take.")
        }
        .task(id: capture.isRecording && !capture.isPaused) {
            guard capture.isRecording, !capture.isPaused else { return }
            while capture.isRecording, !capture.isPaused {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if capture.isPaused {
                    break
                }
                elapsedSeconds += 1
                activityService.update(elapsedSeconds: elapsedSeconds, audioLevel: capture.audioMeter.normalizedLevel)
            }
        }
    }

    // MARK: - Framing preview

    // Honest geometry preview: BG fullscreen with the live camera in the
    // presenter's rect (circle), half (split), or fullscreen (silhouette).
    // No inference runs — the cutout is computed at export.
    // swiftlint:disable:next avoid_helper_func_view
    private func framingPreview(size: CGSize) -> some View {
        ZStack {
            backgroundLayer
            cameraLayer(size: size)
        }
        .clipped()
    }

    @ViewBuilder private var backgroundLayer: some View {
        if capture.background.isVideo {
            BackgroundPlayerView(player: capture.background.previewPlayer)
        } else if let image = capture.background.media?.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.black
        }
    }

    // swiftlint:disable:next avoid_helper_func_view
    @ViewBuilder
    private func cameraLayer(size: CGSize) -> some View {
        switch capture.style.layout {
        case .circle:
            let rect = ReactionCanvasGeometry.presenterRect(unit: presenterBinding.wrappedValue, canvas: size)
            cameraFeed
                .frame(width: rect.width, height: rect.height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(outlinePreviewColor(), lineWidth: 3)
                )
                .position(x: rect.midX, y: rect.midY)
        case .split:
            let presenterHalf = ReactionCanvasGeometry.splitRects(canvas: size).1
            cameraFeed
                .frame(width: presenterHalf.width, height: presenterHalf.height)
                .clipped()
                .overlay(Rectangle().strokeBorder(outlinePreviewColor(), lineWidth: 3))
                .position(x: presenterHalf.midX, y: presenterHalf.midY)
        case .silhouette:
            cameraFeed
        }
    }

    private var cameraFeed: some View {
        CameraPreviewView(session: capture.camera.session, isMirrored: mirrorMode)
    }

    private func outlinePreviewColor() -> Color {
        capture.style.outline.color ?? Color.white.opacity(0.7)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { capture.errorMessage != nil },
            set: {
                if !$0 {
                    capture.clearError()
                }
            }
        )
    }

    private var exportFailedBinding: Binding<Bool> {
        Binding(
            get: { capture.exportError != nil },
            set: {
                if !$0 {
                    capture.clearExportError()
                }
            }
        )
    }

    private var permissionAlertBinding: Binding<Bool> {
        Binding(
            get: { capture.permissionDenied },
            set: { _ in }
        )
    }

    private var errorAlertMessage: String {
        capture.errorMessage ?? ""
    }

    // MARK: - Recording

    private func startRecordingFlow() async {
        if countdownEnabled {
            await runCountdown()
        }
        guard capture.background.hasMedia else {
            capture.setError("Pick a background first — tap BG Media.")
            showBGPicker = true
            return
        }
        recordingStartDate = Date()
        pausedDuration = 0
        elapsedSeconds = 0
        let title = currentScript?.title ?? "Reaction"
        activityService.start(scriptTitle: title)
        let started = capture.startRecording(to: ExportService.takesDirectory().appendingPathComponent("\(UUID().uuidString).mp4"))
        if started {
            haptics.impact(style: .medium)
        } else {
            await activityService.end()
        }
    }

    private func resumeRecording() {
        if let start = pauseStartDate {
            pausedDuration += Date().timeIntervalSince(start)
            pauseStartDate = nil
        }
        capture.resumeRecording()
        haptics.impact(style: .medium)
        activityService.update(elapsedSeconds: elapsedSeconds, audioLevel: capture.audioMeter.normalizedLevel)
    }

    /// Stop capture → process → save the composited take.
    private func stopRecording() async {
        let raw = recordingStartDate.map { Date().timeIntervalSince($0) } ?? Double(elapsedSeconds)
        pendingDuration = max(0, raw - pausedDuration)
        guard let rawURL = await capture.stopCapture() else {
            await activityService.end()
            resetTimers()
            return
        }
        await activityService.end()
        resetTimers()
        haptics.impact(style: .light)
        // Backgrounded stop: park the raw file — the banner offers processing.
        if scenePhase == .background {
            capture.parkRaw(rawURL)
            return
        }
        await export(rawURL: rawURL, duration: pendingDuration)
    }

    private func export(rawURL: URL, duration: TimeInterval) async {
        showProcessing = true
        defer { showProcessing = false }
        guard let finalURL = await capture.startExport(rawURL: rawURL) else {
            // Cancelled → pending banner offers retry; failed → retry alert.
            return
        }
        guard FileManager.default.fileExists(atPath: finalURL.path) else { return }
        let sid = selectedScriptID ?? UUID()
        let take = Take(
            scriptID: sid,
            fileURL: finalURL,
            duration: duration,
            script: scripts.first(where: { $0.id == sid }),
            isReaction: true,
            backgroundAssetLocalID: capture.background.media?.localID
        )
        modelContext.insert(take)
        try? modelContext.save()
    }

    /// Retries (or resumes) the pending export — from alert, banner, or return.
    private func runPendingExport() async {
        guard let pending = capture.pendingExport else { return }
        await export(rawURL: pending.rawURL, duration: pendingDuration)
    }

    private func resetTimers() {
        recordingStartDate = nil
        pausedDuration = 0
        pauseStartDate = nil
    }

    private func runCountdown() async {
        isCountdown = true
        for index in (1 ... 3).reversed() {
            countdownValue = index
            haptics.playCountdownTick(isFinal: false)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        countdownValue = 0
        haptics.playCountdownTick(isFinal: true)
        try? await Task.sleep(nanoseconds: 300_000_000)
        isCountdown = false
    }

    private func requestDismiss() {
        if showProcessing {
            // Cancel first, then close — leaving mid-export discards the raw.
            capture.cancelExport()
        } else if capture.isRecording {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func format(seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview("Reaction - No BG") {
    ReactionStudioView()
        .modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true)
}
