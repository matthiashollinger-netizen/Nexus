import Foundation

/// Runs a macOS system network binary (ping/traceroute/dig/nc) and streams its
/// output live. Self-contained — every tool ships with macOS; nothing installed.
@Observable
final class NetworkToolRunner {
    private(set) var output: String = ""
    private(set) var isRunning = false

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var pipe: Pipe?
    /// Holds a trailing partial UTF-8 sequence between reads (8-bit, 0-based array
    /// so indexing stays safe across removeFirst, unlike Data).
    @ObservationIgnored private var buffer: [UInt8] = []
    /// Bumped on every run/stop so a previous process's async handlers become no-ops.
    @ObservationIgnored private var generation = 0

    func run(executable: String, args: [String]) {
        stop()
        guard FileManager.default.fileExists(atPath: executable) else {
            output = "\(executable) not found"
            return
        }
        generation += 1
        let gen = generation
        output = ""
        buffer.removeAll()
        isRunning = true

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = outPipe
        self.pipe = outPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            DispatchQueue.main.async { if self.generation == gen { self.appendChunk(data) } }
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                self.pipe?.fileHandleForReading.readabilityHandler = nil
                if !self.buffer.isEmpty {
                    self.output += String(decoding: self.buffer, as: UTF8.self)
                    self.buffer.removeAll()
                }
                self.isRunning = false
            }
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
        // Invalidate any in-flight handlers, detach the reader, and tear down.
        generation += 1
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        pipe = nil
        buffer.removeAll()
        isRunning = false
    }

    /// Appends a chunk, holding back a trailing incomplete UTF-8 sequence so a
    /// multi-byte character split across two reads is never dropped.
    private func appendChunk(_ data: Data) {
        buffer.append(contentsOf: data)
        let keepBack = Self.incompleteTrailingByteCount(buffer)
        let decodeCount = buffer.count - keepBack
        guard decodeCount > 0 else { return }
        output += String(decoding: buffer[0..<decodeCount], as: UTF8.self)
        buffer.removeFirst(decodeCount)
    }

    /// How many bytes at the end of `bytes` form the START of an incomplete UTF-8
    /// sequence (0–3) — those are held for the next read.
    static func incompleteTrailingByteCount(_ bytes: [UInt8]) -> Int {
        var i = bytes.count - 1
        var continuation = 0
        while i >= 0 && (bytes[i] & 0xC0) == 0x80 && continuation < 3 {
            continuation += 1; i -= 1
        }
        guard i >= 0 else { return min(continuation, bytes.count) }
        let lead = bytes[i]
        let expected: Int
        if lead & 0x80 == 0 { expected = 1 }
        else if lead & 0xE0 == 0xC0 { expected = 2 }
        else if lead & 0xF0 == 0xE0 { expected = 3 }
        else if lead & 0xF8 == 0xF0 { expected = 4 }
        else { return 0 }   // invalid lead byte — let String(decoding:) substitute U+FFFD
        let have = continuation + 1
        return have < expected ? have : 0
    }
}
