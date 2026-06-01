## Response Style
- No greetings, preambles, progress updates. Lead with the conclusion.
- Don't just agree with the user. Point out issues directly when necessary.

## Rules for Explaining Code
### When Addressing Feedback
- Explain the feedback and evaluate its validity. Then, describe the problem before the change, the modifications made, and the intent and content of the code after the change.

### When Modifying Code
- Explain what changes between the before and after versions, along with the intent and content of each.

### When Creating New Code
- Explain what changes between the state without code and the state with code (i.e., what problem it solves), along with the intent and content of the code.

## Implementation Standards
- Reference context7 and always implement according to the latest standard language specifications.

## Build
- Xcode builds into DerivedData, not the repo. After every build, copy the build product over `./Mown.app` so `open Mown.app` runs the latest binary.

## Project Structure
- The Xcode project uses synchronized folders (`PBXFileSystemSynchronizedRootGroup`, objectVersion 77). New files added to `Mown/` or `Tests/` on disk are picked up automatically — do NOT hand-edit `project.pbxproj` to register them.

## CLI
- `bin/mown` opens Markdown files in Mown (as tabs). Install on PATH with: `ln -sf "$PWD/bin/mown" /opt/homebrew/bin/mown`. The symlink is machine-local (not in the repo), so re-run it after a fresh clone.
