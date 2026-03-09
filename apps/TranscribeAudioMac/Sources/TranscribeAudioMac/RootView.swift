import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: TranscribeStore

    var body: some View {
        NavigationSplitView {
            List(TranscribeSection.allCases, selection: $store.section) { section in
                Label(section.rawValue, systemImage: icon(for: section))
                    .tag(section)
            }
            .navigationTitle("Transcribe Audio")
            .listStyle(.sidebar)
            .onChange(of: store.section) { _, newValue in
                store.setSection(newValue)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 220)
        } detail: {
            switch store.section {
            case .transcribe:
                transcribeWorkspace
            case .history:
                historyWorkspace
            }
        }
        .navigationSplitViewStyle(.balanced)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(store.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func icon(for section: TranscribeSection) -> String {
        switch section {
        case .transcribe:
            return "waveform.badge.mic"
        case .history:
            return "clock.arrow.circlepath"
        }
    }

    private var transcribeWorkspace: some View {
        HSplitView {
            TranscribeDraftView()
                .frame(minWidth: 360, idealWidth: 420, maxWidth: 520, maxHeight: .infinity)
            JobDetailView(job: store.focusedJob, previewText: store.previewText, emptyDescription: "Select local audio/video input, then run a transcription job.")
                .frame(minWidth: 420, idealWidth: 760, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var historyWorkspace: some View {
        HSplitView {
            HistoryListView()
                .frame(minWidth: 340, idealWidth: 420, maxWidth: 520, maxHeight: .infinity)
            JobDetailView(job: store.selectedJob, previewText: store.previewText, emptyDescription: "Select a previous job to inspect its transcript and output files.")
                .frame(minWidth: 460, idealWidth: 780, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TranscribeDraftView: View {
    @EnvironmentObject private var store: TranscribeStore

    private let computeTypes = ["int8", "int8_float16", "float16"]
    private let models = ["small", "medium"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                inputCard
                settingsCard
                runCard
                recentJobsCard
            }
            .padding(18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("新转写任务")
                .font(.title2.weight(.semibold))
            Text("Python backend handles transcription. This app only manages inputs, state, and results.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var inputCard: some View {
        GroupBox("输入") {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.draft?.inputLabel ?? "No input selected")
                    .font(.headline)

                if let draft = store.draft {
                    if !draft.selectedFiles.isEmpty {
                        pathList(title: "Selected Files", items: draft.selectedFiles)
                    } else if !draft.selectedDirectory.isEmpty {
                        pathList(title: "Selected Directory", items: [draft.selectedDirectory])
                    }
                }

                HStack {
                    Button("Select Files") { store.chooseFiles() }
                    Button("Select Directory") { store.chooseInputDirectory() }
                    Button("Clear") { store.clearInputSelection() }
                        .disabled((store.draft?.inputPaths.isEmpty ?? true))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settingsCard: some View {
        GroupBox("设置") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Output Directory")
                            .font(.subheadline.weight(.medium))
                        Text(store.draft?.outputDirectory ?? store.defaults?.outdir ?? "")
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    Spacer()
                }

                HStack {
                    Button("Choose Output") { store.chooseOutputDirectory() }
                    Button("Reset Default") { store.resetOutputDirectory() }
                        .disabled(store.defaults == nil)
                }

                Picker("Model", selection: draftModelBinding) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Picker("Compute Type", selection: draftComputeTypeBinding) {
                    ForEach(computeTypes, id: \.self) { computeType in
                        Text(computeType).tag(computeType)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var runCard: some View {
        GroupBox("执行") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Runs one job at a time and persists the result to local history.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    store.startTranscription()
                } label: {
                    Label(store.isRunning ? "Running..." : "Start Transcription", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canStart)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recentJobsCard: some View {
        GroupBox("最近任务") {
            if store.history.isEmpty {
                ContentUnavailableView(
                    "No Jobs Yet",
                    systemImage: "tray",
                    description: Text("Completed transcriptions appear here.")
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(store.history.prefix(3)), id: \.id) { job in
                        Button {
                            store.selectJob(id: job.id)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(job.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(status: job.status)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func pathList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var draftModelBinding: Binding<String> {
        Binding(
            get: { store.draft?.model ?? store.defaults?.model ?? "small" },
            set: { value in
                guard var draft = store.draft else { return }
                draft.model = value
                store.draft = draft
            }
        )
    }

    private var draftComputeTypeBinding: Binding<String> {
        Binding(
            get: { store.draft?.computeType ?? store.defaults?.computeType ?? "int8" },
            set: { value in
                guard var draft = store.draft else { return }
                draft.computeType = value
                store.draft = draft
            }
        )
    }
}

private struct HistoryListView: View {
    @EnvironmentObject private var store: TranscribeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("历史任务")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Reload") {
                    store.reload(selectJob: store.selectedJobID)
                }
            }

            if store.history.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Run a transcription job first.")
                )
            } else {
                List(store.history, selection: $store.selectedJobID) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(job.title)
                                .font(.headline)
                            Spacer()
                            StatusBadge(status: job.status)
                        }
                        Text(job.createdAt)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(job.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(job.id)
                }
                .onChange(of: store.selectedJobID) { _, newValue in
                    store.selectJob(id: newValue)
                }
            }
        }
        .padding(18)
    }
}

private struct JobDetailView: View {
    let job: TranscribeJob?
    let previewText: String
    let emptyDescription: String

    var body: some View {
        Group {
            if let job {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        overview(job: job)
                        pathCard(title: "Input Paths", items: job.inputPaths)
                        outputsCard(job: job)
                        transcriptCard
                    }
                    .padding(18)
                }
            } else {
                ContentUnavailableView(
                    "No Job Selected",
                    systemImage: "waveform.badge.mic",
                    description: Text(emptyDescription)
                )
            }
        }
    }

    private func overview(job: TranscribeJob) -> some View {
        GroupBox("概览") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title)
                            .font(.title3.weight(.semibold))
                        Text(job.createdAt)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(status: job.status)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 10) {
                    MetaField(label: "Kind", value: job.kind)
                    MetaField(label: "Model", value: job.model)
                    MetaField(label: "Compute", value: job.computeType)
                    MetaField(label: "Outputs", value: "\(job.outputs.count)")
                    MetaField(label: "Language", value: job.languageSummary)
                    MetaField(label: "Output Dir", value: job.outdir)
                }

                if let error = job.error, !error.isEmpty {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pathCard(title: String, items: [String]) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func outputsCard(job: TranscribeJob) -> some View {
        GroupBox("Outputs") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(job.outputs, id: \.self) { output in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(output.inputFile)
                            .font(.subheadline.weight(.medium))
                            .textSelection(.enabled)
                        OutputPathRow(label: "Transcript", path: output.txt)
                        OutputPathRow(label: "Segments", path: output.segmentsJSON)
                        OutputPathRow(label: "Meta", path: output.metaJSON)
                    }
                    if output != job.outputs.last {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transcriptCard: some View {
        GroupBox("Transcript Preview") {
            if previewText.isEmpty {
                Text("Transcript text is empty for this job.")
                    .foregroundStyle(.secondary)
            } else {
                Text(previewText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct MetaField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }
}

private struct OutputPathRow: View {
    let label: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

private struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case "success":
            return "Success"
        case "error":
            return "Error"
        case "running":
            return "Running"
        default:
            return status.capitalized
        }
    }

    private var color: Color {
        switch status {
        case "success":
            return .green
        case "error":
            return .red
        case "running":
            return .orange
        default:
            return .secondary
        }
    }
}
