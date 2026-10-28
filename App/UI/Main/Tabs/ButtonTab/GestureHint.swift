//
// --------------------------------------------------------------------------
// GestureHint.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//
// The gesture hint of the Buttons tab:
//     - `GestureHintView`: the animated mouse in the add field. It plays the gestures of `GestureHintTimeline` one after another.
//     - `GestureLegendView`: the strip under the add field with one item per gesture. The item of the gesture that is playing is highlighted, and hovering an item plays its gesture in the add field.
//     - `GestureExplainer`: the popover that opens from the '?' in the add field.
// Both views draw the mouse with `MouseGlyphLayer`, and take their state from `GestureHintClock`, so they stay in sync.

import Cocoa

// MARK: Clock

/// A view that shows the state of the `GestureHintClock`
protocol GestureHintClockObserver: AnyObject {
    /// Whether the view is in a window and not hidden. The clock only runs while one of its observers is showing.
    var isShowingGestureHint: Bool { get }
    func show(_ state: GestureHintState)
}

/// The time of the gesture hint, shared by the add field and the legend.
///     The loop plays while the add field shows its hint (`isLoopShown`). Hovering a legend item plays one gesture instead (`play(_:onEnd:)`), then the loop goes on.
///     A timer pushes the state to the observers at about 30 fps, but only while something moves and an observer is showing.
///     With Reduce Motion on, no timer runs: the add field shows the mouse and the first name, and hovering does nothing.
final class GestureHintClock {

    static let shared = GestureHintClock()

    /// Whether the add field shows the loop. Set by the add field.
    var isLoopShown = false {
        didSet { update() }
    }

    /// The gesture that is played on its own, if any
    private(set) var playingKind: GestureKind?

    private var loopStart = CACurrentMediaTime()
    private var playbackStart: CFTimeInterval = 0
    private var onPlaybackEnd: (() -> Void)?
    private let observers = NSHashTable<AnyObject>.weakObjects()
    private var timer: Timer?

    static var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func now() -> CFTimeInterval { CACurrentMediaTime() }

    func add(_ observer: GestureHintClockObserver) {
        observers.add(observer)
        update()
    }

    /// Plays the loop from the start
    func restartLoop() {
        loopStart = now()
        update()
    }

    /// Plays one gesture, then calls `onEnd` and goes on with the loop. Playing another gesture before the end replaces this one, and its `onEnd` is not called.
    func play(_ kind: GestureKind, onEnd: @escaping () -> Void) {
        guard !GestureHintClock.reducesMotion else { return }
        playingKind = kind
        playbackStart = now()
        onPlaybackEnd = onEnd
        update()
    }

    /// The state at the current time
    func state() -> GestureHintState {
        if GestureHintClock.reducesMotion {
            return isLoopShown ? .still : .hidden
        }
        if let kind = playingKind {
            return GestureHintTimeline.state(at: kind.hoverStart + now() - playbackStart)
        }
        guard isLoopShown else { return .hidden }
        return GestureHintTimeline.state(at: (now() - loopStart).truncatingRemainder(dividingBy: GestureHintTimeline.loopDuration))
    }

    /// Ends the playback of one gesture once it is over, shows the current state, and runs the timer while it is needed.
    ///     Observers call this when they are shown or hidden.
    func update() {

        if let kind = playingKind, now() - playbackStart >= kind.hoverEnd - kind.hoverStart {
            playingKind = nil
            let onEnd = onPlaybackEnd
            onPlaybackEnd = nil
            onEnd?()
        }

        let showing = observers.allObjects.compactMap { $0 as? GestureHintClockObserver }.filter { $0.isShowingGestureHint }
        let state = state()
        for observer in showing {
            observer.show(state)
        }

        let isMoving = !GestureHintClock.reducesMotion && (isLoopShown || playingKind != nil)
        if isMoving && !showing.isEmpty {
            if timer == nil {
                let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.update() }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: Mouse

/// The mouse of the gesture hint, drawn at any scale. Its bounds are the mouse at rest: 46 × 66 points at scale 1.
///     The mouse moves inside these bounds by the state's x offset. The drag arrow stays in place, and the scroll arrow and the arcs move with the mouse.
final class MouseGlyphLayer: CALayer {

    static let mouseSize = CGSize(width: 46, height: 66)
    /// The center of the left button, in the mouse's coordinates at scale 1
    private static let leftButtonCenter = CGPoint(x: 11.5, y: 52)

    let scale: CGFloat

    private let mouse = CALayer()
    private let body = CAShapeLayer()
    private let split = CAShapeLayer()
    private let leftButton = CALayer()
    private let wheel = CAShapeLayer()
    private let wheelLight = CALayer()
    private let clickRing = CAShapeLayer()
    private let holdArc = CAShapeLayer()
    private let scrollArrow = CAShapeLayer()
    private let dragArrow = CAShapeLayer()

    init(scale: CGFloat) {
        self.scale = scale
        super.init()
        setUp()
    }

    override init(layer: Any) {
        scale = (layer as? MouseGlyphLayer)?.scale ?? 1
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {

        let s = scale
        let size = CGSize(width: MouseGlyphLayer.mouseSize.width * s, height: MouseGlyphLayer.mouseSize.height * s)
        let mouseBounds = CGRect(origin: .zero, size: size)
        let lineWidth = max(1, 1.5 * s)
        let accentLineWidth = max(1, 2 * s)
        let center = CGPoint(x: MouseGlyphLayer.leftButtonCenter.x * s, y: MouseGlyphLayer.leftButtonCenter.y * s)

        bounds = mouseBounds
        mouse.frame = mouseBounds
        addSublayer(mouse)

        body.frame = mouseBounds
        body.path = CGPath(roundedRect: mouseBounds, cornerWidth: 20 * s, cornerHeight: 20 * s, transform: nil)
        body.lineWidth = lineWidth
        mouse.addSublayer(body)

        /// The line that separates the buttons: across the top of the buttons, and down the middle
        let splitPath = CGMutablePath()
        splitPath.move(to: CGPoint(x: 0, y: 38 * s))
        splitPath.addLine(to: CGPoint(x: size.width, y: 38 * s))
        splitPath.move(to: CGPoint(x: size.width / 2, y: 38 * s))
        splitPath.addLine(to: CGPoint(x: size.width / 2, y: size.height))
        split.frame = mouseBounds
        split.path = splitPath
        split.fillColor = nil
        split.lineWidth = lineWidth
        mouse.addSublayer(split)

        leftButton.frame = CGRect(x: 3 * s, y: 41 * s, width: 17 * s, height: 22 * s)
        leftButton.cornerRadius = 8 * s
        leftButton.opacity = 0
        mouse.addSublayer(leftButton)

        /// The wheel, on the line between the two buttons
        let wheelRect = CGRect(x: size.width / 2 - 2.5 * s, y: 44 * s, width: 5 * s, height: 12 * s)
        wheel.frame = mouseBounds
        wheel.path = CGPath(roundedRect: wheelRect, cornerWidth: 2.5 * s, cornerHeight: 2.5 * s, transform: nil)
        wheel.lineWidth = lineWidth
        mouse.addSublayer(wheel)
        wheelLight.frame = wheelRect
        wheelLight.cornerRadius = 2.5 * s
        wheelLight.opacity = 0
        mouse.addSublayer(wheelLight)

        let ringRect = CGRect(x: center.x - 15 * s, y: center.y - 15 * s, width: 30 * s, height: 30 * s)
        clickRing.frame = mouseBounds
        clickRing.path = CGPath(ellipseIn: ringRect, transform: nil)
        clickRing.fillColor = nil
        clickRing.lineWidth = accentLineWidth
        clickRing.opacity = 0
        mouse.addSublayer(clickRing)

        /// The hold arc: around the left button, clockwise from the top
        let arcPath = CGMutablePath()
        arcPath.addArc(center: center, radius: 15 * s, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        holdArc.frame = mouseBounds
        holdArc.path = arcPath
        holdArc.fillColor = nil
        holdArc.lineWidth = accentLineWidth
        holdArc.lineCap = .round
        holdArc.strokeEnd = 0
        holdArc.opacity = 0
        mouse.addSublayer(holdArc)

        /// The scroll arrow: up and down, right of the mouse
        let x = size.width + 10 * s
        let top = CGPoint(x: x, y: 50 * s)
        let bottom = CGPoint(x: x, y: 16 * s)
        let head = 5 * s
        let scrollPath = CGMutablePath()
        scrollPath.move(to: top)
        scrollPath.addLine(to: bottom)
        scrollPath.move(to: CGPoint(x: x - head, y: top.y - head))
        scrollPath.addLine(to: top)
        scrollPath.addLine(to: CGPoint(x: x + head, y: top.y - head))
        scrollPath.move(to: CGPoint(x: x - head, y: bottom.y + head))
        scrollPath.addLine(to: bottom)
        scrollPath.addLine(to: CGPoint(x: x + head, y: bottom.y + head))
        configureArrow(scrollArrow, path: scrollPath, lineWidth: accentLineWidth)
        mouse.addSublayer(scrollArrow)

        /// The drag arrow: from the left button to just past where the button ends up after the drag
        let end = CGPoint(x: center.x + (GestureHintTimeline.dragDistance + 22) * s, y: center.y)
        let dragPath = CGMutablePath()
        dragPath.move(to: center)
        dragPath.addLine(to: end)
        dragPath.move(to: CGPoint(x: end.x - 9 * s, y: end.y + 6 * s))
        dragPath.addLine(to: end)
        dragPath.addLine(to: CGPoint(x: end.x - 9 * s, y: end.y - 6 * s))
        configureArrow(dragArrow, path: dragPath, lineWidth: accentLineWidth)
        dragArrow.strokeEnd = 0
        addSublayer(dragArrow)

        updateColors()
    }

    private func configureArrow(_ arrow: CAShapeLayer, path: CGPath, lineWidth: CGFloat) {
        arrow.frame = bounds
        arrow.path = path
        arrow.fillColor = nil
        arrow.lineWidth = lineWidth
        arrow.lineCap = .round
        arrow.lineJoin = .round
        arrow.opacity = 0
    }

    /// Call this with the view's appearance as the current drawing appearance
    func updateColors() {
        body.fillColor = NSColor.textBackgroundColor.cgColor
        body.strokeColor = NSColor.tertiaryLabelColor.cgColor
        split.strokeColor = NSColor.tertiaryLabelColor.cgColor
        wheel.fillColor = NSColor.textBackgroundColor.cgColor
        wheel.strokeColor = NSColor.tertiaryLabelColor.cgColor
        wheelLight.backgroundColor = NSColor.controlAccentColor.cgColor
        leftButton.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.4).cgColor
        for accentLayer in [clickRing, holdArc, scrollArrow, dragArrow] {
            accentLayer.strokeColor = NSColor.controlAccentColor.cgColor
        }
    }

    /// Sets the scale of this layer and its sublayers, so the shapes are sharp on the window's screen
    func setContentsScale(_ scale: CGFloat) {
        var layers: [CALayer] = [self]
        while let layer = layers.popLast() {
            layer.contentsScale = scale
            layers.append(contentsOf: layer.sublayers ?? [])
        }
    }

    /// Shows the state, without implicit animations
    func apply(_ state: GestureHintState) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        opacity = Float(state.mouseOpacity)
        mouse.frame.origin.x = CGFloat(state.mouseXOffset) * scale
        leftButton.opacity = Float(state.leftButtonLit)
        clickRing.opacity = Float(state.ringOpacity)
        holdArc.opacity = state.holdProgress > 0 ? 1 : 0
        holdArc.strokeEnd = CGFloat(state.holdProgress)
        dragArrow.opacity = Float(state.dragArrowOpacity)
        dragArrow.strokeEnd = CGFloat(state.dragArrowProgress)
        wheelLight.opacity = Float(state.wheelLit)
        scrollArrow.opacity = Float(state.scrollArrowOpacity)
        CATransaction.commit()
    }
}

// MARK: Hint in the add field

/// The animated hint in the add field: the mouse at full size, playing the gestures one after another, with the name of each gesture under it.
///     The mouse itself stays still, except during the drag, where it moves to the right while the left button is held.
///     The timing is in `GestureHintTimeline`. With Reduce Motion on, it shows the mouse and the first name, without animation.
final class GestureHintView: NSView, GestureHintClockObserver {

    private static let viewSize = NSSize(width: 200, height: 130)
    /// Where the mouse is at rest, in this view's coordinates
    private static let mouseOrigin = CGPoint(x: 77, y: 44)

    private let glyph = MouseGlyphLayer(scale: 1)
    /// One name per gesture. At most one of them is shown at a time, under the mouse.
    private let nameLayers = GestureKind.allCases.map { _ in CATextLayer() }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: GestureHintView.viewSize))
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: NSSize { GestureHintView.viewSize }

    private func setUp() {

        wantsLayer = true
        setAccessibilityElement(false) /// Purely decorative

        glyph.anchorPoint = .zero
        glyph.position = GestureHintView.mouseOrigin
        glyph.opacity = 0
        layer?.addSublayer(glyph)

        for (nameLayer, kind) in zip(nameLayers, GestureKind.allCases) {
            nameLayer.string = MFLocalizedString(kind.nameKey, comment: "Name of a gesture, shown under the mouse hint in the add field")
            nameLayer.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            nameLayer.fontSize = 12
            nameLayer.alignmentMode = .center
            nameLayer.frame = CGRect(x: 0, y: 14, width: GestureHintView.viewSize.width, height: 18)
            nameLayer.opacity = 0
            layer?.addSublayer(nameLayer)
        }

        updateColors()
        GestureHintClock.shared.add(self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let apply = {
            self.glyph.updateColors()
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
        if let window = window {
            glyph.setContentsScale(window.backingScaleFactor)
            for nameLayer in nameLayers {
                nameLayer.contentsScale = window.backingScaleFactor
            }
        }
        GestureHintClock.shared.update()
    }

    override func viewDidHide() {
        super.viewDidHide()
        GestureHintClock.shared.update()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        GestureHintClock.shared.update()
    }

    var isShowingGestureHint: Bool { window != nil && !isHiddenOrHasHiddenAncestor }

    func show(_ state: GestureHintState) {
        glyph.apply(state)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (nameLayer, kind) in zip(nameLayers, GestureKind.allCases) {
            nameLayer.opacity = state.nameKind == kind ? Float(state.nameOpacity) : 0
        }
        CATransaction.commit()
    }
}

// MARK: Legend

/// The strip under the add field: one item per gesture, each a small mouse and the gesture's name.
///     While the add field plays a gesture, its item is highlighted and its mouse plays along. Hovering an item plays its gesture in the add field (see `onHoverGesture`).
///     With Reduce Motion on, nothing is highlighted, and hovering does nothing.
final class GestureLegendView: NSView, GestureHintClockObserver {

    static let height: CGFloat = 48

    /// Called when the pointer enters an item, or VoiceOver presses it
    var onHoverGesture: ((GestureKind) -> Void)?

    private let items = GestureKind.allCases.map { GestureLegendItemView(kind: $0) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {

        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: items)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for item in items {
            item.onHover = { [weak self] kind in
                guard !GestureHintClock.reducesMotion else { return }
                self?.onHoverGesture?(kind)
            }
        }

        GestureHintClock.shared.add(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        GestureHintClock.shared.update()
    }

    override func viewDidHide() {
        super.viewDidHide()
        GestureHintClock.shared.update()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        GestureHintClock.shared.update()
    }

    var isShowingGestureHint: Bool { window != nil && !isHiddenOrHasHiddenAncestor }

    func show(_ state: GestureHintState) {
        let highlighted = GestureHintClock.reducesMotion ? nil : state.nameKind
        for item in items {
            item.show(highlighted == item.kind ? state : nil, highlight: highlighted == item.kind ? state.nameOpacity : 0)
        }
    }
}

/// One item of the legend
private final class GestureLegendItemView: NSView {

    let kind: GestureKind
    var onHover: ((GestureKind) -> Void)?

    private static let glyphScale: CGFloat = 0.36

    private let glyphHost = NSView()
    private let glyph = MouseGlyphLayer(scale: GestureLegendItemView.glyphScale)
    private let nameLabel: NSTextField
    private let background = CALayer()
    private var highlight: Double = 0

    init(kind: GestureKind) {
        self.kind = kind
        nameLabel = NSTextField(labelWithString: MFLocalizedString(kind.nameKey, comment: "Name of a gesture, shown under the mouse hint in the add field"))
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {

        wantsLayer = true
        background.cornerRadius = 6
        background.opacity = 0
        layer?.addSublayer(background)

        /// The mouse is decorative. The item is named after the gesture.
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(nameLabel.stringValue)
        setAccessibilityHelp(MFLocalizedString("add-field.legend.accessibility-help", comment: ""))
        nameLabel.setAccessibilityElement(false)
        glyphHost.setAccessibilityElement(false)

        glyphHost.translatesAutoresizingMaskIntoConstraints = false
        glyphHost.wantsLayer = true
        glyphHost.layer?.addSublayer(glyph)
        addSubview(glyphHost)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(nameLabel)

        let mouseSize = MouseGlyphLayer.mouseSize
        NSLayoutConstraint.activate([
            glyphHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyphHost.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            glyphHost.widthAnchor.constraint(equalToConstant: mouseSize.width * GestureLegendItemView.glyphScale),
            glyphHost.heightAnchor.constraint(equalToConstant: mouseSize.height * GestureLegendItemView.glyphScale),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        ])

        glyph.anchorPoint = .zero
        glyph.position = .zero

        show(nil, highlight: 0)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.frame = bounds
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(kind)
    }

    override func accessibilityPerformPress() -> Bool {
        onHover?(kind)
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window { glyph.setContentsScale(window.backingScaleFactor) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let apply = {
            self.glyph.updateColors()
            self.background.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            self.nameLabel.textColor = self.highlight > 0.5 ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        }
        if #available(macOS 11.0, *) {
            effectiveAppearance.performAsCurrentDrawingAppearance(apply)
        } else {
            apply()
        }
    }

    /// Shows the live state while this item's gesture plays, and the gesture's still picture otherwise.
    ///     `highlight` fades the accent background in and out with the gesture's name in the add field.
    func show(_ state: GestureHintState?, highlight: Double) {

        var glyphState = state ?? GestureLegendItemView.stillState(of: kind)
        glyphState.mouseOpacity = 1
        if kind != .clickAndDrag { glyphState.mouseXOffset = 0 }
        glyph.apply(glyphState)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.opacity = Float(highlight)
        CATransaction.commit()

        let wasHighlighted = self.highlight > 0.5
        self.highlight = highlight
        if wasHighlighted != (highlight > 0.5) { updateColors() }
    }

    /// The still picture of a gesture: the left button lit, and what sets the gesture apart. The mouse is at rest.
    private static func stillState(of kind: GestureKind) -> GestureHintState {
        var state = GestureHintState(mouseOpacity: 1, leftButtonLit: 1)
        switch kind {
        case .click: break
        case .doubleClick: state.ringOpacity = 1
        case .clickAndDrag: state.dragArrowOpacity = 1; state.dragArrowProgress = 1
        case .clickAndScroll: state.wheelLit = 1; state.scrollArrowOpacity = 1
        case .hold: state.holdProgress = 1
        }
        return state
    }
}

// MARK: Explainer

/// The popover that opens from the '?' in the add field. It explains each gesture in one line, and can play the animation in the add field again.
enum GestureExplainer {

    /// The popover that is showing. NSPopover does not keep itself alive.
    private static var popover: NSPopover?

    /// Shows the popover under the button. `onShowAnimation` is called when the user clicks "Show animation", after the popover closes.
    static func show(relativeTo button: NSView, onShowAnimation: @escaping () -> Void) {

        popover?.close()

        let controller = GestureExplainerViewController()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        controller.onShowAnimation = { [weak popover] in
            popover?.performClose(nil)
            onShowAnimation()
        }

        /// The button is flipped, so its maxY edge is its bottom edge, and the popover opens under the add field's corner.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        self.popover = popover
    }
}

private final class GestureExplainerViewController: NSViewController {

    var onShowAnimation: (() -> Void)?

    private static let width: CGFloat = 340
    private static let nameColumnWidth: CGFloat = 100

    override func loadView() {

        let title = NSTextField(labelWithString: MFLocalizedString("add-field.explainer.title", comment: ""))
        title.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)

        /// One row per gesture: its name, and what to do
        let rows: [[NSView]] = GestureKind.allCases.map { kind in
            let name = NSTextField(labelWithString: MFLocalizedString(kind.nameKey, comment: "Name of a gesture, shown under the mouse hint in the add field"))
            name.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            let line = NSTextField(wrappingLabelWithString: MFLocalizedString(kind.explainerKey, comment: ""))
            line.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            line.textColor = .secondaryLabelColor
            return [name, line]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 0).width = GestureExplainerViewController.nameColumnWidth
        grid.rowAlignment = .firstBaseline

        let closing = NSTextField(wrappingLabelWithString: MFLocalizedString("add-field.explainer.closing", comment: ""))
        closing.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        closing.textColor = .secondaryLabelColor

        let button = NSButton(title: MFLocalizedString("add-field.explainer.show-animation", comment: ""), target: self, action: #selector(showAnimation(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [title, grid, closing, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: closing)
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentWidth = GestureExplainerViewController.width - stack.edgeInsets.left - stack.edgeInsets.right
        closing.preferredMaxLayoutWidth = contentWidth
        for row in rows {
            (row[1] as? NSTextField)?.preferredMaxLayoutWidth = contentWidth - GestureExplainerViewController.nameColumnWidth - grid.columnSpacing
        }
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: GestureExplainerViewController.width),
            grid.widthAnchor.constraint(equalToConstant: contentWidth),
            closing.widthAnchor.constraint(equalToConstant: contentWidth),
        ])

        view = stack
    }

    @objc private func showAnimation(_ sender: NSButton) {
        onShowAnimation?()
    }
}
