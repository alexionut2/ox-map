import UIKit
import OxydeCore

/// Draws the driver's marker for each `VehicleIcon`, pointing up (north), so either map
/// engine can rotate it to the travel direction.
enum VehicleIconRenderer {
    static let size = CGSize(width: 48, height: 48)

    private static var cache: [String: UIImage] = [:]

    static func image(for icon: VehicleIcon, tint: UIColor) -> UIImage {
        let key = "\(icon.rawValue)-\(tint.description)"
        if let img = cache[key] { return img }
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            g.setShadow(offset: .zero, blur: 10, color: tint.withAlphaComponent(0.85).cgColor)
            draw(icon, tint: tint, in: g)
        }
        cache[key] = img
        return img
    }

    private static func draw(_ icon: VehicleIcon, tint: UIColor, in g: CGContext) {
        let white = UIColor.white
        let dark = UIColor(white: 0.08, alpha: 1)
        func round(_ r: CGRect, _ radius: CGFloat, _ color: UIColor) {
            color.setFill(); UIBezierPath(roundedRect: r, cornerRadius: radius).fill()
        }
        switch icon {
        case .arrow:
            white.setFill(); UIBezierPath(ovalIn: CGRect(x: 8, y: 8, width: 32, height: 32)).fill()
            g.setShadow(offset: .zero, blur: 0, color: nil)
            tint.setFill()
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 24, y: 12)); p.addLine(to: CGPoint(x: 34, y: 35))
            p.addLine(to: CGPoint(x: 24, y: 29)); p.addLine(to: CGPoint(x: 14, y: 35)); p.close(); p.fill()
        case .sedan, .sports, .suv:
            let w: CGFloat = icon == .suv ? 22 : (icon == .sports ? 19 : 20)
            let h: CGFloat = icon == .sports ? 36 : 34
            let body = CGRect(x: 24 - w / 2, y: 24 - h / 2, width: w, height: h)
            round(body, icon == .suv ? 4 : 8, tint)
            g.setShadow(offset: .zero, blur: 0, color: nil)
            // Windshield and rear window.
            round(CGRect(x: body.minX + 3, y: body.minY + (icon == .sports ? 10 : 8), width: w - 6, height: 6), 2, dark.withAlphaComponent(0.85))
            round(CGRect(x: body.minX + 3, y: body.maxY - 8, width: w - 6, height: 4), 1.5, dark.withAlphaComponent(0.7))
            if icon == .sports {
                // Racing stripes.
                round(CGRect(x: 22, y: body.minY + 1, width: 1.6, height: h - 2), 0.8, white.withAlphaComponent(0.9))
                round(CGRect(x: 24.4, y: body.minY + 1, width: 1.6, height: h - 2), 0.8, white.withAlphaComponent(0.9))
            }
            if icon == .suv { round(CGRect(x: body.minX + 4, y: body.minY + 16, width: w - 8, height: 8), 1, white.withAlphaComponent(0.25)) }
            // Headlights.
            round(CGRect(x: body.minX + 2, y: body.minY + 1, width: 4, height: 2.5), 1, white)
            round(CGRect(x: body.maxX - 6, y: body.minY + 1, width: 4, height: 2.5), 1, white)
        case .motorbike:
            round(CGRect(x: 21, y: 8, width: 6, height: 32), 3, dark)
            round(CGRect(x: 19, y: 16, width: 10, height: 14), 5, tint)
            g.setShadow(offset: .zero, blur: 0, color: nil)
            round(CGRect(x: 14, y: 14, width: 20, height: 2.5), 1.2, white)
            white.setFill(); UIBezierPath(ovalIn: CGRect(x: 20.5, y: 20, width: 7, height: 7)).fill()
        case .rocket:
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 24, y: 4))
            p.addCurve(to: CGPoint(x: 31, y: 30), controlPoint1: CGPoint(x: 31, y: 12), controlPoint2: CGPoint(x: 32, y: 22))
            p.addLine(to: CGPoint(x: 17, y: 30))
            p.addCurve(to: CGPoint(x: 24, y: 4), controlPoint1: CGPoint(x: 16, y: 22), controlPoint2: CGPoint(x: 17, y: 12))
            p.close(); white.setFill(); p.fill()
            g.setShadow(offset: .zero, blur: 0, color: nil)
            tint.setFill()
            UIBezierPath(ovalIn: CGRect(x: 20.5, y: 13, width: 7, height: 7)).fill()
            let fins = UIBezierPath()
            fins.move(to: CGPoint(x: 17, y: 24)); fins.addLine(to: CGPoint(x: 11, y: 34)); fins.addLine(to: CGPoint(x: 18, y: 31)); fins.close()
            fins.move(to: CGPoint(x: 31, y: 24)); fins.addLine(to: CGPoint(x: 37, y: 34)); fins.addLine(to: CGPoint(x: 30, y: 31)); fins.close()
            fins.fill()
            UIColor.systemOrange.setFill()
            let flame = UIBezierPath()
            flame.move(to: CGPoint(x: 19, y: 31)); flame.addLine(to: CGPoint(x: 24, y: 44)); flame.addLine(to: CGPoint(x: 29, y: 31)); flame.close()
            flame.fill()
        case .saucer:
            tint.setFill(); UIBezierPath(ovalIn: CGRect(x: 6, y: 17, width: 36, height: 14)).fill()
            g.setShadow(offset: .zero, blur: 0, color: nil)
            white.withAlphaComponent(0.9).setFill(); UIBezierPath(ovalIn: CGRect(x: 16, y: 10, width: 16, height: 14)).fill()
            for x in stride(from: 11.0, through: 35.0, by: 6.0) {
                UIColor.systemYellow.setFill(); UIBezierPath(ovalIn: CGRect(x: x, y: 23, width: 3, height: 3)).fill()
            }
            // A notch at the front so heading stays readable.
            white.setFill()
            let n = UIBezierPath()
            n.move(to: CGPoint(x: 24, y: 2)); n.addLine(to: CGPoint(x: 28, y: 9)); n.addLine(to: CGPoint(x: 20, y: 9)); n.close(); n.fill()
        case .block:
            // A blocky minecart seen from above.
            tint.setFill(); UIBezierPath(rect: CGRect(x: 12, y: 10, width: 24, height: 28)).fill()
            g.setShadow(offset: .zero, blur: 0, color: nil)
            dark.withAlphaComponent(0.6).setFill(); UIBezierPath(rect: CGRect(x: 16, y: 14, width: 16, height: 20)).fill()
            white.setFill()
            UIBezierPath(rect: CGRect(x: 12, y: 10, width: 6, height: 4)).fill()
            UIBezierPath(rect: CGRect(x: 30, y: 10, width: 6, height: 4)).fill()
            UIColor.black.setFill()
            for r in [CGRect(x: 8, y: 14, width: 4, height: 6), CGRect(x: 36, y: 14, width: 4, height: 6),
                      CGRect(x: 8, y: 28, width: 4, height: 6), CGRect(x: 36, y: 28, width: 4, height: 6)] {
                UIBezierPath(rect: r).fill()
            }
        }
    }
}
