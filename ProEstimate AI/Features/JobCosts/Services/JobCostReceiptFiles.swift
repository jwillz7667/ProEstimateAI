import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Receipt bytes are short-lived and never part of the payment/cost journals.
/// Import and preview I/O run away from the main actor with strict size bounds.
actor JobCostReceiptFiles {
    static let shared = JobCostReceiptFiles()
    private var previews: Set<URL> = []

    func importFile(_ url: URL) throws -> JobCostReceiptAttachment {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 5_000_000 else {
            throw JobCostError.validation("Choose a receipt file no larger than 5 MB.")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let mimeType: String
        switch url.pathExtension.lowercased() {
        case "pdf": mimeType = "application/pdf"
        case "jpg", "jpeg": mimeType = "image/jpeg"
        case "png": mimeType = "image/png"
        default: throw JobCostError.validation("Choose a JPEG, PNG or PDF receipt.")
        }
        let attachment = JobCostReceiptAttachment(data: data, mimeType: mimeType, filename: url.lastPathComponent)
        if let error = attachment.validationMessage { throw JobCostError.validation(error) }
        return attachment
    }

    func photo(_ data: Data) throws -> JobCostReceiptAttachment {
        guard !data.isEmpty, data.count <= 40_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { throw JobCostError.validation("This photo couldn't be read. Choose another receipt image.") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw JobCostError.validation("The receipt photo couldn't be prepared.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw JobCostError.validation("The receipt photo couldn't be prepared.") }
        let attachment = JobCostReceiptAttachment(data: output as Data, mimeType: "image/jpeg", filename: "Receipt.jpg")
        if let error = attachment.validationMessage { throw JobCostError.validation(error) }
        return attachment
    }

    func preview(data: Data, filename: String, mimeType: String) throws -> URL {
        let attachment = JobCostReceiptAttachment(data: data, mimeType: mimeType, filename: filename)
        if let error = attachment.validationMessage { throw JobCostError.validation(error) }
        let suffix = mimeType == "application/pdf" ? "pdf" : (mimeType == "image/png" ? "png" : "jpg")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProEstimate-PrivateReceipt-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent("Receipt.\(suffix)")
        do {
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            previews.insert(file)
            return file
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func removePreview(_ url: URL) {
        guard previews.remove(url) != nil else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func removeAllPreviews() {
        let files = previews
        previews.removeAll()
        for file in files { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    }
}
