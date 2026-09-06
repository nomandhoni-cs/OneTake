//
//  ReactionModels.swift
//  OneTake
//
//  Owns: Reaction Studio shared value types — StudioMode, ReactionLayout,
//  ReactionOutline, and presenter-rect defaults.
//  Why: Small enums + unit-rect math live apart from services/views so the
//  picker, compositor, capture service, and tests share one source of truth.
//  See: docs/ARCHITECTURE.md §6 + openspec/changes/reaction-studio-cutout/specs/reaction-studio/spec.md
//
import Foundation
import SwiftUI

/// Studio capture mode — picked in `StudioTab`, presented full-screen.
enum StudioMode: String, CaseIterable, Identifiable {
    case teleprompter
    case reaction

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .teleprompter: "Teleprompter"
        case .reaction: "Reaction"
        }
    }

    var subtitle: String {
        switch self {
        case .teleprompter: "Read your script on camera"
        case .reaction: "React with auto cutout"
        }
    }

    var iconName: String {
        switch self {
        case .teleprompter: "video.fill"
        case .reaction: "person.crop.rectangle.stack"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .teleprompter: "Opens the teleprompter camera full screen"
        case .reaction: "Opens the reaction cutout camera full screen"
        }
    }
}

/// Cutout arrangement over the background canvas.
enum ReactionLayout: String, CaseIterable, Identifiable {
    case silhouette
    case circle
    case split

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .silhouette: "Silhouette"
        case .circle: "Circle PiP"
        case .split: "Split"
        }
    }

    var iconName: String {
        switch self {
        case .silhouette: "person.fill"
        case .circle: "circle.dashed"
        case .split: "rectangle.split.2x1"
        }
    }
}

/// Optional glow stroke around the presenter's silhouette.
enum ReactionOutline: String, CaseIterable, Identifiable {
    case off
    case white
    case cyan
    case yellow
    case red

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .off: "Off"
        case .white: "White"
        case .cyan: "Cyan"
        case .yellow: "Yellow"
        case .red: "Red"
        }
    }

    var color: Color? {
        switch self {
        case .off: nil
        case .white: Color.white
        case .cyan: Color.cyan
        case .yellow: Color.yellow
        case .red: Color.red
        }
    }
}

/// Presenter placement as a unit rect in canvas space (0...1), persisted via
/// `@AppStorage` doubles so creators keep their framing between sessions.
enum ReactionPresenterDefaults {
    static let centerX = 0.78
    static let centerY = 0.72
    static let width = 0.34
    static let height = 0.34
    static let minSide = 0.16
    static let maxSide = 0.9
}

/// Snap-to preset for the presenter rect (unit space, top-left origin).
/// Nine cells in reading order so settings can render a spatial 3×3 grid;
/// keeps the current size and moves the origin to the chosen slot.
enum PresenterPosition: String, CaseIterable, Identifiable {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case center
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topCenter: "Top"
        case .topRight: "Top right"
        case .middleLeft: "Left"
        case .center: "Center"
        case .middleRight: "Right"
        case .bottomLeft: "Bottom left"
        case .bottomCenter: "Bottom"
        case .bottomRight: "Bottom right"
        }
    }

    var iconName: String {
        switch self {
        case .topLeft: "arrow.up.left"
        case .topCenter: "arrow.up"
        case .topRight: "arrow.up.right"
        case .middleLeft: "arrow.left"
        case .center: "square.dashed"
        case .middleRight: "arrow.right"
        case .bottomLeft: "arrow.down.left"
        case .bottomCenter: "arrow.down"
        case .bottomRight: "arrow.down.right"
        }
    }

    /// Grid slot, row-major (0...2, 0...2).
    private var slot: (column: Int, row: Int) {
        switch self {
        case .topLeft: (0, 0)
        case .topCenter: (1, 0)
        case .topRight: (2, 0)
        case .middleLeft: (0, 1)
        case .center: (1, 1)
        case .middleRight: (2, 1)
        case .bottomLeft: (0, 2)
        case .bottomCenter: (1, 2)
        case .bottomRight: (2, 2)
        }
    }

    /// Snapped rect for the given size, with an edge margin.
    func rect(for size: CGSize, margin: Double = 0.04) -> CGRect {
        let width = min(max(size.width, ReactionPresenterDefaults.minSide), ReactionPresenterDefaults.maxSide)
        let height = min(max(size.height, ReactionPresenterDefaults.minSide), ReactionPresenterDefaults.maxSide)
        let originsX = [margin, (1 - width) / 2, 1 - margin - width]
        let originsY = [margin, (1 - height) / 2, 1 - margin - height]
        let x = max(originsX[slot.column], margin)
        let y = max(originsY[slot.row], margin)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Nearest preset when the rect center is close, else nil.
    static func matching(_ rect: CGRect, tolerance: Double = 0.06) -> PresenterPosition? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return allCases.min { left, right in
            distance(center, left.rect(for: rect.size).center) < distance(center, right.rect(for: rect.size).center)
        }.flatMap { match in
            distance(center, match.rect(for: rect.size).center) < tolerance ? match : nil
        }
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
