import MapKit

enum PlaceSearchService {
    static func search(_ query: String) async throws -> [PlaceSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        if let coordinate = GeoCoordinate.parse(normalized) {
            return [PlaceSearchResult(
                id: coordinate.id,
                title: "座標",
                subtitle: coordinate.display,
                coordinate: coordinate
            )]
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = normalized
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(10).compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate = GeoCoordinate(item.placemark.coordinate)
            return PlaceSearchResult(
                id: "\(coordinate.id)-\(name)",
                title: name,
                subtitle: item.placemark.title ?? coordinate.display,
                coordinate: coordinate
            )
        }
    }
}
