// ∅ 2026 lil org

import QuartzCore
import UIKit

let mobilePlayerBrowserPlaceholderToneColor = UIColor(
    white: 0.14,
    alpha: 1
)

struct MobilePlayerBrowserContentIdentity: Equatable {
    let collectionId: String
    let tokenIndex: Int
}

struct MobilePlayerBrowserCarryoverLayer {
    let image: UIImage
    let usesNativeMetalCardCornerMask: Bool
    let alpha: CGFloat
}

struct MobilePlayerBrowserCarryoverContent {
    let identity: MobilePlayerBrowserContentIdentity
    let primary: MobilePlayerBrowserCarryoverLayer
    let qualityUpgrade: MobilePlayerBrowserCarryoverLayer?

    init(
        identity: MobilePlayerBrowserContentIdentity,
        image: UIImage,
        usesNativeMetalCardCornerMask: Bool
    ) {
        self.identity = identity
        primary = MobilePlayerBrowserCarryoverLayer(
            image: image,
            usesNativeMetalCardCornerMask: usesNativeMetalCardCornerMask,
            alpha: 1
        )
        qualityUpgrade = nil
    }

    init(
        identity: MobilePlayerBrowserContentIdentity,
        primary: MobilePlayerBrowserCarryoverLayer,
        qualityUpgrade: MobilePlayerBrowserCarryoverLayer?
    ) {
        self.identity = identity
        self.primary = primary
        self.qualityUpgrade = qualityUpgrade
    }
}

typealias MobilePlayerBrowserGridCarryoverSource =
    PlayerBrowserGridCarryoverSource<MobilePlayerBrowserCarryoverContent>

@MainActor
final class MobilePlayerCollectionBrowserTransitionPresentation {
    typealias ContentFadeAnimator = (
        @escaping () -> Void,
        ((Bool) -> Void)?
    ) -> Void

    enum PresentationState: Equatable {
        case empty
        case incoming(identity: MobilePlayerBrowserContentIdentity)
        case carryover(
            identity: MobilePlayerBrowserContentIdentity,
            phase: CarryoverPhase
        )

        var identity: MobilePlayerBrowserContentIdentity? {
            switch self {
            case .empty:
                nil
            case let .incoming(identity), let .carryover(identity, _):
                identity
            }
        }
    }

    enum CarryoverPhase: Equatable {
        case held
        case fading
    }

    enum UpgradeState: Equatable {
        case none
        case installed
        case fading
    }

    enum ToneState: Equatable {
        case hidden
        case heldForBaseLoad
        case fading
    }

    private enum DelayedRole: Hashable {
        case carryoverFade
        case upgradeFade
        case toneFade
    }

    private struct DelayedValidation {
        let generation: UInt
        let role: DelayedRole
        let identity: MobilePlayerBrowserContentIdentity?
    }

    static let contentFadeDuration: TimeInterval = 0.25

    private let contentView: UIView
    private let toneView: UIView
    private let contentFadeAnimator: ContentFadeAnimator
    private var contentContainerView: UIView?
    private var primaryContentView: NativeMetalCardCornerMaskedImageView?
    private var upgradeContentView: NativeMetalCardCornerMaskedImageView?
    private var roleGenerations = [DelayedRole: UInt]()
    private(set) var presentationState: PresentationState = .empty
    private(set) var upgradeState: UpgradeState = .none
    private(set) var toneState: ToneState = .hidden
    /// When the current tone hold began. A cell whose tone went up within
    /// the last frame or two has never been seen without it — its first
    /// image may install instantly, Photos-style. Tone the user has already
    /// watched for a while must crossfade to content instead.
    private(set) var toneHeldSince: CFTimeInterval?

    var hasCarryoverContent: Bool {
        if case .carryover = presentationState {
            true
        } else {
            false
        }
    }

    var holdsToneForBaseLoad: Bool {
        toneState == .heldForBaseLoad
    }

    init(
        contentView: UIView,
        contentFadeAnimator: ContentFadeAnimator? = nil
    ) {
        self.contentView = contentView
        self.contentFadeAnimator = contentFadeAnimator ?? {
            animations,
            completion in
            Self.animateContentFade(
                animations,
                completion: completion
            )
        }
        let toneView = UIView(frame: contentView.bounds)
        toneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        toneView.backgroundColor = mobilePlayerBrowserPlaceholderToneColor
        toneView.isUserInteractionEnabled = false
        toneView.isHidden = true
        toneView.alpha = 0
        contentView.addSubview(toneView)
        self.toneView = toneView
    }

    static func makeContentImageView(
        frame: CGRect
    ) -> NativeMetalCardCornerMaskedImageView {
        let imageView = NativeMetalCardCornerMaskedImageView(frame: frame)
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.makeBackgroundTransparent()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = false
        imageView.isUserInteractionEnabled = false
        imageView.layer.minificationFilter = .trilinear
        return imageView
    }

    static func animateContentFade(
        _ animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: contentFadeDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveLinear],
            animations: animations,
            completion: completion
        )
    }

    func installIncoming(
        image: UIImage,
        usesNativeMetalCardCornerMask: Bool,
        targetAlpha: CGFloat,
        animated: Bool,
        identity: MobilePlayerBrowserContentIdentity
    ) {
        if replaceIncomingIfPresent(
            image: image,
            usesNativeMetalCardCornerMask: usesNativeMetalCardCornerMask,
            targetAlpha: targetAlpha,
            animated: animated,
            identity: identity
        ) {
            return
        }
        setPrimaryContent(
            image: image,
            usesNativeMetalCardCornerMask: usesNativeMetalCardCornerMask,
            alpha: animated ? 0 : targetAlpha,
            state: .incoming(identity: identity)
        )
        if animated {
            animateContentAlpha(to: targetAlpha)
        }
    }

    func setIncomingAlpha(
        _ alpha: CGFloat,
        interruptingAnimation: Bool = false
    ) {
        if interruptingAnimation,
           contentContainerView?.layer.animation(forKey: "opacity") != nil {
            contentContainerView?.layer.removeAnimation(forKey: "opacity")
        }
        guard contentContainerView?.alpha != alpha else { return }
        contentContainerView?.alpha = alpha
    }

    func allowsSelection(
        representing identity: MobilePlayerBrowserContentIdentity
    ) -> Bool {
        !hasCarryoverContent || presentationState.identity == identity
    }

    func clear(preservingCarryover: Bool = false) {
        guard !(preservingCarryover && hasCarryoverContent) else { return }
        invalidate(.carryoverFade)
        invalidate(.upgradeFade)
        presentationState = .empty
        contentContainerView?.layer.removeAllAnimations()
        primaryContentView?.layer.removeAllAnimations()
        contentContainerView?.isHidden = true
        contentContainerView?.alpha = 0
        primaryContentView?.isHidden = true
        primaryContentView?.image = nil
        primaryContentView?.alpha = 1
        primaryContentView?.usesNativeMetalCardCornerMask = false
        clearUpgrade()
    }

    func holdTone() {
        invalidate(.toneFade)
        toneView.layer.removeAllAnimations()
        if toneState != .heldForBaseLoad {
            toneHeldSince = CACurrentMediaTime()
        }
        toneState = .heldForBaseLoad
        toneView.isHidden = false
        toneView.alpha = 1
    }

    func clearTone(animated: Bool) {
        let wasHeld = toneState == .heldForBaseLoad
        toneHeldSince = nil
        invalidate(.toneFade)
        guard animated, wasHeld else {
            toneState = .hidden
            toneView.layer.removeAllAnimations()
            toneView.alpha = 0
            toneView.isHidden = true
            return
        }
        toneState = .fading
        let validation = beginValidation(
            role: .toneFade,
            identity: nil
        )
        contentFadeAnimator(
            { self.toneView.alpha = 0 },
            { [weak self] _ in
                guard let self, self.isValid(validation) else { return }
                self.toneState = .hidden
                self.toneView.isHidden = true
            }
        )
    }

    func installCarryover(_ content: MobilePlayerBrowserCarryoverContent) {
        setPrimaryContent(
            image: content.primary.image,
            usesNativeMetalCardCornerMask:
                content.primary.usesNativeMetalCardCornerMask,
            alpha: 1,
            state: .carryover(identity: content.identity, phase: .held)
        )
        primaryContentView?.alpha = content.primary.alpha
        if let qualityUpgrade = content.qualityUpgrade,
           let contentContainerView {
            let upgrade = ensureUpgradeContentView(in: contentContainerView)
            upgrade.usesNativeMetalCardCornerMask =
                qualityUpgrade.usesNativeMetalCardCornerMask
            upgrade.image = qualityUpgrade.image
            upgrade.alpha = qualityUpgrade.alpha
            upgrade.isHidden = false
            upgradeState = .installed
        }
    }

    func holdCarryoverForRetarget() {
        guard case let .carryover(identity, .fading) = presentationState,
              let contentContainerView else {
            return
        }
        invalidate(.carryoverFade)
        contentContainerView.layer.removeAllAnimations()
        contentContainerView.alpha = 1
        presentationState = .carryover(identity: identity, phase: .held)
    }

    func fadeCarryoverIfNeeded() {
        guard case let .carryover(identity, .held) = presentationState else {
            return
        }
        guard let contentContainerView else {
            presentationState = .empty
            return
        }
        presentationState = .carryover(identity: identity, phase: .fading)
        let validation = beginValidation(
            role: .carryoverFade,
            identity: identity
        )
        RunLoop.main.perform(inModes: [.common]) {
            [weak self, weak contentContainerView] in
            MainActor.assumeIsolated {
                guard let self,
                      let contentContainerView,
                      self.contentContainerView === contentContainerView,
                      self.isValid(validation) else {
                    return
                }
                self.contentFadeAnimator(
                    { contentContainerView.alpha = 0 },
                    {
                        [weak self, weak contentContainerView] _ in
                        guard let self,
                              let contentContainerView,
                              self.contentContainerView === contentContainerView,
                              self.isValid(validation) else {
                            return
                        }
                        self.clear()
                    }
                )
            }
        }
    }

    func sourceContent(
        baseImageView: NativeMetalCardCornerMaskedImageView,
        baseIdentity: MobilePlayerBrowserContentIdentity?
    ) -> MobilePlayerBrowserCarryoverContent? {
        let transitionOpacity = contentContainerView.flatMap { container in
            primaryContentView?.image == nil
                ? nil
                : displayedOpacity(of: container)
        } ?? 0
        let baseOpacity = baseImageView.image == nil
            ? 0
            : displayedOpacity(of: baseImageView)
        let transitionContribution = transitionOpacity
        let baseContribution = (1 - transitionOpacity) * baseOpacity
        let backgroundContribution = (1 - transitionOpacity) * (1 - baseOpacity)

        if transitionContribution > baseContribution,
           transitionContribution > backgroundContribution,
           let identity = presentationState.identity,
           let primaryContentView,
           let image = primaryContentView.image {
            let primary = MobilePlayerBrowserCarryoverLayer(
                image: image,
                usesNativeMetalCardCornerMask:
                    primaryContentView.usesNativeMetalCardCornerMask,
                alpha: 1
            )
            guard let upgradeContentView,
                  let upgradeImage = upgradeContentView.image,
                  !upgradeContentView.isHidden else {
                return MobilePlayerBrowserCarryoverContent(
                    identity: identity,
                    primary: primary,
                    qualityUpgrade: nil
                )
            }
            let upgradeAlpha = displayedUpgradeOpacity(of: upgradeContentView)
            if upgradeAlpha < 0.01 {
                return MobilePlayerBrowserCarryoverContent(
                    identity: identity,
                    primary: primary,
                    qualityUpgrade: nil
                )
            }
            if upgradeAlpha > 0.99 {
                return MobilePlayerBrowserCarryoverContent(
                    identity: identity,
                    image: upgradeImage,
                    usesNativeMetalCardCornerMask:
                        upgradeContentView.usesNativeMetalCardCornerMask
                )
            }
            return MobilePlayerBrowserCarryoverContent(
                identity: identity,
                primary: primary,
                qualityUpgrade: MobilePlayerBrowserCarryoverLayer(
                    image: upgradeImage,
                    usesNativeMetalCardCornerMask:
                        upgradeContentView.usesNativeMetalCardCornerMask,
                    alpha: upgradeAlpha
                )
            )
        }
        if baseContribution > backgroundContribution,
           let baseIdentity,
           let image = baseImageView.image {
            return MobilePlayerBrowserCarryoverContent(
                identity: baseIdentity,
                image: image,
                usesNativeMetalCardCornerMask:
                    baseImageView.usesNativeMetalCardCornerMask
            )
        }
        return nil
    }

    var destinationOverlayOpacity: CGFloat? {
        guard case .incoming = presentationState,
              let contentContainerView,
              primaryContentView?.image != nil else {
            return nil
        }
        return displayedOpacity(of: contentContainerView)
    }

    private func replaceIncomingIfPresent(
        image: UIImage,
        usesNativeMetalCardCornerMask: Bool,
        targetAlpha: CGFloat,
        animated: Bool,
        identity: MobilePlayerBrowserContentIdentity
    ) -> Bool {
        guard case .incoming = presentationState,
              let contentContainerView,
              let primaryContentView,
              !contentContainerView.isHidden,
              !primaryContentView.isHidden,
              primaryContentView.image != nil else {
            return false
        }
        presentationState = .incoming(identity: identity)
        setContentAlpha(targetAlpha, animated: animated)
        if let upgradeContentView,
           !upgradeContentView.isHidden,
           upgradeContentView.image === image,
           upgradeContentView.usesNativeMetalCardCornerMask
                == usesNativeMetalCardCornerMask {
            guard upgradeState == .fading else { return true }
            animateUpgrade(
                upgradeContentView,
                identity: identity,
                primaryContentView: primaryContentView
            )
            return true
        }
        if primaryContentView.image === image,
           primaryContentView.usesNativeMetalCardCornerMask
                == usesNativeMetalCardCornerMask {
            invalidate(.upgradeFade)
            clearUpgrade()
            return true
        }
        invalidate(.upgradeFade)
        clearUpgrade()
        guard animated else {
            primaryContentView.usesNativeMetalCardCornerMask =
                usesNativeMetalCardCornerMask
            primaryContentView.image = image
            return true
        }

        let upgrade = ensureUpgradeContentView(in: contentContainerView)
        upgrade.usesNativeMetalCardCornerMask = usesNativeMetalCardCornerMask
        upgrade.image = image
        upgrade.alpha = 0
        upgrade.isHidden = false
        upgradeState = .fading
        animateUpgrade(
            upgrade,
            identity: identity,
            primaryContentView: primaryContentView
        )
        return true
    }

    private func animateUpgrade(
        _ upgrade: NativeMetalCardCornerMaskedImageView,
        identity: MobilePlayerBrowserContentIdentity,
        primaryContentView: NativeMetalCardCornerMaskedImageView
    ) {
        upgradeState = .fading
        let validation = beginValidation(
            role: .upgradeFade,
            identity: identity
        )
        contentFadeAnimator(
            { upgrade.alpha = 1 },
            {
                [weak self, weak primaryContentView, weak upgrade] _ in
                guard let self,
                      let primaryContentView,
                      let upgrade,
                      self.primaryContentView === primaryContentView,
                      self.upgradeContentView === upgrade,
                      self.isValid(validation) else {
                    return
                }
                primaryContentView.usesNativeMetalCardCornerMask =
                    upgrade.usesNativeMetalCardCornerMask
                primaryContentView.image = upgrade.image
                self.clearUpgrade()
            }
        )
    }

    private func setPrimaryContent(
        image: UIImage,
        usesNativeMetalCardCornerMask: Bool,
        alpha: CGFloat,
        state: PresentationState
    ) {
        invalidate(.carryoverFade)
        invalidate(.upgradeFade)
        let views = ensureContentViews()
        presentationState = state
        views.container.layer.removeAllAnimations()
        views.primary.layer.removeAllAnimations()
        clearUpgrade()
        views.primary.usesNativeMetalCardCornerMask =
            usesNativeMetalCardCornerMask
        views.primary.image = image
        views.primary.alpha = 1
        views.primary.isHidden = false
        views.container.alpha = alpha
        views.container.isHidden = false
    }

    private func ensureContentViews() -> (
        container: UIView,
        primary: NativeMetalCardCornerMaskedImageView
    ) {
        let container: UIView
        if let contentContainerView {
            container = contentContainerView
        } else {
            container = UIView(frame: contentView.bounds)
            container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.makeBackgroundTransparent()
            container.isUserInteractionEnabled = false
            contentView.addSubview(container)
            contentContainerView = container
        }

        let primary: NativeMetalCardCornerMaskedImageView
        if let primaryContentView {
            primary = primaryContentView
        } else {
            primary = Self.makeContentImageView(frame: container.bounds)
            primaryContentView = primary
        }
        if primary.superview !== container {
            container.addSubview(primary)
        }
        return (container, primary)
    }

    private func ensureUpgradeContentView(
        in container: UIView
    ) -> NativeMetalCardCornerMaskedImageView {
        let upgrade: NativeMetalCardCornerMaskedImageView
        if let upgradeContentView {
            upgrade = upgradeContentView
        } else {
            upgrade = Self.makeContentImageView(frame: container.bounds)
            upgradeContentView = upgrade
        }
        if upgrade.superview !== container {
            container.addSubview(upgrade)
        } else {
            container.bringSubviewToFront(upgrade)
        }
        return upgrade
    }

    private func clearUpgrade() {
        upgradeState = .none
        upgradeContentView?.layer.removeAllAnimations()
        upgradeContentView?.isHidden = true
        upgradeContentView?.image = nil
        upgradeContentView?.alpha = 0
        upgradeContentView?.usesNativeMetalCardCornerMask = false
    }

    private func animateContentAlpha(to alpha: CGFloat) {
        guard let contentContainerView else { return }
        contentFadeAnimator(
            { contentContainerView.alpha = alpha },
            nil
        )
    }

    private func setContentAlpha(_ alpha: CGFloat, animated: Bool) {
        guard let contentContainerView else { return }
        guard animated else {
            contentContainerView.layer.removeAllAnimations()
            contentContainerView.alpha = alpha
            return
        }
        contentFadeAnimator(
            { contentContainerView.alpha = alpha },
            nil
        )
    }

    private func displayedOpacity(of view: UIView) -> CGFloat {
        let modelOpacity = view.alpha.isFinite
            ? min(max(view.alpha, 0), 1)
            : 0
        guard !view.isHidden,
              view.window != nil,
              view.layer.animation(forKey: "opacity") != nil,
              let presentationOpacity = view.layer.presentation()?.opacity,
              presentationOpacity.isFinite else {
            return view.isHidden ? 0 : modelOpacity
        }
        return CGFloat(min(max(presentationOpacity, 0), 1))
    }

    private func displayedUpgradeOpacity(of view: UIView) -> CGFloat {
        guard !view.isHidden else { return 0 }
        guard upgradeState == .fading else {
            return view.alpha.isFinite ? min(max(view.alpha, 0), 1) : 0
        }
        guard view.window != nil,
              let presentationOpacity = view.layer.presentation()?.opacity,
              presentationOpacity.isFinite else {
            return 0
        }
        return CGFloat(min(max(presentationOpacity, 0), 1))
    }

    private func beginValidation(
        role: DelayedRole,
        identity: MobilePlayerBrowserContentIdentity?
    ) -> DelayedValidation {
        let generation = (roleGenerations[role] ?? 0) &+ 1
        roleGenerations[role] = generation
        return DelayedValidation(
            generation: generation,
            role: role,
            identity: identity
        )
    }

    private func invalidate(_ role: DelayedRole) {
        roleGenerations[role] = (roleGenerations[role] ?? 0) &+ 1
    }

    private func isValid(_ validation: DelayedValidation) -> Bool {
        guard roleGenerations[validation.role] == validation.generation else {
            return false
        }
        switch validation.role {
        case .carryoverFade:
            guard case let .carryover(identity, .fading) = presentationState else {
                return false
            }
            return identity == validation.identity
        case .upgradeFade:
            return upgradeState == .fading
                && presentationState.identity == validation.identity
        case .toneFade:
            return toneState == .fading && validation.identity == nil
        }
    }
}
