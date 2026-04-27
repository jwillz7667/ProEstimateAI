import CoreLocation
import MapKit
import SwiftUI

/// Tap-to-add-vertex satellite map for measuring a lawn polygon.
///
/// Apple MapKit's iOS 17 `Map(...)` API lets us render the polygon as
/// an `MKMapPolygon` overlay alongside `Annotation`s for each vertex.
/// We don't ship a Google Maps SDK on-device — the satellite imagery
/// from Apple is plenty for property scouting, and it keeps our binary
/// small while staying inside Google's Maps API ToS (which forbids
/// using Static Map tiles in a custom map view).
struct LawnMeasurementView: View {
    @State var viewModel: LawnMeasurementViewModel
    @Environment(\.dismiss) private var dismiss
    var onSaved: ((LawnAreaResult) -> Void)?

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            controlsCard
        }
        .navigationTitle("Measure Lawn")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        if await viewModel.save(),
                           let result = viewModel.savedResult
                        {
                            onSaved?(result)
                            dismiss()
                        }
                    }
                }
                .disabled(!viewModel.hasValidPolygon || viewModel.isSaving)
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

    // MARK: - Map

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $viewModel.cameraPosition) {
                // Connecting outline overlay for the closed polygon.
                if viewModel.vertices.count >= 2 {
                    MapPolyline(coordinates: viewModel.vertices + [viewModel.vertices[0]])
                        .stroke(ColorTokens.primaryOrange, lineWidth: 3)
                }

                // Filled polygon overlay once 3+ vertices form a region.
                if viewModel.hasValidPolygon {
                    MapPolygon(coordinates: viewModel.vertices)
                        .foregroundStyle(ColorTokens.primaryOrange.opacity(0.25))
                        .stroke(ColorTokens.primaryOrange, lineWidth: 3)
                }

                // Vertex pins, numbered for clarity.
                ForEach(Array(viewModel.vertices.enumerated()), id: \.offset) { index, coord in
                    Annotation("\(index + 1)", coordinate: coord) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(ColorTokens.primaryOrange, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .onTapGesture { screenPoint in
                if let coord = proxy.convert(screenPoint, from: .local) {
                    viewModel.addVertex(at: coord)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Controls

    private var controlsCard: some View {
        VStack(spacing: SpacingTokens.sm) {
            // Live readout
            HStack {
                Image(systemName: "ruler")
                    .foregroundStyle(ColorTokens.primaryOrange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.hasValidPolygon
                        ? formattedArea(viewModel.liveAreaSqFt)
                        : "Tap to mark each lawn corner")
                        .font(TypographyTokens.headline)
                    Text("\(viewModel.vertices.count) point\(viewModel.vertices.count == 1 ? "" : "s") placed")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: SpacingTokens.sm) {
                Button {
                    viewModel.removeLastVertex()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.vertices.isEmpty)

                Button(role: .destructive) {
                    viewModel.clearVertices()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.vertices.isEmpty)
            }

            if viewModel.isSaving {
                ProgressView("Saving…")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(SpacingTokens.md)
        .glassCard()
        .padding(SpacingTokens.md)
    }

    private func formattedArea(_ sqFt: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let n = formatter.string(from: NSNumber(value: sqFt)) ?? "\(Int(sqFt))"
        let acres = sqFt / 43560
        if acres >= 0.1 {
            return "\(n) sq ft · \(String(format: "%.2f", acres)) acres"
        }
        return "\(n) sq ft"
    }
}

#Preview {
    NavigationStack {
        LawnMeasurementView(
            viewModel: LawnMeasurementViewModel(
                projectId: nil,
                initialCenter: CLLocationCoordinate2D(latitude: 44.9778, longitude: -93.2650)
            )
        )
    }
}
