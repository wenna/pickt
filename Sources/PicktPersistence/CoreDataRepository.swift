import Foundation
import CoreData
#if SWIFT_PACKAGE
import PicktCore
#endif

public protocol LibraryRepository { func load() throws -> StudyLibrary; func save(_ library: StudyLibrary) throws }

/// Metadata is split into versioned question, paper, source and catalog records.
/// Image bytes are stored exclusively in AssetStore. All writes use one context.
public final class CoreDataRepository: LibraryRepository {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    private let encoder=JSONEncoder(),decoder=JSONDecoder()
    public init(url: URL) throws {
        let model=NSManagedObjectModel();model.versionIdentifiers=["PicktSchema1"]
        model.entities=["QuestionRecord","PaperRecord","SourceRecord","CatalogRecord"].map { name in
            let entity=NSEntityDescription();entity.name=name;entity.managedObjectClassName="NSManagedObject"
            let key=NSAttributeDescription();key.name="key";key.attributeType = .stringAttributeType;key.isOptional=false
            let payload=NSAttributeDescription();payload.name="payload";payload.attributeType = .binaryDataAttributeType;payload.isOptional=false
            entity.properties=[key,payload];entity.uniquenessConstraints=[["key"]];return entity
        }
        container=NSPersistentContainer(name:"Pickt",managedObjectModel:model)
        let description=NSPersistentStoreDescription(url:url);description.shouldAddStoreAsynchronously=false
        description.shouldMigrateStoreAutomatically=true;description.shouldInferMappingModelAutomatically=true
        container.persistentStoreDescriptions=[description]
        var failure: Error?;container.loadPersistentStores { _,error in failure=error }
        if let failure=failure { throw failure }
        context=container.newBackgroundContext();context.mergePolicy=NSErrorMergePolicy
    }
    private func perform<T>(_ body: () throws -> T) throws -> T {
        var result: Result<T,Error>!
        context.performAndWait { result=Result { try body() } }
        return try result.get()
    }
    private func records<T:Decodable>(_ entity: String,as type:T.Type) throws -> [T] {
        try context.fetch(NSFetchRequest<NSManagedObject>(entityName:entity)).map { object in
            guard let data=object.value(forKey:"payload") as? Data else { throw LibraryError("本地资料损坏，请保留文件并恢复备份") }
            return try decoder.decode(type,from:data)
        }
    }
    public func load() throws -> StudyLibrary {
        try perform {
            let catalogs:[StudyLibrary]=try records("CatalogRecord",as:StudyLibrary.self)
            let count=try ["QuestionRecord","PaperRecord","SourceRecord"].reduce(0) { try $0 + context.count(for:NSFetchRequest<NSFetchRequestResult>(entityName:$1)) }
            if catalogs.isEmpty && count==0 { return StudyLibrary() }
            guard catalogs.count==1 else { throw LibraryError("资料目录损坏，已停止载入") }
            var library=catalogs[0]
            library.questions=try records("QuestionRecord",as:Question.self)
            library.papers=try records("PaperRecord",as:Paper.self)
            library.sources=try records("SourceRecord",as:SourceDocument.self)
            try LibraryCommands.validate(library);return library
        }
    }
    public func save(_ library: StudyLibrary) throws {
        try LibraryCommands.validate(library)
        try perform {
            do {
                func replace<T:Encodable>(_ values:[T],keys:[String],entity:String) throws {
                    let existing=try context.fetch(NSFetchRequest<NSManagedObject>(entityName:entity))
                    let byKey=Dictionary(uniqueKeysWithValues:existing.compactMap { object -> (String,NSManagedObject)? in
                        guard let key=object.value(forKey:"key") as? String else { return nil };return (key,object)
                    })
                    for object in existing where !keys.contains(object.value(forKey:"key") as? String ?? "") { context.delete(object) }
                    for (index,key) in keys.enumerated() {
                        let object=byKey[key] ?? NSEntityDescription.insertNewObject(forEntityName:entity,into:context)
                        object.setValue(key,forKey:"key");object.setValue(try encoder.encode(values[index]),forKey:"payload")
                    }
                }
                try replace(library.questions,keys:library.questions.map{$0.id.uuidString},entity:"QuestionRecord")
                try replace(library.papers,keys:library.papers.map{$0.id.uuidString},entity:"PaperRecord")
                try replace(library.sources,keys:library.sources.map{$0.id.uuidString},entity:"SourceRecord")
                var metadata=library;metadata.questions=[];metadata.papers=[];metadata.sources=[]
                try replace([metadata],keys:["library"],entity:"CatalogRecord")
                try context.save();context.reset()
            } catch { context.rollback();throw error }
        }
    }
}

public actor LibraryService {
    private let repository: LibraryRepository
    private var library: StudyLibrary
    private var revision=0
    public init(repository: LibraryRepository) throws { self.repository=repository;library=try repository.load() }
    public func snapshot() -> (StudyLibrary,Int) { (library,revision) }
    public func transact(_ mutation: (inout StudyLibrary) throws -> Void) throws -> (StudyLibrary,Int) {
        var candidate=library;try mutation(&candidate);try repository.save(candidate)
        library=candidate;revision+=1;return (library,revision)
    }
    public func replace(_ candidate: StudyLibrary) throws -> (StudyLibrary,Int) {
        try repository.save(candidate);library=candidate;revision+=1;return (library,revision)
    }
}
