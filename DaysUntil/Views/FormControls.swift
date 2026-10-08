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
/// keys in the Mac's format, drawn without its bezel inside the form's capsule. A click on it or
/// on its clock also opens our hours and minutes under the row, for setting the time without the
/// keyboard. Tabbing into it doesn't, so they never get in the way of typing.
struct TimeField: View {
    @Binding var time: TimeOfDay
    @Binding var isOpen: Bool
    @State private var handle = PickerHandle()

    var body: some View {
        HStack(spacing: 5) {
            TimePicker(time: $time, handle: handle) { isOpen = true }
                .fixedSize()
            Button {
                if isOpen {
                    isOpen = false
                } else {
                    // Typing goes to the field while they're open.
                    if let picker = handle.picker {
                        picker.window?.makeFirstResponder(picker)
                    }
                    isOpen = true
                }
            } label: {
                Image(systemName: isOpen ? "chevron.up" : "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(isOpen ? Text("Close Hours and Minutes") : Text("Show Hours and Minutes"))
        }
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .frame(height: 24)
        .fieldBackground(isActive: isOpen)
    }
}

/// The field's own picker, so its clock can give it the keyboard.
private final class PickerHandle {
    weak var picker: NSDatePicker?
}

/// The system's date picker, telling when it's clicked.
private final class ClickablePicker: NSDatePicker {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
        super.mouseDown(with: event)
    }
}

private struct TimePicker: NSViewRepresentable {
    @Binding var time: TimeOfDay
    let handle: PickerHandle
    let onClick: () -> Void

    func makeNSView(context: Context) -> ClickablePicker {
        let picker = ClickablePicker()
        picker.calendar = .editor
        picker.timeZone = .gmt
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.font = .systemFont(ofSize: NSFont.systemFontSize)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.setAccessibilityLabel(String(localized: "Time"))
        handle.picker = picker
        return picker
    }

    func updateNSView(_ picker: ClickablePicker, context: Context) {
        context.coordinator.time = $time
        picker.onClick = onClick
        let value = CountdownMath.date(CalendarDay(year: 2001, month: 1, day: 1), at: time, in: .gmt)
        if picker.dateValue != value { picker.dateValue = value }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(time: $time)
    }

    final class Coordinator: NSObject {
        var time: Binding<TimeOfDay>

        init(time: Binding<TimeOfDay>) {
            self.time = time
        }

        @objc func changed(_ picker: NSDatePicker) {
            time.wrappedValue = CountdownMath.timeOfDay(of: picker.dateValue, in: .gmt)
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
