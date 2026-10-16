import Metal
import QuartzCore
import ScreenSaver
import os

private let log = Logger(subsystem: "com.bosse.starfields.metalsaver", category: "saver")

/// Native screen saver (option B): the Hyperspace renderer as one full-screen
/// Metal fragment shader (Hyperspace.metal, a port of shaders/hyperspace.frag).
///
/// Frames come from the host's animation timer (`animateOneFrame`), not from
/// a display link: in legacyScreenSaver only the main display's view gets a
/// `window.screen` (see the Flutter saver, macos_saver/), so a display link
/// has nothing to bind to on the others.
///
/// Built and installed by tool/build_metal_saver.sh.
@objc(StarfieldsMetalSaverView)
final class StarfieldsMetalSaverView: ScreenSaverView {
  private let metalLayer = CAMetalLayer()
  private let drive = HyperspaceDrive()
  private var startTime: CFTimeInterval = 0
  private var stats = FrameStats()
  private var stopObserver: NSObjectProtocol?

  /// Same density as the Flutter saver's star count would give.
  private static let stars = 2000.0

  override init?(frame: NSRect, isPreview: Bool) {
    super.init(frame: frame, isPreview: isPreview)
    log.notice("init frame=\(NSStringFromRect(frame), privacy: .public) preview=\(isPreview)")
    animationTimeInterval = 1.0 / 120.0
    guard let renderer = Renderer.shared else { return nil }
    metalLayer.device = renderer.device
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    metalLayer.isOpaque = true
    metalLayer.framebufferOnly = true
    // The host's timer paces the frames; don't let nextDrawable stall it.
    metalLayer.allowsNextDrawableTimeout = true
    metalLayer.backgroundColor = NSColor.black.cgColor
    wantsLayer = true
    layer = metalLayer
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  deinit {
    log.notice("deinit")
  }

  /// Device pixels per point. In legacyScreenSaver only the main display's
  /// view gets a `window.screen`; the other windows report the main display's
  /// scale (2 on a 1x display). Their view fills its display, so the screen
  /// with the same size tells the scale.
  private var backingScale: CGFloat {
    if let screen = window?.screen { return screen.backingScaleFactor }
    let sameSize = NSScreen.screens.filter { $0.frame.size == bounds.size }
    if sameSize.count == 1 { return sameSize[0].backingScaleFactor }
    return window?.backingScaleFactor ?? 2
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateDrawableSize()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    updateDrawableSize()
  }

  private func updateDrawableSize() {
    metalLayer.contentsScale = backingScale
    metalLayer.drawableSize = CGSize(width: bounds.width * backingScale, height: bounds.height * backingScale)
  }

  override func startAnimation() {
    super.startAnimation()
    let screen = window?.screen.map { NSStringFromRect($0.frame) } ?? "none"
    log.notice("startAnimation \(Int(self.bounds.width))x\(Int(self.bounds.height)) @\(self.backingScale)x screen=\(screen, privacy: .public)")
    updateDrawableSize()
    startTime = CACurrentMediaTime()
    stats = FrameStats()
    stopObserver = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("com.apple.screensaver.willstop"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      log.notice("willstop notification")
      self?.stopAnimation()
    }
  }

  override func stopAnimation() {
    if let stopObserver {
      DistributedNotificationCenter.default().removeObserver(stopObserver)
      self.stopObserver = nil
      log.notice("stopAnimation after \(CACurrentMediaTime() - self.startTime, format: .fixed(precision: 1)) s")
    }
    super.stopAnimation()
  }

  override func draw(_ rect: NSRect) {
    // Layer-backed: drawing happens in animateOneFrame.
  }

  override func animateOneFrame() {
    stats.ticks += 1
    defer {
      if let report = stats.report(now: CACurrentMediaTime()) {
        log.notice("\(Int(self.bounds.width))x\(Int(self.bounds.height)) @\(self.backingScale)x: \(report, privacy: .public)")
      }
    }
    guard let renderer = Renderer.shared else { return }
    let now = CACurrentMediaTime() - startTime
    let travel = drive.travel(now)
    let stretch = drive.stretch(now)
    let wrap = HyperspaceDrive.row * HyperspaceDrive.rowPeriod
    var uniforms = HyperspaceUniforms(
      size: SIMD2(Float(bounds.width), Float(bounds.height)),
      density: Float(min(1, Self.stars / HyperspaceDrive.cells)),
      scale: Float(backingScale),
      // Wrapped in Double so 32-bit GPU floats never see a large value.
      shift: SIMD4(HyperspaceDrive.layerSpeeds.map { Float(($0 * travel).truncatingRemainder(dividingBy: wrap)) }),
      length: SIMD4(HyperspaceDrive.layerSpeeds.map { Float($0 * HyperspaceDrive.lengthPerSpeed * stretch) })
    )
    let cpuStart = CACurrentMediaTime()
    guard let drawable = metalLayer.nextDrawable() else {
      stats.missedDrawables += 1
      return
    }
    renderer.draw(to: drawable, uniforms: &uniforms)
    stats.frame(cpuMillis: (CACurrentMediaTime() - cpuStart) * 1000)
  }
}

/// Must match `Uniforms` in Hyperspace.metal (16-byte aligned float4s).
private struct HyperspaceUniforms {
  var size: SIMD2<Float>
  var density: Float
  var scale: Float
  var shift: SIMD4<Float>
  var length: SIMD4<Float>
}

/// Device, queue and pipeline, shared by all views of the host process.
private final class Renderer {
  static let shared: Renderer? = Renderer()

  let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState

  private init?() {
    let start = CACurrentMediaTime()
    guard
      let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue(),
      let url = Bundle(for: StarfieldsMetalSaverView.self).url(forResource: "Hyperspace", withExtension: "metal"),
      let source = try? String(contentsOf: url, encoding: .utf8)
    else {
      log.error("Metal setup failed (device, queue or Hyperspace.metal)")
      return nil
    }
    do {
      let library = try device.makeLibrary(source: source, options: nil)
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = library.makeFunction(name: "fullScreenVertex")
      descriptor.fragmentFunction = library.makeFunction(name: "hyperspaceFragment")
      descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    } catch {
      log.error("shader compile failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
    self.device = device
    self.queue = queue
    log.notice("Metal ready on \(device.name, privacy: .public) in \((CACurrentMediaTime() - start) * 1000, format: .fixed(precision: 1)) ms")
  }

  func draw(to drawable: CAMetalDrawable, uniforms: inout HyperspaceUniforms) {
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = drawable.texture
    pass.colorAttachments[0].loadAction = .dontCare
    pass.colorAttachments[0].storeAction = .store
    guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
    else { return }
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<HyperspaceUniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    buffer.present(drawable)
    buffer.commit()
  }
}

/// Frames per second and CPU time per frame, reported every 5 s.
private struct FrameStats {
  private var windowStart = CACurrentMediaTime()
  private var frames = 0
  private var cpuMillis = 0.0
  var ticks = 0  // animateOneFrame calls
  var missedDrawables = 0

  mutating func frame(cpuMillis: Double) {
    frames += 1
    self.cpuMillis += cpuMillis
  }

  mutating func report(now: CFTimeInterval) -> String? {
    let elapsed = now - windowStart
    guard elapsed >= 5 else { return nil }
    let text = String(
      format: "fps %.1f, ticks/s %.1f, cpu %.2f ms/frame, missed drawables %d",
      Double(frames) / elapsed, Double(ticks) / elapsed, frames > 0 ? cpuMillis / Double(frames) : 0,
      missedDrawables)
    self = FrameStats()
    return text
  }
}
