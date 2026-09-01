import Foundation

/// GPX 1.1 route import/export compatible with the GFlyer Android codec:
/// each `trk`/`rte` with at least two points becomes a route, and standalone
/// `wpt` elements form a fallback route when no track exists.
enum GpxCodec {
    struct ExportRoute {
        let name: String
        let points: [GeoCoordinate]
    }

    struct ImportedRoute: Equatable {
        let name: String?
        let points: [GeoCoordinate]
    }

    static let maxPointsPerRoute = 500

    static func readRoutes(from data: Data) -> [ImportedRoute] {
        let parser = XMLParser(data: data)
        let delegate = GpxParserDelegate()
        parser.delegate = delegate
        _ = parser.parse()
        var routes = delegate.routes
        if routes.isEmpty, delegate.waypoints.count >= 2 {
            routes = [ImportedRoute(name: nil, points: delegate.waypoints)]
        }
        return routes.map { route in
            ImportedRoute(name: route.name, points: Array(route.points.prefix(maxPointsPerRoute)))
        }
    }

    static func write(routes: [ExportRoute]) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<gpx version=\"1.1\" creator=\"GFlyer\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        for route in routes where route.points.count >= 2 {
            xml += "  <trk>\n"
            xml += "    <name>\(escape(route.name))</name>\n"
            xml += "    <trkseg>\n"
            for point in route.points {
                xml += "      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"></trkpt>\n"
            }
            xml += "    </trkseg>\n"
            xml += "  </trk>\n"
        }
        xml += "</gpx>\n"
        return Data(xml.utf8)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private final class GpxParserDelegate: NSObject, XMLParserDelegate {
    var routes: [GpxCodec.ImportedRoute] = []
    var waypoints: [GeoCoordinate] = []
    private var currentPoints: [GeoCoordinate]?
    private var currentName: String?
    private var isReadingRouteName = false
    private var nameBuffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "trk", "rte":
            if currentPoints == nil {
                currentPoints = []
                currentName = nil
            }
        case "trkpt", "rtept", "wpt":
            guard
                let latitudeText = attributeDict["lat"],
                let longitudeText = attributeDict["lon"],
                let latitude = Double(latitudeText),
                let longitude = Double(longitudeText),
                let point = GeoCoordinate.validated(latitude: latitude, longitude: longitude)
            else { return }
            if currentPoints != nil {
                currentPoints?.append(point)
            } else {
                waypoints.append(point)
            }
        case "name":
            // Only a name that appears before any point counts as the
            // track/route title; per-point names are ignored.
            if let points = currentPoints, points.isEmpty, currentName == nil {
                isReadingRouteName = true
                nameBuffer = ""
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingRouteName { nameBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "name":
            if isReadingRouteName {
                isReadingRouteName = false
                let trimmed = nameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                currentName = trimmed.isEmpty ? nil : trimmed
            }
        case "trk", "rte":
            if let points = currentPoints, points.count >= 2 {
                routes.append(GpxCodec.ImportedRoute(name: currentName, points: points))
            }
            currentPoints = nil
            currentName = nil
        default:
            break
        }
    }
}
