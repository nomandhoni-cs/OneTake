//
//  StudioView.swift
//  OneTake
//

//  See: docs/ARCHITECTURE.md §6 (Studio) + openspec/specs/prompter-studio/spec.md + AGENTS.md §6
import AVFoundation
import SwiftData
import SwiftUI

// swiftlint:disable force_try force_cast force_unwrapping
// swiftlint:disable file_length type_body_length

struct StudioView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.dismiss)
    private var dismiss
    @Environment(ProEntitlementService.self)
    private var pro

    @Query(sort: \Script.updatedAt, order: .reverse)

    // swiftlint:disable:next attributes
    private var scripts: [Script]

    var initialScriptID: Script.ID?

    /// Shows the in-UI back control. `true` for modal presentation, where no
    /// system back button exists; `false` when pushed on a `NavigationStack`,
    /// so the native back button and swipe-back gesture stay available.
    var showsDismissButton = true

    /// AppStorage defaults (task 9.3)
    @AppStorage("resolution")
    private var storedResolution = StudioSettings.defaultResolution.rawValue
    @AppStorage("frameRate")
    private var storedFrameRate = StudioSettings.defaultFrameRate.rawValue
    @AppStorage("mirrorMode")
    private var mirrorMode = StudioSettings.defaultMirror
    @AppStorage("countdownEnabled")
    private var countdownEnabled = true
    @AppStorage("aspectRatio")
    private var storedAspect = StudioSettings.defaultAspect.rawValue
    @AppStorage("lastScriptID")
    private var lastScriptIDStorage = ""
    @AppStorage("studioIsRecording")
    private var studioIsRecordingFlag = false

    @State private var resolution: Resolution = StudioSettings.defaultResolution
    @State private var frameRate: FrameRate = StudioSettings.defaultFrameRate
    @State private var aspect: AspectRatio = StudioSettings.defaultAspect
    @State private var enableHDR = false

    // Selector state
    @State private var selectedScriptID: Script.ID?
    @State private var showMissingIndicator = false

    // Prompter tweak state (shared with sheet)
    @State private var speed: Double = 2.0
    @State private var fontSize: Double = 24
    @State private var backdropOpacity: Double = 0.35

    @State private var isRecording = false
    @State private var isPaused = false
    @State private var isCountdown = false
    @State private var countdownValue = 3
    @State private var elapsedSeconds = 0
    @State private var showPermissionDenied = false
    @State private var showThermalBanner = false
    @State private var showSettingsSheet = false
    @State private var showDiscardConfirmation = false
    @State private var showPaywall = false

    @State private var captureService = CaptureService()
    @State private var audioService = AudioSessionService()
    @State private var haptics = HapticsService()
    @State private var activityService = RecordingActivityService()
    @State private var thermal = ThermalMonitor()

    @State private var recordingURL: URL?
    @State private var recordingStartDate: Date?
    @State private var pausedDuration: TimeInterval = 0
    @State private var pauseStartDate: Date?

    private var currentScript: Script? {
        guard let id = selectedScriptID else { return nil }
        return scripts.first(where: { $0.id == id })
    }

    private var prompterText: String {
        currentScript?.body ?? "Your script will appear here.\n\nSelect a script above or add words in the Scripts tab, then press Record."
    }

    private var isRecordingOrPaused: Bool {
        isRecording || isPaused
    }

    private var studioContent: some View {
        ZStack {
            cameraLayer
                .overlay { AspectMaskView(ratio: aspect).allowsHitTesting(false) }
                .overlay(alignment: .top) {
                    // Dim overlay when paused
                    if isPaused {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack {
                            Text("Paused").font(.headline).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
                                .background(
                                    Color.black.opacity(0.6),
                                    in: Capsule()
                                ).padding(.top, 80)
                        }
                    }
                }

            VStack(spacing: 0) {
                prompterSection
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()

                VUMeterView(level: audioService.level)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                recordingControls
                    .padding(.horizontal)
                    .padding(.bottom, 12)

                // Inline aspect is now in sheet; keep no inline tray per 4.5 — only show recording state capsule
                if isRecordingOrPaused {
                    Text(isPaused ? "Paused • \(format(seconds: elapsedSeconds))" : "● REC \(format(seconds: elapsedSeconds))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isPaused ? Color.white : Color.appSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(Color.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 8)
                }
            }

            if isCountdown {
                CountdownView(count: countdownValue).transition(.opacity)
            }
            if thermal.shouldDowngrade, showThermalBanner {
                VStack {
                    Label("Thermal pressure — downgraded to 1080p to cool down", systemImage: "thermometer.sun.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white).padding(10).background(
                            Color.orange.opacity(0.92),
                            in: Capsule()
                        ).padding(.top, 60)
                    Spacer()
                }.transition(.move(edge: .top))
            }
        }
    }

    var body: some View {
        Group {
            if showsDismissButton {
                // Fullscreen modal: system NavigationStack chrome (close +
                // script + settings) over a transparent bar. Plain glyphs,
                // zero custom styling.
                NavigationStack {
                    studioContent
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .toolbarColorScheme(.dark, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button(action: requestDismiss) {
                                    Image(systemName: "xmark")
                                }
                                .accessibilityLabel("Close studio")
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
                                .accessibilityLabel("Camera settings")
                            }
                        }
                }
            } else {
                // Pushed on a Scripts stack: inherit the parent bar (system
                // back button) and contribute script + settings items.
                studioContent
                    .navigationTitle(isPaused ? "Paused" : (isRecording ? "● REC \(format(seconds: elapsedSeconds))" : "Studio"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
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
                            .buttonStyle(.plain)
                            .accessibilityLabel("Camera settings")
                        }
                    }
            }
        }
        .confirmationDialog("Discard this take?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard Take", role: .destructive) {
                Task { await discardRecording(); dismiss() }
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("You're still recording. Leaving now discards this take.")
        }
        .task {
            // Restore selector from initial or lastScriptID
            if let initial = initialScriptID {
                selectedScriptID = initial
                lastScriptIDStorage = initial.uuidString
            } else if let last = UUID(uuidString: lastScriptIDStorage), scripts.contains(where: { $0.id == last }) {
                selectedScriptID = last
            } else if let s = UUID(uuidString: lastScriptIDStorage), !scripts.contains(where: { $0.id == s }),
                      !lastScriptIDStorage.isEmpty
            // swiftlint:disable:next opening_brace
            {
                selectedScriptID = nil
                withAnimation { showMissingIndicator = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { showMissingIndicator = false } }
            }
            resolution = Resolution(rawValue: storedResolution) ?? .hd1080p
            frameRate = FrameRate(rawValue: storedFrameRate) ?? .standard
            aspect = AspectRatio(rawValue: storedAspect) ?? .wide
            await configureSession()
            haptics.prewarm()
            audioService.startMetering()
        }
        .onChange(of: selectedScriptID) { _, new in
            if let id = new {
                lastScriptIDStorage = id.uuidString
            } else {
                lastScriptIDStorage = ""
            }
        }
        .onDisappear {
            captureService.stopSession()
            audioService.stopMetering()
            activityService.endSync()
            studioIsRecordingFlag = false
        }
        .onChange(of: resolution) { _, v in storedResolution = v.rawValue; Task { await configureSession() } }
        .onChange(of: frameRate) { _, v in storedFrameRate = v.rawValue; Task { await configureSession() } }
        .onChange(of: aspect) { _, v in storedAspect = v.rawValue }
        .onChange(of: thermal.shouldDowngrade) { _, critical in
            if critical, resolution == .uhd4K {
                resolution = .hd1080p
                withAnimation { showThermalBanner = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { showThermalBanner = false } }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                if isPaused {
                    Task { await stopRecording() }
                } else if isRecording {
                    Task { await stopRecording() }
                }
            }
        }
        .onChange(of: isRecordingOrPaused) { _, active in
            studioIsRecordingFlag = active
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack {
                PaywallView(showsClose: true)
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
                isRecordingOrPaused: isRecordingOrPaused,
                supportedCombos: captureService.supportedCombinations()
            )
        }
        .alert("Camera & Microphone Required", isPresented: $showPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Allow camera and microphone access in Settings to record.") }
        .overlay(alignment: .top) {
            if showMissingIndicator {
                Text("Script not available").font(.caption2.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 8).padding(
                    .vertical,
                    4
                ).background(Color.red, in: Capsule()).padding(.top, 100)
            }
        }
        .task(id: isRecording && !isPaused) {
            guard isRecording, !isPaused else { return }
            while isRecording, !isPaused {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if isPaused {
                    break
                }
                elapsedSeconds += 1
                activityService.update(elapsedSeconds: elapsedSeconds, audioLevel: audioService.normalizedLevel)
            }
        }
    }

    // swiftlint:disable:next attributes
    private var cameraLayer: some View {
        CameraPreviewView(session: captureService.session, isMirrored: mirrorMode)
            .ignoresSafeArea()
    }

    private var prompterSection: some View {
        PrompterView(
            text: prompterText,
            speedMultiplier: speed,
            fontSize: fontSize,
            opacity: backdropOpacity,
            isScrolling: isRecording && !isPaused && !isCountdown
        )
    }

    private var recordingControls: some View {
        HStack(spacing: 16) {
            Label(audioService.currentRouteName, systemImage: "mic.fill")
                .font(.caption2.weight(.medium)).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6).background(
                    Color.black.opacity(0.55),
                    in: Capsule()
                )
            Spacer()
            if isPaused {
                Button { Task { await resumeRecording() } } label: {
                    ZStack {
                        Circle().fill(Color.green).frame(width: 68, height: 68); Image(systemName: "play.fill").foregroundStyle(.white)
                            .font(.title2)
                    }.shadow(
                        color: .black.opacity(0.3),
                        radius: 8
                    )
                }.accessibilityLabel("Resume recording")
                Button { Task { await stopRecording() } } label: {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 68, height: 68); RoundedRectangle(cornerRadius: 6).fill(Color.white).frame(
                            width: 28,
                            height: 28
                        )
                    }.shadow(color: .black.opacity(0.3), radius: 8)
                }.accessibilityLabel("Stop recording")
            } else if isRecording {
                Button { Task { await pauseRecording() } } label: {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 68, height: 68); HStack(spacing: 6) { Rectangle().fill(Color.black).frame(
                            width: 8,
                            height: 28
                        ).clipShape(Capsule()); Rectangle().fill(Color.black).frame(width: 8, height: 28).clipShape(Capsule())
                        }
                    }.shadow(
                        color: .black.opacity(0.3),
                        radius: 8
                    )
                }.accessibilityLabel("Pause recording")
                Button { Task { await stopRecording() } } label: {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 68, height: 68); RoundedRectangle(cornerRadius: 6).fill(Color.white).frame(
                            width: 28,
                            height: 28
                        )
                    }.shadow(color: .black.opacity(0.3), radius: 8)
                }.accessibilityLabel("Stop recording")
            } else {
                Button { Task { await startRecordingFlow() } } label: {
                    ZStack { Circle().fill(Color.white).frame(width: 68, height: 68); Circle().fill(Color.red).frame(width: 58, height: 58)
                    }.shadow(
                        color: .black.opacity(0.3),
                        radius: 8
                    )
                }.accessibilityLabel("Start recording")
            }
            Spacer()
            Text(isRecordingOrPaused ? format(seconds: elapsedSeconds) : "Ready")
                .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    Color.black.opacity(0.55),
                    in: Capsule()
                )
        }
    }

    private func configureSession() async {
        let perm = captureService.checkPermission()
        if perm == .notDetermined {
            let granted = await captureService.requestPermission()
            if !granted {
                showPermissionDenied = true; return
            }
        } else if perm == .denied {
            showPermissionDenied = true; return
        }
        await captureService.configure(resolution: resolution, frameRate: frameRate, enableHDR: enableHDR)
        captureService.startSession()
    }

    private func startRecordingFlow() async {
        guard pro.isPro else {
            showPaywall = true
            return
        }
        if countdownEnabled {
            await runCountdown()
        }
        await startRecording()
    }

    private func runCountdown() async {
        isCountdown = true
        for i in (1 ... 3).reversed() {
            countdownValue = i; haptics.playCountdownTick(isFinal: false); try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        countdownValue = 0; haptics.playCountdownTick(isFinal: true); try? await Task.sleep(nanoseconds: 300_000_000)
        isCountdown = false
    }

    private func startRecording() async {
        let url = ExportService.takesDirectory().appendingPathComponent("\(UUID().uuidString).mp4")
        recordingURL = url; recordingStartDate = Date(); pausedDuration = 0; elapsedSeconds = 0; isRecording = true; isPaused = false
        let title = currentScript?.title ?? (selectedScriptID == nil ? "Freestyle" : "OneTake")
        activityService.start(scriptTitle: title)
        audioService.startMetering()
        captureService.startRecording(to: url, lockExposure: true)
        haptics.impact(style: .medium)
    }

    private func pauseRecording() async {
        isPaused = true
        pauseStartDate = Date()
        captureService.pauseRecording()
        haptics.impact(style: .light)
        // Single paused Live Activity update (audio silenced; no paused-flag API yet).
        activityService.update(elapsedSeconds: elapsedSeconds, audioLevel: 0)
    }

    private func resumeRecording() async {
        if let start = pauseStartDate {
            pausedDuration += Date().timeIntervalSince(start)
            pauseStartDate = nil
        }
        isPaused = false
        captureService.resumeRecording()
        haptics.impact(style: .medium)
        let title = currentScript?.title ?? "Freestyle"
        activityService.start(scriptTitle: title) // ensure activity alive; service handles single instance
        // Also send resume tick
        activityService.update(elapsedSeconds: elapsedSeconds, audioLevel: audioService.normalizedLevel)
    }

    private func stopRecording() async {
        let wasPaused = isPaused
        captureService.stopRecording()
        // If using segment fallback, merge needed — handled inside CaptureService.stop path? For now we merge here if needed
        isRecording = false; isPaused = false
        await activityService.end()
        // Compute actual duration minus paused time
        let raw = recordingStartDate.map { Date().timeIntervalSince($0) } ?? Double(elapsedSeconds)
        let duration = max(0, raw - pausedDuration)
        if let url = recordingURL {
            // If CaptureService used segments, the final merged file may be at segments dir; check if url still exists or if merged file
            // produced
            var finalURL = url
            // Check for segment merge: if captureService has segments for this recording, merge
            if let merged = await captureService.finalizeSegmentsIfNeeded(originalURL: url) {
                finalURL = merged
            } else if !FileManager.default.fileExists(atPath: finalURL.path) {
                // No file, possibly still segments? Try merge anyway
                if let m = await captureService.finalizeSegmentsIfNeeded(originalURL: url) {
                    finalURL = m
                }
            }
            // Without a file (e.g., no camera hardware), there is nothing to save.
            if FileManager.default.fileExists(atPath: finalURL.path) || wasPaused {
                let sid = selectedScriptID ?? currentScript?.id ?? UUID()
                let take = Take(scriptID: sid, fileURL: finalURL, duration: duration, script: scripts.first(where: { $0.id == sid }))
                modelContext.insert(take)
                try? modelContext.save()
            } else {
                debugPrint("[Studio] no file at \(finalURL)")
            }
        }
        recordingURL = nil; recordingStartDate = nil; pausedDuration = 0; pauseStartDate = nil
        haptics.impact(style: .light)
    }

    private func format(seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Dismissal

    /// Leaves the camera, confirming first so an in-progress take is not lost.
    private func requestDismiss() {
        if isRecordingOrPaused {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    /// Stops capture and deletes the file instead of saving it as a `Take`.
    private func discardRecording() async {
        captureService.stopRecording()
        isRecording = false
        isPaused = false
        await activityService.end()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        recordingStartDate = nil
        pausedDuration = 0
        pauseStartDate = nil
        haptics.impact(style: .light)
    }
}

#Preview("Studio - No script") {
    NavigationStack { StudioView(initialScriptID: nil).modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true) }
        .environment(ProEntitlementService.previewUnlocked)
}

#Preview("Studio - With script") {
    let c = try! ModelContainer(
        for: Script.self,
        Take.self,
        ScriptCategory.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let s = Script(title: "Demo", body: "Hello OneTake\n\nScroll me at 2x.")
    ModelContext(c).insert(s)
    return NavigationStack { StudioView(initialScriptID: s.id).modelContainer(c) }
        .environment(ProEntitlementService.previewUnlocked)
}

#Preview("Paused") {
    NavigationStack { StudioView(initialScriptID: nil).modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true) }
        .environment(ProEntitlementService.previewUnlocked)
}

// swiftlint:enable force_try force_cast force_unwrapping
