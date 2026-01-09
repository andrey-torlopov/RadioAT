import Foundation
import Dispatch
import FMTransmitterCLib
import Glibc

public struct StreamConfiguration: Sendable {
    public var frequencyMHz: Double
    public var sampleRate: Int
    public var channels: Int
    public var bitsPerSample: Int
    public var ffmpegPath: String

    public init(
        frequencyMHz: Double,
        sampleRate: Int = 44_100,
        channels: Int = 1,
        bitsPerSample: Int = 16,
        ffmpegPath: String = "ffmpeg"
    ) {
        self.frequencyMHz = frequencyMHz
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.ffmpegPath = ffmpegPath
    }
}

public enum FMTransmitterError: Error, CustomStringConvertible {
    case emptyPlaylist
    case missingCLibrary
    case transmitterExit(code: Int32)
    case ffmpegFailed(code: Int32, message: String)
    case systemError(message: String)

    public var description: String {
        switch self {
        case .emptyPlaylist:
            return "Playlist is empty."
        case .missingCLibrary:
            return "fm_transmitter sources are missing. Run Scripts/bootstrap_fm_transmitter.sh to fetch them."
        case .transmitterExit(let code):
            return "fm_transmitter exited with code \(code)."
        case .ffmpegFailed(let code, let message):
            return "ffmpeg failed with code \(code): \(message)"
        case .systemError(let message):
            return "System error: \(message)"
        }
    }
}

public struct FMTransmitter {
    public init() {}

    public func transmitStream(playlist: [URL], configuration: StreamConfiguration) throws {
        guard fm_transmitter_is_available() == 1 else {
            throw FMTransmitterError.missingCLibrary
        }
        guard !playlist.isEmpty else {
            throw FMTransmitterError.emptyPlaylist
        }

        let (readFD, writeFD) = try makePipe()
        let originalStdin = try duplicateFD(STDIN_FILENO)
        defer {
            _ = dup2(originalStdin, STDIN_FILENO)
            close(originalStdin)
        }

        try replaceStdin(with: readFD)
        close(readFD)

        let args = [
            "fm_transmitter",
            "-f",
            String(format: "%.3f", configuration.frequencyMHz),
            "-"
        ]

        let group = DispatchGroup()
        let exitCodeLock = NSLock()
        var transmitterExitCode: Int32 = 0
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let code = args.withCStringArray { cArray in
                fm_transmitter_run(Int32(args.count), cArray)
            }
            exitCodeLock.lock()
            transmitterExitCode = code
            exitCodeLock.unlock()
            group.leave()
        }

        try writeWavHeader(to: writeFD, configuration: configuration)
        for item in playlist {
            try streamFile(item, to: writeFD, configuration: configuration)
        }

        close(writeFD)
        group.wait()

        exitCodeLock.lock()
        let finalExitCode = transmitterExitCode
        exitCodeLock.unlock()

        if finalExitCode != 0 {
            throw FMTransmitterError.transmitterExit(code: finalExitCode)
        }
    }
}

private func makePipe() throws -> (Int32, Int32) {
    var fds: [Int32] = [0, 0]
    if pipe(&fds) != 0 {
        throw FMTransmitterError.systemError(message: errnoMessage())
    }
    return (fds[0], fds[1])
}

private func duplicateFD(_ fd: Int32) throws -> Int32 {
    let duplicated = dup(fd)
    if duplicated == -1 {
        throw FMTransmitterError.systemError(message: errnoMessage())
    }
    return duplicated
}

private func replaceStdin(with readFD: Int32) throws {
    if dup2(readFD, STDIN_FILENO) == -1 {
        throw FMTransmitterError.systemError(message: errnoMessage())
    }
}

private func writeWavHeader(to fd: Int32, configuration: StreamConfiguration) throws {
    let header = WavHeader(
        sampleRate: configuration.sampleRate,
        channels: configuration.channels,
        bitsPerSample: configuration.bitsPerSample
    ).data
    try writeAll(fd: fd, data: header)
}

private func streamFile(_ url: URL, to fd: Int32, configuration: StreamConfiguration) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: configuration.ffmpegPath)
    process.arguments = [
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        url.path,
        "-f",
        "s16le",
        "-ac",
        "\(configuration.channels)",
        "-ar",
        "\(configuration.sampleRate)",
        "-acodec",
        "pcm_s16le",
        "pipe:1"
    ]

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    let outputHandle = stdoutPipe.fileHandleForReading
    while true {
        let data = try outputHandle.read(upToCount: 32_768) ?? Data()
        if data.isEmpty {
            break
        }
        try writeAll(fd: fd, data: data)
    }

    process.waitUntilExit()

    let status = process.terminationStatus
    if status != 0 {
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errorData, encoding: .utf8) ?? ""
        throw FMTransmitterError.ffmpegFailed(code: status, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private func writeAll(fd: Int32, data: Data) throws {
    try data.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else { return }
        var remaining = rawBuffer.count
        var offset = 0
        while remaining > 0 {
            let written = write(fd, base.advanced(by: offset), remaining)
            if written <= 0 {
                throw FMTransmitterError.systemError(message: errnoMessage())
            }
            remaining -= written
            offset += written
        }
    }
}

private func errnoMessage() -> String {
    String(cString: strerror(errno))
}

private struct WavHeader {
    let sampleRate: Int
    let channels: Int
    let bitsPerSample: Int

    var data: Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let unknownSize = UInt32.max

        var buffer = Data()
        buffer.append("RIFF".data(using: .ascii) ?? Data())
        buffer.append(unknownSize.littleEndianData)
        buffer.append("WAVE".data(using: .ascii) ?? Data())
        buffer.append("fmt ".data(using: .ascii) ?? Data())
        buffer.append(UInt32(16).littleEndianData)
        buffer.append(UInt16(1).littleEndianData)
        buffer.append(UInt16(channels).littleEndianData)
        buffer.append(UInt32(sampleRate).littleEndianData)
        buffer.append(UInt32(byteRate).littleEndianData)
        buffer.append(UInt16(blockAlign).littleEndianData)
        buffer.append(UInt16(bitsPerSample).littleEndianData)
        buffer.append("data".data(using: .ascii) ?? Data())
        buffer.append(unknownSize.littleEndianData)
        return buffer
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}

private extension Array where Element == String {
    func withCStringArray<R>(_ body: ([UnsafePointer<CChar>?]) -> R) -> R {
        let cStrings = self.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        let cArray: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) } + [nil]
        return body(cArray)
    }
}
