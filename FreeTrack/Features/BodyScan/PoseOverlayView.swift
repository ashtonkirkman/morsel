import SwiftUI

/// Photo with the person mask tinted and the skeleton drawn on top with `Canvas`. Works with or without a mask,
/// so stored scans (keypoints only) render the same way as fresh analyses.
struct PoseOverlayView: View {
    let image: UIImage
    let keypoints: BodyKeypoints?
    var maskImage: UIImage?
    var showsMask = true

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                Canvas { context, size in
                    guard image.size.width > 0, image.size.height > 0 else { return }
                    let rect = CGRect(origin: .zero, size: size)
                    if showsMask, let maskImage {
                        context.draw(Image(uiImage: maskImage), in: rect)
                    }
                    guard let kp = keypoints, kp.imageWidth > 0, kp.imageHeight > 0 else { return }
                    let sx = size.width / CGFloat(kp.imageWidth), sy = size.height / CGFloat(kp.imageHeight)
                    func point(_ joint: BodyJoint) -> CGPoint? {
                        guard let p = kp[joint], p.confidence >= 0.2 else { return nil }
                        return CGPoint(x: CGFloat(p.x) * sx, y: CGFloat(p.y) * sy)
                    }
                    var bones = Path()
                    for (a, b) in BodyJoint.connections {
                        guard let pa = point(a), let pb = point(b) else { continue }
                        bones.move(to: pa)
                        bones.addLine(to: pb)
                    }
                    context.stroke(bones, with: .color(Color.mAccent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    for joint in kp.joints {
                        guard let p = point(joint.joint) else { continue }
                        let r: CGFloat = 4
                        let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                        context.fill(dot, with: .color(.white))
                        context.stroke(dot, with: .color(Color.mAccent), lineWidth: 1.5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityLabel("Body scan photo with detected joints")
    }
}
