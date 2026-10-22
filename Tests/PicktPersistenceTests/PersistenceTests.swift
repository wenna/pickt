import XCTest
import PicktCore
@testable import PicktPersistence

final class PersistenceTests: XCTestCase {
    func temporaryDirectory() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) };return url
    }
    func testCoreDataRoundTripAndInvalidWriteRetainsOldLibrary() throws {
        let directory=try temporaryDirectory(),url=directory.appendingPathComponent("library.sqlite")
        let repo=try CoreDataRepository(url:url)
        var library=StudyLibrary();library.questions=[Question(text:"Original")];try repo.save(library)
        XCTAssertEqual(try repo.load(),library)
        var invalid=library;invalid.schemaVersion=99
        XCTAssertThrowsError(try repo.save(invalid))
        XCTAssertEqual(try repo.load(),library)
        XCTAssertEqual(try CoreDataRepository(url:url).load(),library)
    }
    func testUnsafeAssetsCannotReadOrWriteOutsideStore() throws {
        let assets=try AssetStore(root:temporaryDirectory())
        XCTAssertThrowsError(try assets.url(for:"../test.jpg"))
        XCTAssertThrowsError(try assets.write(Data([1,2]),name:"../../test.png"))
        let name=UUID().uuidString+".jpg";try assets.write(Data([1,2,3]),name:name)
        XCTAssertEqual(try Data(contentsOf:assets.url(for:name)),Data([1,2,3]))
    }
    func testBackupRoundTripAndTamperingIsRejected() throws {
        let root=try temporaryDirectory(),assets=try AssetStore(root:root.appendingPathComponent("source"))
        let name=UUID().uuidString+".jpg";try assets.write(Data([1,2,3]),name:name)
        var library=StudyLibrary();library.questions=[Question(fragments:[QuestionFragment(asset:name,originalAsset:name)])]
        let backup=try BackupArchive.export(library:library,assets:assets,to:root.appendingPathComponent("Test.picktbackup"))
        XCTAssertEqual(try BackupArchive.inspect(backup).library,library)
        try Data([4,5,6]).write(to:backup.appendingPathComponent("assets").appendingPathComponent(name))
        XCTAssertThrowsError(try BackupArchive.inspect(backup))
    }
    func testMissingAssetPreventsBackupRatherThanProducingIncompleteArchive() throws {
        let root=try temporaryDirectory(),assets=try AssetStore(root:root.appendingPathComponent("images"))
        let name=UUID().uuidString+".jpg"
        var library=StudyLibrary();library.questions=[Question(fragments:[QuestionFragment(asset:name,originalAsset:name)])]
        XCTAssertThrowsError(try BackupArchive.export(library:library,assets:assets,to:root.appendingPathComponent("Invalid.picktbackup")))
    }
    func testChangedBackupCannotInstallDifferentValidatedBytes() throws {
        let root=try temporaryDirectory(),a=try AssetStore(root:root.appendingPathComponent("a")),b=try AssetStore(root:root.appendingPathComponent("b")),target=try AssetStore(root:root.appendingPathComponent("target"))
        let name=UUID().uuidString+".jpg";try a.write(Data([1]),name:name);try b.write(Data([2]),name:name)
        var library=StudyLibrary();library.questions=[Question(fragments:[QuestionFragment(asset:name,originalAsset:name)])]
        let archiveA=try BackupArchive.export(library:library,assets:a,to:root.appendingPathComponent("A.picktbackup"))
        let archiveB=try BackupArchive.export(library:library,assets:b,to:root.appendingPathComponent("B.picktbackup"))
        XCTAssertThrowsError(try BackupArchive.installAssets(from:archiveB,manifest:BackupArchive.inspect(archiveA),into:target))
        XCTAssertFalse(FileManager.default.fileExists(atPath:try target.url(for:name).path))
    }
    func testFailedSaveDoesNotPublishCandidateSnapshot() async throws {
        final class FailureRepository:LibraryRepository {
            func load()throws->StudyLibrary{StudyLibrary()}
            func save(_ library:StudyLibrary)throws{throw LibraryError("Injected disk error")}
        }
        let service=try LibraryService(repository:FailureRepository())
        do { _ = try await service.transact{$0.questions=[Question(text:"unsaved")]};XCTFail("Save should fail") } catch {}
        let (snapshot,revision)=await service.snapshot();XCTAssertTrue(snapshot.questions.isEmpty);XCTAssertEqual(revision,0)
    }
}
