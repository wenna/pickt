import XCTest
@testable import PicktCore

final class SegmentationTests:XCTestCase {
    func testCoordinatesAndFormulaText() throws {
        let items=try Segmentation.decode(#"{"questions":[{"number":"1","text":"2/3 × 9/10","boxes":[[100,200,900,400]]}]}"#)
        XCTAssertEqual(items[0].regions[0].x,0.1)
        XCTAssertEqual(items[0].regions[0].height,0.2,accuracy:0.0001)
        XCTAssertEqual(items[0].text,"2/3 × 9/10")
    }
    func testRejectsBadCoordinatesAndEmptyOutput() {
        for box in ["[-1,0,900,400]","[900,0,100,400]","[0,0,1001,400]","[0,0,0,400]"] {
            XCTAssertThrowsError(try Segmentation.decode("{\"questions\":[{\"number\":\"1\",\"text\":\"\",\"boxes\":[\(box)]}]}"))
        }
        XCTAssertThrowsError(try Segmentation.decode(#"{"questions":[]}"#))
    }
    func testNestedMergeUndoKeepsOriginalEditedRegions() throws {
        var session=CaptureSession()
        let first=CaptureCandidate(page:0,number:"1",text:"a",regions:[.init(x:0.1,y:0.2,width:0.3,height:0.2)])
        let second=CaptureCandidate(page:1,number:"2",text:"b",regions:[.init()])
        session.candidates=[first,second];session.selected=[first.id,second.id]
        session.merge();let merged=try XCTUnwrap(session.candidates.first)
        XCTAssertEqual(merged.pieces.count,2);XCTAssertEqual(merged.pieces[1].page,1)
        session.unmerge(merged.id);session.unmerge(merged.id)
        XCTAssertEqual(session.candidates,[first,second]);XCTAssertEqual(session.selected.count,2)
    }
    func testReplacingOnePagePreservesOtherSelection() {
        var s=CaptureSession();let other=CaptureCandidate(page:1,number:"2",text:"",regions:[.init()])
        s.candidates=[other];s.selected=[other.id]
        s.append([CaptureCandidate(page:0,number:"1",text:"",regions:[.init()])])
        XCTAssertTrue(s.selected.contains(other.id));XCTAssertEqual(s.candidates.count,2)
    }
    func testUnmergeNonAdjacentRestoresReadingOrder() {
        var s=CaptureSession()
        let a=CaptureCandidate(page:0,number:"1",text:"",regions:[.init()]),b=CaptureCandidate(page:0,number:"2",text:"",regions:[.init()]),c=CaptureCandidate(page:1,number:"3",text:"",regions:[.init()])
        s.candidates=[a,b,c];s.selected=[a.id,c.id];s.merge();let merged=s.candidates[0].id
        s.selected.insert(b.id);s.merge();s.unmerge(s.candidates[0].id);s.unmerge(merged)
        XCTAssertEqual(s.candidates,[a,b,c]);XCTAssertEqual(s.selected.count,3)
    }
}
