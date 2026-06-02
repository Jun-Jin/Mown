import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case edit
    case preview
    case split

    var id: String { rawValue }

    var label: String {
        switch self {
        case .edit:    return "Edit"
        case .preview: return "Preview"
        case .split:   return "Split"
        }
    }

    var systemImage: String {
        switch self {
        case .edit:    return "pencil"
        case .preview: return "eye"
        case .split:   return "rectangle.split.2x1"
        }
    }

}

struct ViewModePicker: View {
    @Binding var mode: ViewMode

    var body: some View {
        Picker("View Mode", selection: $mode) {
            ForEach(ViewMode.allCases) { m in
                Image(systemName: m.systemImage)
                    .help(m.label)
                    .tag(m)
            }
        }
        .pickerStyle(.segmented)
    }
}
