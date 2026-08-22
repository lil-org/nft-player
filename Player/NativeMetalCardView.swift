// ∅ 2026 lil org

import AppKit
import Foundation
import MetalKit
import os
import simd

private let nativeMetalCardLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
    category: "NativeMetalCard"
)

final class NativeMetalCardView: NSView {

    private static let pointerTrackingInterval: TimeInterval = 1.0 / 30.0

    private var renderer: NativeMetalCardRenderer?
    private var trackingArea: NSTrackingArea?
    private var windowFocusObservers = [NSObjectProtocol]()
    private var pointerTrackingTimer: Timer?
    private var lastPolledScreenLocation: CGPoint?
    private var isDisplayed = false

    override var isHidden: Bool {
        didSet {
            if oldValue != isHidden {
                updateRendererRunningState()
            }
            updatePointerTrackingTimer()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        configureMetalView()
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    isolated deinit {
        removeWindowFocusObservers()
        stopPointerTrackingTimer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeWindowFocusObservers()
        } else {
            installWindowFocusObservers()
        }
        updateRendererRunningState()
        updatePointerTrackingTimer()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointer(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updatePointer(with: event)
    }

    func display(tokenId: String, renderKind: NativeMetalCardRenderKind) {
        guard let tokenID = Int(tokenId) else {
            hideUnavailableContent()
            return
        }

        isDisplayed = true
        renderer?.display(tokenID: tokenID, renderKind: renderKind)
        revealOrRefreshRenderer()
        updatePointerTrackingTimer()
    }

    func stop() {
        isDisplayed = false
        updateRendererRunningState()
        updatePointerTrackingTimer()
    }

    static func resetMotionCalibration() {
        NativeMetalCardPointerStateTracker.shared.reset()
    }

    private func configureMetalView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            nativeMetalCardLogger.error("Metal device is unavailable")
            return
        }
        guard let renderer = NativeMetalCardRenderer(device: device) else {
            nativeMetalCardLogger.error("Metal renderer initialization failed")
            return
        }

        let metalView = MTKView(frame: bounds, device: device)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.layer?.backgroundColor = NSColor.clear.cgColor
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 0)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true
        metalView.preferredFramesPerSecond = 30
        metalView.delegate = renderer
        addSubview(metalView)

        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        renderer.attach(to: metalView)
        self.renderer = renderer
    }

    private func updatePointer(with event: NSEvent) {
        if let window {
            lastPolledScreenLocation = window.convertPoint(toScreen: event.locationInWindow)
        }
        let location = convert(event.locationInWindow, from: nil)
        renderer?.updatePointer(location: location, in: bounds.size)
    }

    private func installWindowFocusObservers() {
        removeWindowFocusObservers()

        guard let window else { return }

        let notificationCenter = NotificationCenter.default
        let observerSpecs: [(Notification.Name, Any?)] = [
            (NSWindow.didBecomeKeyNotification, window),
            (NSWindow.didResignKeyNotification, window),
            (NSApplication.didBecomeActiveNotification, nil),
            (NSApplication.didResignActiveNotification, nil)
        ]
        windowFocusObservers = observerSpecs.map { name, object in
            notificationCenter.addObserver(
                forName: name,
                object: object,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updatePointerTrackingTimer()
                }
            }
        }
    }

    private func removeWindowFocusObservers() {
        windowFocusObservers.forEach(NotificationCenter.default.removeObserver)
        windowFocusObservers = []
    }

    private var shouldPollPointerOutsideWindow: Bool {
        isDisplayed
            && !isHidden
            && window?.isKeyWindow == true
            && NSApplication.shared.isActive
    }

    private var shouldRunRenderer: Bool {
        isDisplayed && !isHidden && window != nil
    }

    private func revealOrRefreshRenderer() {
        if isHidden {
            isHidden = false
        } else if shouldRunRenderer {
            renderer?.start()
        }
    }

    private func hideUnavailableContent() {
        isDisplayed = false
        if !isHidden {
            isHidden = true
        } else {
            updateRendererRunningState()
            updatePointerTrackingTimer()
        }
    }

    private func updateRendererRunningState() {
        if shouldRunRenderer {
            renderer?.start()
        } else {
            renderer?.stop()
        }
    }

    private func updatePointerTrackingTimer() {
        if shouldPollPointerOutsideWindow {
            startPointerTrackingTimer()
        } else {
            stopPointerTrackingTimer()
        }
    }

    private func startPointerTrackingTimer() {
        guard pointerTrackingTimer == nil else { return }

        pollPointerFromScreen()

        let timer = Timer(timeInterval: Self.pointerTrackingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPointerFromScreen()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTrackingTimer = timer
    }

    private func stopPointerTrackingTimer() {
        pointerTrackingTimer?.invalidate()
        pointerTrackingTimer = nil
        lastPolledScreenLocation = nil
    }

    private func pollPointerFromScreen() {
        guard shouldPollPointerOutsideWindow, let window else {
            updatePointerTrackingTimer()
            return
        }

        let screenLocation = NSEvent.mouseLocation
        guard screenLocation != lastPolledScreenLocation else { return }

        lastPolledScreenLocation = screenLocation
        let windowLocation = window.convertPoint(fromScreen: screenLocation)
        let location = convert(windowLocation, from: nil)
        renderer?.updatePointer(location: location, in: bounds.size)
    }
}

private struct NativeMetalCardPointerState {
    var pointer = SIMD2<Float>(0.5, 0.5)
    var background = SIMD2<Float>(0.5, 0.5)
    var pointerFromCenter: Float = 0
    var effectOpacity: Float = 0.99
}

private final class NativeMetalCardPointerStateTracker {
    static let shared = NativeMetalCardPointerStateTracker()

    private(set) var state = NativeMetalCardPointerState()

    private init() {}

    func update(location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            reset()
            return
        }

        let x = Float(min(max(location.x / size.width, 0), 1))
        let y = Float(min(max(1 - location.y / size.height, 0), 1))
        let pointer = SIMD2<Float>(x, y)
        let centered = pointer - SIMD2<Float>(0.5, 0.5)
        state.pointer = clamped(pointer, lowerBound: 0.04, upperBound: 0.96)
        state.background = clamped(SIMD2<Float>(0.5, 0.5) + centered * 0.32, lowerBound: 0.25, upperBound: 0.75)
        state.pointerFromCenter = min(length(centered) * 2, 1)
        state.effectOpacity = 0.99
    }

    func reset() {
        state = NativeMetalCardPointerState()
    }

    private func clamped(_ value: SIMD2<Float>, lowerBound: Float, upperBound: Float) -> SIMD2<Float> {
        SIMD2<Float>(
            min(max(value.x, lowerBound), upperBound),
            min(max(value.y, lowerBound), upperBound)
        )
    }
}

private final class NativeMetalCardRenderer: NSObject, MTKViewDelegate {

    private weak var metalView: MTKView?
    private let rendererCore: NativeMetalCardRendererCore
    private let pointerTracker = NativeMetalCardPointerStateTracker.shared

    init?(device: MTLDevice) {
        guard let rendererCore = NativeMetalCardRendererCore(device: device, logger: nativeMetalCardLogger) else {
            nativeMetalCardLogger.error("Metal renderer core initialization failed")
            return nil
        }

        self.rendererCore = rendererCore
        super.init()
        self.rendererCore.requestDraw = { [weak self] in
            self?.metalView?.draw()
        }
    }

    func attach(to metalView: MTKView) {
        self.metalView = metalView
    }

    func display(tokenID: Int, renderKind: NativeMetalCardRenderKind) {
        rendererCore.display(tokenID: tokenID, renderKind: renderKind)
    }

    func start() {
        guard metalView?.window != nil else { return }
        metalView?.draw()
    }

    func stop() {
        rendererCore.cancelPrefetchDownloads()
        pointerTracker.reset()
        metalView?.draw()
    }

    func updatePointer(location: CGPoint, in size: CGSize) {
        pointerTracker.update(location: location, in: size)
        metalView?.draw()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.draw()
    }

    func draw(in view: MTKView) {
        let cardRect = cardRect(in: view.bounds.size)
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let pointerState = pointerTracker.state
        let interactionState = NativeMetalCardInteractionState(
            pointer: pointerState.pointer,
            background: pointerState.background,
            pointerFromCenter: pointerState.pointerFromCenter,
            effectOpacity: pointerState.effectOpacity
        )
        rendererCore.draw(
            in: view,
            cardRect: cardRect,
            cardScale: CGSize(width: scale, height: scale),
            interactionState: interactionState
        )
    }

    private func cardRect(in size: CGSize) -> CGRect {
        NativeMetalCardLayout.cardContentRect(in: size)
    }
}
