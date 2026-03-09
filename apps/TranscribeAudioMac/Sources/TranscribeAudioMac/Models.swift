import Foundation

enum TranscribeSection: String, CaseIterable, Identifiable {
    case transcribe = "转写"
    case history = "历史"

    var id: String { rawValue }
}

struct TranscribeSnapshot: Decodable {
    let defaults: TranscribeDefaults
    let history: [TranscribeJob]
    let count: Int
}

struct TranscribeDefaults: Decodable {
    let outdir: String
    let model: String
    let computeType: String
    let device: String
    let beamSize: Int
    let vadFilter: Bool

    enum CodingKeys: String, CodingKey {
        case outdir
        case model
        case computeType = "compute_type"
        case device
        case beamSize = "beam_size"
        case vadFilter = "vad_filter"
    }
}

struct TranscribeOutput: Decodable, Hashable {
    let inputFile: String
    let txt: String
    let segmentsJSON: String
    let metaJSON: String
    let language: String?

    enum CodingKeys: String, CodingKey {
        case inputFile = "input_file"
        case txt
        case segmentsJSON = "segments_json"
        case metaJSON = "meta_json"
        case language
    }
}

struct TranscribeJob: Identifiable, Decodable, Hashable {
    let id: String
    let kind: String
    let inputPaths: [String]
    let inputFiles: [String]
    let outdir: String
    let model: String
    let computeType: String
    let device: String
    let beamSize: Int
    let vadFilter: Bool
    let createdAt: String
    let finishedAt: String?
    let status: String
    let outputs: [TranscribeOutput]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case inputPaths = "input_paths"
        case inputFiles = "input_files"
        case outdir
        case model
        case computeType = "compute_type"
        case device
        case beamSize = "beam_size"
        case vadFilter = "vad_filter"
        case createdAt = "created_at"
        case finishedAt = "finished_at"
        case status
        case outputs
        case error
    }

    var title: String {
        if let first = inputPaths.first {
            return URL(fileURLWithPath: first).lastPathComponent
        }
        return id
    }

    var subtitle: String {
        "\(outputs.count) output(s) · \(model) · \(computeType)"
    }

    var statusLabel: String {
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

    var primaryTranscriptPath: String? {
        outputs.first?.txt
    }

    var languageSummary: String {
        let langs = Set(outputs.compactMap(\.language)).sorted()
        return langs.isEmpty ? "Unknown" : langs.joined(separator: ", ")
    }
}

struct JobEnvelope: Decodable {
    let ok: Bool
    let job: TranscribeJob?
    let error: String?
}

struct TranscribeDraft {
    var selectedFiles: [String]
    var selectedDirectory: String
    var outputDirectory: String
    var model: String
    var computeType: String

    init(defaults: TranscribeDefaults) {
        selectedFiles = []
        selectedDirectory = ""
        outputDirectory = defaults.outdir
        model = defaults.model
        computeType = defaults.computeType
    }

    var inputPaths: [String] {
        if !selectedFiles.isEmpty {
            return selectedFiles
        }
        if !selectedDirectory.isEmpty {
            return [selectedDirectory]
        }
        return []
    }

    var inputLabel: String {
        if !selectedFiles.isEmpty {
            return "\(selectedFiles.count) file(s)"
        }
        if !selectedDirectory.isEmpty {
            return URL(fileURLWithPath: selectedDirectory).lastPathComponent
        }
        return "No input selected"
    }
}
