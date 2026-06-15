import SwiftUI

/// Every user-invocable Format-menu action in one place: its menu title, its
/// default keyboard shortcut, and the underlying formatting operation. Both the
/// Format menu (`MownApp`) and the rebindable-shortcut list (`SettingsView`)
/// are built from these cases, so the two never drift and a single source
/// defines what's configurable.
enum FormatCommand: String, CaseIterable, Identifiable {
    // Inline (Tier 2, #5)
    case bold, italic, code, strikethrough, link
    // Block headings (Tier 3, #6)
    case heading1, heading2, heading3, heading4, heading5, heading6
    case increaseHeading, decreaseHeading
    // Other block (Tier 3, #6)
    case blockquote, codeBlock, taskToggle, horizontalRule, insertTable

    var id: String { rawValue }

    /// Grouping for the Settings list / menu sectioning.
    enum Group { case inline, heading, block }

    var group: Group {
        switch self {
        case .bold, .italic, .code, .strikethrough, .link:
            return .inline
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6,
             .increaseHeading, .decreaseHeading:
            return .heading
        case .blockquote, .codeBlock, .taskToggle, .horizontalRule, .insertTable:
            return .block
        }
    }

    var title: String {
        switch self {
        case .bold:            return "Bold"
        case .italic:          return "Italic"
        case .code:            return "Inline Code"
        case .strikethrough:   return "Strikethrough"
        case .link:            return "Link"
        case .heading1:        return "Heading 1"
        case .heading2:        return "Heading 2"
        case .heading3:        return "Heading 3"
        case .heading4:        return "Heading 4"
        case .heading5:        return "Heading 5"
        case .heading6:        return "Heading 6"
        case .increaseHeading: return "Increase Level"
        case .decreaseHeading: return "Decrease Level"
        case .blockquote:      return "Blockquote"
        case .codeBlock:       return "Code Block"
        case .taskToggle:      return "Toggle Task"
        case .horizontalRule:  return "Horizontal Rule"
        case .insertTable:     return "Insert Table"
        }
    }

    /// The inline operation this command fires, or `nil` for a block command.
    var inline: InlineFormat? {
        switch self {
        case .bold:          return .bold
        case .italic:        return .italic
        case .code:          return .code
        case .strikethrough: return .strikethrough
        case .link:          return .link
        default:             return nil
        }
    }

    /// The block operation this command fires, or `nil` for an inline command.
    var block: BlockFormat? {
        switch self {
        case .heading1:        return .heading(1)
        case .heading2:        return .heading(2)
        case .heading3:        return .heading(3)
        case .heading4:        return .heading(4)
        case .heading5:        return .heading(5)
        case .heading6:        return .heading(6)
        case .increaseHeading: return .bumpHeading(1)
        case .decreaseHeading: return .bumpHeading(-1)
        case .blockquote:      return .blockquote
        case .codeBlock:       return .codeBlock
        case .taskToggle:      return .taskToggle
        case .horizontalRule:  return .horizontalRule
        case .insertTable:     return .table
        default:               return nil
        }
    }

    /// The factory-default shortcut. Horizontal Rule and Insert Table ship with
    /// none; the user can assign one in Settings.
    var defaultShortcut: KeyboardShortcutSetting {
        switch self {
        case .bold:            return .init(key: "b", modifiers: .command)
        case .italic:          return .init(key: "i", modifiers: .command)
        case .code:            return .init(key: "c", modifiers: [.command, .shift])
        case .strikethrough:   return .init(key: "x", modifiers: [.command, .shift])
        case .link:            return .init(key: "k", modifiers: .command)
        case .heading1:        return .init(key: "1", modifiers: [.command, .option])
        case .heading2:        return .init(key: "2", modifiers: [.command, .option])
        case .heading3:        return .init(key: "3", modifiers: [.command, .option])
        case .heading4:        return .init(key: "4", modifiers: [.command, .option])
        case .heading5:        return .init(key: "5", modifiers: [.command, .option])
        case .heading6:        return .init(key: "6", modifiers: [.command, .option])
        case .increaseHeading: return .init(key: "]", modifiers: .command)
        case .decreaseHeading: return .init(key: "[", modifiers: .command)
        case .blockquote:      return .init(key: "'", modifiers: .command)
        case .codeBlock:       return .init(key: "c", modifiers: [.control, .command])
        case .taskToggle:      return .init(key: "l", modifiers: [.command, .shift])
        case .horizontalRule:  return .none
        case .insertTable:     return .none
        }
    }
}
