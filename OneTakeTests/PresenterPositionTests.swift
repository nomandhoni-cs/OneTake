import CoreGraphics
import Foundation
@testable import OneTake
import Testing

struct PresenterPositionTests {
    @Test func bottomRightSnapsWithMarginKeepingSize() {
        let rect = PresenterPosition.bottomRight.rect(for: CGSize(width: 0.34, height: 0.34))
        #expect(abs(rect.origin.x - 0.62) < 0.001)
        #expect(abs(rect.origin.y - 0.62) < 0.001)
        #expect(rect.size == CGSize(width: 0.34, height: 0.34))
    }

    @Test func topLeftSnapsToMargin() {
        let rect = PresenterPosition.topLeft.rect(for: CGSize(width: 0.5, height: 0.5))
        #expect(rect.origin.x == 0.04)
        #expect(rect.origin.y == 0.04)
    }

    @Test func matchingFindsCenterAndRejectsFarRect() {
        let centered = PresenterPosition.center.rect(for: CGSize(width: 0.34, height: 0.34))
        #expect(PresenterPosition.matching(centered) == .center)
        #expect(PresenterPosition.matching(CGRect(x: 0.1, y: 0.1, width: 0.34, height: 0.34)) == nil)
    }

    @Test func edgeCellsSnapToSlots() {
        let top = PresenterPosition.topCenter.rect(for: CGSize(width: 0.34, height: 0.34))
        #expect(abs(top.origin.x - 0.33) < 0.001)
        #expect(top.origin.y == 0.04)
        let right = PresenterPosition.middleRight.rect(for: CGSize(width: 0.34, height: 0.34))
        #expect(abs(right.origin.x - 0.62) < 0.001)
        #expect(abs(right.origin.y - 0.33) < 0.001)
        #expect(PresenterPosition.matching(right) == .middleRight)
    }

    @Test func allNineCasesRenderDistinctSlots() {
        let centers = PresenterPosition.allCases.map {
            $0.rect(for: CGSize(width: 0.2, height: 0.2))
        }.map { CGPoint(x: $0.midX, y: $0.midY) }
        #expect(Set(centers.map { "\($0.x.roundedTo(3))-\($0.y.roundedTo(3))" }).count == 9)
    }
}

private extension CGFloat {
    func roundedTo(_ places: Int) -> CGFloat {
        let divisor = pow(10, CGFloat(places))
        return (self * divisor).rounded() / divisor
    }
}
