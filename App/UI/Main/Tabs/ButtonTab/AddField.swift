//
// --------------------------------------------------------------------------
// AddField.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2022
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

///
/// [Sep 12 2025] Context:
///     Replaced with `AddField_New.swift` for macOS Tahoe, but then reverted to this . See `AddField_New.swift` for more.
///
///     We reverted by copy-pasting commit d814e3d
///

import Cocoa

@objc class AddField: NSBox {

    /// Storage
    
    @IBOutlet var plusIconView: NSImageView!
    
    /// Drawing
    ///     Overriding draw() breaks desktop tinting even if we just call super.draw()
    
//    override func draw(_ dirtyRect: NSRect) {
//        super.draw(dirtyRect)
//
//        // Drawing code here.
//    }
    
    var appearanceObservation: NSKeyValueObservation? = nil
    
    func coolInit() {
        
        /// Override icon on older macOS
        /// Explanation: We bundle an svg fallback for the SFSymbol that is used by default, but the resolution is wayy to low it's rendered too large. Maybe there's a more elegant solution but this should work.
        /// Notes:
        /// - Actually maybe we should just use NSAddTemplate in the first place even on newer macOS?
        /// - I think this makes it unnecessary that we bundle the svg fallback for the 'add' SFSymbol
        
        if #available(macOS 11.0, *) { } else {
            plusIconView.image = NSImage(named: NSImage.addTemplateName)
        }
        
        /// Fix hover animations
        ///     Need to set some shadow before (and not directly, synchronously before) the hover animation first plays. No idea why this works
        self.shadow = .clearShadow
        plusIconView.shadow = .clearShadow
        
        /// Make colors non-transparent
        updateColors()

        /// Show how to add a button: an animated mouse left of the '+'
        installGestureHint()
        
        /// Observe darkmode changes to update colors (we do the same thing in RemapTable)
        if #available(macOS 10.14, *) {
            appearanceObservation = NSApp.observe(\.effectiveAppearance) { nsApp, change in
                self.updateColors()
            }
        }
    }
    
    func updateColors() {
        
        /// Explanation / why this is complicated [Aug 2025]
        ///     We want the AddField to simply look like a NSPrimaryBox with a '+' in the middle.
        ///     And that's exactly what the AddField was in MMF 2
        ///     However, in MMF 3, we wanted to a an effect where the AddField raises slightly when you hover over it. The 'raise' effect applies a shadow to the AddField.
        ///     Problem:
        ///         NSPrimaryBox is transparent, so when you apply a shadow to make it look raised up, it just looks blurry!
        ///     Solution ideas:
        ///     - Apply non-transparent custom colors
        ///         -> but those don't support wallpaper tinting, which ends up looking broken.
        ///     - Choose specific *system* NSColors for which NSBox *does* enable wallpaper tinting:
        ///         -> The solution we shipped for MMF 3
        ///             – This made the code a bit more complicated and less maintainable since we have to draw an NSCustomBox which emulates an NSPrimaryBox. We also didn't manage to perfectly emulate the look, since only a few colors were available.
        ///     - Try to render a custom NSShadow to a bitmap and then draw that
        ///         -> Too complicated (See 35742760e0bb0c126e16183f11f65532953822cb)
        ///     - Set .windowBackgroundColor to the NSBox's CAlayer
        ///         -> Almost works but also doesn't support wallpaper tinting.
        ///         -> This allows you to use NSPrimaryBox instead of NSCustomBox.
        ///     - Try to find some private API that gives you the 'wallpaperTintColor' and then mix that in with your NSColors
        ///         -> I don't think this exists. Evidence:
        ///             - When you set one of the special system colors that enable wallpaper tinting to NSBox, the NSBox will actually secretly insert an *NSVisualEffectsView* as its subview. Also, other views than NSBox don't support wallpaper tinting at all. So it seems wallpaper tinting always requires an NSVisualEffectsView and cannot be done at the NSColor level (Which would be much simpler and more flexible, and which I originally assumed)
        ///                 Also see: Assembly of `[_NSBoxMaterialCapableCustomView _updateSubviews]` on macOS Tahoe Beta 8
        ///             - This kind of makes sense from a security perspective. If apps could directly access the colors of the windows behind them, then they could possibly reconstruct a sharp image of the background-windows via "multi-frame super-resolution" techniques. I assume that, instead, the `NSVisualEffectBlendingModeBehindWindow` happens in that background process that does the CALayer rendering or whatever. [Aug 2025]
        ///     - Take a screenshot of a tinted view and then sample the color to get the 'wallpaperTintColor' to mix with your NSColors.
        ///         -> This could work – IIRC, we're already taking such screnshots for the ResizingTabWindow transitions ... Update: True, but it's using the deprecated CGWindowListCreateImage() API.
        ///     - Put our own NSVisualEffectsView behind / inside the NSBox
        ///         -> Since this is what NSBox does natively (See above), it may be the most robust approach.
        ///         -> This way we could simply keep using NSPrimaryBox, to get the desired styling with little effort
        ///
        ///     Also see:
        ///         - This old, reverted commit from 2022 35742760e0bb0c126e16183f11f65532953822cb
        ///             - Here, we tried to do custom drawing for the shadow
        ///             - We also found 4 NSColors for which NSBox enables wallpaper tinting: .controlBackgroundColor, .textBackgroundColor, .underPageBackgroundColor, .windowBackgroundColor
        ///                 (found them by searching for 'background', maybe there are more)
        ///         - Commit before we removed all the old comments, and wrote one, comprehensive comment up top [Aug 2025] e7fc400a0ac84baba4b9ad2548f3cdecf906272c
        ///         - The solidColor methods from NSColor+Additions.m – In older notes we said we tried those here but they didn't work
        ///
        ///     Sidenotes:
        ///         - We could simplify some of the code that shipped for MMF 3 a little but using `+[NSColor colorWithName:dynamicProvider:]` However, that had a bug that broke desktop tinting on earlier Tahoe Betas until we filed FB18739714 with Apple. (Thanks!) (I assume it was also broken on Sequoia, but I didn't test.)
        ///             - Also see:  [Jun 2025]  `mfl_dynamiccolor()` wrapper around  `+[NSColor colorWithName:dynamicProvider:]` which we wrote in the `swiftui-test-tahoe-beta` project.
        
        /// TESTING
        /// Set NSPrimaryBox style
        if (false), #available(macOS 26.0, *) {
            
            self.wantsLayer = true
            self.boxType = .primary /// [Aug 2025] This doesn't really belong in 'updateColors()' – TODO: maybe clean this up.
            
            if (false) {
                mfrun(CFRunLoopGetMain()) {
                    (MainAppState.shared.window?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance { /// [Aug 2025] seems to be necessary as of Tahoe Beta 8. Not sure why. Otherwise the color will never change when appearance changes after the app is first launched. Credit: https://stackoverflow.com/a/79490975/10601702
                        self.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                    }
                }
            }
            if (true) {
                self.boxType = .custom
                if (false)  { self.fillColor = .windowBackgroundColor }
                else        { self.fillColor = .systemGreen }
            }
            
            /// Make the layer corners match the NSPrimaryBox
            do {
                self.layer?.cornerCurve = .continuous
                self.layer?.cornerRadius = 13 /// [Aug 2025] Not sure if 12 or 13
            }
        }
        else {
            
            /// Prepare
            self.wantsLayer = true
            let isDarkMode = checkDarkMode()

            /// Update fillColor
            do {

                /// v New systemColor approach
                /// Color choice notes: `[Pre-Tahoe]`
                ///     - I found these colors that support tinting (found them by searching for 'background', maybe there are more):
                ///         - .controlBackgroundColor, .textBackgroundColor, .underPageBackgroundColor, .windowBackgroundColor
                ///     - Lightmode: .underPageBackgroundColor is not semantic but it looks perfect.
                ///     - Darkmode: .controlBackgroundColor looks good while tinting, but is too dark otherwise. .textBackgroundColor is the same. .underPageBackgroundColor is even darker. -> best choice is .windowBackgroundColor
                if isDarkMode   { self.fillColor = .windowBackgroundColor }
                else            { self.fillColor = .underPageBackgroundColor }
                
                /// v Old solidColor approach
                
                if (false) {
                
                    /// Get baseColor
                    let baseColor: NSColor = isDarkMode ? .black : .white

                    /// Define baseColor blending fractions
                    let fillFraction = isDarkMode ? 0.1 : 0.25
                    let borderFraction = isDarkMode ? 0.1 : 0.25
                
                    var quarternayLabelColor: NSColor
                    if isDarkMode {
                        quarternayLabelColor = NSColor(red: 57/255, green: 57/255, blue: 57/255, alpha: 1.0)
                    } else {
                        quarternayLabelColor = NSColor(red: 227/255, green: 227/255, blue: 227/255, alpha: 1.0)
                    }
            
                    self.fillColor = quarternayLabelColor.blended(withFraction: fillFraction, of: baseColor)!
                }
            }
            
            /// Update borderColor
            do {
                /// v New systemColor approach
                ///     Using systemColors now to properly support desktop tinting. Also the transparency isn't an issue at all here, not sure why we did the old solidColor approach in the first place
                
                if #available(macOS 10.14, *)   { self.borderColor = .separatorColor }
                else                            { self.borderColor = .gridColor }
                
                /// v Old solidColor approach
                ///     This is really just .separatorColor without transparency
                
                if (false) {
                
                    /// Get baseColor
                    let baseColor: NSColor = isDarkMode ? .black : .white

                    /// Define baseColor blending fractions
                    let fillFraction = isDarkMode ? 0.1 : 0.25
                    let borderFraction = isDarkMode ? 0.1 : 0.25
                
                    let separatorColor: NSColor
                    if isDarkMode {
                        separatorColor = NSColor(red: 77/255, green: 77/255, blue: 77/255, alpha: 1.0)
                    } else {
                        separatorColor = NSColor(red: 198/255, green: 198/255, blue: 198/255, alpha: 1.0)
                    }
            
                    self.borderColor = separatorColor.blended(withFraction: borderFraction, of: baseColor)!
                }
            }
            
            /// Make border thicker in darkmode
            ///     Since the addField is now the same color as the windowBackground in darkmode we want to give it more visual presence this way
            
            if isDarkMode {
                self.borderWidth = 1.5
            } else {
                self.borderWidth = 1.0
            }
        
        }
        
        /// Update plusIcon color
        if #available(macOS 10.14, *) {
            plusIconView.contentTintColor = plusIconViewBaseColor()
        }
        
        /// Testing
        ///     Doesn't seem to change anything
        self.needsDisplay = true
    }
    
    /// Visual FX
    
    func hoverEffect(enable: Bool, playAcceptAnimation: Bool = false) {
        /// Ideas: Draw focus ring or shadow, or zoom

        /// Debug

        DDLogDebug("FIELD HOOVER: \(enable)")

        /// Init
        self.wantsLayer = true
        self.layer?.transform = CATransform3DIdentity
        self.coolSetAnchorPoint(anchorPoint: .init(x: 0.5, y: 0.5))

        if !enable {

            
            /// Animation curve
            
            let animation       = CASpringAnimation(speed: 2.25, damping: 1.0)
            let bounceAnimation = CASpringAnimation(speed: 3.75, damping: 0.25, initialVelocity: -10)
            let transformAnimation = playAcceptAnimation ? bounceAnimation : animation
            
            /// Make shadow animation.
            ///     [Aug 2025] We used to just use the transformAnimation as the shadowAnimation.
            ///     However, on some macOS versions, the overshoot caused visual glitches:
            ///         - Pre-Ventura, having overshoot in the shadow animation causes visual glitches
            ///         - [Aug 2025] the pre-Ventura glitches seem to be back – in macOS 15.5 Sequoia, on my 2018 Intel Mac Mini
            ///             (I haven't tested if the glitches occur on macOS 14, too)
            ///         - [Aug 2025] the pre-Ventura glitches are gone again – In macOS 26 Tahoe Beta 5, on my M1 MBA
            ///
            ///     Solutions we tried:
            ///         - Always use the `animation` instead of the `bounceAnimation` for the shadow to prevent overshoot.
            ///             > But that animation only removes the shadow shortly *after* the addField 'hits the ground', which looks a bit weird.
            ///         - Always use the`bounceAnimation` for the shadow, but put a 'clamp' on it  to keep it from overshooting.
            ///             - CoreAnimation doesn't let you do that. The CAAnimation objects are only parameter-holders for algorithms that run somewhere deep inside the CoreAnimation framework. (In a different process I think) (Might be wrong about this)
            ///             - The most customization you get is using a CASpringAnimation or CAMediaTimingFunction (cubic bezier). CAKeyFrameAnimation requires you to create an object for every keyframe. None of these are suited to creating a completely customized animation curve that could do something like 'clamping'.  (Might be wrong about all of this)
            ///             - Did a slight bit of reverse engineering on CASpringAnimation:
            ///                 CASpringAnimation seems to be copied into a C++ struct/class (`CA::Render::SpringAnimation::SpringAnimation()`) before actually being queried. The copying happens in `-[CASpringAnimation _copyRenderAnimationForLayer:]` and `-[CASpringAnimation _setCARenderAnimation:layer:]
            ///         - Measure the time when the animation first overshoots and create a shadow animation based on that.
            ///             > This is what we're using as of [Aug 2025]
            ///     Other solution ideas:
            ///         - Perhaps we could've removed the visual glitches without removing the overshoot.
            ///             > It's a bit weird how we're animating the shadow out by setting `NSShadow.clearShadow`, and I think that also interacts in complex ways with our `ReactiveAnimatorPropertyProxy`. Maybe the problem lies somewhere in there.
            ///         - Use CVDisplayLink
            ///             - This gives us full control over the animation, but loses the optimizations that CAAnimation claims (Doing the animations in the 'hardware' instead of the 'software'. See:  Core Animation Programming Guide > Core Animation Basics) (I have some reason to doubt that this matters)
            
            var shadowAnimation: CABasicAnimation
            do {
                if transformAnimation == animation {
                    if (true) { shadowAnimation = transformAnimation }
                    else      { shadowAnimation = CABasicAnimation(name: .linear, duration: transformAnimation.duration) } /// [Aug 2025] When we do this, the non-bouncy zoom-out animation of the addField seems much longer. (macOS 15.5, 2018 Mac Mini) Not sure what's going on. Perhaps getting `transformAnimation.duration` modifies the animation?
                }
                else if transformAnimation == bounceAnimation {
                    var firstOvershootTime = -1.0;
                    let framesPerSecond = 60;
                    let samplesPerFrame = 10;
                    let samplesPerSecond = Int32(framesPerSecond * samplesPerFrame) /// [Aug 2025] Making this many samples feels slow, but I think it's actually fast. To optimize I think we could lower the number of samples (haven't looked into when quality drops off), only calculate the samples up to the first overshoot, or reuse the transition-point-finder algorithm from BezierHybridCurve
                    let samples = MFCABasicAnimation_Sample(transformAnimation, samplesPerSecond)
                    
                    for (i, sample) in samples.enumerated() {
                        if sample.doubleValue >= 1.0 {
                            firstOvershootTime = Double(i) / Double(samplesPerSecond)
                            break
                        }
                    }
                    if firstOvershootTime != -1.0 {
                        shadowAnimation = CABasicAnimation(name: .linear, duration: firstOvershootTime)
                    }
                    else {
                        assert(false)
                        shadowAnimation = CABasicAnimation(name: .linear, duration: transformAnimation.duration) /// [Aug 2025] We only hit this case if it turns out the weird private stuff inside `MFCABasicAnimation_Sample()` is not portable and it fails.
                    }
                }
                else { fatalError() }
            }
            
            /// Play animation
            
            Animate.with(transformAnimation) {
                self.reactiveAnimator().layer.transform.set(CATransform3DIdentity)
            }
            Animate.with(shadowAnimation) {
                
//                var isDarkMode = false
//                if #available(macOS 10.14, *) {
//                    isDarkMode = (NSApp.effectiveAppearance == .init(named: .darkAqua)!)
//                }
//                let baseShadow = NSShadow() /// NSShadow.clearShadow
//                baseShadow.shadowColor = .shadowColor.withAlphaComponent(isDarkMode ? 0.75 : 0.225)
//                baseShadow.shadowOffset = NSMakeSize(0, 0)
//                baseShadow.shadowBlurRadius = 0.0
                
                self.reactiveAnimator().shadow.set(NSShadow.clearShadow)
            }
            

            /// Play tint animation

            if #available(macOS 10.14, *) {
                if playAcceptAnimation {
                    Animate.with(CASpringAnimation(speed: 3.5, damping: 1.0)) {
                        plusIconView.reactiveAnimator().contentTintColor.set(NSColor.controlAccentColor)
                    } onComplete: {
                        assertRunLoop(CFRunLoopGetMain());
                        Timer.mf_scheduledTimer(withTimeInterval: 1.5, mode: .common) { timer in /// This timer is not terminated when unhover is triggered some other way, leading to slightly weird behaviour
                            Animate.with(CASpringAnimation(speed: 3.5, damping: 1.3)) {
                                self.plusIconView.reactiveAnimator().contentTintColor.set(self.plusIconViewBaseColor())
                            }
                        }
                    }
                } else { /// Normal un-hovering
                    Animate.with(CASpringAnimation(speed: 3.5, damping: 1.3)) {
                        self.plusIconView.reactiveAnimator().contentTintColor.set(self.plusIconViewBaseColor())
                    }
                }
            }


        } else {

            /// Setup addField shadow

            var isDarkMode = checkDarkMode()

            let s = NSShadow()
            if #available(macOS 26.0, *) {
                s.shadowColor = .shadowColor.withAlphaComponent(isDarkMode ? 0.75 : 0.125) /// [Aug 2025] lighten the shadow on Tahoe since everything's lighter. TODO: Play around a little bit to perfect it.
                s.shadowOffset = .init(width: 0, height: -2)
                s.shadowBlurRadius = 1.5
            }
            else {
                s.shadowColor = .shadowColor.withAlphaComponent(isDarkMode ? 0.75 : 0.225)
                s.shadowOffset = .init(width: 0, height: -2)
                s.shadowBlurRadius = 1.5
            }

            self.wantsLayer = true
            self.layer?.masksToBounds = false
            self.superview?.wantsLayer = true
            self.superview?.layer?.masksToBounds = false

            /// Setup plusIcon shadow

            let t = NSShadow()
            t.shadowColor = .shadowColor.withAlphaComponent(0.5)
            t.shadowOffset = .init(width: 0, height: -1)
            t.shadowBlurRadius = /*3*/10

            plusIconView.wantsLayer = true
            plusIconView.layer?.masksToBounds = false
            plusIconView.superview?.wantsLayer = true
            plusIconView.superview?.layer?.masksToBounds = false

            /// Animate

            Animate.with(CASpringAnimation(speed: 3.75, damping: 1.0)) {
                self.reactiveAnimator().layer.transform.set(CATransform3DTranslate(CATransform3DMakeScale(1.005, 1.005, 1.0), 0.0, 1.0, 0.0))
                self.reactiveAnimator().shadow.set(s)
            }

            //Timer.mf_scheduledTimer(withTimeInterval: 0.05, mode: .common) { timer in
            //    Animate.with(CABasicAnimation(name: .default, duration: 0.25)) {
            //        self.plusIconView.reactiveAnimator().shadow.set(t)
            //    }
            //}
        }

    }
    
    private func plusIconViewBaseColor() -> NSColor { return NSColor.systemGray }
    
    private func checkDarkMode() -> Bool {
        
        if #available(macOS 10.14, *) {
            let isDarkMode = (NSApp.effectiveAppearance == .init(named: .darkAqua)!)
            return isDarkMode
        }
        return false
    }
    
}

extension AddField {

    /// Puts the animated mouse hint left of the '+', and a '?' button in the corner that shows the hint again. See `MouseGestureHintView`.
    func installGestureHint() {
        guard let container = plusIconView.superview else { return }

        let hint = MouseGestureHintView()
        hint.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hint)

        let help = NSButton()
        help.translatesAutoresizingMaskIntoConstraints = false
        help.isBordered = false
        help.imagePosition = .imageOnly
        help.image = SFSymbolStrings.image(withSymbolName: "questionmark.circle", accessibilityDescription: MFLocalizedString("add-field.hint.help.tooltip", comment: ""))
        help.toolTip = MFLocalizedString("add-field.hint.help.tooltip", comment: "")
        help.target = self
        help.action = #selector(toggleGestureHint(_:))
        container.addSubview(help)

        NSLayoutConstraint.activate([
            hint.centerYAnchor.constraint(equalTo: plusIconView.centerYAnchor),
            hint.centerXAnchor.constraint(equalTo: plusIconView.centerXAnchor, constant: -150),
            help.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            help.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            help.widthAnchor.constraint(equalToConstant: 18),
            help.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    /// The hint in this field, once it is installed
    func gestureHint() -> MouseGestureHintView? {
        return plusIconView.superview?.subviews.compactMap { $0 as? MouseGestureHintView }.first
    }

    /// Shows the hint, playing it from the start, or hides it
    func setGestureHintVisible(_ visible: Bool) {
        guard let hint = gestureHint() else { return }
        if visible && hint.isHidden {
            hint.isHidden = false
            hint.restartAnimation()
        } else if !visible {
            hint.isHidden = true
        }
    }

    /// The '?' button: shows the hint again, or hides it if it is showing
    @objc func toggleGestureHint(_ sender: NSButton) {
        setGestureHintVisible(gestureHint()?.isHidden ?? false)
    }
}

/// Animated hint for the add field. A mouse is shown on its own, and three gestures are played on it, each named under the mouse:
/// Click, Double Click, Click and Drag. These are the gestures the button table offers. The mouse itself stays still, and the drag is shown by an arrow.
/// The pauses between the gestures are long enough to read the names. With Reduce Motion on, it shows the mouse and the first name, without animation.
final class MouseGestureHintView: NSView {

    /// The mouse. Its left button is lit while it is pressed.
    private let mouse = CALayer()
    private let body = CAShapeLayer()
    private let split = CAShapeLayer()
    private let leftButton = CALayer()
    private let clickRing = CAShapeLayer()
    /// Shown during the drag, from the left button to the right
    private let dragArrow = CAShapeLayer()
    /// The gesture names. One of them is shown at a time, under the mouse.
    private let nameLayers = [CATextLayer(), CATextLayer(), CATextLayer()]

    /// The names of the gestures, in the order they are played
    private static let nameKeys = ["add-field.hint.click", "add-field.hint.double-click", "add-field.hint.click-and-drag"]

    /// Length of one loop in seconds. The keyframe times below are seconds within one loop.
    private static let loopDuration: Double = 18.0
    private static let viewSize = NSSize(width: 200, height: 130)
    /// The mouse, in this view's coordinates
    private static let mouseFrame = CGRect(x: 77, y: 44, width: 46, height: 66)
    /// The center of the left button, in the mouse's coordinates
    private static let leftButtonCenter = CGPoint(x: 11.5, y: 52)
    /// How far the mouse moves to the right during the drag
    private static let dragDistance: CGFloat = 44

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: MouseGestureHintView.viewSize))
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: NSSize { MouseGestureHintView.viewSize }

    private func setUp() {

        wantsLayer = true
        setAccessibilityElement(false) /// Purely decorative

        mouse.frame = MouseGestureHintView.mouseFrame
        mouse.opacity = 0
        layer?.addSublayer(mouse)
        let mouseBounds = mouse.bounds

        body.frame = mouseBounds
        body.path = CGPath(roundedRect: mouseBounds, cornerWidth: 20, cornerHeight: 20, transform: nil)
        body.lineWidth = 1.5
        mouse.addSublayer(body)

        /// The line that separates the buttons: across the top of the buttons, and down the middle
        let splitPath = CGMutablePath()
        splitPath.move(to: CGPoint(x: 0, y: 38))
        splitPath.addLine(to: CGPoint(x: mouseBounds.width, y: 38))
        splitPath.move(to: CGPoint(x: mouseBounds.midX, y: 38))
        splitPath.addLine(to: CGPoint(x: mouseBounds.midX, y: mouseBounds.height))
        split.frame = mouseBounds
        split.path = splitPath
        split.fillColor = nil
        split.lineWidth = 1.5
        mouse.addSublayer(split)

        leftButton.frame = CGRect(x: 3, y: 41, width: 17, height: 22)
        leftButton.cornerRadius = 8
        leftButton.opacity = 0
        mouse.addSublayer(leftButton)

        let center = MouseGestureHintView.leftButtonCenter
        clickRing.frame = mouseBounds
        clickRing.path = CGPath(ellipseIn: CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30), transform: nil)
        clickRing.fillColor = nil
        clickRing.lineWidth = 2
        clickRing.opacity = 0
        mouse.addSublayer(clickRing)

        /// The drag arrow, in this view's coordinates: from the left button to just past where the button ends up after the drag
        let start = CGPoint(x: MouseGestureHintView.mouseFrame.minX + center.x, y: MouseGestureHintView.mouseFrame.minY + center.y)
        let end = CGPoint(x: start.x + MouseGestureHintView.dragDistance + 22, y: start.y)
        let arrowPath = CGMutablePath()
        arrowPath.move(to: start)
        arrowPath.addLine(to: end)
        arrowPath.move(to: CGPoint(x: end.x - 9, y: end.y + 6))
        arrowPath.addLine(to: end)
        arrowPath.addLine(to: CGPoint(x: end.x - 9, y: end.y - 6))
        dragArrow.frame = CGRect(origin: .zero, size: MouseGestureHintView.viewSize)
        dragArrow.path = arrowPath
        dragArrow.fillColor = nil
        dragArrow.lineWidth = 2
        dragArrow.lineCap = .round
        dragArrow.lineJoin = .round
        dragArrow.strokeEnd = 0
        dragArrow.opacity = 0
        layer?.addSublayer(dragArrow)

        for (nameLayer, key) in zip(nameLayers, MouseGestureHintView.nameKeys) {
            nameLayer.string = MFLocalizedString(key, comment: "Name of a gesture, shown under the mouse hint in the add field")
            nameLayer.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            nameLayer.fontSize = 12
            nameLayer.alignmentMode = .center
            nameLayer.frame = CGRect(x: 0, y: 14, width: MouseGestureHintView.viewSize.width, height: 18)
            nameLayer.opacity = 0
            layer?.addSublayer(nameLayer)
        }

        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let apply = {
            self.body.fillColor = NSColor.textBackgroundColor.cgColor
            self.body.strokeColor = NSColor.tertiaryLabelColor.cgColor
            self.split.strokeColor = NSColor.tertiaryLabelColor.cgColor
            self.leftButton.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.4).cgColor
            self.clickRing.strokeColor = NSColor.controlAccentColor.cgColor
            self.dragArrow.strokeColor = NSColor.controlAccentColor.cgColor
            for nameLayer in self.nameLayers {
                nameLayer.foregroundColor = NSColor.secondaryLabelColor.cgColor
            }
        }
        if #available(macOS 11.0, *) {
            effectiveAppearance.performAsCurrentDrawingAppearance(apply)
        } else {
            apply()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = window else { return }
        for nameLayer in nameLayers {
            nameLayer.contentsScale = window.backingScaleFactor
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            showStillFrame()
        } else {
            startAnimation()
        }
    }

    /// Plays the animation again from the start. Used by the '?' button.
    func restartAnimation() {
        removeAnimations(in: layer)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            showStillFrame()
        } else {
            startAnimation()
        }
    }

    private func removeAnimations(in layer: CALayer?) {
        guard let layer = layer else { return }
        layer.removeAllAnimations()
        layer.sublayers?.forEach { removeAnimations(in: $0) }
    }

    /// Reduce Motion: the mouse with the first gesture name, and no animation
    private func showStillFrame() {
        mouse.opacity = 1
        nameLayers[0].opacity = 1
    }

    /// One loop, in seconds:
    ///     0.4  the mouse fades in
    ///     1.0  click. The name "Click" stays up until 4.4
    ///     4.8  double click, at 4.8 and 5.1. The name "Double Click" stays up until 8.4
    ///     9.0  press and hold the left button, and drag. The mouse moves to the right until 10.8, and the arrow shows the drag until 11.3
    ///     11.0 the button is released. The name "Click and Drag" stays up until 13.8
    ///     14.2 the mouse fades out, and the loop pauses until it starts again
    private func startAnimation() {
        let loop = MouseGestureHintView.loopDuration
        let x = mouse.position.x
        let drag = MouseGestureHintView.dragDistance

        animate(mouse, "opacity", [(0, 0), (0.4, 1), (13.8, 1), (14.2, 0), (loop, 0)])

        animate(nameLayers[0], "opacity", [(0, 0), (0.4, 0), (0.7, 1), (4.2, 1), (4.4, 0), (loop, 0)])
        animate(nameLayers[1], "opacity", [(0, 0), (4.4, 0), (4.7, 1), (8.2, 1), (8.4, 0), (loop, 0)])
        animate(nameLayers[2], "opacity", [(0, 0), (8.4, 0), (8.7, 1), (13.5, 1), (13.8, 0), (loop, 0)])

        animate(leftButton, "opacity", MouseGestureHintView.pulses([(1.0, 1.15), (4.8, 4.95), (5.1, 5.25), (9.0, 11.0)], end: loop))
        animate(clickRing, "opacity", MouseGestureHintView.pulses([(1.0, 1.4), (4.8, 5.25)], end: loop))

        /// The drag: the mouse slides to the right while the left button is held. It stays there until it fades out, then the loop starts over with the mouse back in place.
        animate(mouse, "position.x", [(0, x), (9.0, x), (10.8, x + drag), (14.2, x + drag), (loop, x)])

        /// The arrow appears with the drag, grows along with the mouse, and stays until the button is released
        animate(dragArrow, "opacity", [(0, 0), (8.95, 0), (9.0, 1), (11.3, 1), (11.6, 0), (loop, 0)])
        animate(dragArrow, "strokeEnd", [(0, 0), (9.0, 0), (10.8, 1), (loop, 1)])
    }

    /// Keyframes that are 1 during each interval and 0 otherwise. Each interval switches on and off over 0.02 s.
    private static func pulses(_ intervals: [(Double, Double)], end: Double) -> [(Double, CGFloat)] {
        var keys: [(Double, CGFloat)] = [(0, 0)]
        for (start, stop) in intervals {
            keys.append((start, 0))
            keys.append((start + 0.02, 1))
            keys.append((stop, 1))
            keys.append((stop + 0.02, 0))
        }
        keys.append((end, 0))
        return keys
    }

    /// Adds a looping animation. `keys` are (seconds within the loop, value).
    private func animate(_ layer: CALayer, _ keyPath: String, _ keys: [(Double, CGFloat)]) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.keyTimes = keys.map { NSNumber(value: $0.0 / MouseGestureHintView.loopDuration) }
        animation.values = keys.map { NSNumber(value: Double($0.1)) }
        animation.duration = MouseGestureHintView.loopDuration
        animation.repeatCount = .infinity
        animation.calculationMode = .linear
        layer.add(animation, forKey: keyPath)
    }
}
