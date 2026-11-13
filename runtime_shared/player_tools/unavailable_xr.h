#pragma once

#include "core/string/print_string.h"
#include "servers/xr/xr_interface.h"
#include "servers/xr/xr_server.h"
#include "servers/rendering/rendering_server_types.h"

// Desktop exports may query OpenXR without checking for null: desktop Godot
// registers that interface even when no headset is present. Preserve that
// capability query on iOS, where OpenXR is not compiled. Never claim VR support.
class HollowUnavailableXR : public XRInterface {
public:
    StringName get_name() const override { return "OpenXR"; }
    uint32_t get_capabilities() const override { return XR_NONE; }
    bool is_initialized() const override { return false; }
    bool initialize() override { return false; }
    void uninitialize() override {}
    Dictionary get_system_info() override { return Dictionary(); }
    TrackingStatus get_tracking_status() const override { return XR_NOT_TRACKING; }
    Transform3D get_camera_transform() override { return Transform3D(); }
    void process() override {}
    Size2 get_render_target_size() override { return Size2(); }
    uint32_t get_view_count() override { return 0; }
    Transform3D get_transform_for_view(uint32_t, const Transform3D &transform) override { return transform; }
    Projection get_projection_for_view(uint32_t, double, double, double) override { return Projection(); }
    Vector<RenderingServerTypes::BlitToScreen> post_draw_viewport(RID, const Rect2 &) override { return {}; }
};

inline void hollow_register_unavailable_xr() {
    XRServer *server = XRServer::get_singleton();
    if (server && server->find_interface("OpenXR").is_null()) {
        Ref<HollowUnavailableXR> unavailable;
        unavailable.instantiate();
        server->add_interface(unavailable);
        print_line("Godot Player: OpenXR capability queries return unavailable on iOS.");
    }
}
