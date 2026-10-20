import UIKit

/// Protocol for forwarding translated touch-to-mouse events to the underlying emulation core.
@objc public protocol TouchInputDelegate: AnyObject {
    /// Dispatches mouse movement in guest framebuffer coordinates (e.g., 0..<1024, 0..<768).
    func mouseMoved(to point: CGPoint)
    
    /// Dispatches mouse button down event.
    /// - Parameters:
    ///   - button: 0 = Left button, 1 = Right button, 2 = Middle button
    ///   - point: Coordinates in guest framebuffer space.
    func mouseDown(button: Int, at point: CGPoint)
    
    /// Dispatches mouse button up event.
    /// - Parameters:
    ///   - button: 0 = Left button, 1 = Right button, 2 = Middle button
    ///   - point: Coordinates in guest framebuffer space.
    func mouseUp(button: Int, at point: CGPoint)
    
    /// Dispatches map pan delta (e.g. from two-finger drag or edge scrolling).
    func mapScroll(deltaX: CGFloat, deltaY: CGFloat)
    
    /// Dispatches keyboard key events (for hotkeys like Escape, Space, Delete, Arrow keys).
    func sendKeyEvent(keyCode: UInt16, isDown: Bool)
}

/// Operational touch mode for translating iOS touches to PC mouse controls.
/// Directly mirrors the input options available in `fallout1-ce`.
@objc public enum TouchControlMode: Int {
    /// Direct mode: Tapping on screen moves cursor directly to touched coordinate and clicks.
    /// Dragging draws a selection box (left button down).
    case direct = 0
    
    /// Trackpad mode: Moving finger moves the cursor relative to its previous position with acceleration.
    /// Tap anywhere to left click, two-finger tap to right click.
    case trackpad = 1
}

/// TouchInputOverlay
/// 
/// Complete touch gesture controller directly modeled on Alex Batalov's `fallout1-ce` iOS port.
/// Adapted for Age of Empires II (1999) mechanics:
/// - Single tap: Left click (select unit/building, confirm destination).
/// - Two-finger tap: Right click (issue move/attack/gather command).
/// - Tap-and-hold + Drag: Left mouse button down (drag selection box around multiple units).
/// - Two-finger drag: Pan/scroll the map viewport.
/// - Edge scrolling: Automatic scrolling when the cursor/finger approaches screen edges.
/// - Pinch-to-zoom / Scale viewport.
/// - Trackpad relative mode vs. Direct absolute mode.
public class TouchInputOverlay: UIView, UIGestureRecognizerDelegate {
    
    // MARK: - Properties & Delegates
    
    public weak var delegate: TouchInputDelegate?
    
    /// Coordinate mapping provider (typically `MetalViewportView`)
    public var coordinateConverter: ((CGPoint) -> CGPoint?)?
    
    /// Current touch mapping mode (Direct vs Trackpad)
    public var controlMode: TouchControlMode = .direct {
        didSet {
            virtualCursorView.isHidden = (controlMode == .direct)
        }
    }
    
    /// Virtual cursor position in guest framebuffer coordinates
    public private(set) var guestCursorPosition: CGPoint = CGPoint(x: 512, y: 384)
    
    /// Trackpad sensitivity multiplier
    public var trackpadSensitivity: CGFloat = 1.35
    
    /// Trackpad acceleration curve factor
    public var accelerationFactor: CGFloat = 1.15
    
    /// Inset threshold in view points for edge scrolling (default 24 points)
    public var edgeScrollInset: CGFloat = 24.0
    
    /// Speed multiplier for edge scrolling
    public var edgeScrollSpeed: CGFloat = 12.0
    
    // MARK: - Internal Gesture State
    
    private var isLeftMouseDown = false
    private var isRightMouseDown = false
    private var isDraggingSelection = false
    private var dragStartGuestPoint: CGPoint = .zero
    
    private var tapHoldTimer: Timer?
    private var edgeScrollTimer: CADisplayLink?
    private var activeEdgeScrollDirection: CGPoint = .zero
    
    // Visual indicators
    private let selectionBoxLayer = CAShapeLayer()
    private let virtualCursorView = UIImageView()
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    // Command Bar Zoom Loupe for Small Screens (iPhone)
    public var isZoomLoupeEnabled: Bool = true {
        didSet {
            if !isZoomLoupeEnabled {
                loupeView.dismiss()
            }
        }
    }
    public var loupeMagnification: CGFloat = 2.2 {
        didSet {
            loupeView.magnification = loupeMagnification
        }
    }
    public var bottomHUDThresholdRatio: CGFloat = 0.74
    public var guestSnapshotProvider: (() -> CGImage?)?
    private let loupeView = CommandBarLoupeView()
    
    // Multi-touch tracking
    private var initialTouchPoint: CGPoint = .zero
    private var lastTrackpadTouchPoint: CGPoint = .zero
    
    // MARK: - Initialization
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupOverlay()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupOverlay()
    }
    
    deinit {
        tapHoldTimer?.invalidate()
        edgeScrollTimer?.invalidate()
    }
    
    // MARK: - Setup
    
    private func setupOverlay() {
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
        
        // Setup visual selection box for drag-select (AoE2 marquee box)
        selectionBoxLayer.strokeColor = UIColor(red: 0.2, green: 0.85, blue: 0.3, alpha: 0.85).cgColor
        selectionBoxLayer.fillColor = UIColor(red: 0.2, green: 0.85, blue: 0.3, alpha: 0.15).cgColor
        selectionBoxLayer.lineWidth = 1.5
        selectionBoxLayer.lineDashPattern = [4, 2]
        selectionBoxLayer.isHidden = true
        layer.addSublayer(selectionBoxLayer)
        
        // Setup Virtual Cursor (used in Trackpad mode or when hovering)
        virtualCursorView.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        virtualCursorView.image = createSoftwareCursorImage()
        virtualCursorView.contentMode = .scaleAspectFit
        virtualCursorView.isHidden = (controlMode == .direct)
        addSubview(virtualCursorView)
        
        // Setup Edge Scroll display link
        edgeScrollTimer = CADisplayLink(target: self, selector: #selector(handleEdgeScrollTick))
        edgeScrollTimer?.add(to: .main, forMode: .common)
        
        // Setup Command Bar Zoom Loupe for small screens
        loupeView.magnification = loupeMagnification
        addSubview(loupeView)
        
        // Setup High-level Gestures
        setupGestureRecognizers()
        
        feedbackGenerator.prepare()
    }
    
    private func setupGestureRecognizers() {
        // 1. Two-finger single tap -> Right click (AoE2 Command / Move / Attack)
        let twoFingerTap = UITapGestureRecognizer(target: self, selector: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.delegate = self
        addGestureRecognizer(twoFingerTap)
        
        // 2. Two-finger pan -> Map scrolling (Camera pan)
        let twoFingerPan = UIPanGestureRecognizer(target: self, selector: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = self
        addGestureRecognizer(twoFingerPan)
        
        // 3. Pinch gesture -> Zoom / UI Scaling
        let pinchGesture = UIPinchGestureRecognizer(target: self, selector: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        addGestureRecognizer(pinchGesture)
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow two-finger gestures to coexist smoothly
        return true
    }
    
    // MARK: - Low-Level Touch Handling (Fallout1-CE Style Translation)
    
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        
        let location = touch.location(in: self)
        initialTouchPoint = location
        lastTrackpadTouchPoint = location
        
        if touches.count == 1 {
            if controlMode == .direct {
                guard let guestPoint = convertToGuest(location) else { return }
                guestCursorPosition = guestPoint
                delegate?.mouseMoved(to: guestPoint)
                
                // Update 2.2x Command Bar Zoom Loupe if touching bottom HUD
                updateLoupeIfNeeded(location: location, guestPoint: guestPoint)
                
                // Start a timer for Tap-and-Hold drag selection (AoE2 marquee box)
                tapHoldTimer?.invalidate()
                tapHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.startDragSelection(at: location, guestPoint: guestPoint)
                }
            }
        }
    }
    
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        // Evaluate Edge Scrolling
        updateEdgeScrollDirection(at: location)
        
        if controlMode == .direct {
            guard let guestPoint = convertToGuest(location) else { return }
            guestCursorPosition = guestPoint
            
            // Update 2.2x Command Bar Zoom Loupe during touch movement
            updateLoupeIfNeeded(location: location, guestPoint: guestPoint)
            
            let distance = hypot(location.x - initialTouchPoint.x, location.y - initialTouchPoint.y)
            if distance > 10.0 && !isDraggingSelection {
                // User moved finger beyond threshold: promote to drag selection immediately
                tapHoldTimer?.invalidate()
                tapHoldTimer = nil
                loupeView.dismiss()
                startDragSelection(at: initialTouchPoint, guestPoint: convertToGuest(initialTouchPoint) ?? guestPoint)
            }
            
            if isDraggingSelection {
                // Update selection marquee geometry
                updateSelectionBox(from: initialTouchPoint, to: location)
                delegate?.mouseMoved(to: guestPoint)
            }
        } else {
            // Trackpad (Relative) Mode
            let deltaX = (location.x - lastTrackpadTouchPoint.x) * trackpadSensitivity
            let deltaY = (location.y - lastTrackpadTouchPoint.y) * trackpadSensitivity
            
            // Apply gentle acceleration curve
            let speed = hypot(deltaX, deltaY)
            let accel = max(1.0, pow(speed, accelerationFactor - 1.0))
            
            guestCursorPosition.x += deltaX * accel
            guestCursorPosition.y += deltaY * accel
            
            // Clamp to guest bounds (e.g., standard 1024x768 AoE2 resolution)
            guestCursorPosition.x = max(0, min(1024, guestCursorPosition.x))
            guestCursorPosition.y = max(0, min(768, guestCursorPosition.y))
            
            updateVirtualCursorScreenPosition()
            delegate?.mouseMoved(to: guestCursorPosition)
            lastTrackpadTouchPoint = location
        }
    }
    
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        tapHoldTimer?.invalidate()
        tapHoldTimer = nil
        activeEdgeScrollDirection = .zero
        loupeView.dismiss()
        
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        if controlMode == .direct {
            if isDraggingSelection {
                // Release left mouse drag
                guard let guestPoint = convertToGuest(location) else { return }
                delegate?.mouseUp(button: 0, at: guestPoint)
                isLeftMouseDown = false
                isDraggingSelection = false
                endSelectionBox()
            } else {
                // Single tap detected -> left click at point
                guard let guestPoint = convertToGuest(location) else { return }
                performLeftClick(at: guestPoint)
            }
        } else {
            // Trackpad mode: tap to click
            let distance = hypot(location.x - initialTouchPoint.x, location.y - initialTouchPoint.y)
            if distance < 6.0 {
                performLeftClick(at: guestCursorPosition)
            }
            if isLeftMouseDown {
                delegate?.mouseUp(button: 0, at: guestCursorPosition)
                isLeftMouseDown = false
            }
        }
    }
    
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        tapHoldTimer?.invalidate()
        tapHoldTimer = nil
        activeEdgeScrollDirection = .zero
        loupeView.dismiss()
        
        if isLeftMouseDown {
            delegate?.mouseUp(button: 0, at: guestCursorPosition)
            isLeftMouseDown = false
        }
        if isRightMouseDown {
            delegate?.mouseUp(button: 1, at: guestCursorPosition)
            isRightMouseDown = false
        }
        if isDraggingSelection {
            endSelectionBox()
            isDraggingSelection = false
        }
    }
    
    // MARK: - Gesture Recognizer Callbacks
    
    @objc private func handleTwoFingerTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        
        let targetGuestPoint: CGPoint
        if controlMode == .direct {
            let location = recognizer.location(in: self)
            guard let converted = convertToGuest(location) else { return }
            targetGuestPoint = converted
        } else {
            targetGuestPoint = guestCursorPosition
        }
        
        performRightClick(at: targetGuestPoint)
    }
    
    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)
        
        if recognizer.state == .changed {
            // Invert translation to match camera pan feel
            let panDeltaX = -translation.x * 2.0
            let panDeltaY = -translation.y * 2.0
            delegate?.mapScroll(deltaX: panDeltaX, deltaY: panDeltaY)
        }
    }
    
    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        // Pinch can be mapped to in-game viewport zoom or tactical view
        if recognizer.state == .changed {
            let scale = recognizer.scale
            if scale > 1.05 {
                // Zoom in / Increase UI scaling
            } else if scale < 0.95 {
                // Zoom out / Overview map
            }
            recognizer.scale = 1.0
        }
    }
    
    // MARK: - Mouse Actions
    
    private func performLeftClick(at guestPoint: CGPoint) {
        feedbackGenerator.impactOccurred()
        CrashReporter.recordBreadcrumb(withCategory: "Touch", message: String(format: "LeftClick at (%.0f, %.0f)", guestPoint.x, guestPoint.y))
        delegate?.mouseMoved(to: guestPoint)
        delegate?.mouseDown(button: 0, at: guestPoint)
        
        // 35ms simulated micro-delay for Win32 message pump processing (WM_LBUTTONDOWN -> WM_LBUTTONUP)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
            self?.delegate?.mouseUp(button: 0, at: guestPoint)
        }
    }
    
    private func performRightClick(at guestPoint: CGPoint) {
        feedbackGenerator.impactOccurred()
        CrashReporter.recordBreadcrumb(withCategory: "Touch", message: String(format: "RightClick at (%.0f, %.0f)", guestPoint.x, guestPoint.y))
        delegate?.mouseMoved(to: guestPoint)
        delegate?.mouseDown(button: 1, at: guestPoint)
        
        // 35ms simulated micro-delay for Win32 message pump (WM_RBUTTONDOWN -> WM_RBUTTONUP)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
            self?.delegate?.mouseUp(button: 1, at: guestPoint)
        }
    }
    
    private func startDragSelection(at screenPoint: CGPoint, guestPoint: CGPoint) {
        isDraggingSelection = true
        isLeftMouseDown = true
        dragStartGuestPoint = guestPoint
        
        CrashReporter.recordBreadcrumb(withCategory: "Touch", message: String(format: "DragSelect at (%.0f, %.0f)", guestPoint.x, guestPoint.y))
        feedbackGenerator.impactOccurred()
        delegate?.mouseDown(button: 0, at: guestPoint)
        
        selectionBoxLayer.path = UIBezierPath(rect: CGRect(origin: screenPoint, size: .zero)).cgPath
        selectionBoxLayer.isHidden = false
    }
    
    private func updateSelectionBox(from start: CGPoint, to current: CGPoint) {
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        selectionBoxLayer.path = UIBezierPath(rect: rect).cgPath
    }
    
    private func endSelectionBox() {
        selectionBoxLayer.isHidden = true
        selectionBoxLayer.path = nil
    }
    
    // MARK: - Edge Scrolling (Classic AoE2 Border Scroll)
    
    private func updateEdgeScrollDirection(at location: CGPoint) {
        var dirX: CGFloat = 0.0
        var dirY: CGFloat = 0.0
        
        if location.x < edgeScrollInset {
            dirX = -1.0
        } else if location.x > bounds.width - edgeScrollInset {
            dirX = 1.0
        }
        
        if location.y < edgeScrollInset {
            dirY = -1.0
        } else if location.y > bounds.height - edgeScrollInset {
            dirY = 1.0
        }
        
        activeEdgeScrollDirection = CGPoint(x: dirX, y: dirY)
    }
    
    @objc private func handleEdgeScrollTick() {
        guard activeEdgeScrollDirection != .zero else { return }
        let scrollX = activeEdgeScrollDirection.x * edgeScrollSpeed
        let scrollY = activeEdgeScrollDirection.y * edgeScrollSpeed
        delegate?.mapScroll(deltaX: scrollX, deltaY: scrollY)
    }
    
    // MARK: - Helpers & Coordinates
    
    private func convertToGuest(_ point: CGPoint) -> CGPoint? {
        if let converter = coordinateConverter {
            return converter(point)
        }
        // Fallback default aspect-fit conversion assuming 1024x768 guest
        let scale = min(bounds.width / 1024.0, bounds.height / 768.0)
        let offsetX = (bounds.width - 1024.0 * scale) * 0.5
        let offsetY = (bounds.height - 768.0 * scale) * 0.5
        
        let guestX = (point.x - offsetX) / scale
        let guestY = (point.y - offsetY) / scale
        
        if guestX < 0 || guestX > 1024 || guestY < 0 || guestY > 768 {
            return nil
        }
        return CGPoint(x: guestX, y: guestY)
    }
    
    private func updateVirtualCursorScreenPosition() {
        // Reverse map guestCursorPosition to screen coordinates
        let scale = min(bounds.width / 1024.0, bounds.height / 768.0)
        let offsetX = (bounds.width - 1024.0 * scale) * 0.5
        let offsetY = (bounds.height - 768.0 * scale) * 0.5
        
        let screenX = offsetX + guestCursorPosition.x * scale
        let screenY = offsetY + guestCursorPosition.y * scale
        
        virtualCursorView.center = CGPoint(x: screenX, y: screenY)
    }
    
    private func createSoftwareCursorImage() -> UIImage {
        let size = CGSize(width: 24, height: 24)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 2, y: 2))
            path.addLine(to: CGPoint(x: 2, y: 20))
            path.addLine(to: CGPoint(x: 7, y: 15))
            path.addLine(to: CGPoint(x: 12, y: 22))
            path.addLine(to: CGPoint(x: 15, y: 20))
            path.addLine(to: CGPoint(x: 10, y: 13))
            path.addLine(to: CGPoint(x: 18, y: 13))
            path.close()
            
            UIColor.black.setStroke()
            UIColor.white.setFill()
            path.lineWidth = 1.5
            path.fill()
            path.stroke()
        }
    }
    
    // MARK: - Command Bar Zoom Loupe Helper
    
    private func updateLoupeIfNeeded(location: CGPoint, guestPoint: CGPoint?) {
        guard isZoomLoupeEnabled else {
            loupeView.dismiss()
            return
        }
        
        let isBottomHUD = location.y >= bounds.height * bottomHUDThresholdRatio || (guestPoint != nil && guestPoint!.y >= 540)
        if isBottomHUD, let guest = guestPoint {
            loupeView.update(
                touchPoint: location,
                guestPoint: guest,
                snapshotImage: guestSnapshotProvider?(),
                guestSize: CGSize(width: 1024, height: 768)
            )
        } else {
            loupeView.dismiss()
        }
    }
}
