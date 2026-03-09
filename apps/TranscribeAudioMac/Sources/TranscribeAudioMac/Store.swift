import AppKit
import Foundation

@MainActor
final class TranscribeStore: ObservableObject {
    @Published var section: TranscribeSection = .transcribe
    @Published var history: [TranscribeJob] = []
    @Published var defaults: TranscribeDefaults?
    @Published var draft: TranscribeDraft?
    @Published var selectedJobID: String?
    @Published var previewText = ""
    @Published var isRunning = false
    @Published var statusMessage = "Ready."

    private let cli = TranscribeCLI()

    var selectedJob: TranscribeJob? {
        guard let selectedJobID else { return nil }
        return history.first(where: { $0.id == selectedJobID })
    }

    var focusedJob: TranscribeJob? {
        selectedJob ?? history.first
    }

    var canStart: Bool {
        guard let draft else { return false }
        return !isRunning && !draft.inputPaths.isEmpty
    }

    private func suggestedOutputDirectory(for draft: TranscribeDraft) -> String {
        if !draft.selectedFiles.isEmpty {
            let firstParent = URL(fileURLWithPath: draft.selectedFiles[0]).deletingLastPathComponent()
            return firstParent.appendingPathComponent("output", isDirectory: true).path
        }
        if !draft.selectedDirectory.isEmpty {
            return URL(fileURLWithPath: draft.selectedDirectory)
                .appendingPathComponent("output", isDirectory: true)
                .path
        }
        return defaults?.outdir ?? ""
    }

    func reload(selectJob jobID: String? = nil) {
        do {
            let snapshot = try cli.exportState()
            defaults = snapshot.defaults
            history = snapshot.history

            if draft == nil {
                draft = TranscribeDraft(defaults: snapshot.defaults)
            } else if var draft, draft.outputDirectory.isEmpty {
                draft.outputDirectory = snapshot.defaults.outdir
                self.draft = draft
            }

            let allIDs = Set(history.map(\.id))
            if let jobID, allIDs.contains(jobID) {
                selectedJobID = jobID
            } else if let selectedJobID, allIDs.contains(selectedJobID) {
                self.selectedJobID = selectedJobID
            } else {
                selectedJobID = history.first?.id
            }

            loadPreview()
            statusMessage = "Loaded \(history.count) transcription job(s)."
        } catch {
            statusMessage = "Reload failed: \(error.localizedDescription)"
        }
    }

    func setSection(_ newSection: TranscribeSection) {
        section = newSection
    }

    func selectJob(id: String?) {
        selectedJobID = id
        loadPreview()
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        if panel.runModal() == .OK {
            guard var draft else { return }
            draft.selectedFiles = panel.urls.map(\.path)
            draft.selectedDirectory = ""
            draft.outputDirectory = suggestedOutputDirectory(for: draft)
            self.draft = draft
            statusMessage = "Selected \(draft.selectedFiles.count) file(s)."
        }
    }

    func chooseInputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            guard var draft else { return }
            draft.selectedDirectory = url.path
            draft.selectedFiles = []
            draft.outputDirectory = suggestedOutputDirectory(for: draft)
            self.draft = draft
            statusMessage = "Selected input directory."
        }
    }

    func clearInputSelection() {
        guard var draft else { return }
        draft.selectedFiles = []
        draft.selectedDirectory = ""
        draft.outputDirectory = defaults?.outdir ?? ""
        self.draft = draft
        statusMessage = "Cleared selected input."
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            guard var draft else { return }
            draft.outputDirectory = url.path
            self.draft = draft
            statusMessage = "Updated output directory."
        }
    }

    func resetOutputDirectory() {
        guard var draft else { return }
        draft.outputDirectory = suggestedOutputDirectory(for: draft)
        self.draft = draft
        statusMessage = "Reset output directory to default."
    }

    func startTranscription() {
        guard let draft else {
            statusMessage = "Load defaults first."
            return
        }
        let inputPaths = draft.inputPaths
        if inputPaths.isEmpty {
            statusMessage = "Choose one or more files, or one directory."
            return
        }

        isRunning = true
        statusMessage = "Running transcription..."

        let request = draft
        let cli = self.cli
        Task {
            do {
                let job = try await Task.detached(priority: .userInitiated) {
                    try cli.transcribe(
                        inputPaths: request.inputPaths,
                        outdir: request.outputDirectory,
                        model: request.model,
                        computeType: request.computeType
                    )
                }.value
                isRunning = false
                reload(selectJob: job.id)
                statusMessage = "Finished \(job.outputs.count) file(s)."
            } catch {
                isRunning = false
                reload()
                statusMessage = "Transcription failed: \(error.localizedDescription)"
            }
        }
    }

    private func loadPreview() {
        guard let path = focusedJob?.primaryTranscriptPath else {
            previewText = ""
            return
        }
        let url = URL(fileURLWithPath: path)
        previewText = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private final class TranscribeCLI {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var cliScriptURL: URL {
        repoRoot.appendingPathComponent("tools/transcribe_audio/transcribe_cli.py")
    }

    private var pythonURL: URL {
        let candidates = [
            repoRoot.appendingPathComponent(".tools/transcribe_audio/.venv/bin/python"),
            URL(fileURLWithPath: "/opt/homebrew/bin/python3.11"),
            URL(fileURLWithPath: "/opt/homebrew/bin/python3"),
            URL(fileURLWithPath: "/usr/local/bin/python3"),
            URL(fileURLWithPath: "/usr/bin/python3"),
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        return URL(fileURLWithPath: "/usr/bin/env")
    }

    func exportState() throws -> TranscribeSnapshot {
        let response: StateResponse = try runJSON(arguments: ["export_state"])
        guard response.ok, let defaults = response.defaults, let history = response.history, let count = response.count else {
            throw CLIError.message(response.error ?? "Failed to load transcribe state.")
        }
        return TranscribeSnapshot(defaults: defaults, history: history, count: count)
    }

    func transcribe(inputPaths: [String], outdir: String, model: String, computeType: String) throws -> TranscribeJob {
        var args = ["transcribe"]
        for input in inputPaths {
            args.append(contentsOf: ["--input", input])
        }
        args.append(contentsOf: ["--outdir", outdir, "--model", model, "--compute-type", computeType])
        let response: JobResponse = try runJSON(arguments: args)
        guard response.ok, let job = response.job else {
            throw CLIError.message(response.error ?? "Transcription failed.")
        }
        return job
    }

    private func runJSON<Response: Decodable>(arguments: [String]) throws -> Response {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let resolvedPythonURL = pythonURL
        process.currentDirectoryURL = repoRoot
        process.executableURL = resolvedPythonURL
        if resolvedPythonURL.path == "/usr/bin/env" {
            process.arguments = ["python3", cliScriptURL.path] + arguments
        } else {
            process.arguments = [cliScriptURL.path] + arguments
        }
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: stdoutData), let error = envelope.error {
                throw CLIError.message(error)
            }
            let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stderrText.isEmpty {
                throw CLIError.message(stderrText)
            }
            throw CLIError.message("CLI exited with status \(process.terminationStatus).")
        }

        do {
            return try decoder.decode(Response.self, from: stdoutData)
        } catch {
            let raw = String(data: stdoutData, encoding: .utf8) ?? ""
            throw CLIError.message("Invalid CLI response: \(raw)")
        }
    }
}

private struct StateResponse: Decodable {
    let ok: Bool
    let defaults: TranscribeDefaults?
    let history: [TranscribeJob]?
    let count: Int?
    let error: String?
}

private struct JobResponse: Decodable {
    let ok: Bool
    let job: TranscribeJob?
    let error: String?
}

private struct ErrorEnvelope: Decodable {
    let ok: Bool?
    let error: String?
}

private enum CLIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}
