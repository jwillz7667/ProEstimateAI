import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

@Observable
final class LawnMeasurementViewModel {
    private let service: MapsServiceProtocol
    private let projectId: String?
    /// Initial map region — centered on the project's saved property
    /// coordinates when known, otherwise the user's last-known location
    /// or a continental-US default.
    var cameraPosition: MapCameraPosition

    /// Polygon vertices the contractor has tapped onto the map. The
    /// view renders an outline closing the loop on the last → first
    /// vertex automatically.
    var vertices: [CLLocationCoordinate2D] = []

    /// Result of the last successful save — surfaced to the calling
    /// project detail view so it can refresh the project's measurement.
    var savedResult: LawnAreaResult?

    var errorMessage: String?
    var isSaving: Bool = false

    /// Whether enough vertices have been placed to compute an area.
    var hasValidPolygon: Bool {
        vertices.count >= 3
    }

    /// Last computed area — recomputed locally after every vertex change
    /// so the contractor sees a live readout while drawing. The server
    /// commits the canonical value on Save.
    var liveAreaSqFt: Double {
        guard hasValidPolygon else { return 0 }
        return polygonAreaSqFtLocal(vertices)
    }

    init(
        projectId: String?,
        initialCenter: CLLocationCoordinate2D?,
        service: MapsServiceProtocol = LiveMapsService()
    ) {
        self.projectId = projectId
        self.service = service
        let center = initialCenter
            ?? CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795)
        cameraPosition = .region(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(
                    latitudeDelta: initialCenter == nil ? 30 : 0.001,
                    longitudeDelta: initialCenter == nil ? 30 : 0.001
                )
            )
        )
    }

    // MARK: - Vertex Editing

    func addVertex(at coordinate: CLLocationCoordinate2D) {
        vertices.append(coordinate)
    }

    func removeLastVertex() {
        guard !vertices.isEmpty else { return }
        vertices.removeLast()
    }

    func clearVertices() {
        vertices.removeAll()
    }

    // MARK: - Save

    func save() async -> Bool {
        guard hasValidPolygon else {
            errorMessage = "Tap at least 3 corners to bound the lawn."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let result = try await service.measureLawn(
                polygon: vertices,
                projectId: projectId
            )
            savedResult = result
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Local area math

    // Mirrors `polygonAreaSqMeters` in backend/src/lib/geo.ts. We compute
    // locally so the live readout updates instantly without a network
    // round-trip per vertex; the backend value still wins on Save.

    private static let earthRadiusM: Double = 6_378_137
    private static let sqMToSqFt: Double = 10.7639

    private func polygonAreaSqFtLocal(_ ring: [CLLocationCoordinate2D]) -> Double {
        guard ring.count >= 3 else { return 0 }
        var total: Double = 0
        for i in 0 ..< ring.count {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            total +=
                (b.longitude - a.longitude).toRadians()
                * (2 + sin(a.latitude.toRadians()) + sin(b.latitude.toRadians()))
        }
        let sqMeters = abs(
            (total * Self.earthRadiusM * Self.earthRadiusM) / 2
        )
        return sqMeters * Self.sqMToSqFt
    }
}

private extension Double {
    func toRadians() -> Double {
        self * .pi / 180
    }
}
