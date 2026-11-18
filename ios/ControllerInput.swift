import SwiftUI
import GameController
import UIKit

enum ControllerSnapshot {
    static func buttons(_ controller: GCController) -> [(String, GCControllerButtonInput)] {
        var result: [(String, GCControllerButtonInput)] = []
        if let g = controller.extendedGamepad {
            result = [("A",g.buttonA),("B",g.buttonB),("X",g.buttonX),("Y",g.buttonY),("L1",g.leftShoulder),("R1",g.rightShoulder),("L2",g.leftTrigger),("R2",g.rightTrigger),("Menu",g.buttonMenu),("Up",g.dpad.up),("Down",g.dpad.down),("Left",g.dpad.left),("Right",g.dpad.right)]
            if let b=g.buttonOptions { result.append(("Options",b)) }
            if let b=g.buttonHome { result.append(("Home",b)) }
            if let b=g.leftThumbstickButton { result.append(("L3",b)) }
            if let b=g.rightThumbstickButton { result.append(("R3",b)) }
        }
        var seen=Set(result.map { ObjectIdentifier($0.1) })
        for (name,button) in controller.physicalInputProfile.buttons.sorted(by: { $0.key < $1.key }) where seen.insert(ObjectIdentifier(button)).inserted {
            result.append(("Extra: " + name,button))
        }
        return result
    }
}

final class ControllerInput: ObservableObject {
    private var timer: Timer?
    private var profile=ControllerProfile()
    private var held=Set<String>()
    private var lastAxes: [Int:Double]=[:]
    private weak var view: UIView?
    private var last=Date()
    private var device: ObjectIdentifier?
    func configure(_ value: ControllerProfile?, active: Bool, view: UIView) {
        var p=value ?? ControllerProfile(); p.constrain()
        if profile != p { releaseOwned(); profile=p }
        self.view=view
        guard p.enabled && active else { stop(); return }
        if timer == nil {
            last=Date()
            let timer=Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in self?.poll() }
            self.timer=timer; RunLoop.main.add(timer, forMode: .common)
        }
    }
    func stop() { timer?.invalidate(); timer=nil; releaseOwned(); device=nil }
    deinit { timer?.invalidate() }
    private func releaseOwned() {
        for key in GameInput.ordered(held).reversed() { GameInput.key(key, pressed: false) }; held=[]
        for axis in lastAxes.keys { GameInput.axis(axis,value:0,source:"physical-controller") }; lastAxes=[:]
    }
    private func poll() {
        let now=Date(), dt=min(0.05,max(0,now.timeIntervalSince(last))); last=now
        guard let controller=GCController.controllers().first else { releaseOwned(); device=nil; return }
        let id=ObjectIdentifier(controller)
        if device != id { releaseOwned(); device=id }
        var next=Set<String>(), axes: [Int:Double]=[:]
        for (name,button) in ControllerSnapshot.buttons(controller) {
            let target=profile.target(name)
            if target == "Pad L2" || target == "Pad R2" {
                let axis=target == "Pad L2" ? 4 : 5
                axes[axis]=max(axes[axis] ?? 0,Double(button.value))
            } else if button.isPressed, target != "None", !target.isEmpty { next.insert(target) }
        }
        if let g=controller.extendedGamepad {
            for (name,mode,stick,base) in [("Left Stick",profile.leftMode,g.leftThumbstick,0),("Right Stick",profile.rightMode,g.rightThumbstick,2)] {
                let (x,y)=profile.stick(Double(stick.xAxis.value),-Double(stick.yAxis.value))
                if mode == "gamepad" { axes[base]=x; axes[base+1]=y }
                if mode == "keys" {
                    for (direction,pressed) in [("Up",y < -0.35),("Down",y > 0.35),("Left",x < -0.35),("Right",x > 0.35)] where pressed {
                        let target=profile.target(name+" "+direction); if target != "None" { next.insert(target) }
                    }
                }
                if mode == "mouse", let view=view, x != 0 || y != 0 {
                    PlayerRuntime.moveMouse(CGPoint(x:CGFloat(x*profile.mouseSpeed*dt),y:CGFloat(y*profile.mouseSpeed*dt)),from:view,relative:true)
                }
            }
        }
        for key in GameInput.ordered(held.subtracting(next)).reversed() { GameInput.key(key,pressed:false) }
        for key in GameInput.ordered(next.subtracting(held)) { GameInput.key(key,pressed:true) }; held=next
        for axis in Set(lastAxes.keys).union(axes.keys) where lastAxes[axis] != axes[axis] { GameInput.axis(axis,value:axes[axis] ?? 0,source:"physical-controller") }
        lastAxes=axes
    }
}

struct ControllerEditor: View {
    @State var profile: ControllerProfile
    let onSave: (ControllerProfile) -> Void
    @Environment(\.presentationMode) private var presentation
    @State private var available: [String]=[]
    @State private var status="Connect a controller in iOS Settings."
    private let timer=Timer.publish(every:0.2,on:.main,in:.common).autoconnect()
    var body: some View {
        NavigationView {
            Form {
                Toggle("Use this controller profile",isOn:$profile.enabled)
                Text(status).font(.caption)
                Text("When enabled, this profile replaces native controller forwarding. Extra buttons appear only when iOS exposes them independently. Some 8BitDo paddles duplicate standard buttons in firmware.").font(.caption)
                Section(header:Text("Sticks")) {
                    modePicker("Left stick",mode:$profile.leftMode)
                    modePicker("Right stick",mode:$profile.rightMode)
                    Text("Deadzone \(Int(profile.deadzone*100))%")
                    Slider(value:$profile.deadzone,in:0.05...0.6)
                    Text("Mouse speed \(Int(profile.mouseSpeed))")
                    Slider(value:$profile.mouseSpeed,in:100...2000)
                }
                Section(header:Text("Buttons and direction keys")) {
                    ForEach(Array(Set(ControllerProfile.defaults.keys).union(available).union(profile.bindings.keys)).sorted(),id:\.self) { name in
                        bindingRow(name)
                    }
                }
                Text("Examples: Space, Enter, Escape, Shift, W, Pad A, Pad R2, Mouse Left. Assign a stick to Mouse and a button to Mouse Left for pointer control.").font(.caption)
            }.navigationTitle("Controller")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { presentation.wrappedValue.dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Save") { profile.constrain(); onSave(profile); presentation.wrappedValue.dismiss() } }
            }
        }.navigationViewStyle(StackNavigationViewStyle())
        .onReceive(timer) { _ in
            guard let c=GCController.controllers().first else { status="No controller connected."; available=[]; return }
            let buttons=ControllerSnapshot.buttons(c)
            available=buttons.map { $0.0 }
            let pressed=buttons.filter { $0.1.isPressed }.map { $0.0 }.joined(separator:", ")
            status=(c.vendorName ?? "Controller") + (pressed.isEmpty ? " · Press a button to identify it." : " · "+pressed)
        }
    }
    private func modePicker(_ title: String,mode: Binding<String>) -> some View {
        Picker(title,selection:mode) { Text("Gamepad").tag("gamepad"); Text("Keys").tag("keys"); Text("Mouse").tag("mouse"); Text("Off").tag("off") }
    }
    private func bindingRow(_ name: String) -> some View {
        let selection = Binding<String>(get: { profile.target(name) }, set: { profile.bindings[name] = $0 })
        let standard = ["None"] + ControlKeys.all
        let choices = standard.contains(selection.wrappedValue) ? standard : [selection.wrappedValue] + standard
        return VStack(alignment: .leading, spacing: 6) {
            Picker(name, selection: selection) { ForEach(choices, id: \.self) { Text($0).tag($0) } }
            DisclosureGroup("Custom key name") {
                TextField("For example: F13", text: selection).autocapitalization(.none).disableAutocorrection(true)
                    .accessibilityLabel("Custom input for \(name)")
            }.font(.caption)
        }.padding(.vertical, 3)
    }
}
