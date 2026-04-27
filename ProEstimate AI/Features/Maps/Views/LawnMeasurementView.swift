import CoreLocation
import MapKit
import SwiftUI

/// Tap-to-add-vertex satellite map for measuring a lawn polygon.
///
/// Uses Apple MapKit's hybrid imagery (satellite + roads + labels +
/// POIs) so the contractor can navigate to the correct property by
/// street name, then tap each lawn corner to drop a vertex. Includes
/// an `MKLocalSearchCompleter`-powered address search so jumping to a
/// specific address is one tap.
///
/// Note on parcel/property lines: Apple MapKit doesn't ship parcel
/// boundary data. The hybrid map style does render building footprints
/// and roads at street zoom — combined with satellite, that's enough
/// to visually trace the lawn. A future paid parcel tile overlay
/// (Regrid, Mapbox) can drop in via a `MapTileOverlay` without
/// reshaping this view.
struct LawnMeasurementView: View {
    @State var viewModel: LawnMeasurementViewModel
    @Environment(\.dismiss) private var dismiss
    var onSaved: ((LawnAreaResult) -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
                .ignoresSafeArea(edges: .bottom)

            // Floating address search at the very top.
            AddressSearchField(placeholder: "Search address or location") { result in
                viewModel.recenter(on: result.coordinate, zoomedIn: true)
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.top, SpacingTokens.xs)

            // Floating action card at the bottom.
            VStack {
                Spacer()
                controlsCard
                    .padding(.horizontal, SpacingTokens.md)
                    .padding(.bottom, SpacingTokens.md)
            }
        }
        .navigationTitle("Measure Lawn")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
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
                // User location pin so the contractor can sanity-check
                // they're looking at the right neighborhood.
                UserAnnotation()

                if viewModel.vertices.count >= 2 {
                    MapPolyline(coordinates: viewModel.vertices + [viewModel.vertices[0]])
                        .stroke(ColorTokens.primaryOrange, lineWidth: 3)
                }
                if viewModel.hasValidPolygon {
                    MapPolygon(coordinates: viewModel.vertices)
                        .foregroundStyle(ColorTokens.primaryOrange.opacity(0.25))
                        .stroke(ColorTokens.primaryOrange, lineWidth: 3)
                }
                ForEach(Array(viewModel.vertices.enumerated()), id: \.offset) { index, coord in
                    Annotation("\(index + 1)", coordinate: coord) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(ColorTokens.primaryOrange, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
            }
            // Hybrid = satellite imagery + streets + labels + POIs. Lets
            // the contractor see street names, building footprints, and
            // intersections — critical for finding the right property.
            .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .all))
            .mapControls {
                MapCompass()
                MapUserLocationButton()
                MapScaleView()
            }
            // The single-arg `.onTapGesture { CGPoint in }` overload is
            // iOS 17+ and explicitly requires `coordinateSpace:` — without
            // it Apple delivers () instead of a CGPoint and our vertex
            // drops never fire. That was the original bug.
            .onTapGesture(coordinateSpace: .local) { screenPoint in
                if let coord = proxy.convert(screenPoint, from: .local) {
                    viewModel.addVertex(at: coord)
                }
            }
        }
    }

    // MARK: - Controls

    private var controlsCard: some View {
        VStack(spacing: SpacingTokens.sm) {
            HStack {
                Image(systemName: "ruler")
                    .foregroundStyle(ColorTokens.primaryOrange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.hasValidPolygon
                        ? formattedArea(viewModel.liveAreaSqFt)
                        : "Tap each corner of the lawn")
                        .font(TypographyTokens.headline)
                    Text("\(viewModel.vertices.count) point\(viewModel.vertices.count == 1 ? "" : "s") placed · pinch to zoom")
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
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: RadiusTokens.card))
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
