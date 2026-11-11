import Foundation

public struct CapturePiece:Equatable {
    public var page:Int
    public var rect:NormalizedRect
    public init(page:Int,rect:NormalizedRect){self.page=page;self.rect=rect}
}
public struct CaptureCandidate:Identifiable,Equatable {
    public var id=UUID()
    public var number:String
    public var text:String
    public var pieces:[CapturePiece]
    public var originals:[CaptureCandidate]=[]
    public var regions:[NormalizedRect]{pieces.map(\.rect)}
    public init(page:Int,number:String,text:String,regions:[NormalizedRect]){self.number=number;self.text=text;self.pieces=regions.map{CapturePiece(page:page,rect:$0)}}
}
public struct CaptureSession {
    public var candidates:[CaptureCandidate]=[]
    public var selected:Set<UUID>=[]
    public init(){}
    public mutating func append(_ values:[CaptureCandidate]){candidates.append(contentsOf:values)}
    public mutating func toggle(_ id:UUID){guard candidates.contains(where:{$0.id==id}) else{return};if !selected.insert(id).inserted{selected.remove(id)}}
    public mutating func merge(){
        let items=candidates.filter{selected.contains($0.id)};guard items.count>1 else{return}
        var merged=items[0];merged.id=UUID();merged.originals=items;merged.pieces=items.flatMap(\.pieces)
        merged.number=items.map(\.number).joined(separator:"＋");merged.text=items.map(\.text).joined(separator:"\n")
        let index=candidates.firstIndex{$0.id==items[0].id} ?? 0
        candidates.removeAll{selected.contains($0.id)};candidates.insert(merged,at:min(index,candidates.count));selected=[merged.id]
    }
    public mutating func unmerge(_ id:UUID){
        guard let index=candidates.firstIndex(where:{$0.id==id}),!candidates[index].originals.isEmpty else{return}
        let originals=candidates[index].originals,wasSelected=selected.remove(id) != nil
        candidates.replaceSubrange(index...index,with:originals);if wasSelected{selected.formUnion(originals.map(\.id))}
    }
    public mutating func remove(_ id:UUID){candidates.removeAll{$0.id==id};selected.remove(id)}
}
public enum Segmentation {
    private struct Output:Decodable{var questions:[Item]}
    private struct Item:Decodable{var number:String;var text:String;var boxes:[[Double]]}
    public static func decode(_ content:String,page:Int=0)throws->[CaptureCandidate]{
        var clean=content.trimmingCharacters(in:.whitespacesAndNewlines)
        if clean.hasPrefix("```"),let first=clean.firstIndex(of:"\n"),clean.hasSuffix("```"){clean=String(clean[clean.index(after:first)..<clean.index(clean.endIndex,offsetBy:-3)])}
        guard let bytes=clean.data(using:.utf8),bytes.count<500_000 else{throw LibraryError("分题输出过大或无效，请手动框选")}
        let result:Output
        do{result=try JSONDecoder().decode(Output.self,from:bytes)}catch{throw LibraryError("分题格式无法读取，请重试或手动框选")}
        guard !result.questions.isEmpty,result.questions.count<=80 else{throw LibraryError("没有可靠的题目范围，请手动框选")}
        return try result.questions.map{item in
            guard item.number.count<=80,item.text.count<=20000,!item.boxes.isEmpty,item.boxes.count<=12 else{throw LibraryError("题目范围异常，请手动框选")}
            let rects=try item.boxes.map{b -> NormalizedRect in
                guard b.count==4,b.allSatisfy({$0.isFinite && $0>=0 && $0<=1000}),b[2]-b[0]>=3,b[3]-b[1]>=3 else{throw LibraryError("分题坐标异常，请重试或手动框选")}
                return NormalizedRect(x:b[0]/1000,y:b[1]/1000,width:(b[2]-b[0])/1000,height:(b[3]-b[1])/1000)
            }
            return CaptureCandidate(page:page,number:item.number,text:item.text,regions:rects)
        }
    }
}
