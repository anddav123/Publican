import Foundation

struct BrewCommandResult: Sendable {
    let command: String
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
    let output: String
}

enum BrewCommandError: LocalizedError {
    case executableNotFound
    case failedToDecodeOutput

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Homebrew was not found at /opt/homebrew/bin/brew or /usr/local/bin/brew."
        case .failedToDecodeOutput:
            return "The command output could not be decoded as UTF-8."
        }
    }
}

struct BrewCommandRunner {
    let brewPath: String

    static func detect() -> BrewCommandRunner? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return BrewCommandRunner(brewPath: candidate)
        }

        return nil
    }

    func run(arguments: [String]) async throws -> BrewCommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                guard let standardOutput = String(data: outputData, encoding: .utf8),
                      let standardError = String(data: errorData, encoding: .utf8) else {
                    continuation.resume(throwing: BrewCommandError.failedToDecodeOutput)
                    return
                }

                let command = ([brewPath] + arguments).joined(separator: " ")
                let trimmedOutput = standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedError = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                let combinedOutput = [trimmedOutput, trimmedError]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                continuation.resume(returning: BrewCommandResult(
                    command: command,
                    exitCode: process.terminationStatus,
                    standardOutput: trimmedOutput,
                    standardError: trimmedError,
                    output: combinedOutput
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func commandText(arguments: [String]) -> String {
        ([brewPath] + arguments).joined(separator: " ")
    }
}
