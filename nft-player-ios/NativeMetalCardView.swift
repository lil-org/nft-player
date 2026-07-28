// ∅ 2026 lil org

import CoreMotion
import Foundation
import MetalKit
import UIKit
import os
import simd

private let nativeMetalCardLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
    category: "NativeMetalCard"
)

final class NativeMetalCardView: UIView {

    private var renderer: NativeMetalCardRenderer?
    private var isDisplayed = false

    override var isHidden: Bool {
        didSet {
            if oldValue != isHidden {
                updateRendererRunningState()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        configureMetalView()
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        updateRendererRunningState()
    }

    func display(
        tokenId: String,
        renderKind: NativeMetalCardRenderKind,
        onContentReady: (() -> Void)? = nil
    ) {
        guard let tokenID = Int(tokenId) else {
            hideUnavailableContent()
            return
        }

        isDisplayed = true
        renderer?.display(tokenID: tokenID, renderKind: renderKind, onContentReady: onContentReady)
        revealOrRefreshRenderer()
    }

    func stop() {
        isDisplayed = false
        updateRendererRunningState()
    }

    static func resetMotionCalibration() {
        NativeMetalCardMotionTracker.shared.resetCalibration()
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
        metalView.backgroundColor = .clear
        metalView.isOpaque = false
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
        }
    }

    private func updateRendererRunningState() {
        if shouldRunRenderer {
            renderer?.start()
        } else {
            renderer?.stop(discardPendingContentReady: !isDisplayed)
        }
    }
}

private struct NativeMetalCardMotionState {
    var pointer = SIMD2<Float>(0.5, 0.5)
    var background = SIMD2<Float>(0.5, 0.5)
    var pointerFromCenter: Float = 0
    var effectOpacity: Float = 0
}

private final class NativeMetalCardMotionTracker {

    static let shared = NativeMetalCardMotionTracker()
    private static let fixedLightPosition = SIMD2<Float>(0.5, 0.5)
    private static let pointerTravel = SIMD2<Float>(0.42, 0.42)
    private static let backgroundTravel = SIMD2<Float>(0.13, 0.17)

    private let motionManager = CMMotionManager()
    private var neutralGravity: CMAcceleration?
    private var state = NativeMetalCardMotionState()
    private var observers = [UUID: () -> Void]()
    private var applicationIsActive = UIApplication.shared.applicationState == .active
    private var applicationLifecycleObservers = [NSObjectProtocol]()

    private init() {
        installApplicationLifecycleObservers()
    }

    deinit {
        applicationLifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func addObserver(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeObserver(id: UUID) {
        observers[id] = nil
        if observers.isEmpty {
            stopDeviceMotionUpdates(resetCalibration: false)
        }
    }

    func start() {
        guard applicationIsActive else {
            resetCalibration(notifyObservers: false)
            return
        }
        guard motionManager.isDeviceMotionAvailable else {
            if state.effectOpacity == 0 {
                updateEffect(rawX: 0, rawY: 0, smooth: false)
            }
            return
        }
        guard !motionManager.isDeviceMotionActive else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self,
                  self.applicationIsActive,
                  !self.observers.isEmpty,
                  let motion else {
                return
            }
            self.handleMotion(motion)
        }
    }

    func snapshot() -> NativeMetalCardMotionState {
        state
    }

    func resetCalibration() {
        resetCalibration(notifyObservers: applicationIsActive)
    }

    private func resetCalibration(notifyObservers: Bool) {
        neutralGravity = nil
        updateEffect(rawX: 0, rawY: 0, smooth: false, notifyObservers: notifyObservers)
    }

    private func installApplicationLifecycleObservers() {
        let notificationCenter = NotificationCenter.default
        let inactiveNotifications: [NSNotification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification
        ]

        applicationLifecycleObservers = inactiveNotifications.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspendForApplicationLifecycle()
            }
        }
        applicationLifecycleObservers.append(
            notificationCenter.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.resumeFromApplicationLifecycle()
            }
        )
    }

    private func suspendForApplicationLifecycle() {
        guard applicationIsActive else { return }

        applicationIsActive = false
        stopDeviceMotionUpdates(resetCalibration: true, notifyObservers: false)
    }

    private func resumeFromApplicationLifecycle() {
        applicationIsActive = true
        resetCalibration()

        guard !observers.isEmpty else { return }
        start()
    }

    private func stopDeviceMotionUpdates(resetCalibration: Bool, notifyObservers: Bool = true) {
        motionManager.stopDeviceMotionUpdates()

        if resetCalibration {
            self.resetCalibration(notifyObservers: notifyObservers)
        }
    }

    private func handleMotion(_ motion: CMDeviceMotion) {
        if neutralGravity == nil {
            neutralGravity = motion.gravity
            if state.effectOpacity == 0 {
                updateEffect(rawX: 0, rawY: 0, smooth: false)
            }
            return
        }

        guard let neutralGravity else { return }

        let rawX = Self.clamped(Float((motion.gravity.x - neutralGravity.x) * 4.0))
        let rawY = Self.clamped(Float((neutralGravity.z - motion.gravity.z) * 4.8))
        updateEffect(rawX: rawX, rawY: rawY, smooth: true)
    }

    private func updateEffect(rawX: Float, rawY: Float, smooth: Bool, notifyObservers: Bool = true) {
        let cardTilt = SIMD2<Float>(Self.clamped(rawX), Self.clamped(rawY))
        let cardOffset = cardTilt * Self.pointerTravel
        let backgroundOffset = cardTilt * Self.backgroundTravel

        let targetPointer = Self.clamped(
            Self.fixedLightPosition - cardOffset,
            lowerBound: 0.04,
            upperBound: 0.96
        )
        let targetBackground = Self.clamped(
            Self.fixedLightPosition - backgroundOffset,
            lowerBound: 0.25,
            upperBound: 0.75
        )

        let smoothing: Float = smooth ? 0.30 : 1
        state.pointer += (targetPointer - state.pointer) * smoothing
        state.pointer = Self.clamped(state.pointer, lowerBound: 0.01, upperBound: 0.99)

        state.background += (targetBackground - state.background) * smoothing
        state.background = Self.clamped(state.background, lowerBound: 0.12, upperBound: 0.88)
        state.pointerFromCenter = min(length(cardTilt), 1)
        state.effectOpacity = 0.99
        if notifyObservers {
            self.notifyObservers()
        }
    }

    private func notifyObservers() {
        guard applicationIsActive else { return }
        Array(observers.values).forEach { $0() }
    }

    private static func clamped(_ value: Float) -> Float {
        min(max(value, -1), 1)
    }

    private static func clamped(_ value: SIMD2<Float>, lowerBound: Float, upperBound: Float) -> SIMD2<Float> {
        SIMD2<Float>(
            min(max(value.x, lowerBound), upperBound),
            min(max(value.y, lowerBound), upperBound)
        )
    }
}

private final class NativeMetalCardRenderer: NSObject, MTKViewDelegate {

    private weak var metalView: MTKView?
    private let rendererCore: NativeMetalCardRendererCore
    private let motionTracker = NativeMetalCardMotionTracker.shared

    private var motionObserverID: UUID?
    private var activeContentPresentationID: UUID?
    private var pendingContentReadyCallback: (() -> Void)?

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

    deinit {
        stop()
    }

    func attach(to metalView: MTKView) {
        self.metalView = metalView
    }

    func display(
        tokenID: Int,
        renderKind: NativeMetalCardRenderKind,
        onContentReady: (() -> Void)?
    ) {
        invalidatePendingContentReadyCallback()
        if let onContentReady {
            activeContentPresentationID = UUID()
            pendingContentReadyCallback = onContentReady
        }
        rendererCore.display(tokenID: tokenID, renderKind: renderKind)
    }

    func start() {
        guard metalView?.window != nil else { return }
        if motionObserverID == nil {
            motionObserverID = motionTracker.addObserver { [weak self] in
                self?.metalView?.draw()
            }
        }
        motionTracker.start()
        metalView?.draw()
    }

    func stop(discardPendingContentReady: Bool = true) {
        rendererCore.cancelPrefetchDownloads()
        rendererCore.cancelContentReadyCallbacks()
        if discardPendingContentReady {
            invalidatePendingContentReadyCallback()
        }
        guard let motionObserverID else { return }
        motionTracker.removeObserver(id: motionObserverID)
        self.motionObserverID = nil
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.draw()
    }

    func draw(in view: MTKView) {
        let cardRect = cardRect(in: view.bounds.size)
        let scaleX = view.bounds.width > 0 ? view.drawableSize.width / view.bounds.width : view.contentScaleFactor
        let scaleY = view.bounds.height > 0 ? view.drawableSize.height / view.bounds.height : view.contentScaleFactor
        let motionState = motionTracker.snapshot()
        let interactionState = NativeMetalCardInteractionState(
            pointer: motionState.pointer,
            background: motionState.background,
            pointerFromCenter: motionState.pointerFromCenter,
            effectOpacity: motionState.effectOpacity
        )
        let onContentFramePresented: (() -> Void)?
        if pendingContentReadyCallback != nil,
           let presentationID = activeContentPresentationID {
            onContentFramePresented = { [weak self] in
                DispatchQueue.main.async {
                    guard let self,
                          self.activeContentPresentationID == presentationID,
                          let callback = self.pendingContentReadyCallback else {
                        return
                    }

                    self.activeContentPresentationID = nil
                    self.pendingContentReadyCallback = nil
                    callback()
                }
            }
        } else {
            onContentFramePresented = nil
        }
        rendererCore.draw(
            in: view,
            cardRect: cardRect,
            cardScale: CGSize(width: scaleX, height: scaleY),
            interactionState: interactionState,
            onContentFramePresented: onContentFramePresented
        )
    }

    private func invalidatePendingContentReadyCallback() {
        activeContentPresentationID = nil
        pendingContentReadyCallback = nil
    }

    private func cardRect(in size: CGSize) -> CGRect {
        NativeMetalCardLayout.cardContentRect(in: size)
    }
}
