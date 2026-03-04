import Foundation
import UIKit

final class OfflineQueueService {
    static let shared = OfflineQueueService()

    private let defaultsKey = "plumbquote.offline.quotequeue.v1"
    private let queue = DispatchQueue(label: "plumbquote.offline.queue")

    private init() {}

    struct QueuedQuoteInput: Codable, Identifiable {
        let id: String
        let createdAt: Date
        let imagesBase64: [String]
        let audioBase64: String?
        let audioMimeType: String?
        let voiceTranscript: String?
        let additionalNotes: String?
        let customerName: String?
        let customerPhone: String?
        let customerEmail: String?
        let customerAddress: String?
    }

    func enqueue(
        images: [UIImage],
        audioBase64: String?,
        audioMimeType: String?,
        voiceTranscript: String?,
        additionalNotes: String?,
        customerName: String?,
        customerPhone: String?,
        customerEmail: String?,
        customerAddress: String?
    ) {
        let encodedImages = images.compactMap { $0.compressed()?.base64EncodedString() }
        guard !encodedImages.isEmpty else { return }

        let entry = QueuedQuoteInput(
            id: UUID().uuidString,
            createdAt: Date(),
            imagesBase64: encodedImages,
            audioBase64: audioBase64,
            audioMimeType: audioMimeType,
            voiceTranscript: voiceTranscript,
            additionalNotes: additionalNotes,
            customerName: customerName,
            customerPhone: customerPhone,
            customerEmail: customerEmail,
            customerAddress: customerAddress
        )

        queue.sync {
            var items = loadQueue()
            items.append(entry)
            saveQueue(Array(items.suffix(30)))
        }
    }

    func pendingCount() -> Int {
        queue.sync { loadQueue().count }
    }

    func drain() -> [QueuedQuoteInput] {
        queue.sync {
            let items = loadQueue()
            saveQueue([])
            return items
        }
    }

    func putBack(_ items: [QueuedQuoteInput]) {
        queue.sync {
            var existing = loadQueue()
            existing.insert(contentsOf: items, at: 0)
            saveQueue(Array(existing.suffix(30)))
        }
    }

    private func loadQueue() -> [QueuedQuoteInput] {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([QueuedQuoteInput].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func saveQueue(_ items: [QueuedQuoteInput]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
