import AppKit

/// The saver's options window ("Options…" in System Settings), built in code:
/// a grid of label, slider and value. OK stores the settings and hands them
/// to `onSave`; Cancel leaves them as they were.
final class ConfigureSheet: NSObject {
  let window: NSWindow
  private let onSave: (SaverSettings) -> Void
  private var settings: SaverSettings

  private let jumps = NSButton(checkboxWithTitle: "Jump to light speed", target: nil, action: nil)
  private let cruise = NSSlider()
  private let light = NSSlider()
  private let stars = NSSlider()
  private let cruiseValue = NSTextField(labelWithString: "")
  private let lightValue = NSTextField(labelWithString: "")
  private let starsValue = NSTextField(labelWithString: "")
  private lazy var cruiseLabel = NSTextField(labelWithString: "Time between jumps:")
  private lazy var lightLabel = NSTextField(labelWithString: "Light speed lasts:")

  init(settings: SaverSettings, onSave: @escaping (SaverSettings) -> Void) {
    self.settings = settings
    self.onSave = onSave
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered,
      defer: true)
    super.init()
    window.title = "Starfields Metal"
    let content = makeContent()
    window.contentView = content
    show(settings)
    // Size the window to its content (insets included), not a guess.
    content.layoutSubtreeIfNeeded()
    window.setContentSize(content.fittingSize)
  }

  private func makeContent() -> NSView {
    for (slider, range) in [
      (cruise, SaverSettings.cruiseRange), (light, SaverSettings.lightRange), (stars, SaverSettings.starsRange),
    ] {
      slider.minValue = range.lowerBound
      slider.maxValue = range.upperBound
      slider.target = self
      slider.action = #selector(changed)
      slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
    }
    jumps.target = self
    jumps.action = #selector(changed)
    for value in [cruiseValue, lightValue, starsValue] {
      value.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      value.alignment = .right
      value.widthAnchor.constraint(equalToConstant: 56).isActive = true
    }

    let grid = NSGridView(views: [
      [NSGridCell.emptyContentView, jumps, NSGridCell.emptyContentView],
      [cruiseLabel, cruise, cruiseValue],
      [lightLabel, light, lightValue],
      [NSTextField(labelWithString: "Stars:"), stars, starsValue],
    ])
    grid.column(at: 0).xPlacement = .trailing
    grid.cell(atColumnIndex: 1, rowIndex: 0).xPlacement = .leading  // the checkbox, above the sliders
    grid.rowSpacing = 10
    grid.columnSpacing = 8
    grid.rowAlignment = .firstBaseline

    let defaultsButton = NSButton(title: "Defaults", target: self, action: #selector(restoreDefaults))
    let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
    cancel.keyEquivalent = "\u{1b}"
    let ok = NSButton(title: "OK", target: self, action: #selector(save))
    ok.keyEquivalent = "\r"
    let buttons = NSStackView(views: [defaultsButton, NSView(), cancel, ok])
    buttons.distribution = .fill

    let stack = NSStackView(views: [grid, buttons])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 20
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    buttons.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
    return stack
  }

  /// Puts `settings` into the controls.
  private func show(_ settings: SaverSettings) {
    jumps.state = settings.jumps ? .on : .off
    cruise.doubleValue = settings.cruiseSeconds
    light.doubleValue = settings.lightSeconds
    stars.doubleValue = settings.stars
    updateLabels()
  }

  private func updateLabels() {
    let jumpsOn = jumps.state == .on
    for control in [cruise, light] { control.isEnabled = jumpsOn }
    for label in [cruiseLabel, lightLabel, cruiseValue, lightValue] {
      label.textColor = jumpsOn ? .labelColor : .disabledControlTextColor
    }
    cruiseValue.stringValue = "\(Int(cruise.doubleValue.rounded())) s"
    lightValue.stringValue = "\(Int(light.doubleValue.rounded())) s"
    starsValue.stringValue = "\(Int((stars.doubleValue / 100).rounded()) * 100)"
  }

  @objc private func changed() { updateLabels() }

  @objc private func restoreDefaults() { show(SaverSettings()) }

  @objc private func cancel() { close() }

  @objc private func save() {
    settings = SaverSettings(
      jumps: jumps.state == .on,
      cruiseSeconds: cruise.doubleValue.rounded(),
      lightSeconds: light.doubleValue.rounded(),
      stars: (stars.doubleValue / 100).rounded() * 100)
    settings.save()
    onSave(settings)
    close()
  }

  private func close() {
    if let parent = window.sheetParent {
      parent.endSheet(window)
    } else {
      window.close()
    }
  }
}
