import Foundation

/// One square of the exploration grid, about 500 m on a side.
public struct GridCell: Hashable, Codable, Sendable {
    public var row: Int32
    public var column: Int32

    public init(row: Int32, column: Int32) {
        self.row = row
        self.column = column
    }
}

/// Explorer mode: the "fog of war" of game maps, for real roads. Squares the driver has
/// passed through are remembered on the device only. It is off until the driver turns it
/// on, and it can be erased at any time.
public struct ExplorationGrid: Codable, Equatable, Sendable {
    /// Grid step in degrees of latitude (~550 m). Longitude steps widen with latitude so
    /// cells stay roughly square.
    public static let step = 0.005
    /// Fixes less accurate than this never reveal squares.
    public static let maxAccuracy = 60.0

    public private(set) var cells: Set<GridCell>

    public init(cells: Set<GridCell> = []) { self.cells = cells }

    public var count: Int { cells.count }
    /// Area explored, in square kilometers.
    public var areaKm2: Double { Double(cells.count) * 0.55 * 0.55 }

    static func columnStep(atRow row: Int32) -> Double {
        let lat = (Double(row) + 0.5) * step
        return step / max(0.05, cos(lat * .pi / 180))
    }

    public static func cell(for c: Coordinate) -> GridCell {
        let row = Int32((c.latitude / step).rounded(.down))
        let column = Int32((c.longitude / columnStep(atRow: row)).rounded(.down))
        return GridCell(row: row, column: column)
    }

    /// Corner coordinates of a cell, counter-clockwise from the south-west corner.
    public static func corners(of cell: GridCell) -> [Coordinate] {
        let s = Double(cell.row) * step, n = s + step
        let colStep = columnStep(atRow: cell.row)
        let w = Double(cell.column) * colStep, e = w + colStep
        return [Coordinate(latitude: s, longitude: w), Coordinate(latitude: s, longitude: e),
                Coordinate(latitude: n, longitude: e), Coordinate(latitude: n, longitude: w)]
    }

    /// Records a location fix. Returns true when it revealed a new square.
    @discardableResult
    public mutating func record(_ c: Coordinate, accuracy: Double) -> Bool {
        guard accuracy >= 0, accuracy <= Self.maxAccuracy, c.isValid else { return false }
        return cells.insert(Self.cell(for: c)).inserted
    }

    /// Explored cells inside an area, capped so a zoomed-out map stays fast.
    public func cells(in area: BoundingBox, limit: Int = 4000) -> [GridCell] {
        var out: [GridCell] = []
        for cell in cells {
            let sw = Self.corners(of: cell)[0]
            if sw.latitude <= area.maxLatitude, sw.latitude + Self.step >= area.minLatitude,
               sw.longitude <= area.maxLongitude, sw.longitude + Self.columnStep(atRow: cell.row) >= area.minLongitude {
                out.append(cell)
                if out.count >= limit { break }
            }
        }
        return out
    }

    public mutating func erase() { cells.removeAll() }
}
