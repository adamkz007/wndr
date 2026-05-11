import SwiftUI
import WndrKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct AnnotationToolbarView: View {
    @Binding var selectedTool: AnnotationTool
    @Binding var selectedColor: String
    var onClearAll: () -> Void

    public init(
        selectedTool: Binding<AnnotationTool>,
        selectedColor: Binding<String>,
        onClearAll: @escaping () -> Void
    ) {
        self._selectedTool = selectedTool
        self._selectedColor = selectedColor
        self.onClearAll = onClearAll
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Tool selection
            toolButton(.select, icon: "arrow.up.left.and.arrow.down.right", label: "Select")
            toolButton(.highlight, icon: "highlighter", label: "Highlight")
            toolButton(.underline, icon: "underline", label: "Underline")

            Divider()
                .frame(height: 20)

            // Color picker
            colorPicker

            Divider()
                .frame(height: 20)

            // Actions
            Button(action: onClearAll) {
                Label("Clear All", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.platformControlBackground)
    }

    private func toolButton(_ tool: AnnotationTool, icon: String, label: String) -> some View {
        Button(action: { selectedTool = tool }) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 50, height: 40)
            .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .help(label)
        #endif
    }

    private var colorPicker: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationColorOption.allCases, id: \.self) { colorOption in
                Circle()
                    .fill(colorOption.color)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(selectedColor == colorOption.id ? Color.primary : Color.clear, lineWidth: 2)
                    )
                    .onTapGesture {
                        selectedColor = colorOption.id
                    }
            }
        }
    }
}

public enum AnnotationTool: String, CaseIterable {
    case select
    case highlight
    case underline

    #if canImport(AppKit)
    public var cursor: NSCursor {
        switch self {
        case .select:
            return .arrow
        case .highlight, .underline:
            return .iBeam
        }
    }
    #endif
}

public enum AnnotationColorOption: String, CaseIterable {
    case yellow
    case green
    case blue
    case pink
    case orange
    case purple

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.92, blue: 0.23)
        case .green: return Color(red: 0.30, green: 0.69, blue: 0.31)
        case .blue: return Color(red: 0.13, green: 0.59, blue: 0.95)
        case .pink: return Color(red: 0.91, green: 0.12, blue: 0.39)
        case .orange: return Color(red: 1.0, green: 0.60, blue: 0.0)
        case .purple: return Color(red: 0.61, green: 0.15, blue: 0.69)
        }
    }

    /// Platform-native color with translucency for PDF highlight annotations.
    public var platformColor: PlatformColor {
        switch self {
        case .yellow: return PlatformColor(red: 1.0, green: 0.92, blue: 0.23, alpha: 0.4)
        case .green: return PlatformColor(red: 0.30, green: 0.69, blue: 0.31, alpha: 0.4)
        case .blue: return PlatformColor(red: 0.13, green: 0.59, blue: 0.95, alpha: 0.4)
        case .pink: return PlatformColor(red: 0.91, green: 0.12, blue: 0.39, alpha: 0.4)
        case .orange: return PlatformColor(red: 1.0, green: 0.60, blue: 0.0, alpha: 0.4)
        case .purple: return PlatformColor(red: 0.61, green: 0.15, blue: 0.69, alpha: 0.4)
        }
    }

    /// Backwards-compatible alias for macOS code.
    public var nsColor: PlatformColor { platformColor }
}

#if DEBUG
#Preview {
    AnnotationToolbarView(
        selectedTool: .constant(.highlight),
        selectedColor: .constant("yellow"),
        onClearAll: {}
    )
}
#endif
