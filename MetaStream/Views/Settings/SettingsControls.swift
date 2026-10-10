import SwiftUI

/// Shared Settings row helpers: one slider row and one capability-gated toggle so every settings
/// screen shares layout instead of repeating the VStack/HStack/Slider and Toggle/disabled pairs.
func labeledSlider(_ title: String, valueText: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack { Text(title); Spacer(); Text(valueText).monospacedDigit().foregroundStyle(.secondary) }
        Slider(value: value, in: range)
    }
}

func capToggle(_ title: String, isOn: Binding<Bool>, supported: Bool = true) -> some View {
    Toggle(title, isOn: isOn).disabled(!supported)
}
