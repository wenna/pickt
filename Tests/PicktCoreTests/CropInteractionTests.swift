import XCTest
@testable import PicktCore

final class CropInteractionTests:XCTestCase {
    let box=NormalizedRect(x:0.2,y:0.25,width:0.4,height:0.3)
    func testDragInsideMovesWithoutChangingSize() {
        let drag=CropInteraction(selection:box,start:.init(x:0.4,y:0.4),toleranceX:0.02,toleranceY:0.02)
        let result=drag.updated(to:.init(x:0.55,y:0.5))
        XCTAssertEqual(result.x,0.35,accuracy:0.0001);XCTAssertEqual(result.y,0.35,accuracy:0.0001)
        XCTAssertEqual(result.width,box.width);XCTAssertEqual(result.height,box.height)
    }
    func testMoveClampsToImageWithoutShrinking() {
        let drag=CropInteraction(selection:box,start:.init(x:0.4,y:0.4))
        let result=drag.updated(to:.init(x:2,y:-1))
        XCTAssertEqual(result.x,0.6,accuracy:0.0001);XCTAssertEqual(result.y,0,accuracy:0.0001)
        XCTAssertEqual(result.width,box.width);XCTAssertEqual(result.height,box.height)
    }
    func testBottomRightHandleKeepsOppositeCorner() {
        let drag=CropInteraction(selection:box,start:.init(x:0.6,y:0.55),toleranceX:0.025,toleranceY:0.025)
        let result=drag.updated(to:.init(x:0.9,y:0.8))
        XCTAssertEqual(result.x,0.2);XCTAssertEqual(result.y,0.25)
        XCTAssertEqual(result.width,0.7,accuracy:0.0001);XCTAssertEqual(result.height,0.55,accuracy:0.0001)
    }
    func testTopEdgeOnlyChangesHeight() {
        let drag=CropInteraction(selection:box,start:.init(x:0.4,y:0.25))
        let result=drag.updated(to:.init(x:0.8,y:0.1))
        XCTAssertEqual(result.x,box.x);XCTAssertEqual(result.width,box.width)
        XCTAssertEqual(result.y,0.1,accuracy:0.0001);XCTAssertEqual(result.height,0.45,accuracy:0.0001)
    }
    func testAllEightHandlesAreSelectable() {
        for handle in CropHandle.allCases {
            let point=handle.point(in:box)
            let drag=CropInteraction(selection:box,start:point,toleranceX:0.015,toleranceY:0.015)
            XCTAssertEqual(drag.mode,.resize(handle))
        }
    }
    func testOutsideDragCreatesNewBoxInEitherDirection() {
        let drag=CropInteraction(selection:box,start:.init(x:0.9,y:0.9))
        let result=drag.updated(to:.init(x:0.1,y:0.7))
        XCTAssertEqual(result.x,0.1);XCTAssertEqual(result.y,0.7)
        XCTAssertEqual(result.width,0.8,accuracy:0.0001);XCTAssertEqual(result.height,0.2,accuracy:0.0001)
    }
    func testInitialFullPageStillAllowsDrawingInside() {
        let drag=CropInteraction(selection:.init(),start:.init(x:0.2,y:0.3))
        XCTAssertEqual(drag.mode,.create)
        let result=drag.updated(to:.init(x:0.6,y:0.7))
        XCTAssertEqual(result.width,0.4,accuracy:0.0001)
    }
    func testMaskDrawOnlyAlwaysCreatesRatherThanMoves() {
        let drag=CropInteraction(selection:box,start:.init(x:0.4,y:0.4),drawOnly:true)
        XCTAssertEqual(drag.mode,.create)
    }
    func testResizeCannotInvertOrCollapseSelection() {
        let drag=CropInteraction(selection:box,start:.init(x:0.2,y:0.25),minimumWidth:0.05,minimumHeight:0.06)
        let result=drag.updated(to:.init(x:0.9,y:0.9))
        XCTAssertEqual(result.width,0.05,accuracy:0.0001);XCTAssertEqual(result.height,0.06,accuracy:0.0001)
        XCTAssertEqual(result.x+result.width,0.6,accuracy:0.0001);XCTAssertEqual(result.y+result.height,0.55,accuracy:0.0001)
    }
    func testUpdatesUseOriginalGestureSnapshot() {
        let drag=CropInteraction(selection:box,start:.init(x:0.4,y:0.4))
        _=drag.updated(to:.init(x:0.45,y:0.45))
        let result=drag.updated(to:.init(x:0.5,y:0.5))
        XCTAssertEqual(result.x,0.3,accuracy:0.0001);XCTAssertEqual(result.y,0.35,accuracy:0.0001)
    }
    func testOffsetHandleGrabKeepsFingerOffsetInsteadOfJumping() {
        let start=CropPoint(x:0.62,y:0.4)
        let drag=CropInteraction(selection:box,start:start,toleranceX:0.03,toleranceY:0.03)
        XCTAssertEqual(drag.mode,.resize(.right))
        XCTAssertEqual(drag.updated(to:start).width,box.width,accuracy:0.0001)
        let result=drag.updated(to:.init(x:0.72,y:0.4))
        XCTAssertEqual(result.width,0.5,accuracy:0.0001)
        XCTAssertEqual(result.x,box.x);XCTAssertEqual(result.height,box.height)
    }
}
