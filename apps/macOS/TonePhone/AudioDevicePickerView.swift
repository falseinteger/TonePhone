//
//  AudioDevicePickerView.swift
//  TonePhone
//
//  Audio device picker popover following macOS Human Interface Guidelines.
//  Styled similar to macOS Sound menu in Control Center.
//

import SwiftUI

/// A popover view for selecting audio input and output devices.
/// Follows macOS HIG with menu-like appearance and proper visual hierarchy.
struct AudioDevicePickerView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Output section (speakers - most commonly changed, so first)
            DeviceSection(
                title: "Output",
                icon: "speaker.wave.2.fill",
                devices: viewModel.outputDevices,
                selectedDevice: viewModel.selectedOutputDevice,
                defaultDeviceName: viewModel.getDefaultOutputDeviceName(),
                onSelect: { device in
                    viewModel.selectOutputDevice(device)
                }
            )

            SectionDivider()

            // Input section (microphones)
            DeviceSection(
                title: "Input",
                icon: "mic.fill",
                devices: viewModel.inputDevices,
                selectedDevice: viewModel.selectedInputDevice,
                defaultDeviceName: viewModel.getDefaultInputDeviceName(),
                onSelect: { device in
                    viewModel.selectInputDevice(device)
                }
            )
        }
        .padding(.vertical, 8)
        .frame(width: 280)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }
}

// MARK: - Visual Effect View

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Section Divider

private struct SectionDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

// MARK: - Device Section

private struct DeviceSection: View {
    let title: String
    let icon: String
    let devices: [AudioDevice]
    let selectedDevice: AudioDevice?
    let defaultDeviceName: String?
    let onSelect: (AudioDevice?) -> Void

    /// Whether system default is currently selected
    private var isSystemDefaultSelected: Bool {
        selectedDevice == nil || selectedDevice?.id.isEmpty == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            // System Default option (shows actual default device name)
            DeviceRow(
                name: "System Default",
                subtitle: defaultDeviceName,
                isSelected: isSystemDefaultSelected,
                showDefaultBadge: false
            ) {
                onSelect(nil)
            }

            // Device list
            ForEach(devices) { device in
                DeviceRow(
                    name: device.name,
                    subtitle: nil,
                    isSelected: !isSystemDefaultSelected && selectedDevice?.id == device.id,
                    showDefaultBadge: device.isDefault
                ) {
                    onSelect(device)
                }
            }
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let name: String
    let subtitle: String?
    let isSelected: Bool
    let showDefaultBadge: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Selection indicator
                ZStack {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(width: 16)

                // Device info
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if showDefaultBadge {
                            Text("Default")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.3))
                                )
                        }
                    }

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected && isHovered {
            return Color.accentColor.opacity(0.15)
        } else if isHovered {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.5)
        } else if isSelected {
            return Color.accentColor.opacity(0.08)
        }
        return .clear
    }
}

// MARK: - Preview

#Preview("Audio Device Picker") {
    AudioDevicePickerView(
        viewModel: AppViewModel(),
        isPresented: .constant(true)
    )
    .frame(height: 300)
}
