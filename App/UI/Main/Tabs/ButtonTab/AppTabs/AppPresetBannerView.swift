//
// --------------------------------------------------------------------------
// AppPresetBannerView.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import AppKit

/// The banner in an empty app tab that offers a built-in preset.
final class AppPresetBannerView: NSView {
    
    /// Called when the user clicks Add
    var onAdd: (() -> Void)?
    
    private let label = NSTextField(labelWithString: "")
    private let addButton = NSButton(title: MFLocalizedString("app-presets.add", comment: ""), target: nil, action: nil)
    
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
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addTapped(_:))
        
        let stack = NSStackView(views: [label, addButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    
    /// Sets the text of the offer
    func setText(_ text: String) {
        label.stringValue = text
    }
    
    @objc private func addTapped(_ sender: NSButton) {
        onAdd?()
    }
}
