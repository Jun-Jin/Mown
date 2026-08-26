import AppKit

func documentIcon(size: CGFloat) -> NSImage {
    let icon = NSApp.application.copy() as! NSImage
    icon.size = NSSize(width: size, height: size)
    return icon
}