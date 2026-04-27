import Combine
import CoreLocation
import MapKit
import SwiftUI

/// Native iOS address search powered by `MKLocalSearchCompleter`. Renders
/// a text field with a dropdown of autocomplete suggestions; tapping a
/// suggestion runs `MKLocalSearch` to resolve the full coordinate and
/// fires `onSelect` with the result.
///
/// Used by both the lawn measurement and roof scouting screens so the
/// contractor can jump to a specific property at street-level zoom
/// without manually panning across the map.
struct AddressSearchField: View {
    var placeholder: String = "Search address"
    var onSelect: (AddressSearchResult) -> Void

    @State private var query: String = ""
    @State private var coordinator = AddressSearchCoordinator()
    @State private var isFocusedDropdown: Bool = false
    @FocusState private var fieldFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $query)
                    .focused($fieldFocus)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onChange(of: query) { _, newValue in
                        coordinator.update(query: newValue)
                    }
                    .onSubmit {
                        // Pressing return = pick the top suggestion.
                        if let first = coordinator.results.first {
                            select(first)
                        }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        coordinator.update(query: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, SpacingTokens.sm)
            .padding(.vertical, SpacingTokens.xs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RadiusTokens.button))

            // Dropdown with up to 6 suggestions. Floats above the map
            // without pushing other content down so the contractor keeps
            // the map context while choosing a result.
            if fieldFocus, !coordinator.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(coordinator.results.prefix(6), id: \.self) { completion in
                        Button {
                            select(completion)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .font(TypographyTokens.subheadline)
                                    .foregroundStyle(ColorTokens.primaryText)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(TypographyTokens.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, SpacingTokens.sm)
                            .padding(.vertical, SpacingTokens.xs)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
                .padding(.top, SpacingTokens.xxs)
            }
        }
    }

    /// Resolves a completion → full `MKMapItem` with a CLLocationCoordinate
    /// then bubbles it up. We hide the keyboard so the map regains the
    /// vertical space immediately.
    private func select(_ completion: MKLocalSearchCompletion) {
        query = completion.title
        fieldFocus = false
        coordinator.update(query: "")

        let request = MKLocalSearch.Request(completion: completion)
        Task {
            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                guard let first = response.mapItems.first else { return }
                let coord = first.placemark.coordinate
                let formatted = [completion.title, completion.subtitle]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                await MainActor.run {
                    onSelect(AddressSearchResult(
                        formattedAddress: formatted,
                        coordinate: coord
                    ))
                }
            } catch {
                // Silently swallow — the user can pick a different result.
            }
        }
    }
}

struct AddressSearchResult: Hashable {
    let formattedAddress: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: AddressSearchResult, rhs: AddressSearchResult) -> Bool {
        lhs.formattedAddress == rhs.formattedAddress
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(formattedAddress)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}

// MARK: - Search Completer

/// Bridges `MKLocalSearchCompleter`'s delegate-based API into a SwiftUI
/// `@Observable` so the `AddressSearchField` can read `results` directly.
@Observable
final class AddressSearchCoordinator: NSObject, MKLocalSearchCompleterDelegate {
    private let completer: MKLocalSearchCompleter
    var results: [MKLocalSearchCompletion] = []

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_: MKLocalSearchCompleter, didFailWithError _: Error) {
        // Apple sometimes returns transient errors while the user is typing.
        // We don't surface them — the dropdown just stays empty until the
        // next valid completer update.
        results = []
    }
}
