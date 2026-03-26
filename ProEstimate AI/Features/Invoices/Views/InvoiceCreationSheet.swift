import SwiftUI

/// Sheet for creating a new invoice from an approved estimate.
/// The user enters an estimate ID (or selects from a list), then the
/// backend creates the invoice with copied line items and totals.
struct InvoiceCreationSheet: View {
    @State private var estimateId: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createdInvoiceId: String?
    @Environment(\.dismiss) private var dismiss

    private let service: InvoiceServiceProtocol = LiveInvoiceService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                        Text("Create a new invoice from an approved estimate.")
                            .font(TypographyTokens.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Estimate") {
                    TextField("Estimate ID (e.g. e-001)", text: $estimateId)
                        .font(TypographyTokens.body)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(TypographyTokens.caption)
                            .foregroundStyle(ColorTokens.error)
                    }
                }

                if let createdInvoiceId {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ColorTokens.success)
                            Text("Invoice created: \(createdInvoiceId)")
                                .font(TypographyTokens.subheadline)
                        }
                    }
                }

                Section {
                    PrimaryCTAButton(
                        title: "Create Invoice",
                        icon: "plus.circle.fill",
                        isLoading: isCreating,
                        isDisabled: estimateId.trimmingCharacters(in: .whitespaces).isEmpty
                    ) {
                        Task { await createInvoice() }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if createdInvoiceId != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func createInvoice() async {
        let trimmed = estimateId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        do {
            let invoice = try await service.createFromEstimate(estimateId: trimmed)
            createdInvoiceId = invoice.invoiceNumber
        } catch {
            errorMessage = error.localizedDescription
        }

        isCreating = false
    }
}

// MARK: - Preview

#Preview {
    InvoiceCreationSheet()
}
