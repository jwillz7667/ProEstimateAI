import CoreLocation
import MapKit
import SwiftUI

/// Wizard step where the contractor pins the lawn polygon on a hybrid
/// satellite map so we can capture an area for per-sq-ft pricing.
///
/// This is the embedded sibling of `LawnMeasurementView` (used from the
/// project detail screen). The embedded version omits the navigation
/// toolbar's Cancel/Save items because the project creation wizard owns
/// its own Cancel/Next bar and persists the polygon through the
/// pipeline after the project is created — there's nothing for an
/// in-step Save button to commit against until the project exists.
struct LawnAreaCaptureStep: View {
    @Bindable var viewModel: ProjectCreationViewModel

    var body: some View {
        let lawnVM = viewModel.lawnMeasurementVM

        VStack(spacing: 0) {
            instructions
                .padding(.horizontal, SpacingTokens.md)
                .padding(.top, SpacingTokens.xs)
                .padding(.bottom, SpacingTokens.sm)

            ZStack(alignment: .top) {
                mapLayer(lawnVM: lawnVM)

                AddressSearchField(placeholder: "Search address or location") { result in
                    lawnVM.recenter(on: result.coordinate, zoomedIn: true)
                }
                .padding(.horizontal, SpacingTokens.md)
                .padding(.top, SpacingTokens.xs)

                VStack {
                    Spacer()
                    controlsCard(lawnVM: lawnVM)
                        .padding(.horizontal, SpacingTokens.md)
                        .padding(.bottom, SpacingTokens.md)
                }
            }
        }
    }

    // MARK: - Header

    private var instructions: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            Text("Pin each corner of the lawn")
                .font(TypographyTokens.title3)
            Text("Search the address, then tap each corner of the lawn to bound the area for estimation.")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Map

    private func mapLayer(lawnVM: LawnMeasurementViewModel) -> some View {
        MapReader { proxy in
            Map(position: Bindable(lawnVM).cameraPosition) {
                UserAnnotation()

                if lawnVM.vertices.count >= 2 {
                    MapPolyline(coordinates: lawnVM.vertices + [lawnVM.vertices[0]])
                        .stroke(ColorTokens.primaryOrange, lineWidth: 3)
                }
                if lawnVM.hasValidPolygon {
                    MapPolygon(coordinates: lawnVM.vertices)
                        .foregroundStyle(ColorTokens.primaryOrange.opacity(0.25))
                        .stroke(ColorTokens.primaryOrange, lineWidth: 3)
                }
                ForEach(Array(lawnVM.vertices.enumerated()), id: \.offset) { index, coord in
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
            .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .all))
            .mapControls {
                MapCompass()
                MapUserLocationButton()
                MapScaleView()
            }
            // Single-arg `.onTapGesture { CGPoint in }` requires
            // `coordinateSpace:` on iOS 17+ — without it the closure
            // receives `()` instead of the screen point and vertex
            // drops never fire.
            .onTapGesture(coordinateSpace: .local) { screenPoint in
                if let coord = proxy.convert(screenPoint, from: .local) {
                    lawnVM.addVertex(at: coord)
                }
            }
        }
    }

    // MARK: - Controls

    private func controlsCard(lawnVM: LawnMeasurementViewModel) -> some View {
        VStack(spacing: SpacingTokens.sm) {
            HStack {
                Image(systemName: "ruler")
                    .foregroundStyle(ColorTokens.primaryOrange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lawnVM.hasValidPolygon
                        ? formattedArea(lawnVM.liveAreaSqFt)
                        : "Tap each corner of the lawn")
                        .font(TypographyTokens.headline)
                    Text("\(lawnVM.vertices.count) point\(lawnVM.vertices.count == 1 ? "" : "s") placed · pinch to zoom")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: SpacingTokens.sm) {
                Button {
                    lawnVM.removeLastVertex()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(lawnVM.vertices.isEmpty)

                Button(role: .destructive) {
                    lawnVM.clearVertices()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(lawnVM.vertices.isEmpty)
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

// MARK: - Preview

#Preview {
    let vm = ProjectCreationViewModel()
    vm.selectedProjectType = .lawnCare
    return NavigationStack {
        LawnAreaCaptureStep(viewModel: vm)
    }
}
