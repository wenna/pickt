import SwiftUI
import VisionKit
import PhotosUI
import Vision

enum ImportKind:String,Identifiable { case scanner,album,camera;var id:String{rawValue} }
struct ImageBatch:Identifiable { let id=UUID();let images:[UIImage] }

struct ImageImporter:UIViewControllerRepresentable {
    var kind:ImportKind
    var completion:([UIImage])->Void
    var failure:(String)->Void
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func makeUIViewController(context:Context)->UIViewController {
        if kind == .scanner && VNDocumentCameraViewController.isSupported { let vc=VNDocumentCameraViewController();vc.delegate=context.coordinator;return vc }
        if kind == .camera && UIImagePickerController.isSourceTypeAvailable(.camera) { let vc=UIImagePickerController();vc.sourceType = .camera;vc.delegate=context.coordinator;return vc }
        var configuration=PHPickerConfiguration(photoLibrary:.shared());configuration.filter = .images;configuration.selectionLimit=20
        let vc=PHPickerViewController(configuration:configuration);vc.delegate=context.coordinator;return vc
    }
    func updateUIViewController(_ controller:UIViewController,context:Context){}
    final class Coordinator:NSObject,VNDocumentCameraViewControllerDelegate,PHPickerViewControllerDelegate,UIImagePickerControllerDelegate,UINavigationControllerDelegate {
        let parent:ImageImporter
        init(_ parent:ImageImporter){self.parent=parent}
        func documentCameraViewController(_ controller:VNDocumentCameraViewController,didFinishWith scan:VNDocumentCameraScan){parent.completion((0..<scan.pageCount).map{scan.imageOfPage(at:$0).upright()})}
        func documentCameraViewControllerDidCancel(_ controller:VNDocumentCameraViewController){parent.completion([])}
        func documentCameraViewController(_ controller:VNDocumentCameraViewController,didFailWithError error:Error){parent.failure(error.localizedDescription)}
        func picker(_ picker:PHPickerViewController,didFinishPicking results:[PHPickerResult]) {
            guard !results.isEmpty else{parent.completion([]);return}
            let group=DispatchGroup(),lock=NSLock();var images:[Int:UIImage]=[:]
            for (index,result) in results.enumerated() where result.itemProvider.canLoadObject(ofClass:UIImage.self) {
                group.enter();result.itemProvider.loadObject(ofClass:UIImage.self){object,_ in defer{group.leave()};if let image=object as? UIImage{lock.lock();images[index]=image.upright();lock.unlock()}}
            }
            group.notify(queue:.main){let sorted=images.sorted{$0.key<$1.key}.map(\.value);if sorted.isEmpty{self.parent.failure("所选照片无法读取，请重新选择")}else{self.parent.completion(sorted)}}
        }
        func imagePickerController(_ picker:UIImagePickerController,didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]){parent.completion((info[.originalImage] as? UIImage).map{[$0.upright()]} ?? [])}
        func imagePickerControllerDidCancel(_ picker:UIImagePickerController){parent.completion([])}
    }
}

extension UIImage {
    func upright()->UIImage {
        let limit:CGFloat=3000,ratio=min(1,limit/max(size.width,size.height)),target=CGSize(width:size.width*ratio,height:size.height*ratio)
        let format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:target,format:format).image{_ in draw(in:CGRect(origin:.zero,size:target))}
    }
    func cropped(_ rect:NormalizedRect)->UIImage? {
        guard let cg=cgImage else{return nil}
        let box=CGRect(x:rect.x*Double(cg.width),y:rect.y*Double(cg.height),width:rect.width*Double(cg.width),height:rect.height*Double(cg.height)).intersection(CGRect(x:0,y:0,width:cg.width,height:cg.height))
        guard box.width>8,box.height>8,let cut=cg.cropping(to:box) else{return nil};return UIImage(cgImage:cut)
    }
    func rotated()->UIImage {
        let target=CGSize(width:size.height,height:size.width),format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:target,format:format).image{ctx in ctx.cgContext.translateBy(x:target.width/2,y:target.height/2);ctx.cgContext.rotate(by:.pi/2);draw(in:CGRect(x:-size.width/2,y:-size.height/2,width:size.width,height:size.height))}
    }
}

enum OCRService {
    static func recognize(_ image:UIImage) async throws -> String {
        guard let cg=image.cgImage else{throw LibraryError("无法读取作答图片")}
        return try await Task.detached(priority:.userInitiated){
            let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.usesLanguageCorrection=false
            let supported=try request.supportedRecognitionLanguages()
            request.recognitionLanguages=["zh-Hans","en-US"].filter{supported.contains($0)}
            try VNImageRequestHandler(cgImage:cg,options:[:]).perform([request])
            return (request.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
        }.value
    }
    static func suggestedTopics(_ text:String)->[String] {
        let rules=[("百分","百分数"),("%","百分数"),("圆","圆"),("π","圆"),("比例","比和比例"),("分数","分数运算"),("方程","方程"),("体积","面积与体积"),("统计","统计")]
        return Array(Set(rules.filter{text.contains($0.0)}.map(\.1))).sorted()
    }
}

struct CaptureHome:View {
    @EnvironmentObject var store:AppStore
    var completed:()->Void
    @State private var importer:ImportKind?
    @State private var batch:ImageBatch?
    @State private var manual=false
    var body:some View {
        NavigationView{VStack(spacing:20){EmptyHint(title:"把纸上的错题收好",detail:"扫描整页后框选题目。保留原图，可连续收录多道题。",icon:"camera.viewfinder")
            Button{importer=VNDocumentCameraViewController.isSupported ? .scanner : .camera}label:{Label("拍试卷",systemImage:"camera").frame(maxWidth:.infinity,minHeight:48)}.buttonStyle(.borderedProminent)
            Button{importer = .album}label:{Label("从相册导入",systemImage:"photo.on.rectangle").frame(maxWidth:.infinity,minHeight:48)}.buttonStyle(.bordered)
            Button("手动录入文字题"){manual=true};Text("识别文字仅用于辅助搜索；题图和公式以原图为准。").font(.footnote).foregroundColor(.secondary);Spacer()
        }.padding().navigationTitle("拍试卷")}.navigationViewStyle(.stack)
        .sheet(item:$importer){kind in ImageImporter(kind:kind){images in importer=nil;if !images.isEmpty{DispatchQueue.main.asyncAfter(deadline:.now()+0.35){batch=ImageBatch(images:images)}}}failure:{store.error=$0;importer=nil}}
        .fullScreenCover(item:$batch){item in CaptureFlow(images:item.images){batch=nil;completed()}}
        .sheet(isPresented:$manual){QuestionEditor(question:Question()){q in let saved=await store.change{try LibraryCommands.addQuestion(in:&$0,question:q)};if saved{completed()};return saved}}
    }
}

struct CaptureFlow:View {
    @EnvironmentObject var store:AppStore
    @State var images:[UIImage]
    var finish:()->Void
    @State private var page=0
    @State private var rect=NormalizedRect()
    @State private var draft=Question(classificationSource:"本地关键词建议；年级沿用六年级默认设置")
    @State private var source=SourceDocument(title:"拍摄试卷",pages:[])
    @State private var originalNames:[Int:String]=[:]
    @State private var editor=false
    @State private var processing=false
    @State private var savedCount=0
    @State private var editingFragment:Int?
    var body:some View {
        NavigationView{VStack(spacing:10){
            Text("一指框选，双指平移或缩放；同一题可添加多个片段。").font(.footnote).foregroundColor(.secondary)
            Picker("原卷页",selection:$page){ForEach(images.indices,id:\.self){Text("第 \($0+1) 页").tag($0)}}.pickerStyle(.segmented).onChange(of:page){_ in rect=NormalizedRect()}
            CropCanvas(image:images[page],rect:$rect).background(Color.secondary.opacity(0.08)).frame(maxWidth:.infinity,maxHeight:.infinity)
            HStack{Button("旋转本页"){images[page]=images[page].rotated();originalNames[page]=nil;rect=NormalizedRect()};Spacer();Button(processing ? "正在读取…" : "加入当前题片段"){addFragment()}.disabled(processing)}
            ScrollView(.horizontal){HStack{ForEach(Array(draft.fragments.enumerated()),id:\.element.id){index,fragment in Button{editingFragment=index}label:{VStack{AssetImage(name:fragment.asset).frame(width:90,height:70);Text("片段 \(index+1) · 可遮盖").font(.caption2)}}}}}.frame(height:draft.fragments.isEmpty ? 0 : 100)
            Button("下一步：分类保存（\(draft.fragments.count) 个片段）"){editor=true}.buttonStyle(.borderedProminent).disabled(draft.fragments.isEmpty || processing)
            Text("已保存 \(savedCount) 道题，保存后可继续选下一题").font(.caption).foregroundColor(.secondary)
        }.padding().navigationTitle("从试卷中选错题").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("完成"){finish()}}}}
        .navigationViewStyle(.stack)
        .sheet(isPresented:$editor){QuestionEditor(question:draft){question in
            do { for index in images.indices where originalNames[index] == nil { originalNames[index]=try store.saveImage(images[index]) } } catch { store.error=error.localizedDescription;return false }
            var document=source;document.pages=originalNames.sorted{$0.key<$1.key}.map(\.value)
            let success=await store.change{lib in if !lib.sources.contains(where:{$0.id==document.id}){lib.sources.append(document)}else if let index=lib.sources.firstIndex(where:{$0.id==document.id}){lib.sources[index].pages=document.pages};var q=question;q.sourceID=document.id;try LibraryCommands.addQuestion(in:&lib,question:q)}
            if success{savedCount+=1;draft=Question(subject:question.subject,grade:question.grade,classificationSource:"本地关键词建议；年级沿用本次设置");rect=NormalizedRect()};return success
        }}
        .sheet(isPresented:Binding(get:{editingFragment != nil},set:{if !$0{editingFragment=nil}})){
            if let index=editingFragment,index<draft.fragments.count,let url=store.imageURL(draft.fragments[index].asset),let image=UIImage(contentsOfFile:url.path){MaskEditor(image:image){updated in do{draft.fragments[index].asset=try store.saveImage(updated);editingFragment=nil}catch{store.error=error.localizedDescription}}}
        }
    }
    private func addFragment(){
        guard let cropped=images[page].cropped(rect)else{store.error="框选范围太小，请重新选择";return}
        do{
            let original=try originalNames[page] ?? store.saveImage(images[page]);originalNames[page]=original
            draft.fragments.append(QuestionFragment(asset:try store.saveImage(cropped),originalAsset:original,crop:rect))
            processing=true
            Task{do{let text=try await OCRService.recognize(cropped);draft.text += (draft.text.isEmpty ? "" : "\n")+text;draft.topics=Array(Set(draft.topics+OCRService.suggestedTopics(text))).sorted()}catch{store.error="题图已保留，文字识别失败，可手动填写。"};processing=false}
        }catch{store.error=error.localizedDescription}
    }
}

struct CropCanvas:UIViewRepresentable {
    var image:UIImage
    @Binding var rect:NormalizedRect
    func makeUIView(context:Context)->CropSurface { let view=CropSurface();view.changed={rect=$0};return view }
    func updateUIView(_ view:CropSurface,context:Context){view.changed={rect=$0};view.set(image:image,selection:rect)}
}
final class CropSurface:UIView,UIScrollViewDelegate {
    private let scroll=UIScrollView(),picture=UIImageView(),selectionLayer=CAShapeLayer()
    private var start=CGPoint.zero,selected=NormalizedRect(),needsFit=true
    var changed:((NormalizedRect)->Void)?
    override init(frame:CGRect){super.init(frame:frame);addSubview(scroll);scroll.addSubview(picture);scroll.delegate=self;scroll.panGestureRecognizer.minimumNumberOfTouches=2;picture.isUserInteractionEnabled=true;picture.layer.addSublayer(selectionLayer);selectionLayer.strokeColor=UIColor.systemBlue.cgColor;selectionLayer.fillColor=UIColor.systemBlue.withAlphaComponent(0.12).cgColor;let pan=UIPanGestureRecognizer(target:self,action:#selector(selectArea(_:)));pan.maximumNumberOfTouches=1;picture.addGestureRecognizer(pan)}
    required init?(coder:NSCoder){fatalError("init(coder:) is unsupported")}
    func set(image:UIImage,selection:NormalizedRect){if picture.image !== image{scroll.minimumZoomScale=min(scroll.minimumZoomScale,1);scroll.maximumZoomScale=max(scroll.maximumZoomScale,1);scroll.setZoomScale(1,animated:false);picture.transform = .identity;picture.image=image;picture.bounds=CGRect(origin:.zero,size:image.size);picture.center=CGPoint(x:image.size.width/2,y:image.size.height/2);scroll.contentSize=image.size;scroll.contentOffset = .zero;needsFit=true};selected=selection;setNeedsLayout()}
    override func layoutSubviews(){super.layoutSubviews();scroll.frame=bounds;if needsFit,bounds.width>0,bounds.height>0,let image=picture.image{let scale=min(bounds.width/image.size.width,bounds.height/image.size.height);scroll.minimumZoomScale=scale;scroll.maximumZoomScale=scale*6;scroll.zoomScale=scale;needsFit=false};drawSelection()}
    func viewForZooming(in scrollView:UIScrollView)->UIView?{picture}
    func scrollViewDidZoom(_ scrollView:UIScrollView){drawSelection()}
    private func drawSelection(){let size=picture.bounds.size;selectionLayer.lineWidth=2/max(scroll.zoomScale,0.01);selectionLayer.path=UIBezierPath(rect:CGRect(x:selected.x*size.width,y:selected.y*size.height,width:selected.width*size.width,height:selected.height*size.height)).cgPath}
    @objc private func selectArea(_ gesture:UIPanGestureRecognizer){let point=gesture.location(in:picture),size=picture.bounds.size;guard size.width>0,size.height>0 else{return};let p=CGPoint(x:min(max(0,point.x),size.width),y:min(max(0,point.y),size.height));if gesture.state == .began{start=p};let r=NormalizedRect(x:min(start.x,p.x)/size.width,y:min(start.y,p.y)/size.height,width:abs(p.x-start.x)/size.width,height:abs(p.y-start.y)/size.height);selected=r;drawSelection();if gesture.state == .ended{changed?(r)}}
}

struct MaskEditor:View {
    @Environment(\.dismiss) var dismiss
    @State var image:UIImage
    var save:(UIImage)->Void
    @State private var rect=NormalizedRect()
    @State private var undo:[UIImage]=[]
    var body:some View {NavigationView{VStack{Text("框选要遮盖的笔迹后点遮盖。遮住题干时请撤销。原图始终保留。").font(.footnote);CropCanvas(image:image,rect:$rect);HStack{Button("撤销"){if let previous=undo.popLast(){image=previous}}.disabled(undo.isEmpty);Spacer();Button("用白色遮盖所选区域"){undo.append(image);if undo.count>6{undo.removeFirst()};let original=image;let format=UIGraphicsImageRendererFormat();format.scale=1;image=UIGraphicsImageRenderer(size:image.size,format:format).image{ctx in original.draw(at:.zero);UIColor.white.setFill();ctx.fill(CGRect(x:rect.x*original.size.width,y:rect.y*original.size.height,width:rect.width*original.size.width,height:rect.height*original.size.height))}}}.padding()}.padding().navigationTitle("手动遮盖").toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("保留修改"){save(image);dismiss()}}}}.navigationViewStyle(.stack)}
}
