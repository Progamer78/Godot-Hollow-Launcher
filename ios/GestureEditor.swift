import SwiftUI

struct GestureEditor: View {
    @State var value: TouchGestures
    let onSave: (TouchGestures) -> Void
    @Environment(\.presentationMode) private var presentation
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Click while moving the pointer"), footer: Text("Keep one finger on the trackpad and tap elsewhere with another to click at the current pointer position. Choosing a button enables trackpad mouse mode. Turn this off to use two-finger dragging, scrolling or tap gestures.")) {
                    Picker("Second-finger click", selection: Binding(get: { value.secondFingerClick ?? "off" }, set: { value.secondFingerClick = $0 == "off" ? nil : $0; if $0 != "off" { value.twoFingerDrag = false } })) {
                        Text("Off").tag("off"); Text("Left Click").tag("left"); Text("Right Click").tag("right")
                    }
                }
                Section(header: Text("Other trackpad gestures")) {
                    Toggle("Enable multi-finger gestures",isOn:$value.enabled)
                    TextField("Two-finger tap key",text:$value.twoFingerTap).autocapitalization(.none).disableAutocorrection(true)
                    TextField("Three-finger tap key",text:$value.threeFingerTap).autocapitalization(.none).disableAutocorrection(true)
                    TextField("Two-finger double-tap key", text: Binding(get: { value.twoFingerDoubleTap ?? "Mouse Right" }, set: { value.twoFingerDoubleTap = $0 })).autocapitalization(.none).disableAutocorrection(true)
                    Toggle("Hold one finger, drag with another", isOn: Binding(get: { value.twoFingerDrag == true }, set: { value.twoFingerDrag = $0 }))
                    Text("Hold one finger still, then slide another to move the pointer with the left button held. Lift either finger to release. Useful for scrollbars, sliders and dragging items.").font(.caption)
                    if value.twoFingerDrag != true { Toggle("Two-finger drag scrolls the wheel",isOn:$value.scroll) }
                }.disabled(value.secondFingerButton != nil)
                Text("Use Trackpad mouse mode. Gestures act outside virtual buttons and joysticks. Key examples: Mouse Right, Escape, Space, F5, or None. Direct Touch retains its normal touch behavior.").font(.caption)
            }.navigationTitle("Touch Gestures")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { presentation.wrappedValue.dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Save") { value.constrain(); onSave(value); presentation.wrappedValue.dismiss() } }
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
