//
//  ScriptEditorSheet.swift
//  OneTake
//

import SwiftData
import SwiftUI

/// Distraction-free editor sheet with live word-count telemetry in the
/// toolbar and a 1-tap "Record with Prompter" launch action.
struct ScriptEditorSheet: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @Bindable var script: Script
    @Binding var path: NavigationPath

    @State private var cadence = CadenceViewModel()
    @FocusState private var bodyFocused: Bool

    private var telemetry: String {
        "\(cadence.wordCount) words · \(CadenceViewModel.formattedDuration(wordCount: cadence.wordCount))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Script title", text: $script.title, axis: .vertical)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                TextEditor(text: $script.body)
                    .font(.body)
                    .focused($bodyFocused)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    CategoryPickerBar(script: script)
                    Button {
                        startRecording()
                    } label: {
                        Label("Record with Prompter", systemImage: "video.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
                .padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle("Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(telemetry)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .onAppear {
                cadence.update(body: script.body)
                bodyFocused = true
            }
            .onChange(of: script.body) { _, newBody in
                script.updatedAt = Date()
                cadence.update(body: newBody)
            }
        }
    }

    // MARK: - Actions

    private func startRecording() {
        save()
        let scriptID = script.id
        UserDefaults.standard.set(scriptID.uuidString, forKey: "lastScriptID")
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if ENABLE_TAB_SHELL {
                NotificationCenter.default.post(name: .showStudio, object: nil)
            } else {
                path.append(Route.studio(scriptID))
            }
        }
    }

    private func saveAndDismiss() {
        save()
        // Remove an empty, untouched script created by "Add Script" if the user bailed.
        if script.title.trimmingCharacters(in: .whitespaces).isEmpty,
           script.body.trimmingCharacters(in: .whitespaces).isEmpty,
           script.takes.isEmpty
        // swiftlint:disable:next opening_brace
        {
            modelContext.delete(script)
        }
        dismiss()
    }

    private func save() {
        try? modelContext.save()
    }
}

#Preview {
    ScriptEditorSheet(
        script: Script(title: "Hello", body: "One take. No cuts."),
        path: .constant(NavigationPath())
    )
    .modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true)
}
