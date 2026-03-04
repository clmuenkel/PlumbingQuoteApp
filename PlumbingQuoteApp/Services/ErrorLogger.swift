import Foundation
import Supabase
import UIKit
import Combine

enum ErrorLogger {
    private struct LogRow: Codable {
        let id: String
        let source: String
        let severity: String
        let message: String
        let context: [String: String]
        let device_info: String
        let app_version: String
    }

    private static var cancellables = Set<AnyCancellable>()
    private static let queueKey = "plumbquote.errorlog.queue.v1"
    private static let flushQueue = DispatchQueue(label: "plumbquote.errorlog.flush")

    static func start() {
        NetworkMonitor.shared.$isConnected
            .removeDuplicates()
            .sink { isConnected in
                guard isConnected else { return }
                Task { await flushQueuedLogs() }
            }
            .store(in: &cancellables)
    }

    static func log(
        message: String,
        severity: String = "error",
        context: [String: String] = [:]
    ) {
        Task {
            let payload = LogRow(
                id: "err_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
                source: "ios_app",
                severity: severity,
                message: message,
                context: enrichContext(context),
                device_info: "\(UIDevice.current.model) \(UIDevice.current.systemVersion)",
                app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            )
            do {
                try await send([payload])
            } catch {
                await enqueue(payload)
            }
        }
    }

    static func flushQueuedLogs() async {
        let queued = loadQueue()
        guard !queued.isEmpty else { return }

        do {
            try await send(queued)
            saveQueue([])
        } catch {
            // Keep queue intact; it will retry on next reconnect.
        }
    }

    private static func enrichContext(_ context: [String: String]) -> [String: String] {
        var logContext = context
        logContext["device"] = UIDevice.current.model
        logContext["os"] = UIDevice.current.systemVersion
        return logContext
    }

    private static func send(_ rows: [LogRow]) async throws {
        let supabase = SupabaseService.shared.client
        _ = try await supabase
            .from("error_logs")
            .insert(rows)
            .execute()
    }

    private static func enqueue(_ row: LogRow) async {
        await withCheckedContinuation { continuation in
            flushQueue.async {
                var queue = loadQueue()
                queue.append(row)
                let cappedQueue = Array(queue.suffix(300))
                saveQueue(cappedQueue)
                continuation.resume()
            }
        }
    }

    private static func loadQueue() -> [LogRow] {
        guard
            let data = UserDefaults.standard.data(forKey: queueKey),
            let rows = try? JSONDecoder().decode([LogRow].self, from: data)
        else {
            return []
        }
        return rows
    }

    private static func saveQueue(_ rows: [LogRow]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: queueKey)
    }
}
