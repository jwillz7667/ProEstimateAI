import CoreLocation
import MapKit
import SwiftUI

/// Roof scouting screen — contractor enters a prospect's address (or
/// a project that already has a saved coordinate), we hit Google Solar
/// API, then surface roof segments + total square footage so the bid
/// can be quoted against measured area instead of pacing the driveway.
struct RoofScoutingView: View {
    @State var viewModel: RoofScoutingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            addressSection
            if viewModel.isScouting {
                Section { ProgressView("Scouting roof…") }
            }
            if let result = viewModel.result {
                resultSummarySection(result)
                mapSection(result)
                segmentsSection(result)
            }
        }
        .navigationTitle("Roof Scouting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.hasResult {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var addressSection: some View {
        Section {
            TextField("Property address", text: $viewModel.addressInput)
                .textContentType(.fullStreetAddress)
                .autocapitalization(.words)
                .submitLabel(.search)
                .onSubmit {
                    Task { await viewModel.scout() }
                }

            Button {
                Task { await viewModel.scout() }
            } label: {
                HStack {
                    Image(systemName: "scope")
                    Text(viewModel.hasResult ? "Re-scout" : "Scout Roof")
                    Spacer()
                    if viewModel.isScouting {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(!viewModel.canScout || viewModel.isScouting)
        } header: {
            Text("Property")
        } footer: {
            Text("Pulls roof outline + segment areas from Google Solar imagery. Saves total roof square footage to the project for the next AI estimate.")
        }
    }

    private func resultSummarySection(_ r: RoofScoutingResult) -> some View {
        Section("Roof Summary") {
            stat(label: "Total Roof Area", value: areaLabel(r.totalRoofAreaSqFt))
            stat(label: "Roofing Squares", value: String(format: "%.1f sq", r.totalSquares))
            stat(label: "Segments", value: "\(r.segments.count)")
            if let quality = r.imageryQuality {
                stat(label: "Imagery Quality", value: quality.capitalized)
            }
            if let date = r.imageryDate {
                stat(label: "Imagery Date", value: shortDate(date))
            }
        }
    }

    private func mapSection(_ r: RoofScoutingResult) -> some View {
        Section("Satellite") {
            Map(initialPosition: .region(
                MKCoordinateRegion(
                    center: r.buildingCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.0006, longitudeDelta: 0.0006)
                )
            )) {
                ForEach(r.segments) { segment in
                    Annotation("Seg \(segment.index)", coordinate: segment.coordinate) {
                        Text("\(segment.index)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(ColorTokens.primaryOrange, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .frame(height: 240)
            .cornerRadius(RadiusTokens.card)
        }
    }

    private func segmentsSection(_ r: RoofScoutingResult) -> some View {
        Section("Segments (largest first)") {
            ForEach(r.segments) { segment in
                HStack(spacing: SpacingTokens.sm) {
                    Text("\(segment.index)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(ColorTokens.primaryOrange, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(segment.compassDirection)-facing · \(Int(segment.pitchDegrees))° pitch")
                            .font(TypographyTokens.subheadline)
                        Text(areaLabel(segment.areaSqFt))
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(String(format: "%.1f sq", segment.areaSqFt / 100))
                        .font(TypographyTokens.moneySmall)
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
            }
        }
    }

    // MARK: - Helpers

    private func stat(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }

    private func areaLabel(_ sqFt: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: sqFt)) ?? "\(Int(sqFt))") + " sq ft"
    }

    private func shortDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}

#Preview {
    NavigationStack {
        RoofScoutingView(
            viewModel: RoofScoutingViewModel(projectId: nil)
        )
    }
}
