import AppKit
import Vision

final class OCRService {
    static let shared = OCRService()

    private let queue = DispatchQueue(label: "dev.tzgyn.kapture.ocr", qos: .userInitiated)

    func recognize(_ cgImage: CGImage, completion: @escaping (String) -> Void) {
        queue.async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                completion("")
                return
            }

            let observations = request.results ?? []
            let lines = observations
                .sorted { a, b in
                    let ay = a.boundingBox.midY
                    let by = b.boundingBox.midY
                    if abs(ay - by) > 0.02 { return ay > by }
                    return a.boundingBox.minX < b.boundingBox.minX
                }
                .compactMap { $0.topCandidates(1).first?.string }
            completion(lines.joined(separator: "\n"))
        }
    }
}
