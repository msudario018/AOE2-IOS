import UIKit
import MetalKit
import QuartzCore

public enum ScalingFilterMode: UInt32 {
    case nearestNeighbor = 0
    case bilinear = 1
    case crtScanline = 2
}

struct ViewportUniforms {
    var viewportScale: SIMD2<Float> = SIMD2<Float>(1.0, 1.0)
    var viewportOffset: SIMD2<Float> = SIMD2<Float>(0.0, 0.0)
    var scalingMode: UInt32 = 0
    var crtIntensity: Float = 0.25
}

/// MetalViewportView
///
/// High-performance Metal rendering surface inspired by UTM (`utmapp/UTM`).
/// Renders the guest Win32 / DOSBox-Pure framebuffer with 120Hz ProMotion support via CADisplayLink.
public class MetalViewportView: UIView, MTKViewDelegate {
    
    // MARK: - Metal Infrastructure
    
    private var mtkView: MTKView!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var nearestSamplerState: MTLSamplerState!
    private var linearSamplerState: MTLSamplerState!
    private var vertexBuffer: MTLBuffer!
    private var uniformBuffer: MTLBuffer!
    
    // Texture Double-Buffering
    private var guestTextures: [MTLTexture?] = [nil, nil]
    private var activeTextureIndex: Int = 0
    private let textureLock = NSLock()
    
    // Pixel Snapshot Cache for Command Bar Zoom Loupe
    private var lastFramebufferData: Data?
    private var lastBytesPerRow: Int = 0
    
    // MARK: - Display Timing & ProMotion (120Hz)
    
    private var displayLink: CADisplayLink?
    private var isFrameDirty: Bool = false
    
    // MARK: - Viewport Geometry & Resolution
    
    public private(set) var guestWidth: Int = 1024
    public private(set) var guestHeight: Int = 768
    public var scalingFilter: ScalingFilterMode = .nearestNeighbor
    
    /// Calculated aspect-fit rect within the current view bounds (in points)
    public private(set) var contentViewportRect: CGRect = .zero
    
    // Quad vertices: (posX, posY, texU, texV)
    private let quadVertices: [Float] = [
        -1.0, -1.0,  0.0,  1.0,  // Bottom-left
         1.0, -1.0,  1.0,  1.0,  // Bottom-right
        -1.0,  1.0,  0.0,  0.0,  // Top-left
         1.0,  1.0,  1.0,  0.0   // Top-right
    ]
    
    // MARK: - Initialization
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupMetal()
        setupDisplayLink()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
        setupDisplayLink()
    }
    
    deinit {
        displayLink?.invalidate()
    }
    
    // MARK: - Metal Setup
    
    private func setupMetal() {
        backgroundColor = .black
        
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            Log.fatal(.metal, "Metal is not supported on this iOS device or simulator environment!")
            fatalError("Metal is not supported on this iOS device.")
        }
        self.device = defaultDevice
        self.commandQueue = defaultDevice.makeCommandQueue()
        Log.info(.metal, "Metal device initialized: \(defaultDevice.name)")
        
        // Setup MTKView
        mtkView = MTKView(frame: bounds, device: defaultDevice)
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.delegate = self
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = false
        addSubview(mtkView)
        
        // Build Pipeline State from Shaders.metal
        guard let library = defaultDevice.makeDefaultLibrary() else {
            Log.error(.metal, "Unable to load default Metal library. Ensure Shaders.metal is compiled in target.")
            fatalError("Unable to load default Metal library. Ensure Shaders.metal is compiled in target.")
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        
        do {
            pipelineState = try defaultDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
            Log.info(.metal, "Metal render pipeline state compiled successfully.")
        } catch {
            Log.fatal(.metal, "Failed to create Metal render pipeline state: \(error)")
            fatalError("Failed to create Metal render pipeline state: \(error)")
        }
        
        // Vertex Buffer
        vertexBuffer = defaultDevice.makeBuffer(
            bytes: quadVertices,
            length: quadVertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        
        // Uniform Buffer
        var uniforms = ViewportUniforms()
        uniformBuffer = defaultDevice.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<ViewportUniforms>.stride,
            options: .storageModeShared
        )
        
        // Sampler States
        let nearestDesc = MTLSamplerDescriptor()
        nearestDesc.minFilter = .nearest
        nearestDesc.magFilter = .nearest
        nearestSamplerState = defaultDevice.makeSamplerState(descriptor: nearestDesc)
        
        let linearDesc = MTLSamplerDescriptor()
        linearDesc.minFilter = .linear
        linearDesc.magFilter = .linear
        linearSamplerState = defaultDevice.makeSamplerState(descriptor: linearDesc)
        
        recalculateViewportGeometry()
    }
    
    // MARK: - 120Hz ProMotion Display Link Configuration
    
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
        
        // Configure 120Hz ProMotion on iPad Pro and iPhone 13 Pro / 14 Pro / 15 Pro / 16 Pro
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        } else {
            displayLink?.preferredFramesPerSecond = 120
        }
        
        displayLink?.add(to: .main, forMode: .common)
    }
    
    // MARK: - Layout & Viewport Geometry
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        recalculateViewportGeometry()
    }
    
    private func recalculateViewportGeometry() {
        guard bounds.width > 0, bounds.height > 0, guestWidth > 0, guestHeight > 0 else { return }
        
        let viewWidth = bounds.width
        let viewHeight = bounds.height
        let guestAspect = CGFloat(guestWidth) / CGFloat(guestHeight)
        let viewAspect = viewWidth / viewHeight
        
        let renderWidth: CGFloat
        let renderHeight: CGFloat
        
        if viewAspect > guestAspect {
            // View is wider than guest: Pillarboxed (black bars on left/right)
            renderHeight = viewHeight
            renderWidth = viewHeight * guestAspect
        } else {
            // View is taller than guest: Letterboxed (black bars on top/bottom)
            renderWidth = viewWidth
            renderHeight = viewWidth / guestAspect
        }
        
        let offsetX = (viewWidth - renderWidth) * 0.5
        let offsetY = (viewHeight - renderHeight) * 0.5
        contentViewportRect = CGRect(x: offsetX, y: offsetY, width: renderWidth, height: renderHeight)
        
        // Update Metal viewport uniforms
        let scaleX = Float(renderWidth / viewWidth)
        let scaleY = Float(renderHeight / viewHeight)
        
        var uniforms = ViewportUniforms(
            viewportScale: SIMD2<Float>(scaleX, scaleY),
            viewportOffset: SIMD2<Float>(0.0, 0.0),
            scalingMode: scalingFilter.rawValue,
            crtIntensity: 0.25
        )
        
        if let ptr = uniformBuffer?.contents() {
            ptr.copyMemory(from: &uniforms, byteCount: MemoryLayout<ViewportUniforms>.stride)
        }
    }
    
    // MARK: - Guest Framebuffer Ingestion
    
    /// Thread-safe update called by the emulation runner (DOSBox-Pure / QEMU / TinyEMU core)
    /// - Parameters:
    ///   - width: Guest resolution width (e.g. 1024)
    ///   - height: Guest resolution height (e.g. 768)
    ///   - bytesPerRow: Row pitch (e.g. 1024 * 4)
    ///   - data: Raw pointer to 32-bit BGRA guest pixels
    ///   - pixelFormat: MTLPixelFormat (defaults to .bgra8Unorm)
    public func updateGuestFramebuffer(width: Int,
                                       height: Int,
                                       bytesPerRow: Int,
                                       data: UnsafeRawPointer,
                                       pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        textureLock.lock()
        defer { textureLock.unlock() }
        
        if self.guestWidth != width || self.guestHeight != height {
            Log.info(.metal, "Guest resolution changed from \(self.guestWidth)x\(self.guestHeight) to \(width)x\(height) (pitch=\(bytesPerRow))")
            self.guestWidth = width
            self.guestHeight = height
            guestTextures = [nil, nil] // Invalidate cached textures on resolution change
            DispatchQueue.main.async { [weak self] in
                self?.recalculateViewportGeometry()
            }
        }
        
        let nextIndex = 1 - activeTextureIndex
        var targetTexture = guestTextures[nextIndex]
        
        if targetTexture == nil || targetTexture?.width != width || targetTexture?.height != height {
            let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            textureDesc.usage = [.shaderRead]
            textureDesc.storageMode = .shared
            targetTexture = device.makeTexture(descriptor: textureDesc)
            guestTextures[nextIndex] = targetTexture
        }
        
        guard let texture = targetTexture else { return }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)
        
        // Cache snapshot buffer for Command Bar Zoom Loupe
        let totalBytes = bytesPerRow * height
        self.lastFramebufferData = Data(bytes: data, count: totalBytes)
        self.lastBytesPerRow = bytesPerRow
        
        activeTextureIndex = nextIndex
        isFrameDirty = true
    }
    
    /// Generates a CGImage of the active guest framebuffer for the 2.2x Command Bar Zoom Loupe
    public func captureCurrentGuestSnapshot() -> CGImage? {
        textureLock.lock()
        defer { textureLock.unlock() }
        
        guard let data = lastFramebufferData, guestWidth > 0, guestHeight > 0 else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // BGRA8888 Little Endian
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        
        return CGImage(
            width: guestWidth,
            height: guestHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: lastBytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
    
    // MARK: - MTKViewDelegate & Rendering
    
    @objc private func renderFrame() {
        guard isFrameDirty else { return }
        mtkView.draw()
        isFrameDirty = false
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        recalculateViewportGeometry()
    }
    
    public func draw(in view: MTKView) {
        textureLock.lock()
        let activeTexture = guestTextures[activeTextureIndex]
        textureLock.unlock()
        
        guard let texture = activeTexture,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.setFragmentSamplerState(nearestSamplerState, index: 0)
        renderEncoder.setFragmentSamplerState(linearSamplerState, index: 1)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // MARK: - Coordinate Translation (Touch <-> Guest Framebuffer)
    
    /// Converts a screen touch point (in points) to exact guest framebuffer pixel coordinates.
    /// Returns nil if the touch occurred in the black pillarbox/letterbox margin.
    public func convertScreenPointToGuestPoint(_ point: CGPoint) -> CGPoint? {
        guard contentViewportRect.contains(point) else { return nil }
        
        let relativeX = point.x - contentViewportRect.origin.x
        let relativeY = point.y - contentViewportRect.origin.y
        
        let scaleX = CGFloat(guestWidth) / contentViewportRect.width
        let scaleY = CGFloat(guestHeight) / contentViewportRect.height
        
        let guestX = relativeX * scaleX
        let guestY = relativeY * scaleY
        
        return CGPoint(
            x: max(0, min(CGFloat(guestWidth - 1), guestX)),
            y: max(0, min(CGFloat(guestHeight - 1), guestY))
        )
    }
    
    /// Converts a guest framebuffer coordinate (e.g. 1024x768) back to screen view points.
    public func convertGuestPointToScreenPoint(_ point: CGPoint) -> CGPoint {
        let scaleX = contentViewportRect.width / CGFloat(guestWidth)
        let scaleY = contentViewportRect.height / CGFloat(guestHeight)
        
        let screenX = contentViewportRect.origin.x + point.x * scaleX
        let screenY = contentViewportRect.origin.y + point.y * scaleY
        
        return CGPoint(x: screenX, y: screenY)
    }
}
