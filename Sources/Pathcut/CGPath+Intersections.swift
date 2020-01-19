//
//  File.swift
//  
//
//  Created by Valentin Radu on 13/01/2020.
//

import Foundation


private let places: Int = 6
private let maxIters: Int = 500

public struct CGLine: Equatable {
    let a: CGFloat
    let b: CGFloat
    let c: CGFloat
    let start: CGPoint
    let end: CGPoint
    init(start: CGPoint, end: CGPoint) {
        var a = start.y - end.y
        var b = end.x - start.x
        var c = start.x * end.y - end.x * start.y
        let distance = sqrt(a * a + b * b)
        if distance != 0 {
            a /= distance
            b /= distance
            c /= distance
        }
        else {
            a = 0
            b = 0
            c = 0
        }
        self.a = a
        self.b = b
        self.c = c
        self.start = start
        self.end = end
    }

    func distance(to point: CGPoint) -> CGFloat {
        return a * point.x + b * point.y + c
    }
}

public struct CGSpline: Equatable {
    enum Kind: Int {
        case segment
        case quad
        case cubic
    }

    struct Collinearity: Equatable {
        enum Kind: Int {
            case point
            case horizontal
            case vertical
            case slope
            case curve
        }
        let kind: Kind
        let m: Double
        let b: Double
        init(kind: Kind, m: Double = 0, b: Double = 0) {
            self.kind = kind
            self.m = m
            self.b = b
        }
    }

    let points: [CGPoint]
    let kind: Kind
    let collinearity: Collinearity
    init(kind: Kind, points: [CGPoint]) {
        let count: Int
        switch kind {
        case .segment:
            count = 2
        case .quad:
            count = 3
        case .cubic:
            count = 4
        }
        assert(points.count == count)
        assert(points.count > 0)

        self.kind = kind
        self.points = Array(points.prefix(count))

        let horizontal = points.reduce(true, {$0 && $1.y == points[0].y})
        let vertical = points.reduce(true, {$0 && $1.x == points[0].x})

        if points.count < 2 {
            self.collinearity = Collinearity(kind: .point)
        }
        else if horizontal && vertical {
            self.collinearity = Collinearity(kind: .point)
        }
        else if horizontal {
            self.collinearity = Collinearity(kind: .horizontal)
        }
        else if vertical {
            self.collinearity = Collinearity(kind: .vertical)
        }
        else {
            if points[0].x != points[points.count - 1].x {
                let m = Double((points[0].y - points[points.count - 1].y)/(points[0].x - points[points.count - 1].x))
                let b = Double(points[0].y) - m * Double(points[0].x)
                let tolerance = pow(10.0, -CGFloat(places))
                for point in points {
                    if !point.y.isAlmostEqual(to: CGFloat(m * Double(point.x) + b), tolerance: tolerance) {
                        self.collinearity = Collinearity(kind: .curve)
                        return
                    }
                }
                self.collinearity = Collinearity(kind: .slope, m: m, b: b)
            }
            else {
                self.collinearity = Collinearity(kind: .curve)
            }
        }
    }

    func fatLine() -> (CGLine, CGFloat, CGFloat)? {
        if points.count < 2 {
            return nil
        }
        let line = CGLine(start: points[0], end: points[points.count - 1])
        var minimum: CGFloat = 0
        var maximum: CGFloat = 0

        for point in points.dropFirst().dropLast()  {
            let distance = line.distance(to: point)
            minimum = min(distance, minimum)
            maximum = max(distance, maximum)
        }

        return (line, minimum, maximum)
    }

    func clip(around line: CGLine, minimum: CGFloat, maximum: CGFloat) -> (CGSpline, CGFloat, CGFloat)? {
        if points.count < 3 || line.start == line.end {
            return nil
        }

        let totalLength = zip(points, points.dropFirst()).reduce(0, {$0 + $1.0.distanceTo($1.1)})
        var length: CGFloat = 0
        var distances: [CGPoint] = []
        for i in 0..<points.count {
            if i != 0 {
                length += points[i - 1].distanceTo(points[i])
            }
            distances.append(CGPoint(x: length/totalLength, y: line.distance(to: points[i])))

        }

        let distanceSpline = CGSpline(kind: kind, points: distances)
        let minSpline = CGSpline(kind: .segment, points: [
            .init(x: 0, y: minimum),
            .init(x: 1, y: minimum)
        ])
        let maxSpline = CGSpline(kind: .segment, points: [
            .init(x: 0, y: maximum),
            .init(x: 1, y: maximum)
        ])

        let crossPointsMin = distanceSpline.intersections(with: minSpline).map({$0.points[0]}).dropFirst()
        let crossPointsMax = distanceSpline.intersections(with: maxSpline).map({$0.points[0]}).dropFirst()
        let crossPoints = crossPointsMin + crossPointsMax

        guard crossPoints.count > 0 else {
            let hull = convexHull(of: distances)
            if hull.allSatisfy({ $0.y < maximum && $0.y > minimum}) {
                return (self, 0, 1)
            }
            else {
                return nil
            }
        }

        var minX: CGFloat = 1
        var maxX: CGFloat = 0
        for point in crossPoints {
            minX = min(point.x, minX)
            maxX = max(point.x, maxX)
        }


        if minX > 0 {
            if maxX < 1 {
                guard let (_, result, _) = split(at: minX, and: maxX) else {assertionFailure();return nil}
                return (result, minX, maxX)
            }
            else {
                guard let (_, result) = split(at: minX) else {assertionFailure();return nil}
                return (result, minX, 1)
            }
        }
        else {
            if maxX < 1 {
                guard let (result, _) = split(at: maxX) else {assertionFailure();return nil}
                return (result, 0, maxX)
            }
            else {
                return nil
            }
        }
    }

    func split(at ratio1: CGFloat, and ratio2: CGFloat) -> (CGSpline, CGSpline, CGSpline)? {
        guard ratio1 < ratio2 else {assertionFailure();return nil}
        if let r1 = split(at: ratio1) {
            if let r2 = r1.1.split(at: (ratio2 - ratio1) / (1.0 - ratio1)) {
                return (r1.0, r2.0, r2.1)
            }
        }
        return nil
    }
    func split(at ratio: CGFloat) -> (CGSpline, CGSpline)? {
        guard ratio > 0 && ratio < 1 else {assertionFailure();return nil}

        var result: (CGSpline, CGSpline)?
        switch collinearity.kind {
        case .point:
            result = nil
        case .horizontal:
            fallthrough
        case .vertical:
            fallthrough
        case .slope:
            let p = lerp(
                start: points[0],
                end: points[points.count - 1],
                t: CGFloat(ratio)
            )
            result = (
                CGSpline(kind: .segment, points: [points[0], p]),
                CGSpline(kind: .segment, points: [p, points[points.count - 1]])
            )
        case .curve:
            var localPoints = self.points
            var firstPoints: [CGPoint] = []
            var lastPoints: [CGPoint] = []
            for k in 1..<localPoints.count {
                for i in 0..<(localPoints.count - k) {
                    localPoints[i].x = (1.0 - ratio) * localPoints[i].x + ratio * localPoints[i + 1].x;
                    localPoints[i].y = (1.0 - ratio) * localPoints[i].y + ratio * localPoints[i + 1].y;
                }
                firstPoints.append(localPoints[0])
                lastPoints.append(localPoints[localPoints.count - k - 1])
            }
            result = (
                CGSpline(kind: kind, points: [points[0]] + firstPoints),
                CGSpline(kind: kind, points: lastPoints.reversed() + [points[points.count - 1]])
            )
        }
        return result
    }

    func intersections(with spline: CGSpline) -> [CGSpline] {
        if points.count < 2 || spline.points.count < 2 {
            return []
        }

        if self == spline {
            return []
        }

        let group = [self, spline].sorted(by: {$0.collinearity.kind.rawValue < $1.collinearity.kind.rawValue})

        if (group[0].collinearity.kind == .point)
            || (group[0].collinearity.kind == .horizontal && group[1].collinearity.kind == .horizontal)
            || (group[0].collinearity.kind == .vertical && group[1].collinearity.kind == .vertical) {
            return []
        }
        else {
            var intersectionPoint: CGPoint? = nil
            if (group[0].collinearity.kind == .horizontal && group[1].collinearity.kind == .vertical) {
                intersectionPoint = CGPoint(x: group[1].points[0].x, y: group[0].points[0].y)
            }
            else if (group[0].collinearity.kind == .horizontal && group[1].collinearity.kind == .slope) {
                let y = Double(group[0].points[0].y)
                let c = group[1].collinearity
                let x = (y - c.b)/c.m
                intersectionPoint = CGPoint(x: x, y: y)
            }
            else if (group[0].collinearity.kind == .vertical && group[1].collinearity.kind == .slope) {
                let x = Double(group[0].points[0].x)
                let c = group[1].collinearity
                let y = x * c.m + c.b
                intersectionPoint = CGPoint(x: x, y: y)
            }
            else if (group[0].collinearity.kind == .slope || group[1].collinearity.kind == .slope) {
                let c = group[0].collinearity
                let oc = group[1].collinearity
                if c.m != oc.m || c.b != oc.b {
                    let x = (oc.b - c.b)/(c.m - oc.m)
                    let y = x * c.m + c.b
                    intersectionPoint = CGPoint(x: x, y: y)
                }
            }

            if let intersectionPoint = intersectionPoint {
                var isOnBothSplines = true

                for s in group {
                    let ad = s.points[0].distanceTo(intersectionPoint)
                    let bd = s.points[0].distanceTo(s.points[s.points.count - 1])
                    let cd = s.points[s.points.count - 1].distanceTo(intersectionPoint)

                    if pow(ad, 2) + pow(bd, 2) < pow(cd, 2) || pow(ad, 2) + pow(cd, 2) > pow(bd, 2) {
                        isOnBothSplines = false
                        break
                    }
                }

                if isOnBothSplines {
                    return [
                        CGSpline(kind: .segment, points: [points[0], intersectionPoint]),
                        CGSpline(kind: .segment, points: [intersectionPoint, points[points.count - 1]])
                    ]
                }
                else {
                    return []
                }
            }
            else {
                if (group[0].collinearity.kind == .horizontal || group[0].collinearity.kind == .vertical && group[1].collinearity.kind == .curve) {
                    let roots: [Double]
                    let l = CGLine(start: group[0].points[0], end: group[0].points[1])
                    let p = group[1].points
                    let ap0 = Double(l.a * p[0].x + l.b * p[0].y + l.c)
                    let ap1 = Double(l.a * p[1].x + l.b * p[1].y + l.c)
                    let ap2 = Double(l.a * p[2].x + l.b * p[2].y + l.c)

                    switch  group[1].kind {
                    case .quad:
                        let a = ap0 - 2.0 * ap1 + ap2
                        let b = -2.0 * ap0 + 2.0 * ap1
                        let c = ap0

                        roots = quadraticSolve(a: a, b: b, c: c)
                    case .cubic:
                        let ap3 = Double(l.a * p[3].x + l.b * p[3].y + l.c)
                        let a = -ap0 + 3.0*ap1 - 3.0*ap2 + ap3
                        let b = 3.0*ap0 - 6.0*ap1 + 3.0*ap2
                        let c = -3.0*ap0 + 3.0*ap1
                        let d = ap0

                        roots = cubicSolve(a: a, b: b, c: c, d: d)
                    case .segment:
                        assertionFailure()
                        return []
                    }

                    var result: [CGSpline] = []
                    let validRoots = roots.filter({$0 >= 0 && $0 <= 1}).sorted()

                    for i in 0..<validRoots.count {
                        guard let (a, c) = group[1].split(at: CGFloat(validRoots[i])) else { assertionFailure();return [] }

                        if i == 0 {
                            result.append(a)
                        }
                        if i == validRoots.count - 1 {
                            result.append(c)
                        }
                        if i < validRoots.count - 1 {
                            guard let (_, b, _) = group[1].split(at: CGFloat(validRoots[i]), and: CGFloat(validRoots[i+1])) else { assertionFailure();return [] }
                            result.append(b)
                        }
                    }

                    // if we are the line
                    if collinearity.kind == .horizontal || collinearity.kind == .vertical {
                        let crossings = [points[0]] + result.map({$0.points[0]}).dropFirst() + [points[1]]
                        return zip(crossings, crossings.dropFirst()).map({a, b in
                            CGSpline(kind: .segment, points: [a, b])
                        })
                    }
                    else {
                        return result
                    }
                }
                else if group[0].collinearity.kind == .curve {
                    return recursiveIntersections(with: spline, count: 0)
                }
                else {
                    assertionFailure()
                    return []
                }
            }
        }
    }

    private func recursiveIntersections(with spline: CGSpline, count: Int) -> [CGSpline] {
        let length = zip(points, points.dropFirst()).reduce(0, {$0 + $1.0.distanceTo($1.1)})
        if length <= pow(10.0, CGFloat(-places)) {
            return [self]
        }
        if count > 100 {
            return []
        }
        guard let (line, minimum, maximum) = spline.fatLine() else {return []}
        guard let (result, _, _) = clip(around: line, minimum: minimum, maximum: maximum) else {return  []}
        return [] + spline.recursiveIntersections(with: result, count: count + 1)
    }
}

public extension CGPath {

    var splines: [CGSpline] {
        var origin: CGPoint = .zero
        var prev: CGPoint = .zero
        var result: [CGSpline] = []
        applyWithBlock {
            let elem = $0.pointee
            var elemPointsCount: Int? = nil
            var splineKind: CGSpline.Kind? = nil
            switch elem.type {
            case .moveToPoint:
                origin = elem.points[0]
                prev = origin
            case .addLineToPoint:
                elemPointsCount = 1
                splineKind = .segment
            case .addQuadCurveToPoint:
                elemPointsCount = 2
                splineKind = .quad
            case .addCurveToPoint:
                elemPointsCount = 3
                splineKind = .cubic
            case .closeSubpath:
                let spline = CGSpline(kind: .segment, points: [prev, origin])
                result.append(spline)
                prev = origin
            @unknown default:
                break
            }

            if let kind = splineKind, let count = elemPointsCount {
                let points = Array(UnsafeBufferPointer(start: elem.points, count: count))
                let spline = CGSpline(kind: kind, points: [prev] + points)
                result.append(spline)
            }

            if let count = elemPointsCount {
                prev = elem.points[count - 1]
            }
        }
        return result
    }

    func intersections(with otherPath: CGPath) -> [CGSpline] {
        return intersections(with: otherPath.splines)
    }

    func intersections(with otherSplines: [CGSpline]) -> [CGSpline] {
        var result: [CGSpline] = []
        for spline in splines {
            for otherSpline in otherSplines {
                result.append(contentsOf: spline.intersections(with: otherSpline))
            }
        }
        return result
    }
}
