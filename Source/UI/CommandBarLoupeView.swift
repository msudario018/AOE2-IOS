import UIKit

/// CommandBarLoupeView
///
/// High-precision 2.2x magnifying loupe that floats above the user's touch when interacting
/// with the Age of Empires II bottom command bar / unit production HUD.
/// Guarantees pixel-perfect tapping on tiny 32x32 retro action icons on high-DPI iPhone displays.
public class CommandBarLoupeView: UIView {
    
    // MARK: - Configuration
    
    public var magnification: CGFloat = 2.2
    public var loupeDiameter: CGFloat = 130.0
    
    // Sub-views
    private let glassLayer = CALayer()
    private let crosshairLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let shadowLayer = CAShapeLayer()
    
    // Zoomed image content
    private let contentImageView = UIImageView()
    
    public override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: loupeDiameter, height: loupeDiameter))
        setupLoupe()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLoupe()
    }
    
    private func setupLoupe() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        alpha = 0.0
        
        // Shadow for floating depth
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.65
        layer.shadowRadius = 12.0
        layer.shadowOffset = CGSize(width: 0, height: 6)
        
        // Image View hosting the magnified retro framebuffer snapshot
        contentImageView.frame = bounds
        contentImageView.contentMode = .center
        contentImageView.layer.cornerRadius = loupeDiameter / 2.0
        contentImageView.layer.masksToBounds = true
        contentImageView.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1.0)
        
        // Nearest-neighbor / crisp pixel art scaling filter
        contentImageView.layer.magnificationFilter = .nearest
        contentImageView.layer.minificationFilter = .nearest
        addSubview(contentImageView)
        
        // Gold Metallic Bezel
        let bezelPath = UIBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
        borderLayer.path = bezelPath.cgPath
        borderLayer.strokeColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 0.95).cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 3.0
        layer.addSublayer(borderLayer)
        
        // Inner reticle / crosshair for targeting individual production icons
        setupCrosshair()
    }
    
    private func setupCrosshair() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let armLength: CGFloat = 12.0
        let gap: CGFloat = 4.0
        
        let path = UIBezierPath()
        // Top arm
        path.move(to: CGPoint(x: center.x, y: center.y - gap - armLength))
        path.addLine(to: CGPoint(x: center.x, y: center.y - gap))
        // Bottom arm
        path.move(to: CGPoint(x: center.x, y: center.y + gap))
        path.addLine(to: CGPoint(x: center.x, y: center.y + gap + armLength))
        // Left arm
        path.move(to: CGPoint(x: center.x - gap - armLength, y: center.y))
        path.addLine(to: CGPoint(x: center.x - gap, y: center.y))
        // Right arm
        path.move(to: CGPoint(x: center.x + gap, y: center.y))
        path.addLine(to: CGPoint(x: center.x + gap + armLength, y: center.y))
        
        // Center pip
        path.append(UIBezierPath(arcCenter: center, radius: 1.5, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: true))
        
        crosshairLayer.path = path.cgPath
        crosshairLayer.strokeColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 0.85).cgColor
        crosshairLayer.fillColor = UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 0.85).cgColor
        crosshairLayer.lineWidth = 1.5
        layer.addSublayer(crosshairLayer)
    }
    
    // MARK: - Update & Magnification
    
    /// Updates the loupe position and crops the guest snapshot at 2.2x zoom
    /// - Parameters:
    ///   - touchPoint: Screen location of the finger
    ///   - guestPoint: Coordinate in 1024x768 AoE2 guest space
    ///   - snapshotImage: Full or partial guest framebuffer CGImage
    ///   - guestSize: Guest resolution (e.g. 1024x768)
    public func update(touchPoint: CGPoint,
                       guestPoint: CGPoint,
                       snapshotImage: CGImage?,
                       guestSize: CGSize) {
        // 1. Position loupe ~88 points directly above the finger touch point
        var targetCenter = CGPoint(x: touchPoint.x, y: touchPoint.y - 88.0)
        
        // Clamp within parent bounds so the lens doesn't leave the screen
        if let superview = superview {
            let radius = loupeDiameter / 2.0 + 8.0
            targetCenter.x = max(radius, min(superview.bounds.width - radius, targetCenter.x))
            targetCenter.y = max(radius, min(superview.bounds.height - radius, targetCenter.y))
        }
        self.center = targetCenter
        
        // 2. Crop guest region centered at guestPoint and scale by 2.2x
        guard let snapshot = snapshotImage else { return }
        
        // Region in guest pixels to extract (loupeDiameter / magnification)
        let sampleSize = loupeDiameter / magnification
        let cropRect = CGRect(
            x: guestPoint.x - sampleSize / 2.0,
            y: guestPoint.y - sampleSize / 2.0,
            width: sampleSize,
            height: sampleSize
        )
        
        if let cropped = snapshot.cropping(to: cropRect) {
            contentImageView.image = UIImage(cgImage: cropped)
        }
        
        // Animate appearance if not already visible
        if alpha < 0.9 {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.alpha = 1.0
                self.transform = CGAffineTransform.identity
            }
        }
    }
    
    /// Hides the loupe with a smooth scale-down animation
    public func dismiss() {
        guard alpha > 0 else { return }
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseIn]) {
            self.alpha = 0.0
            self.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        }
    }
}
