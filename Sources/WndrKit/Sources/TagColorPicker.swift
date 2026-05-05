import SwiftUI

/// A color picker component for tags following macOS/iPadOS design patterns
public struct TagColorPicker: View {
    @Binding var selectedColor: String
    @Environment(\.dismiss) private var dismiss

    // macOS/iPadOS style tag colors (matches Finder tags)
    private let colors = [
        "#FF6B6B", // Red
        "#FF9500", // Orange
        "#FFCC00", // Yellow
        "#34C759", // Green
        "#00C7BE", // Teal
        "#007AFF", // Blue
        "#AF52DE"  // Purple
    ]

    private let colorNames = [
        "Red",
        "Orange",
        "Yellow",
        "Green",
        "Teal",
        "Blue",
        "Purple"
    ]

    public init(selectedColor: Binding<String>) {
        self._selectedColor = selectedColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tag Color")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    Button(action: {
                        selectedColor = color
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(Color(hex: color))
                                .font(.system(size: 18))

                            Text(colorNames[index])
                                .foregroundColor(.primary)

                            Spacer()

                            if selectedColor == color {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedColor == color ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical)
        .frame(width: 200)
    }
}

/// A preview of all available tag colors
public struct TagColorPalette: View {
    private let colors = [
        "#FF6B6B", // Red
        "#FF9500", // Orange
        "#FFCC00", // Yellow
        "#34C759", // Green
        "#00C7BE", // Teal
        "#007AFF", // Blue
        "#AF52DE"  // Purple
    ]

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            ForEach(colors, id: \.self) { color in
                Image(systemName: "tag.fill")
                    .foregroundColor(Color(hex: color))
                    .font(.system(size: 16))
            }
        }
    }
}

// Preview provider
struct TagColorPicker_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TagColorPicker(selectedColor: .constant("#007AFF"))
                .previewDisplayName("Color Picker")

            TagColorPalette()
                .padding()
                .previewDisplayName("Color Palette")
        }
    }
}