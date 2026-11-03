import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct JobCostReceiptPicker: View {
    @Binding var attachment: JobCostReceiptAttachment?
    @Binding var isPreparing: Bool
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var errorMessage: String?

    var body: some View {
        Section("Receipt (optional)") {
            if let attachment {
                Label(attachment.filename, systemImage: "doc.text")
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                    .font(TypographyTokens.caption).foregroundStyle(ColorTokens.secondaryText)
                Button("Remove selected receipt", role: .destructive) { self.attachment = nil; photo = nil }
                    .disabled(isPreparing)
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Take receipt photo", systemImage: "camera") }
                    .disabled(isPreparing)
            }
            PhotosPicker(selection: $photo, matching: .images) { JobCostPhotoPickerLabel() }
                .disabled(isPreparing)
            Button { showFiles = true } label: { Label("Choose PDF or image file", systemImage: "folder") }
                .disabled(isPreparing)
            if isPreparing { ProgressView("Preparing receipt…") }
            if let errorMessage { Text(errorMessage).font(TypographyTokens.footnote).foregroundStyle(ColorTokens.error) }
            Text("JPEG, PNG or PDF, up to 5 MB. The receipt is attached after the cost is saved.")
                .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
        }
        .task(id: photo) {
            guard let photo else { return }
            isPreparing = true
            defer { isPreparing = false }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else { throw JobCostError.validation("This photo couldn't be loaded.") }
                let prepared = try await JobCostReceiptFiles.shared.photo(data)
                try Task.checkCancellation()
                attachment = prepared
                errorMessage = nil
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                Task {
                    isPreparing = true
                    defer { isPreparing = false }
                    await Task.yield()
                    do {
                        guard let data = image.jpegData(compressionQuality: 0.9) else { throw JobCostError.validation("The camera photo couldn't be prepared.") }
                        attachment = try await JobCostReceiptFiles.shared.photo(data)
                        errorMessage = nil
                    } catch { errorMessage = error.localizedDescription }
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .jpeg, .png], allowsMultipleSelection: false) { result in
            Task {
                isPreparing = true
                defer { isPreparing = false }
                do {
                    guard let file = try result.get().first else { return }
                    attachment = try await JobCostReceiptFiles.shared.importFile(file)
                    errorMessage = nil
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct JobCostPhotoPickerLabel: View {
    nonisolated init() {}
    var body: some View { Label("Choose receipt photo", systemImage: "photo") }
}
