import AppKit
import Foundation

/// Install / uninstall the bundled `mown` script as a symlink in /usr/local/bin
/// so users can type `mown notes.md` in any terminal after dragging Mown.app
/// from a DMG into /Applications.
///
/// /usr/local/bin is on the default macOS PATH on both Intel and Apple Silicon
/// (matches what VS Code's "Install 'code' command in PATH" does). Writing
/// there needs root, so we wrap the file operations in NSAppleScript "with
/// administrator privileges" to get the standard system auth prompt.
enum InstallCLI {
    static let destination = "/usr/local/bin/mown"
    static let toolName = "mown"

    enum Status: Equatable {
        /// Nothing at /usr/local/bin/mown.
        case notInstalled
        /// Symlink at /usr/local/bin/mown points at the script inside *this* Mown.app.
        case installed
        /// Something else is at /usr/local/bin/mown (file, or a symlink to a
        /// different `mown`). We leave it alone unless the user explicitly
        /// reinstalls.
        case foreign(path: String)
    }

    static func currentStatus() -> Status {
        let fm = FileManager.default
        guard fm.fileExists(atPath: destination) || isSymlink(at: destination) else {
            return .notInstalled
        }
        // `fileExists` follows symlinks; symlinks to a missing file return false,
        // which is why we check the link separately above.
        if let target = try? fm.destinationOfSymbolicLink(atPath: destination) {
            let resolved = resolveSymlinkTarget(target, relativeTo: destination)
            if resolved == bundledScriptPath() {
                return .installed
            }
            return .foreign(path: resolved)
        }
        return .foreign(path: destination)
    }

    static func install() {
        guard let source = bundledScriptPath() else {
            presentError("Couldn’t find the bundled ‘\(toolName)’ script inside Mown.app.")
            return
        }

        let confirm = NSAlert()
        confirm.messageText = "Install the ‘\(toolName)’ command line tool?"
        confirm.informativeText = """
            This will create a symlink at \(destination) pointing to the script bundled inside Mown.app. \
            You’ll be asked for your administrator password.
            """
        confirm.addButton(withTitle: "Install")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let parent = (destination as NSString).deletingLastPathComponent
        let command = "mkdir -p \(shellQuote(parent)) && ln -sfn \(shellQuote(source)) \(shellQuote(destination))"

        switch runPrivileged(command) {
        case .success:
            let alert = NSAlert()
            alert.messageText = "‘\(toolName)’ installed"
            alert.informativeText = """
                You can now run `\(toolName)` from a new terminal session. \
                If your shell doesn’t pick it up, make sure /usr/local/bin is on your PATH.
                """
            alert.runModal()
        case .cancelled:
            break
        case .failure(let message):
            presentError(message)
        }
    }

    static func uninstall() {
        let confirm = NSAlert()
        confirm.messageText = "Remove the ‘\(toolName)’ command line tool?"
        confirm.informativeText = """
            This will delete the symlink at \(destination). Mown itself is unaffected. \
            You’ll be asked for your administrator password.
            """
        confirm.addButton(withTitle: "Remove")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let command = "rm -f \(shellQuote(destination))"

        switch runPrivileged(command) {
        case .success:
            let alert = NSAlert()
            alert.messageText = "‘\(toolName)’ removed"
            alert.runModal()
        case .cancelled:
            break
        case .failure(let message):
            presentError(message)
        }
    }

    // MARK: - helpers

    private static func bundledScriptPath() -> String? {
        Bundle.main.url(forResource: toolName, withExtension: nil)?.path
    }

    private static func isSymlink(at path: String) -> Bool {
        var attrs = stat()
        return lstat(path, &attrs) == 0 && (attrs.st_mode & S_IFMT) == S_IFLNK
    }

    /// Resolve `target` (which may be relative) against the directory holding
    /// the symlink at `linkPath`, then standardize. Falls back to the raw
    /// target string if standardization fails.
    private static func resolveSymlinkTarget(_ target: String, relativeTo linkPath: String) -> String {
        if (target as NSString).isAbsolutePath {
            return (target as NSString).standardizingPath
        }
        let linkDir = (linkPath as NSString).deletingLastPathComponent
        return ((linkDir as NSString).appendingPathComponent(target) as NSString).standardizingPath
    }

    private enum Result {
        case success
        case cancelled
        case failure(String)
    }

    private static func runPrivileged(_ command: String) -> Result {
        let script = "do shell script \(appleScriptStringLiteral(command)) with administrator privileges"

        guard let appleScript = NSAppleScript(source: script) else {
            return .failure("Couldn’t prepare the install script.")
        }

        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)

        guard let error = errorDict else { return .success }
        // -128 = userCanceledErr: user dismissed the authentication prompt.
        if let number = error[NSAppleScript.errorNumber] as? Int, number == -128 {
            return .cancelled
        }
        let message = (error[NSAppleScript.errorMessage] as? String) ?? "Unknown error."
        return .failure(message)
    }

    private static func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t update ‘\(toolName)’"
        alert.informativeText = message
        alert.runModal()
    }

    /// POSIX shell single-quote: wrap in '…' and escape embedded ' as '\''.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// AppleScript string literal: wrap in "…" and escape \ and ".
    private static func appleScriptStringLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }
}
