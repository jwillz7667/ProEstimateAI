import SwiftUI

struct LanguageSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(AppearanceStore.self) private var appearanceStore

    var body: some View {
        Form {
            // Language Picker
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedLanguage = language
                        }
                        // Drive the SwiftUI `\.locale` environment so the
                        // app interface flips immediately, in addition to
                        // the document-level backend save below. Without
                        // this, the UI was frozen on whatever locale was
                        // active at launch.
                        appearanceStore.setLanguage(language)
                        Task { await viewModel.saveLanguageImmediately() }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.displayName)
                                    .font(TypographyTokens.body)
                                    .foregroundStyle(.primary)

                                if language == .spanish {
                                    Text("Espa\u{00F1}ol")
                                        .font(TypographyTokens.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if viewModel.selectedLanguage == language {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ColorTokens.primaryOrange)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Switches the app interface and the language used in generated estimates, proposals, and invoices sent to clients. Takes effect immediately — no relaunch needed.")
            }

            // Preview Section
            Section("Preview") {
                documentPreview
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsSaveStatusView(status: viewModel.saveStatus)
            }
        }
    }

    // MARK: - Preview

    private var documentPreview: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            // Header
            HStack {
                Text(headerText)
                    .font(TypographyTokens.caption)
                    .fontWeight(.bold)
                    .tracking(3)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Divider()

            // Sample line items
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                sampleRow(name: itemLabel, qty: "2", total: "$150.00")
                sampleRow(name: laborLabel, qty: "8", total: "$520.00")
            }

            Divider()

            // Totals
            HStack {
                Text(subtotalLabel)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("$670.00")
                    .font(TypographyTokens.moneyCaption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(taxLabel)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("$55.28")
                    .font(TypographyTokens.moneyCaption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(totalLabel)
                    .font(TypographyTokens.subheadline)
                    .fontWeight(.bold)
                Spacer()
                Text("$725.28")
                    .font(TypographyTokens.moneySmall)
                    .foregroundStyle(ColorTokens.primaryOrange)
            }
        }
        .padding(.vertical, SpacingTokens.xxs)
    }

    private func sampleRow(name: String, qty: String, total: String) -> some View {
        HStack {
            Text(name)
                .font(TypographyTokens.caption)
            Spacer()
            Text(qty)
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
            Text(total)
                .font(TypographyTokens.moneyCaption)
                .frame(width: 70, alignment: .trailing)
        }
    }

    // MARK: - Localized Labels

    private var headerText: String {
        viewModel.selectedLanguage == .english ? "ESTIMATE" : "PRESUPUESTO"
    }

    private var itemLabel: String {
        viewModel.selectedLanguage == .english ? "Quartz Countertop" : "Encimera de Cuarzo"
    }

    private var laborLabel: String {
        viewModel.selectedLanguage == .english ? "Installation Labor" : "Mano de Obra"
    }

    private var subtotalLabel: String {
        viewModel.selectedLanguage == .english ? "Subtotal" : "Subtotal"
    }

    private var taxLabel: String {
        viewModel.selectedLanguage == .english ? "Tax" : "Impuesto"
    }

    private var totalLabel: String {
        viewModel.selectedLanguage == .english ? "Total" : "Total"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LanguageSettingsView(viewModel: SettingsViewModel())
    }
}
