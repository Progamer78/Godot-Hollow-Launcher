import SwiftUI

struct GestureEditor: View {
    @State var value: TouchGestures
    let onSave: (TouchGestures) -> Void
    @Environment(\.presentationMode) private var presentation
    var body: some View {
        NavigationView {
            Form {
                Toggle("Enable trackpad gestures",isOn:$value.enabled)
                TextField("Two-finger tap key",text:$value.twoFingerTap).autocapitalization(.none).disableAutocorrection(true)
                TextField("Three-finger tap key",text:$value.threeFingerTap).autocapitalization(.none).disableAutocorrection(true)
                Toggle("Two-finger drag scrolls",isOn:$value.scroll)
                Text("Use Trackpad mouse mode. Gestures act outside virtual buttons and joysticks. Key examples: Mouse Right, Escape, Space, F5, or None. Direct Touch retains its normal touch behavior.").font(.caption)
            }.navigationTitle("Touch Gestures")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { presentation.wrappedValue.dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Save") { value.constrain(); onSave(value); presentation.wrappedValue.dismiss() } }
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
