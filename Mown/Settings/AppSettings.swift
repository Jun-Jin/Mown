import SwiftUI
import AppKit

/// A user-selectable color scheme for one surface of the app (editor or
/// preview). `.system` defers to the current macOS appearance; the other two
/// pin the surface regardless of the system setting.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Concrete appearance to force onto an `NSView`, or `nil` to inherit the
    /// system appearance.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    /// Resolves to a concrete light/dark decision. `.system` defers to the
    /// caller's current effective appearance (`systemIsDark`).
    func isDark(whenSystem systemIsDark: Bool) -> Bool {
        switch self {
        case .system: return systemIsDark
        case .light:  return false
        case .dark:   return true
        }
    }
}

/// A persisted keyboard shortcut: a key character plus a set of modifiers.
/// Stored as the raw value of SwiftUI's `EventModifiers` so it round-trips
/// straight into `.keyboardShortcut(_:modifiers:)`.
struct KeyboardShortcutSetting: Codable, Equatable {
    /// Lowercased key character, e.g. `"t"`. Empty means "no shortcut".
    var key: String
    /// `EventModifiers.rawValue` for the modifier set.
    var modifierFlags: Int

    init(key: String, modifierFlags: Int) {
        self.key = key
        self.modifierFlags = modifierFlags
    }

    init(key: String, modifiers: EventModifiers) {
        self.init(key: key, modifierFlags: modifiers.rawValue)
    }

    static let none = KeyboardShortcutSetting(key: "", modifierFlags: 0)

    var isSet: Bool { !key.isEmpty }

    var modifiers: EventModifiers { EventModifiers(rawValue: modifierFlags) }

    var keyEquivalent: KeyEquivalent? {
        guard let character = key.first else { return nil }
        return KeyEquivalent(character)
    }

    /// Human-readable form following the macOS modifier order (⌃⌥⇧⌘), e.g.
    /// `"⇧⌘E"`.
    var displayString: String {
        guard isSet else { return "None" }
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option)  { result += "⌥" }
        if modifiers.contains(.shift)   { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += key.uppercased()
        return result
    }
}

/// App-wide, persisted preferences shared by every window. A single instance
/// (`shared`) is observed by the editor, the preview, the menu commands, and
/// the Settings window, so a change in one place updates everywhere.
///
/// Each property writes through to `UserDefaults` in its `didSet`. Property
/// observers don't fire during `init`, so loading defaults on launch doesn't
/// redundantly write them back.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultNewTabShortcut = KeyboardShortcutSetting(key: "t", modifiers: .command)
    static let defaultCycleViewModeShortcut = KeyboardShortcutSetting(key: "e", modifiers: .command)

    @Published var editorTheme: AppTheme {
        didSet { defaults.set(editorTheme.rawValue, forKey: Key.editorTheme) }
    }

    @Published var previewTheme: AppTheme {
        didSet { defaults.set(previewTheme.rawValue, forKey: Key.previewTheme) }
    }

    @Published var newTabShortcut: KeyboardShortcutSetting {
        didSet { write(newTabShortcut, forKey: Key.newTabShortcut) }
    }

    @Published var cycleViewModeShortcut: KeyboardShortcutSetting {
        didSet { write(cycleViewModeShortcut, forKey: Key.cycleViewModeShortcut) }
    }

    func resetShortcuts() {
        newTabShortcut = Self.defaultNewTabShortcut
        cycleViewModeShortcut = Self.defaultCycleViewModeShortcut
    }

    // MARK: Persistence

    private let defaults: UserDefaults

    private enum Key {
        static let editorTheme = "theme.editor"
        static let previewTheme = "theme.preview"
        static let newTabShortcut = "shortcut.newTab"
        static let cycleViewModeShortcut = "shortcut.cycleViewMode"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.editorTheme = defaults.string(forKey: Key.editorTheme)
            .flatMap(AppTheme.init(rawValue:)) ?? .system
        self.previewTheme = defaults.string(forKey: Key.previewTheme)
            .flatMap(AppTheme.init(rawValue:)) ?? .system
        self.newTabShortcut = Self.read(forKey: Key.newTabShortcut, from: defaults)
            ?? Self.defaultNewTabShortcut
        self.cycleViewModeShortcut = Self.read(forKey: Key.cycleViewModeShortcut, from: defaults)
            ?? Self.defaultCycleViewModeShortcut
    }

    private func write(_ value: KeyboardShortcutSetting, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func read(forKey key: String, from defaults: UserDefaults) -> KeyboardShortcutSetting? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyboardShortcutSetting.self, from: data)
    }
}
