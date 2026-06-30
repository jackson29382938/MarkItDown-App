import Foundation

enum ConversionServiceError: LocalizedError {
    case workerFailed(message: String, debugOutput: String?)
    case invalidWorkerResponse(debugOutput: String?)
    case conversionFailed(message: String, debugOutput: String?)

    var errorDescription: String? {
        switch self {
        case .workerFailed(let message, _):
            return message.isEmpty ? "The MarkItDown worker failed." : message
        case .invalidWorkerResponse:
            return "The MarkItDown worker returned an unreadable response."
        case .conversionFailed(let message, _):
            return message
        }
    }

    var debugOutput: String? {
        switch self {
        case .workerFailed(_, let debugOutput),
             .invalidWorkerResponse(let debugOutput),
             .conversionFailed(_, let debugOutput):
            return debugOutput
        }
    }

    var isOutputPermissionError: Bool {
        let haystack = ([errorDescription, debugOutput].compactMap { $0 }).joined(separator: "\n")
        return haystack.contains("PermissionError") ||
            haystack.contains("Operation not permitted") ||
            haystack.contains("Permission denied")
    }
}

final class ConversionService {
    private struct WorkerRequest: Encodable {
        let inputPath: String
        let outputPath: String
        let enginePath: String
    }

    private struct WorkerResponse: Decodable {
        let success: Bool
        let markdownPath: String?
        let markitdownVersion: String?
        let elapsedTime: TimeInterval
        let errorMessage: String?
        let traceback: String?
    }

    func convert(sourceURL: URL, outputURL: URL, using runtime: EngineRuntime) async throws -> ConversionResult {
        let response = try await runWorker(sourceURL: sourceURL, outputURL: outputURL, runtime: runtime)

        guard response.success else {
            throw ConversionServiceError.conversionFailed(
                message: response.errorMessage ?? "Conversion failed.",
                debugOutput: response.traceback
            )
        }

        guard let markdownPath = response.markdownPath,
              let version = response.markitdownVersion else {
            throw ConversionServiceError.invalidWorkerResponse(debugOutput: "Missing markdownPath or markitdownVersion in worker response.")
        }

        return ConversionResult(
            sourceURL: sourceURL,
            markdownURL: URL(fileURLWithPath: markdownPath),
            engineVersion: version,
            elapsedTime: response.elapsedTime
        )
    }

    private func runWorker(sourceURL: URL, outputURL: URL, runtime: EngineRuntime) async throws -> WorkerResponse {
        try await Task.detached(priority: .userInitiated) {
            let request = WorkerRequest(
                inputPath: sourceURL.path,
                outputPath: outputURL.path,
                enginePath: runtime.rootURL.path
            )
            let requestData = try JSONEncoder().encode(request)

            let process = Process()
            process.executableURL = runtime.pythonURL
            process.arguments = [runtime.workerURL.path]

            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONNOUSERSITE"] = "1"
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            environment["PYTHONPATH"] = runtime.sitePackagesURL.path
            process.environment = environment

            let input = Pipe()
            let output = Pipe()
            let error = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = error

            try process.run()
            input.fileHandleForWriting.write(requestData)
            input.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8) ?? ""
                throw ConversionServiceError.workerFailed(message: message, debugOutput: message)
            }

            do {
                return try JSONDecoder().decode(WorkerResponse.self, from: outputData)
            } catch {
                let message = String(data: outputData + errorData, encoding: .utf8) ?? ""
                throw ConversionServiceError.workerFailed(message: message, debugOutput: message)
            }
        }
        .value
    }
}
