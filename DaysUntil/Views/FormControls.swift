import SwiftUI

/// Handles key presses while the view is on screen, before the focused control sees them. macOS 13
/// has no `onKeyPress`, so this uses a local event monitor. The handler returns true when it used
/// the key.
private struct KeyMonitor: ViewModifier {
    let handler: (NSEvent) -> Bool
    @State private var box = HandlerBox()

    /// Holds the latest handler, so the monitor, installed once, never calls a stale one.
    private final class HandlerBox {
        var handler: (NSEvent) -> Bool = { _ in false }
        var monitor: Any?
    }

    func body(content: Content) -> some View {
        box.handler = handler
        return content
            .onAppear {
                let box = box
                box.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    box.handler(event) ? nil : event
                }
            }
            .onDisappear {
                if let monitor = box.monitor {
                    NSEvent.removeMonitor(monitor)
                }
                box.monitor = nil
            }
    }
}

extension View {
    func onKeyDown(_ handler: @escaping (NSEvent) -> Bool) -> some View {
        modifier(KeyMonitor(handler: handler))
    }
}

extension NSEvent {
    /// Keys the form handles itself.
    enum Key {
        case left, right, up, down, pageUp, pageDown, returnKey, escape
    }

    /// The key pressed, when it's one of those and no command, option or control key is held.
    var key: Key? {
        guard modifierFlags.intersection([.command, .option, .control]).isEmpty else { return nil }
        return switch keyCode {
        case 123: .left
        case 124: .right
        case 125: .down
        case 126: .up
        case 116: .pageUp
        case 121: .pageDown
        case 36, 76: .returnKey
        case 53: .escape
        default: nil
        }
    }
}

/// A time field: the system's own, so hours and minutes can be typed or stepped with the arrow
/// keys in the Mac's format, drawn without its bezel inside the form's capsule.
struct TimeField: View {
    @Binding var time: Date

    var body: some View {
        HStack(spacing: 5) {
            TimePicker(time: $time)
                .fixedSize()
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .frame(height: 24)
        .fieldBackground()
    }
}

private struct TimePicker: NSViewRepresentable {
    @Binding var time: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.font = .systemFont(ofSize: NSFont.systemFontSize)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.setAccessibilityLabel(String(localized: "Time"))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.time = $time
        if picker.dateValue != time {
            picker.dateValue = time
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(time: $time)
    }

    final class Coordinator: NSObject {
        var time: Binding<Date>

        init(time: Binding<Date>) {
            self.time = time
        }

        @objc func changed(_ picker: NSDatePicker) {
            time.wrappedValue = picker.dateValue
        }
    }
}

/// A small switch at the end of a row.
struct RowSwitch: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
    }
}

/// A form row: a label on the left, its control on the right.
struct FormRow<Control: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            control
        }
        .frame(minHeight: 38)
        .padding(.horizontal, 12)
    }
}

/// A validation message, under the field it's about.
struct FieldError: View {
    let text: Text

    var body: some View {
        Label {
            text
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(.subheadline)
        .foregroundStyle(Color.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .padding(.top, -4)
    }
}
