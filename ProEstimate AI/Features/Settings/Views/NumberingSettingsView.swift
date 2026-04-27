import SwiftUI

struct NumberingSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            // Estimate Numbering
            Section {
                HStack {
                    Text("Prefix")
                    Spacer()
                    TextField("EST", text: $viewModel.estimatePrefix)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .autocapitalization(.allCharacters)
                        .onChange(of: viewModel.estimatePrefix) { _, _ in viewModel.scheduleSaveNumbering() }
                }

                Stepper(value: $viewModel.nextEstimateNumber, in: 1 ... 999_999) {
                    HStack {
                        Text("Next Number")
                        Spacer()
                        Text("\(viewModel.nextEstimateNumber)")
                            .font(TypographyTokens.moneySmall)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: viewModel.nextEstimateNumber) { _, _ in viewModel.scheduleSaveNumbering() }
            } header: {
                Text("Estimates")
            } footer: {
                Text("Next estimate will be: \(viewModel.nextEstimateDisplay)")
            }

            // Invoice Numbering — exposed in the iOS UI so a contractor whose
            // billing system already uses a particular invoice number can
            // continue from that sequence rather than restarting at 1001.
            Section {
                HStack {
                    Text("Prefix")
                    Spacer()
                    TextField("INV", text: $viewModel.invoicePrefix)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .autocapitalization(.allCharacters)
                        .onChange(of: viewModel.invoicePrefix) { _, _ in viewModel.scheduleSaveNumbering() }
                }

                Stepper(value: $viewModel.nextInvoiceNumber, in: 1 ... 999_999) {
                    HStack {
                        Text("Next Number")
                        Spacer()
                        Text("\(viewModel.nextInvoiceNumber)")
                            .font(TypographyTokens.moneySmall)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: viewModel.nextInvoiceNumber) { _, _ in viewModel.scheduleSaveNumbering() }
            } header: {
                Text("Invoices")
            } footer: {
                Text("Next invoice will be: \(viewModel.nextInvoiceDisplay)")
            }

            // Preview Section
            Section("Preview") {
                VStack(spacing: SpacingTokens.md) {
                    previewRow(
                        icon: "doc.text",
                        color: ColorTokens.primaryOrange,
                        label: "Next Estimate",
                        value: viewModel.nextEstimateDisplay
                    )
                    previewRow(
                        icon: "doc.plaintext",
                        color: ColorTokens.accentGreen,
                        label: "Next Invoice",
                        value: viewModel.nextInvoiceDisplay
                    )
                }
                .padding(.vertical, SpacingTokens.xxs)
            }
        }
        .navigationTitle("Document Numbering")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsSaveStatusView(status: viewModel.saveStatus)
            }
        }
    }

    // MARK: - Subviews

    private func previewRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(label)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(TypographyTokens.moneyMedium)
                .fontWeight(.bold)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NumberingSettingsView(viewModel: SettingsViewModel())
    }
}
