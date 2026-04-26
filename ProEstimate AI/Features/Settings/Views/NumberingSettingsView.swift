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
                }

                Stepper(value: $viewModel.nextEstimateNumber, in: 1...999999) {
                    HStack {
                        Text("Next Number")
                        Spacer()
                        Text("\(viewModel.nextEstimateNumber)")
                            .font(TypographyTokens.moneySmall)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Estimates")
            } footer: {
                Text("Next estimate will be: \(viewModel.nextEstimateDisplay)")
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
                }
                .padding(.vertical, SpacingTokens.xxs)
            }

            // Save
            Section {
                PrimaryCTAButton(
                    title: "Save Numbering",
                    icon: "checkmark.circle",
                    isLoading: viewModel.isSaving
                ) {
                    Task { await viewModel.saveNumbering() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Document Numbering")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Success", isPresented: .init(
            get: { viewModel.successMessage != nil },
            set: { if !$0 { viewModel.successMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.successMessage = nil }
        } message: {
            Text(viewModel.successMessage ?? "")
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
