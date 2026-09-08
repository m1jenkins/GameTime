#if DEBUG
import SwiftUI

/// Native paths from the supplied 24-unit Matchday icon references.
struct MatchdayMetricIcon: View {
    let metric: ChallengeV1Policy.Metric
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 24, y: size.height / 24)
            var path = Path()
            func line(_ points: [CGPoint]) {
                guard let first = points.first else { return }
                path.move(to: first); for point in points.dropFirst() { path.addLine(to: point) }
            }
            switch metric {
            case .steps:
                context.translateBy(x: 12, y: 12); context.rotate(by: .degrees(20)); context.translateBy(x: -12, y: -12)
                for (x, y) in [(4.0, 5.5), (14.0, 9.5)] {
                    line([CGPoint(x:x,y:y+4.5), CGPoint(x:x,y:y)])
                    path.addArc(center: CGPoint(x:x+2.5,y:y), radius:2.5, startAngle:.degrees(180), endAngle:.degrees(360), clockwise:false)
                    path.addLine(to:CGPoint(x:x+5,y:y+4.5));path.closeSubpath()
                    line([CGPoint(x:x,y:y+7.5),CGPoint(x:x+5,y:y+7.5),CGPoint(x:x+5,y:y+9.5)])
                    path.addArc(center:CGPoint(x:x+2.5,y:y+9.5),radius:2.5,startAngle:.zero,endAngle:.degrees(180),clockwise:false)
                    path.closeSubpath()
                }
            case .exercise:
                context.fill(Path(ellipseIn:CGRect(x:12.8,y:2.3,width:3.4,height:3.4)),with:.foreground)
                line([.init(x:7,y:9),.init(x:10,y:6),.init(x:14,y:9),.init(x:17,y:11),.init(x:20,y:9)])
                line([.init(x:13,y:8),.init(x:10,y:14),.init(x:15,y:16),.init(x:17,y:21)])
                line([.init(x:10,y:14),.init(x:6,y:20),.init(x:3,y:20)])
                line([.init(x:3,y:11),.init(x:6,y:11)]);line([.init(x:2,y:14),.init(x:5,y:14)])
            case .distance:
                path.addEllipse(in:CGRect(x:2.5,y:4.5,width:3,height:3));path.addEllipse(in:CGRect(x:18.5,y:16.5,width:3,height:3))
                line([.init(x:8,y:6),.init(x:17,y:6)])
                path.addArc(center:.init(x:17,y:10),radius:4,startAngle:.degrees(-90),endAngle:.degrees(90),clockwise:false)
                path.addLine(to:.init(x:7,y:14))
                path.addArc(center:.init(x:7,y:16),radius:2,startAngle:.degrees(-90),endAngle:.degrees(90),clockwise:true)
                path.addLine(to:.init(x:16,y:18));line([.init(x:8,y:10),.init(x:16,y:10)])
            case .timed:
                line([.init(x:10,y:2),.init(x:14,y:2)]);line([.init(x:12,y:2),.init(x:12,y:5)])
                line([.init(x:18.5,y:5.5),.init(x:20,y:4)])
                path.addEllipse(in:CGRect(x:4,y:5,width:16,height:16))
                path.move(to:.init(x:12,y:8));path.addArc(center:.init(x:12,y:13),radius:5,startAngle:.degrees(-90),endAngle:.zero,clockwise:true)
                line([.init(x:12,y:13),.init(x:15.5,y:9.5)])
            }
            context.stroke(path,with:.foreground,style:StrokeStyle(lineWidth:1.75,lineCap:.round,lineJoin:.round))
        }.frame(width:28,height:28).accessibilityHidden(true)
    }
}
#endif
