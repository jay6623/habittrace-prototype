import CoreGraphics
import Foundation

extension CGPath {
    /// Minimal SVG path-data parser for the commands the Google mark uses
    /// (M, L, H, V, C, S, A, Z and their relative forms). Arcs are drawn as
    /// straight lines, which is invisible at icon size. Returns nil on
    /// malformed input or unsupported commands.
    nonisolated static func fromSVG(_ data: String) -> CGPath? {
        var parser = SVGPathParser()
        return parser.parse(data)
    }
}

nonisolated private struct SVGPathParser {
    private let path = CGMutablePath()
    private var current = CGPoint.zero
    private var start = CGPoint.zero
    private var lastControl: CGPoint?
    private var command: Character = "M"
    private var numbers: [CGFloat] = []
    private var buffer = ""

    mutating func parse(_ data: String) -> CGPath? {
        for character in data {
            if character.isLetter, character != "e", character != "E" {
                guard endNumber(), flush() else { return nil }
                command = character
                if command == "Z" || command == "z" {
                    path.closeSubpath()
                    current = start
                    lastControl = nil
                }
            } else if character == "," || character.isWhitespace {
                guard endNumber() else { return nil }
            } else if character == "-", !buffer.isEmpty, !buffer.hasSuffix("e"), !buffer.hasSuffix("E") {
                guard endNumber() else { return nil }
                buffer = "-"
            } else if character == ".", buffer.contains(".") || buffer.lowercased().contains("e") {
                guard endNumber() else { return nil }
                buffer = "."
            } else {
                buffer.append(character)
                // Arc flags are single digits that may run into the next value.
                if isArcFlagPosition, buffer == "0" || buffer == "1" {
                    guard endNumber() else { return nil }
                }
            }
        }
        guard endNumber(), flush() else { return nil }
        return path
    }

    private var isArcFlagPosition: Bool {
        (command == "a" || command == "A") && (numbers.count % 7 == 3 || numbers.count % 7 == 4)
    }

    private mutating func endNumber() -> Bool {
        guard !buffer.isEmpty else { return true }
        guard let value = Double(buffer) else { return false }
        numbers.append(CGFloat(value))
        buffer = ""
        return true
    }

    private func arity(for command: Character) -> Int? {
        switch command {
        case "M", "m", "L", "l": 2
        case "H", "h", "V", "v": 1
        case "C", "c": 6
        case "S", "s": 4
        case "A", "a": 7
        case "Z", "z": 0
        default: nil
        }
    }

    /// Applies the buffered numbers to the current command, repeating it
    /// for implicit continuations, then clears the buffer.
    private mutating func flush() -> Bool {
        defer { numbers.removeAll() }
        guard let arity = arity(for: command) else { return false }
        if arity == 0 { return numbers.isEmpty }
        guard !numbers.isEmpty || command == "Z" || command == "z" else { return true }
        guard numbers.count % arity == 0 else { return false }

        var index = 0
        while index < numbers.count {
            let v = Array(numbers[index..<(index + arity)])
            apply(v)
            index += arity
        }
        return true
    }

    private mutating func apply(_ v: [CGFloat]) {
        let isRelative = command.isLowercase
        let origin = isRelative ? current : .zero

        switch command {
        case "M", "m":
            current = CGPoint(x: origin.x + v[0], y: origin.y + v[1])
            path.move(to: current)
            start = current
            // Subsequent pairs are implicit line-tos.
            command = isRelative ? "l" : "L"
            lastControl = nil
        case "L", "l":
            current = CGPoint(x: origin.x + v[0], y: origin.y + v[1])
            path.addLine(to: current)
            lastControl = nil
        case "H", "h":
            current.x = (isRelative ? current.x : 0) + v[0]
            path.addLine(to: current)
            lastControl = nil
        case "V", "v":
            current.y = (isRelative ? current.y : 0) + v[0]
            path.addLine(to: current)
            lastControl = nil
        case "C", "c":
            let c1 = CGPoint(x: origin.x + v[0], y: origin.y + v[1])
            let c2 = CGPoint(x: origin.x + v[2], y: origin.y + v[3])
            current = CGPoint(x: origin.x + v[4], y: origin.y + v[5])
            path.addCurve(to: current, control1: c1, control2: c2)
            lastControl = c2
        case "S", "s":
            let reflected = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
            let c2 = CGPoint(x: origin.x + v[0], y: origin.y + v[1])
            current = CGPoint(x: origin.x + v[2], y: origin.y + v[3])
            path.addCurve(to: current, control1: reflected, control2: c2)
            lastControl = c2
        case "A", "a":
            current = CGPoint(x: origin.x + v[5], y: origin.y + v[6])
            path.addLine(to: current)
            lastControl = nil
        default:
            break
        }
    }
}
