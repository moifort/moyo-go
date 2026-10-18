import SwiftUI

/// The opponent's mode and its one setting, as form rows.
///
/// Shared by the new-game sheet and the mid-game one, so the opponent is described
/// the same way wherever it is chosen. The draft belongs to the caller: nothing is
/// sent to the bridge from here.
struct AIModeFields: View {
    @Bindable var session: GameSession
    @Binding var draft: GameSession.Settings

    private var mode: AIMode { AIMode.mode(for: draft.aiStrategy) }

    private func currentValue(_ setting: AIMode.Setting) -> Double {
        draft.value(for: mode)
            ?? session.settingValue(for: mode)
            ?? (setting.range.lowerBound + setting.range.upperBound) / 2
    }

    private func settingBinding(_ setting: AIMode.Setting) -> Binding<Double> {
        Binding(
            get: { currentValue(setting) },
            set: { draft.setValue($0, for: mode) }
        )
    }

    var body: some View {
        Picker("Adversaire", selection: $draft.aiStrategy) {
            ForEach(session.modes) { mode in
                Text(mode.name).tag(mode.id)
            }
        }
        .onChange(of: draft.aiStrategy) { _, newValue in
            // Each mode keeps its own setting; on switching, start from what
            // was last chosen for it, or from what the bridge holds.
            let switched = AIMode.mode(for: newValue)
            if draft.value(for: switched) == nil,
                let value = session.settingValue(for: switched)
            {
                draft.setValue(value, for: switched)
            }
        }

        if !mode.summary.isEmpty {
            Text(mode.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let setting = mode.setting {
            LabeledContent(setting.label) {
                HStack {
                    Slider(value: settingBinding(setting), in: setting.range, step: setting.step)
                    Text(setting.describe(currentValue(setting)))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
    }
}
