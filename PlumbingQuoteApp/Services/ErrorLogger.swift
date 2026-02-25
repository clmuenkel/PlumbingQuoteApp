import Foundation
import Supabase
import UIKit

enum ErrorLogger {
    private struct LogRow: Encodable {
        let id: String
        let source: String
        let severity: String
        let message: String
        let context: [String: String]
        let device_info: String
        let app_version: String
    }

    static func log(
        message: String,
        severity: String = "error",
        context: [String: String] = [:]
    ) {
        Task {
            let supabase = SupabaseService.shared.client
            var logContext = context
            logContext["device"] = UIDevice.current.model
            logContext["os"] = UIDevice.current.systemVersion

            let payload = LogRow(
                id: "err_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
                source: "ios_app",
                severity: severity,
                message: message,
                context: logContext,
                device_info: "\(UIDevice.current.model) \(UIDevice.current.systemVersion)",
                app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            )

            _ = try? await supabase
                .from("error_logs")
                .insert(payload)
                .execute()
        }
    }
}
