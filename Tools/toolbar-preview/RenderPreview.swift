// Offscreen preview renderer for the Overview header toolbar second row.
// Compiled and run by the reviewer (not part of the app target). swiftc only
// allows top-level statements in a file named main.swift, so copy this file
// under that name before compiling:
//
//   mkdir -p "$TMPDIR/preview-build" && cp Tools/toolbar-preview/RenderPreview.swift "$TMPDIR/preview-build/main.swift"
//   cd codexbar && swiftc Sources/CodexBar/OverviewHeaderToolbarLayout.swift \
//     "$TMPDIR/preview-build/main.swift" -framework AppKit \
//     -o "$TMPDIR/toolbar-preview" && "$TMPDIR/toolbar-preview" "$TMPDIR/toolbar-preview.png"
//
// Uses the actual shared layout code plus real NSSegmentedControls measured with
// sizeToFit. Labels are the English source of truth; the app localizes the same
// strings through its string keys. No providers, no menu tracking, no UI automation.
import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? (NSTemporaryDirectory() + "toolbar-preview.png")
let width: CGFloat = 400

func makeControl(labels: [String], toolTips: [String], accessibilityLabel: String) -> NSSegmentedControl {
    let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
    control.controlSize = .small
    control.font = NSFont.systemFont(ofSize: 11)
    control.selectedSegment = 0
    for index in labels.indices {
        control.setToolTip(toolTips[index], forSegment: index)
    }
    control.setAccessibilityLabel(accessibilityLabel)
    control.sizeToFit()
    return control
}

let usage = makeControl(
    labels: ["Used", "Free"],
    toolTips: ["Used", "Remaining"],
    accessibilityLabel: "Usage")
let reset = makeControl(
    labels: ["Wait", "When"],
    toolTips: ["Countdown", "Clock time"],
    accessibilityLabel: "Reset times")
let controlHeight = max(usage.frame.height, reset.frame.height)
let frames = OverviewHeaderToolbarLayout.frames(width: width, controlHeight: controlHeight)
usage.frame = frames.usage
reset.frame = frames.reset
for segment in 0..<2 {
    usage.setWidth(frames.segmentWidth, forSegment: segment)
    reset.setWidth(frames.segmentWidth, forSegment: segment)
}
let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: frames.rowHeight))
container.wantsLayer = true
container.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
container.addSubview(usage)
container.addSubview(reset)
container.layoutSubtreeIfNeeded()
guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else {
    fatalError("could not allocate bitmap representation")
}
container.cacheDisplay(in: container.bounds, to: rep)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG representation")
}
guard (try? png.write(to: URL(fileURLWithPath: outputPath))) != nil else {
    fatalError("could not write \(outputPath)")
}
print("usage=\(usage.frame) reset=\(reset.frame) segmentWidth=\(frames.segmentWidth) rowHeight=\(frames.rowHeight)")
print("wrote \(outputPath)")
