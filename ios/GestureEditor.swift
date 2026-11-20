import SwiftUI

struct GestureEditor: View {
    @State var value: TouchGestures
    let onSave: (TouchGestures) -> Void
    @Environment(\.presentationMode) private var presentation
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("One-finger camera look"), footer: Text("Slide one finger to look around while your other thumb uses a joystick. The chosen mouse button stays held until you lift. Virtual buttons and joysticks keep their own touches. Mouse sensitivity controls look speed.")) {
                    Picker("Camera area", selection: Binding(get: { value.cameraLook ?? "off" }, set: { value.cameraLook = $0 == "off" ? nil : $0 })) {
                        Text("Off").tag("off"); Text("Right half").tag("right"); Text("Full trackpad").tag("full")
                    }
                    if value.cameraLook != nil {
                        Picker("Hold while looking", selection: Binding(get: { value.cameraButton ?? "right" }, set: { value.cameraButton = $0 })) {
                            Text("Right Click").tag("right"); Text("Left Click").tag("left"); Text("No button (captured mouse games)").tag("none")
                        }
                    }
                }
                Section(header: Text("Mouse wheel scrolling"), footer: Text("Slide vertically in the selected edge strip to scroll at the pointer, without moving it or clicking. This also works when two-finger dragging or second-finger clicking is enabled. Two-finger wheel scrolling is available when those gestures are off.")) {
                    Picker("Edge scroll strip", selection: Binding(get: { value.edgeScroll ?? "off" }, set: { value.edgeScroll = $0 == "off" ? nil : $0 })) {
                        Text("Off").tag("off"); Text("Left edge").tag("left"); Text("Right edge").tag("right")
                    }
                    if value.edgeScroll != nil {
                        Slider(value: Binding(get: { value.edgeScrollWidth ?? 36 }, set: { value.edgeScrollWidth = $0 }), in: 20...80, step: 4)
                        Text("Scroll strip width: \(Int(value.edgeScrollWidth ?? 36)) points").font(.caption)
                    }
                    Slider(value: Binding(get: { value.scrollSpeed ?? 1 }, set: { value.scrollSpeed = $0 }), in: 0.25...4, step: 0.25)
                    Text("Scroll speed: \(String(format: "%.2f", value.scrollSpeed ?? 1))×").font(.caption)
                    Toggle("Reverse scrolling direction", isOn: Binding(get: { value.reverseScroll == true }, set: { value.reverseScroll = $0 }))
                }
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
                    if value.twoFingerDrag == true {
                        Picker("Button held while dragging", selection: Binding(get: { value.twoFingerDragButton ?? "left" }, set: { value.twoFingerDragButton = $0 })) {
                            Text("Left Click").tag("left"); Text("Right Click").tag("right")
                        }
                    }
                    Text("Hold one finger still, then slide another to move the pointer with the selected mouse button held. Lift either finger to release. Use Right Click for games that rotate the camera while holding the right mouse button.").font(.caption)
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
