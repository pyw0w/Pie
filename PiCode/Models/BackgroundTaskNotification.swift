//
//  BackgroundTaskNotification.swift
//  PiCode
//
//  A `background-task-notification` custom message: the terminal notice the
//  pi-background-tasks extension posts when one of `bg_run`'s tasks ends.
//
//  Pi carries it twice — as a body (`content`, XML-ish tags written for someone
//  reading the stream) and as the task snapshot (`details`, the runner's own
//  record: times, exit code, output path). The snapshot is what a transcript row
//  needs, so it wins; the body is parsed when the snapshot is absent, because
//  the alternative is showing the user the extension's markup instead of the
//  task it is describing.
//

import Foundation

struct BackgroundTaskNotification: Equatable {
    /// The `customType` this notice arrives under.
    static let customType = "background-task-notification"

    /// How a task ended, as Pi reported it. A `completed` status with a non-zero
    /// exit code is a failure whatever the status string says, so the row takes
    /// its colour from the outcome rather than from the word.
    enum Outcome: Equatable {
        case success
        case failure
        case cancelled
        case working
        case unknown
    }

    /// The runner's task id — the short id `bg_status` / `bg_logs` accept.
    var id: String
    /// The name the task was launched with (`"verify.sh gate"`).
    var name: String
    /// The status exactly as Pi sent it (`completed`, `failed`, `killed`, …).
    /// A status PiCode has never seen still renders under the name Pi gave it
    /// rather than under a guess.
    var status: String
    var exitCode: Int?
    var signal: String?
    var error: String?
    /// Where the task's output was written, relative to the task's `cwd`.
    var outputPath: String?
    var command: String?
    var cwd: String?
    var startedAt: Date?
    var endedAt: Date?
    var bytesWritten: Int?
    var isAgent: Bool
    /// Pi's own one-line wording (`Background task "x" completed`), carried for
    /// the labels that have nothing better to fall back on.
    var summary: String?

    init(
        id: String,
        name: String,
        status: String,
        exitCode: Int?,
        signal: String?,
        error: String?,
        outputPath: String?,
        command: String?,
        cwd: String?,
        startedAt: Date?,
        endedAt: Date?,
        bytesWritten: Int?,
        isAgent: Bool,
        summary: String?
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.exitCode = exitCode
        self.signal = signal
        self.error = error
        self.outputPath = outputPath
        self.command = command
        self.cwd = cwd
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.bytesWritten = bytesWritten
        self.isAgent = isAgent
        self.summary = summary
    }

    // MARK: Parsing

    /// The notice as Pi delivered it: snapshot first, body as the fallback.
    static func parse(message: PiMessage) -> BackgroundTaskNotification? {
        from(details: message.details) ?? from(content: message.text)
    }

    /// From the runner's `details` snapshot. Without an id there is no task to
    /// name, so an id-less snapshot is not a snapshot — the body is tried next.
    static func from(details json: JSONValue?) -> BackgroundTaskNotification? {
        guard let id = json?.string("id"), !id.isEmpty else { return nil }
        let name = (json?.string("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let status = (json?.string("status") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return BackgroundTaskNotification(
            id: id,
            name: name.isEmpty ? id : name,
            status: status.isEmpty ? "unknown" : status.lowercased(),
            exitCode: json?.int("exitCode"),
            signal: json?.string("signal"),
            error: json?.string("error"),
            outputPath: json?.string("outputPath"),
            command: json?.string("command"),
            cwd: json?.string("cwd"),
            startedAt: json?.double("startTime").map { Date(timeIntervalSince1970: $0 / 1000) },
            endedAt: json?.double("endTime").map { Date(timeIntervalSince1970: $0 / 1000) },
            bytesWritten: json?.int("bytesWritten"),
            isAgent: json?.bool("isAgent") ?? false,
            summary: json?.string("summary")
        )
    }

    /// From the notification's body, for the day the snapshot shape changes.
    static func from(content text: String) -> BackgroundTaskNotification? {
        guard text.contains("<\(customType)>"), let id = tag("task-id", in: text), !id.isEmpty else { return nil }
        let name = tag("task-name", in: text) ?? tag("summary", in: text) ?? id
        let status = tag("status", in: text) ?? "unknown"
        return BackgroundTaskNotification(
            id: id,
            name: name,
            status: status.lowercased(),
            exitCode: tag("exit-code", in: text).flatMap(Int.init),
            signal: tag("signal", in: text),
            error: tag("error", in: text),
            outputPath: tag("output-file", in: text),
            command: nil,
            cwd: nil,
            startedAt: nil,
            endedAt: nil,
            bytesWritten: nil,
            isAgent: false,
            summary: tag("summary", in: text)
        )
    }

    /// The text between `<name>` and `</name>`, or nil when the tag is absent or
    /// empty. The body is a small fixed shape, so a range search is enough — and
    /// it cannot pair an opening tag with the wrong closing one the way a
    /// pattern over the whole document would.
    private static func tag(_ name: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(name)>"),
              let close = text.range(of: "</\(name)>"),
              open.upperBound <= close.lowerBound else { return nil }
        let value = text[open.upperBound..<close.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: Derived

    var outcome: Outcome {
        switch status {
        case "completed": return (exitCode ?? 0) == 0 ? .success : .failure
        case "failed", "failure": return .failure
        case "killed", "cancelled", "canceled": return .cancelled
        case "running", "queued", "pending", "starting", "waiting": return .working
        default: return .unknown
        }
    }

    /// How long the task ran, when the snapshot carries both ends.
    var duration: TimeInterval? {
        guard let startedAt, let endedAt else { return nil }
        let seconds = endedAt.timeIntervalSince(startedAt)
        return seconds >= 0 ? seconds : nil
    }

    /// The facts line under the row's title: everything that describes the run
    /// without repeating the status the pill is already showing.
    var factsLine: String {
        var parts: [String] = []
        if let exitCode { parts.append("exit \(exitCode)") }
        if let signal { parts.append("signal \(signal)") }
        if let duration { parts.append(Format.duration(duration)) }
        if let bytesWritten, bytesWritten > 0 { parts.append(Format.byteSize(bytesWritten)) }
        if isAgent { parts.append("agent task") }
        return parts.joined(separator: " · ")
    }

    /// The row's copy/export text: one line that says which task ended, how, and
    /// where its output is — with none of the notification's markup.
    var oneLine: String {
        var line = displayName == id
            ? "Background task #\(id) — \(status)"
            : "Background task \"\(displayName)\" (#\(id)) — \(status)"
        let facts = factsLine
        if !facts.isEmpty { line += " (\(facts))" }
        if let error, !error.isEmpty {
            line += " — \(error)"
        } else if let outputPath, !outputPath.isEmpty {
            line += " — output: \(outputPath)"
        }
        return line
    }

    /// The name to draw, falling back to the id when Pi sent none.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }
}
