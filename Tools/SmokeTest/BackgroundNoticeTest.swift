//
//  BackgroundNoticeTest.swift
//  PiCode (smoke test)
//
//  Parses the pi-background-tasks extension's terminal notice end to end: the
//  message shape `get_messages` returns, the snapshot and body fallbacks, the
//  transcript row it becomes, and the `entry_appended` event that announces it.
//
//  The first fixture is a verbatim copy of a notification Pi delivered on this
//  machine (task `b4a6f436b`, "verify.sh gate"), so the parse is checked against
//  the extension's real output rather than against a shape someone remembered.
//  No session file is read: everything runs from the literals below.
//
//      ./Tools/SmokeTest/run-notice.sh
//

import Foundation

@main
enum BackgroundNoticeTest {
    static func main() {
        var failures = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("  ok   \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            } else {
                failures += 1
                print("  FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            }
        }
        func message(_ json: String) -> PiMessage {
            PiMessage(raw: (try? JSONCoding.decode(Data(json.utf8))) ?? .null)
        }

        // A notification as `get_messages` hands it over: role, body, and the
        // runner's `details` snapshot, copied from a real session.
        let notice = #"""
        {"role":"custom","customType":"background-task-notification","display":true,"timestamp":1790533505628,"content":"<background-task-notification>\n  <task-id>b4a6f436b</task-id>\n  <task-name>verify.sh gate</task-name>\n  <status>completed</status>\n\n  <exit-code>0</exit-code>\n  <output-file>.pi/tasks/01a0e40a-46b7-7428-b56e-ecc9fcff1b68-91553/b4a6f436b.output</output-file>\n  <summary>Background task \"verify.sh gate\" completed</summary>\n  <guidance>Terminal state and output metadata are durable. Do not call bg_status to reconfirm; use bg_logs only if output is needed.</guidance>\n</background-task-notification>","details":{"id":"b4a6f436b","name":"verify.sh gate","command":"cd /Users/pyw0w/project/Pie && ./Tools/CI/verify.sh 2>&1 | tail -60","status":"completed","outputPath":".pi/tasks/01a0e40a-46b7-7428-b56e-ecc9fcff1b68-91553/b4a6f436b.output","cwd":"/Users/pyw0w/project/Pie","startTime":1790533504127,"endTime":1790533511149,"exitCode":0,"signal":null,"pid":1881,"bytesWritten":4394,"isAgent":false,"notified":true,"notifyOnCompletion":true,"triggerOnCompletion":true,"timeoutSeconds":1200}}
        """#

        print("== snapshot ==")
        let delivered = message(notice)
        check("the message carries the extension's custom type",
              delivered.customType == BackgroundTaskNotification.customType)
        let task = BackgroundTaskNotification.parse(message: delivered)
        check("the notice parses", task != nil)
        guard let task else {
            print("\nRESULT: 1 check(s) failed")
            exit(1)
        }
        check("the task id is the runner's", task.id == "b4a6f436b", task.id)
        check("the task name is the launch name", task.name == "verify.sh gate", task.name)
        check("the status is kept as Pi sent it", task.status == "completed", task.status)
        check("the exit code was read", task.exitCode == 0, "\(task.exitCode ?? -1)")
        check("a zero exit reads as success", task.outcome == .success)
        check("the output path was read",
              task.outputPath == ".pi/tasks/01a0e40a-46b7-7428-b56e-ecc9fcff1b68-91553/b4a6f436b.output")
        check("the task's cwd was read", task.cwd == "/Users/pyw0w/project/Pie")
        check("the command was read", task.command?.contains("verify.sh") ?? false)
        check("the task is not an agent", task.isAgent == false)
        check("the duration comes from both timestamps",
              abs((task.duration ?? 0) - 7.022) < 0.001, "\(task.duration ?? -1)s")
        check("the facts line names the exit code", task.factsLine.contains("exit 0"), task.factsLine)
        check("the facts line names the runtime", task.factsLine.contains("7.0"), task.factsLine)
        check("the copy line names the task", task.oneLine.contains("verify.sh gate"), task.oneLine)
        check("the copy line names the output", task.oneLine.contains("b4a6f436b.output"))

        print("== transcript row ==")
        let items = TranscriptBuilder.items(messages: [delivered])
        check("the notice becomes exactly one row", items.count == 1, "\(items.count) row(s)")
        check("the row is a background-task row", items.first?.kind == .backgroundTask,
              items.first.map { String(describing: $0.kind) } ?? "none")
        check("the row's id is unique and names the task",
              items.first?.id == "bg-0-b4a6f436b", items.first?.id ?? "none")
        check("the row carries the parsed task", items.first?.backgroundTask?.id == "b4a6f436b")
        check("the row's copy text is the notice, not the markup",
              !(items.first?.text.contains("<task-id>") ?? true) && (items.first?.text.contains("completed") ?? false),
              items.first?.text ?? "none")

        // A hidden notice (`display: false`) is not a transcript row — the
        // extension posts state updates this way too.
        let hidden = notice.replacingOccurrences(of: #""display":true"#, with: #""display":false"#)
        check("a hidden notice draws nothing",
              TranscriptBuilder.items(messages: [message(hidden)]).isEmpty)

        print("== body fallback ==")
        // The same notice without `details`: only the body is left to parse.
        let bodyOnly = #"""
        {"role":"custom","customType":"background-task-notification","display":true,"timestamp":1790533505628,"content":"<background-task-notification>\n  <task-id>c0ffee123</task-id>\n  <task-name>nightly build</task-name>\n  <status>failed</status>\n  <exit-code>2</exit-code>\n  <error>command exited 2</error>\n  <output-file>logs/build.log</output-file>\n</background-task-notification>"}
        """#
        let fallback = BackgroundTaskNotification.parse(message: message(bodyOnly))
        check("a notice without a snapshot still parses", fallback != nil)
        check("the id comes from the body", fallback?.id == "c0ffee123", fallback?.id ?? "none")
        check("the status comes from the body", fallback?.status == "failed", fallback?.status ?? "none")
        check("the exit code comes from the body", fallback?.exitCode == 2, "\(fallback?.exitCode ?? -1)")
        check("the error comes from the body", fallback?.error == "command exited 2", fallback?.error ?? "none")
        check("the output path comes from the body", fallback?.outputPath == "logs/build.log")
        check("a failing notice reads as a failure", fallback?.outcome == .failure)
        check("the failure is drawn as a background-task row",
              TranscriptBuilder.items(messages: [message(bodyOnly)]).first?.kind == .backgroundTask)

        // Nothing to parse: an unrelated extension message keeps its generic row.
        let unrelated = #"""
        {"role":"custom","customType":"web-search-results","display":true,"content":"3 results","timestamp":1790533505628}
        """#
        let generic = TranscriptBuilder.items(messages: [message(unrelated)])
        check("another extension's message keeps the generic row",
              generic.count == 1 && generic.first?.kind == .system, "\(generic.count) row(s)")
        check("the generic row still carries its badge", generic.first?.badge == "web-search-results")

        print("== outcome ==")
        func outcome(_ status: String, _ exitCode: Int? = nil) -> BackgroundTaskNotification.Outcome {
            BackgroundTaskNotification(
                id: "t", name: "t", status: status, exitCode: exitCode, signal: nil, error: nil,
                outputPath: nil, command: nil, cwd: nil, startedAt: nil, endedAt: nil,
                bytesWritten: nil, isAgent: false, summary: nil
            ).outcome
        }
        check("completed with no exit code is a success", outcome("completed") == .success)
        check("completed with a failing exit code is a failure", outcome("completed", 1) == .failure)
        check("failed is a failure", outcome("failed") == .failure)
        check("killed is a cancellation", outcome("killed") == .cancelled)
        check("running is not terminal", outcome("running") == .working)
        check("a status PiCode has never seen is not guessed", outcome("exploded") == .unknown)
        check("the unknown status still prints as Pi named it",
              BackgroundTaskNotification(
                id: "t", name: "t", status: "exploded", exitCode: nil, signal: nil, error: nil,
                outputPath: nil, command: nil, cwd: nil, startedAt: nil, endedAt: nil,
                bytesWritten: nil, isAgent: false, summary: nil
              ).oneLine.contains("exploded"))

        print("== entry_appended event ==")
        let eventJSON = #"""
        {"type":"entry_appended","entry":{"type":"custom_message","customType":"background-task-notification","display":true,"content":"<background-task-notification>\n  <task-id>b4a6f436b</task-id>\n</background-task-notification>","details":{"id":"b4a6f436b","status":"completed"}}}
        """#
        let event = PiEvent(json: (try? JSONCoding.decode(Data(eventJSON.utf8))) ?? .null)
        check("the event decodes to its typed case", event.typeName == "entry_appended", event.typeName)
        if case .entryAppended(let entry) = event {
            // The same two fields the controller tests before refreshing.
            check("the appended entry is a custom message", entry.string("type") == "custom_message")
            check("it is this extension's notice",
                  entry.string("customType") == BackgroundTaskNotification.customType)
            check("its payload parses",
                  BackgroundTaskNotification.from(details: entry["details"])?.id == "b4a6f436b")
        } else {
            check("the appended entry is a custom message", false, "case was \(event.typeName)")
            check("it is this extension's notice", false)
            check("its payload parses", false)
        }
        let other = PiEvent(json: .object(["type": .string("agent_start")]))
        check("other events keep their own case", other.typeName == "agent_start", other.typeName)

        print(failures == 0 ? "\nRESULT: all checks passed" : "\nRESULT: \(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
