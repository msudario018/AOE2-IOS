import UIKit
import MetalKit
import SwiftUI

/// FlankContainerView
/// Passes touches in the game's 4:3 area directly through to the underlying touch overlay
private final class FlankContainerView: UIView {
    var contentViewportRect: CGRect = .zero
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if contentViewportRect.contains(point) {
            return nil
        }
        return super.hitTest(point, with: event)
    }
}

public class GameViewController: UIViewController, TouchInputDelegate, VirtualControlsDelegate, DocumentPickerDelegate, SideMarginsDelegate {
    
    // MARK: - Views
    
    private var viewportView: MetalViewportView!
    private var touchOverlay: TouchInputOverlay!
    private var controlsHUD: VirtualControlsOverlay!
    private var documentPickerView: DocumentPickerView?
    private var flankContainer: FlankContainerView?
    private var sideMarginsHostingController: UIHostingController<SideMarginsControlView>?
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        Log.info(.general, "GameViewController viewDidLoad started.")
        
        setupViewport()
        setupTouchOverlay()
        setupControlsHUD()
        setupBridgeCallbacks()
        checkForPreviousCrashLogs()
        checkGameFilesAndBoot()
    }
    
    public override var prefersStatusBarHidden: Bool {
        return true
    }
    
    public override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
    
    // MARK: - Setup Views
    
    private func setupViewport() {
        viewportView = MetalViewportView(frame: view.bounds)
        viewportView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(viewportView)
        Log.info(.metal, "MetalViewportView initialized and attached.")
    }
    
    private func setupTouchOverlay() {
        touchOverlay = TouchInputOverlay(frame: view.bounds)
        touchOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        touchOverlay.delegate = self
        
        // Connect coordinate translation directly to Metal viewport's aspect-fit rect
        touchOverlay.coordinateConverter = { [weak self] screenPoint in
            return self?.viewportView.convertScreenPointToGuestPoint(screenPoint)
        }
        
        // Connect guest framebuffer snapshot for 2.2x Command Bar Zoom Loupe
        touchOverlay.guestSnapshotProvider = { [weak self] in
            return self?.viewportView.captureCurrentGuestSnapshot()
        }
        
        view.addSubview(touchOverlay)
        Log.info(.input, "TouchInputOverlay initialized (mode: \(touchOverlay.controlMode)).")
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSideMarginsLayout()
    }
    
    private func updateSideMarginsLayout() {
        let contentRect = viewportView.contentViewportRect
        guard contentRect.width > 0, contentRect.height > 0 else { return }
        
        let leftMargin = contentRect.origin.x
        let rightMargin = view.bounds.width - contentRect.maxX
        
        // Show side flanks if margins are sufficient (e.g. >= 48pt on 19.5:9 iPhone displays)
        if leftMargin >= 48 || rightMargin >= 48 {
            if flankContainer == nil {
                let container = FlankContainerView(frame: view.bounds)
                container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.backgroundColor = .clear
                view.addSubview(container)
                self.flankContainer = container
                
                let sideView = SideMarginsControlView(
                    delegate: self,
                    leftMarginWidth: leftMargin,
                    rightMarginWidth: rightMargin,
                    isLoupeActive: touchOverlay.isZoomLoupeEnabled
                )
                let hosting = UIHostingController(rootView: sideView)
                hosting.view.backgroundColor = .clear
                hosting.view.frame = container.bounds
                hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                
                addChild(hosting)
                container.addSubview(hosting.view)
                hosting.didMove(toParent: self)
                self.sideMarginsHostingController = hosting
                
                // Ensure top controls HUD stays above
                view.bringSubviewToFront(controlsHUD)
            } else {
                flankContainer?.contentViewportRect = contentRect
                sideMarginsHostingController?.rootView = SideMarginsControlView(
                    delegate: self,
                    leftMarginWidth: leftMargin,
                    rightMarginWidth: rightMargin,
                    isLoupeActive: touchOverlay.isZoomLoupeEnabled
                )
            }
            flankContainer?.contentViewportRect = contentRect
            flankContainer?.isHidden = false
        } else {
            flankContainer?.isHidden = true
        }
    }
    
    private func setupControlsHUD() {
        controlsHUD = VirtualControlsOverlay()
        controlsHUD.delegate = self
        controlsHUD.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsHUD)
        
        NSLayoutConstraint.activate([
            controlsHUD.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            controlsHUD.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controlsHUD.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    // MARK: - Crash Check
    
    private func checkForPreviousCrashLogs() {
        let crashReports = CrashReporter.availableCrashReports()
        if !crashReports.isEmpty {
            Log.warn(.general, "Detected \(crashReports.count) previous crash report(s) on disk.")
            
            // Show alert offering to review the crash
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                let alert = UIAlertController(
                    title: "Crash Detected",
                    message: "The previous game session crashed. A detailed crash report was recorded to help diagnose the issue.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "View Crash Log", style: .default) { [weak self] _ in
                    self?.didRequestLogViewer()
                })
                alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel))
                self.present(alert, animated: true)
            }
        }
    }
    
    // MARK: - Core Emulation Lifecycle
    
    private func setupBridgeCallbacks() {
        let bridge = EmulationBridgeWrapper.sharedInstance()
        
        bridge.onFramebufferAvailable = { [weak self] width, height, pitch, pixels in
            guard let self = self, let px = pixels else { return }
            self.viewportView.updateGuestFramebuffer(
                width: Int(width),
                height: Int(height),
                bytesPerRow: Int(pitch),
                data: px
            )
        }
    }
    
    private func checkGameFilesAndBoot() {
        let status = GameFileManager.shared.verifyGameInstallation()
        
        switch status {
        case .ready(let gameDir, let exePath, let diskImage):
            Log.info(.fileSystem, "Installation verified. Booting EMPIRES2 from: \(exePath.path)")
            bootEmulation(gameDir: gameDir, diskImage: diskImage)
            
        case .missingFiles(let expected, _):
            Log.warn(.fileSystem, "Game files missing (expected: \(expected)). Showing DocumentPickerView.")
            let picker = DocumentPickerView(frame: view.bounds, presentingViewController: self)
            picker.delegate = self
            picker.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(picker)
            self.documentPickerView = picker
            
        case .uninitialized:
            Log.warn(.fileSystem, "Game environment uninitialized.")
        }
    }
    
    private func bootEmulation(gameDir: URL, diskImage: URL?) {
        Log.info(.emulation, "Starting EmulationBridge with GameDir='\(gameDir.path)'...")
        let bridge = EmulationBridgeWrapper.sharedInstance()
        let success = bridge.initialize(withGameDirectory: gameDir.path, diskImagePath: diskImage?.path)
        if success {
            bridge.start()
            Log.info(.emulation, "Emulation runner successfully started.")
        } else {
            Log.error(.emulation, "EmulationBridge initialization returned failure!")
        }
    }
    
    // MARK: - DocumentPickerDelegate
    
    public func didCompleteImport(gameDirectory: URL) {
        Log.info(.fileSystem, "Game folder import completed. Re-verifying installation...")
        let status = GameFileManager.shared.verifyGameInstallation()
        if case .ready(let dir, _, let img) = status {
            bootEmulation(gameDir: dir, diskImage: img)
        }
    }
    
    // MARK: - TouchInputDelegate
    
    public func mouseMoved(to point: CGPoint) {
        EmulationBridgeWrapper.sharedInstance().sendMouseMoveToX(Int32(point.x), y: Int32(point.y))
    }
    
    public func mouseDown(button: Int, at point: CGPoint) {
        EmulationBridgeWrapper.sharedInstance().sendMouseButton(Int32(button), isDown: true)
    }
    
    public func mouseUp(button: Int, at point: CGPoint) {
        EmulationBridgeWrapper.sharedInstance().sendMouseButton(Int32(button), isDown: false)
    }
    
    public func mapScroll(deltaX: CGFloat, deltaY: CGFloat) {
        EmulationBridgeWrapper.sharedInstance().sendMouseScrollDeltaX(Int32(deltaX), deltaY: Int32(deltaY))
    }
    
    public func sendKeyEvent(keyCode: UInt16, isDown: Bool) {
        EmulationBridgeWrapper.sharedInstance().sendKeyEvent(keyCode, isDown: isDown)
    }
    
    // MARK: - VirtualControlsDelegate
    
    public func didTapTownCenterHotkey() {
        Log.debug(.input, "HotKey Town Center (H)")
        EmulationBridgeWrapper.sharedInstance().sendKeyEvent(0x23, isDown: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            EmulationBridgeWrapper.sharedInstance().sendKeyEvent(0x23, isDown: false)
        }
    }
    
    public func didTapIdleVillagerHotkey() {
        Log.debug(.input, "HotKey Idle Villager (.)")
        EmulationBridgeWrapper.sharedInstance().sendKeyEvent(0x34, isDown: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            EmulationBridgeWrapper.sharedInstance().sendKeyEvent(0x34, isDown: false)
        }
    }
    
    public func didTapEscapeKey() {
        Log.debug(.input, "HotKey Escape (0x01)")
        EmulationBridgeWrapper.sharedInstance().sendKeyEvent(0x01, isDown: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            EmulationBridgeWrapper.sharedInstance().sendKeyEvent(0x01, isDown: false)
        }
    }
    
    public func didTapPauseKey() {
        Log.debug(.input, "HotKey Pause / F3 (0x3D)")
        EmulationBridgeWrapper.sharedInstance().sendKeyEvent(0x3D, isDown: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            EmulationBridgeWrapper.sharedInstance().sendKeyEvent(0x3D, isDown: false)
        }
    }
    
    public func didTapMenuKey() {
        Log.debug(.input, "HotKey Menu / F10 (0x44)")
        EmulationBridgeWrapper.sharedInstance().sendKeyEvent(0x44, isDown: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            EmulationBridgeWrapper.sharedInstance().sendKeyEvent(0x44, isDown: false)
        }
    }
    
    public func didToggleControlMode(_ mode: TouchControlMode) {
        touchOverlay.controlMode = mode
        Log.info(.input, "Control mode switched to: \(mode == .direct ? "Direct" : "Trackpad")")
    }
    
    public func didToggleScalingFilter() {
        switch viewportView.scalingFilter {
        case .nearestNeighbor:
            viewportView.scalingFilter = .bilinear
            Log.info(.metal, "Filter changed to Bilinear")
        case .bilinear:
            viewportView.scalingFilter = .crtScanline
            Log.info(.metal, "Filter changed to CRT Scanline")
        case .crtScanline:
            viewportView.scalingFilter = .nearestNeighbor
            Log.info(.metal, "Filter changed to Nearest Neighbor (Crisp)")
        }
    }
    
    public func didRequestKeyboard() {
        if isFirstResponder {
            resignFirstResponder()
        } else {
            becomeFirstResponder()
        }
    }
    
    public func didRequestLogViewer() {
        Log.info(.general, "Presenting LogViewerViewController HUD...")
        let logVC = LogViewerViewController()
        let nav = UINavigationController(rootViewController: logVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }
    
    // MARK: - SideMarginsDelegate (Tactical Flank Controls for 19.5:9 iPhone)
    
    public func didTriggerMarginAction(_ action: SideMarginsAction) {
        switch action {
        case .townCenter:
            didTapTownCenterHotkey()
        case .idleVillager:
            didTapIdleVillagerHotkey()
        case .cycleMilitary:
            Log.debug(.input, "Tactical Flank: Cycle Military (,) scan: 0x33")
            sendKeyPulse(scanCode: 0x33)
        case .focusSelection:
            Log.debug(.input, "Tactical Flank: Focus Selection (Space) scan: 0x39")
            sendKeyPulse(scanCode: 0x39)
        case .econBuildMenu:
            Log.debug(.input, "Tactical Flank: Econ Build Menu (B) scan: 0x30")
            sendKeyPulse(scanCode: 0x30)
        case .milBuildMenu:
            Log.debug(.input, "Tactical Flank: Military Build Menu (V) scan: 0x2F")
            sendKeyPulse(scanCode: 0x2F)
        case .repair:
            Log.debug(.input, "Tactical Flank: Repair Command (R) scan: 0x13")
            sendKeyPulse(scanCode: 0x13)
        case .garrison:
            Log.debug(.input, "Tactical Flank: Garrison Command (T) scan: 0x14")
            sendKeyPulse(scanCode: 0x14)
        case .deleteSelected:
            Log.debug(.input, "Tactical Flank: Delete Selected scan: 0xD3")
            sendKeyPulse(scanCode: 0xD3)
        case .toggleLoupe:
            touchOverlay.isZoomLoupeEnabled.toggle()
            Log.info(.input, "Command Bar Zoom Loupe toggled: \(touchOverlay.isZoomLoupeEnabled)")
            updateSideMarginsLayout()
        case .openLogs:
            didRequestLogViewer()
        }
    }
    
    private func sendKeyPulse(scanCode: UInt16) {
        EmulationBridgeWrapper.sharedInstance().sendKeyEvent(scanCode, isDown: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            EmulationBridgeWrapper.sharedInstance().sendKeyEvent(scanCode, isDown: false)
        }
    }
}
