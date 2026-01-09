import Foundation
import FMTransmitter

struct CLI {
    var frequencyMHz: Double
    var ffmpegPath: String
    var files: [URL]

    init(arguments: [String]) throws {
        var args = arguments
        _ = args.removeFirst()

        var frequency: Double?
        var ffmpeg = "ffmpeg"
        var paths: [String] = []

        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--freq", "-f":
                guard let value = iterator.next(), let freq = Double(value) else {
                    throw CLIError.invalidArguments
                }
                frequency = freq
            case "--ffmpeg":
                guard let value = iterator.next() else {
                    throw CLIError.invalidArguments
                }
                ffmpeg = value
            case "--help", "-h":
                throw CLIError.showHelp
            default:
                paths.append(arg)
            }
        }

        guard let finalFrequency = frequency else {
            throw CLIError.invalidArguments
        }

        if paths.isEmpty {
            throw CLIError.invalidArguments
        }

        self.frequencyMHz = finalFrequency
        self.ffmpegPath = ffmpeg
        self.files = paths.map { URL(fileURLWithPath: $0) }
    }

    static func printUsage() {
        print("""
        Usage: fm-radio --freq <MHz> [--ffmpeg <path>] <file1> <file2> ...

        Streams a playlist to fm_transmitter via stdin. Each file (mp3/wav/etc) is
        decoded with ffmpeg to 44.1kHz mono PCM and sent as a continuous stream.
        """)
    }
}

enum CLIError: Error {
    case invalidArguments
    case showHelp
}

let cli: CLI

do {
    cli = try CLI(arguments: CommandLine.arguments)
} catch CLIError.showHelp {
    CLI.printUsage()
    exit(0)
} catch {
    CLI.printUsage()
    exit(1)
}

let config = StreamConfiguration(
    frequencyMHz: cli.frequencyMHz,
    ffmpegPath: cli.ffmpegPath
)

let transmitter = FMTransmitter()

do {
    try transmitter.transmitStream(playlist: cli.files, configuration: config)
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
