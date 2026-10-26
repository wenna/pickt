import Foundation

public struct CropPoint:Equatable {
    public var x:Double
    public var y:Double
    public init(x:Double,y:Double){self.x=x;self.y=y}
}
public enum CropHandle:CaseIterable,Equatable {
    case topLeft,top,topRight,right,bottomRight,bottom,bottomLeft,left
    public func point(in r:NormalizedRect)->CropPoint {
        let x = self == .topLeft || self == .left || self == .bottomLeft ? r.x : self == .topRight || self == .right || self == .bottomRight ? r.x+r.width : r.x+r.width/2
        let y = self == .topLeft || self == .top || self == .topRight ? r.y : self == .bottomLeft || self == .bottom || self == .bottomRight ? r.y+r.height : r.y+r.height/2
        return CropPoint(x:x,y:y)
    }
    var changesLeft:Bool{self == .topLeft || self == .left || self == .bottomLeft}
    var changesRight:Bool{self == .topRight || self == .right || self == .bottomRight}
    var changesTop:Bool{self == .topLeft || self == .top || self == .topRight}
    var changesBottom:Bool{self == .bottomLeft || self == .bottom || self == .bottomRight}
}
public struct CropInteraction {
    public enum Mode:Equatable {case create,move,resize(CropHandle)}
    public let original:NormalizedRect
    public let start:CropPoint
    public let mode:Mode
    private let minimumWidth:Double
    private let minimumHeight:Double
    public init(selection:NormalizedRect,start:CropPoint,toleranceX:Double=0.025,toleranceY:Double=0.025,minimumWidth:Double=0.01,minimumHeight:Double=0.01,drawOnly:Bool=false) {
        self.original=selection;self.start=start
        self.minimumWidth=min(max(minimumWidth,0.001),selection.width)
        self.minimumHeight=min(max(minimumHeight,0.001),selection.height)
        if drawOnly {mode = .create;return}
        // Corner handles win overlapping hit regions on small selections.
        let handles:[CropHandle]=[.topLeft,.topRight,.bottomLeft,.bottomRight,.top,.right,.bottom,.left]
        if let handle=handles.first(where:{let p=$0.point(in:selection);return abs(p.x-start.x)<=toleranceX && abs(p.y-start.y)<=toleranceY}) {mode = .resize(handle);return}
        let full=selection.x<=0.001 && selection.y<=0.001 && selection.width>=0.999 && selection.height>=0.999
        let inside=start.x>=selection.x && start.x<=selection.x+selection.width && start.y>=selection.y && start.y<=selection.y+selection.height
        mode=inside && !full ? .move:.create
    }
    public func updated(to point:CropPoint)->NormalizedRect {
        func clamp(_ value:Double,_ lower:Double=0,_ upper:Double=1)->Double { min(max(value,lower),upper) }
        let p=CropPoint(x:clamp(point.x),y:clamp(point.y))
        switch mode {
        case .create:
            return NormalizedRect(x:min(start.x,p.x),y:min(start.y,p.y),width:abs(p.x-start.x),height:abs(p.y-start.y))
        case .move:
            return NormalizedRect(x:clamp(original.x+point.x-start.x,0,1-original.width),y:clamp(original.y+point.y-start.y,0,1-original.height),width:original.width,height:original.height)
        case .resize(let handle):
            var left=original.x,top=original.y,right=original.x+original.width,bottom=original.y+original.height
            let dx=point.x-start.x,dy=point.y-start.y
            if handle.changesLeft {left=clamp(left+dx,0,right-minimumWidth)}
            if handle.changesRight {right=clamp(right+dx,left+minimumWidth,1)}
            if handle.changesTop {top=clamp(top+dy,0,bottom-minimumHeight)}
            if handle.changesBottom {bottom=clamp(bottom+dy,top+minimumHeight,1)}
            let width=handle.changesLeft || handle.changesRight ? right-left:original.width
            let height=handle.changesTop || handle.changesBottom ? bottom-top:original.height
            return NormalizedRect(x:left,y:top,width:width,height:height)
        }
    }
}
