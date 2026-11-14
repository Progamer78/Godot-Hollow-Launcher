// Included inside DisplayServerAppleEmbedded by tools/patch_engine.py.
// UIKit draws the virtual pointer; Godot retains its normal mouse API/state.
private:
    DisplayServerEnums::MouseMode player_mouse_mode = DisplayServerEnums::MOUSE_MODE_VISIBLE;
    DisplayServerEnums::MouseMode player_mouse_override = DisplayServerEnums::MOUSE_MODE_VISIBLE;
    bool player_mouse_override_enabled = false;
    DisplayServerEnums::CursorShape player_cursor_shape = DisplayServerEnums::CURSOR_ARROW;
    HashMap<int, Ref<Image>> player_cursor_images;
    HashMap<int, Vector2> player_cursor_hotspots;
    uint64_t player_cursor_revision = 1;

public:
    void mouse_set_mode(DisplayServerEnums::MouseMode p_mode) override { player_mouse_mode = p_mode; }
    DisplayServerEnums::MouseMode mouse_get_mode() const override { return player_mouse_mode; }
    void mouse_set_mode_override(DisplayServerEnums::MouseMode p_mode) override { player_mouse_override = p_mode; }
    DisplayServerEnums::MouseMode mouse_get_mode_override() const override { return player_mouse_override; }
    void mouse_set_mode_override_enabled(bool p_enabled) override { player_mouse_override_enabled = p_enabled; }
    bool mouse_is_mode_override_enabled() const override { return player_mouse_override_enabled; }
    void warp_mouse(const Point2i &p_position) override {
        if (Input::get_singleton()) Input::get_singleton()->set_mouse_position(p_position);
    }
    Point2i mouse_get_position() const override {
        return Input::get_singleton() ? Point2i(Input::get_singleton()->get_mouse_position()) : Point2i();
    }
    BitField<MouseButtonMask> mouse_get_button_state() const override {
        return Input::get_singleton() ? Input::get_singleton()->get_mouse_button_mask() : BitField<MouseButtonMask>();
    }
    void cursor_set_shape(DisplayServerEnums::CursorShape p_shape) override {
        if (player_cursor_shape != p_shape) { player_cursor_shape = p_shape; ++player_cursor_revision; }
    }
    DisplayServerEnums::CursorShape cursor_get_shape() const override { return player_cursor_shape; }
    void cursor_set_custom_image(const Ref<Resource> &p_cursor, DisplayServerEnums::CursorShape p_shape = DisplayServerEnums::CURSOR_ARROW, const Vector2 &p_hotspot = Vector2()) override {
        if (p_cursor.is_null()) {
            player_cursor_images.erase(int(p_shape));
            player_cursor_hotspots.erase(int(p_shape));
        } else {
            Ref<CompressedTexture2D> imported = p_cursor;
            Ref<Image> image = imported.is_valid() ? player_read_imported_cursor(imported) : _get_cursor_image_from_resource(p_cursor, p_hotspot);
            if (image.is_null() || image->is_empty() || p_hotspot.x < 0 || p_hotspot.y < 0 || p_hotspot.x >= image->get_width() || p_hotspot.y >= image->get_height()) {
                // A failed cursor decode should show the native arrow, never
                // keep a corrupt or stale image from an earlier cursor.
                player_cursor_images.erase(int(p_shape));
                player_cursor_hotspots.erase(int(p_shape));
            } else {
                player_cursor_images[int(p_shape)] = image;
                player_cursor_hotspots[int(p_shape)] = p_hotspot;
            }
        }
        ++player_cursor_revision;
    }
    uint64_t player_get_cursor_revision() const { return player_cursor_revision; }
    Ref<Image> player_get_cursor_image() const {
        const Ref<Image> *image = player_cursor_images.getptr(int(player_cursor_shape));
        return image ? *image : Ref<Image>();
    }
    Vector2 player_get_cursor_hotspot() const {
        const Vector2 *hotspot = player_cursor_hotspots.getptr(int(player_cursor_shape));
        return hotspot ? *hotspot : Vector2();
    }
    DisplayServerEnums::MouseMode player_get_effective_mouse_mode() const {
        return player_mouse_override_enabled ? player_mouse_override : player_mouse_mode;
    }
