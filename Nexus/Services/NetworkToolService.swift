import Foundation

/// Runs a macOS system network binary (ping/traceroute/dig/nc) and streams its
/// output live. Self-contained — every tool ships with macOS; nothing installed.
@Observable
final class NetworkToolRunner {
    private(set) var output: String = ""
    private(set) var isRunning = false

    @ObservationIgnored private var process: Process?

    func run(executable: String, args: [String]) {
        stop()
        guard FileManager.default.fileExists(atPath: executable) else {
            output = "\(executable) not found"
            return
        }
        output = ""
        isRunning = true

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.output += chunk }
        }
        proc.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.isRunning = false }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            output = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
    }
}
