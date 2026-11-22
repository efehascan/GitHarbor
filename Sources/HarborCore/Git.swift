import Foundation

public struct GitError: Error, CustomStringConvertible, Sendable {
    public var code: Int32
    public var message: String
    public var description: String { message.isEmpty ? "git çıkış kodu \(code)" : message }
}

/// Sistemdeki `git` komutunu çalıştırır. Kabuk yok: argümanlar doğrudan geçer.
/// Etkileşimli istem kapalı (parola sorusu uygulamayı kilitlemesin).
public enum Git {
    public static var executable = URL(fileURLWithPath: "/usr/bin/git")

    public static func run(_ args: [String], in directory: String, allowedExitCodes: Set<Int32> = [0]) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try runSync(args, in: directory, allowedExitCodes: allowedExitCodes)
        }.value
    }

    public static func runSync(_ args: [String], in directory: String, allowedExitCodes: Set<Int32> = [0]) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-C", directory, "--no-optional-locks"] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["LC_ALL"] = "C"
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Çıktı büyükse borunun dolup süreci kilitlememesi için iki ucu da süreç bitmeden okunur.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        guard allowedExitCodes.contains(process.terminationStatus) else {
            let msg = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError(code: process.terminationStatus, message: msg)
        }
        return data
    }

    public static func status(in directory: String) async throws -> RepoStatus {
        let data = try await run(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], in: directory)
        return StatusParser.parse(data)
    }

    /// Klasör bir git deposunun kökü mü (alt klasör değil).
    public static func isRepositoryRoot(_ directory: String) -> Bool {
        guard let data = try? runSync(["rev-parse", "--show-toplevel"], in: directory) else { return false }
        let top = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: top).standardizedFileURL.path == URL(fileURLWithPath: directory).standardizedFileURL.path
    }
}
