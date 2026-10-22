import UIKit
import SwiftUI
import PDFKit

enum PDFPart:String,CaseIterable,Identifiable {case student,parent,all;var id:String{rawValue};var title:String{self == .student ? "学生练习卷" : self == .parent ? "家长参考页" : "学生卷与家长页"}}
enum PDFService {
    static let bounds=CGRect(x:0,y:0,width:595.28,height:841.89)
    static let left:Double=36,width:Double=523.28,top:Double=100,bottom:Double=794
    static func makePlan(paper:Paper,layout:PaperLayout,assets:AssetStore,parent:Bool=false)throws->[PagePlacement] {
        if !parent && !layout.placements.isEmpty { return layout.placements }
        var plan:[PagePlacement]=[],page=0,y=top
        func nextPage(){page+=1;y=top}
        func add(_ question:UUID,kind:String,height:Double,fragment:Int = -1,offset:Double = 0,text:String = ""){
            if y+height>bottom{nextPage()}
            plan.append(PagePlacement(questionID:question,page:page,kind:kind,fragment:fragment,x:left,y:y,width:width,height:height,offset:offset,text:text));y+=height
        }
        for (index,id) in layout.questionOrder.enumerated() {
            guard let q=paper.questions.first(where:{$0.id==id})else{throw LibraryError("卷面题目顺序损坏")}
            if bottom-y<160{nextPage()}
            add(id,kind:"number",height:24,text:"第 \(index+1) 题")
            if q.fragments.isEmpty {
                let chunks=chunk(q.text,limit:500)
                for text in chunks{let height=textHeight(text,font:.systemFont(ofSize:14));add(id,kind:"text",height:height,text:text)}
            } else {
                for (part,f) in q.fragments.enumerated(){
                    guard let image=UIImage(contentsOfFile:try assets.url(for:f.asset).path),image.size.width>0 else{throw LibraryError("题图无法读取，未生成不完整试卷")}
                    let scaled=Double(image.size.height/image.size.width)*width
                    var offset:Double=0
                    while offset<scaled {
                        if bottom-y<40{nextPage();add(id,kind:"number",height:24,text:"第 \(index+1) 题（续）")}
                        let height=min(bottom-y,scaled-offset)
                        add(id,kind:"image",height:height,fragment:part,offset:offset);offset+=height
                    }
                    y+=8
                }
            }
            if parent {
                let answer="参考答案："+(q.answer.isEmpty ? "尚未添加答案" : q.answer)+(q.explanation.isEmpty ? "" : "\n解析："+q.explanation)
                for text in chunk(answer,limit:500){add(id,kind:"answer",height:textHeight(text,font:.systemFont(ofSize:12)),text:text)}
            } else {
                var remaining=layout.space.points
                while remaining>0 {if bottom-y<20{nextPage()};let height=min(remaining,bottom-y);add(id,kind:"space",height:height);remaining-=height}
            }
            y+=18
        }
        return plan
    }
    static func write(paper:Paper,layout:PaperLayout,assets:AssetStore,part:PDFPart,duplex:Bool)throws->URL {
        for fragment in paper.questions.flatMap(\.fragments) {
            guard UIImage(contentsOfFile:try assets.url(for:fragment.asset).path) != nil else { throw LibraryError("题图无法读取，未生成不完整试卷") }
        }
        let student=try makePlan(paper:paper,layout:layout,assets:assets),parent=try makePlan(paper:paper,layout:layout,assets:assets,parent:true)
        let studentCount=(student.map(\.page).max() ?? 0)+1
        var sections:[([PagePlacement],Bool)]=[]
        if part != .parent {sections.append((student,false))}
        if part != .student {sections.append((parent,true))}
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("拾题-\(paper.serial)-\(UUID().uuidString.prefix(6)).pdf")
        try UIGraphicsPDFRenderer(bounds:bounds).writePDF(to:url){context in
            for (sectionIndex,section) in sections.enumerated(){
                if sectionIndex==1 && duplex && studentCount%2==1{context.beginPage()}
                let count=(section.0.map(\.page).max() ?? 0)+1
                for page in 0..<count {
                    context.beginPage()
                    draw(paper.title,frame:CGRect(x:36,y:30,width:523,height:28),font:.boldSystemFont(ofSize:18))
                    let kind=section.1 ? "家长参考页 · 含答案，请与学生卷分开" : "学生练习卷 · 姓名：________ 日期：________"
                    draw(kind,frame:CGRect(x:36,y:60,width:523,height:20),font:.systemFont(ofSize:10))
                    for block in section.0 where block.page==page {
                        let frame=CGRect(x:block.x,y:block.y,width:block.width,height:block.height)
                        if block.kind=="image",let q=paper.questions.first(where:{$0.id==block.questionID}),q.fragments.indices.contains(block.fragment),let path=try? assets.url(for:q.fragments[block.fragment].asset),let image=UIImage(contentsOfFile:path.path) {
                            context.cgContext.saveGState();context.cgContext.clip(to:frame)
                            image.draw(in:CGRect(x:frame.minX,y:frame.minY-block.offset,width:frame.width,height:frame.width*image.size.height/image.size.width))
                            context.cgContext.restoreGState()
                        }else if block.kind != "space" {draw(block.text,frame:frame,font:block.kind=="number" ? .boldSystemFont(ofSize:13) : .systemFont(ofSize:block.kind=="answer" ? 12 : 14))}
                    }
                    draw("卷号 \(paper.id.uuidString.prefix(8)) · 排版 \(layout.revision) · \(page+1)/\(count)",frame:CGRect(x:36,y:810,width:523,height:16),font:.systemFont(ofSize:9))
                }
            }
        };return url
    }
    private static func chunk(_ text:String,limit:Int)->[String]{var parts:[String]=[],remaining=text[...];while !remaining.isEmpty{let end=remaining.index(remaining.startIndex,offsetBy:min(limit,remaining.count));parts.append(String(remaining[..<end]));remaining=remaining[end...]};return parts.isEmpty ? ["（题目内容待补充）"] : parts}
    private static func textHeight(_ text:String,font:UIFont)->Double{Double((text as NSString).boundingRect(with:CGSize(width:width,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font],context:nil).height.rounded(.up))+8}
    private static func draw(_ text:String,frame:CGRect,font:UIFont){let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byWordWrapping;(text as NSString).draw(in:frame,withAttributes:[.font:font,.foregroundColor:UIColor.black,.paragraphStyle:paragraph])}
}
struct PDFPreview:UIViewRepresentable {
    var url:URL
    func makeUIView(context:Context)->PDFView{let view=PDFView();view.autoScales=true;view.displayMode = .singlePageContinuous;view.document=PDFDocument(url:url);return view}
    func updateUIView(_ view:PDFView,context:Context){if view.document?.documentURL != url{view.document=PDFDocument(url:url)}}
}
struct SharedFile:Identifiable{let id=UUID();let url:URL}
struct ShareSheet:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:[url],applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context){}
}
enum Printer {
    @MainActor static func present(_ url:URL,duplex:Bool,error:@escaping(String)->Void){
        let controller=UIPrintInteractionController.shared,info=UIPrintInfo(dictionary:nil);info.jobName="拾题练习卷";info.outputType = .general;info.duplex=duplex ? .longEdge : .none;controller.printInfo=info;controller.printingItem=url
        let callback:(UIPrintInteractionController, Bool, Error?) -> Void={_,_,failure in if let failure=failure{error(failure.localizedDescription)}}
        if UIDevice.current.userInterfaceIdiom == .pad,let scene=UIApplication.shared.connectedScenes.first as? UIWindowScene,let root=scene.windows.first(where:{$0.isKeyWindow})?.rootViewController?.view{controller.present(from:CGRect(x:root.bounds.midX,y:root.bounds.midY,width:1,height:1),in:root,animated:true,completionHandler:callback)}else{controller.present(animated:true,completionHandler:callback)}
    }
}
