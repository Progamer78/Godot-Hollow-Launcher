#pragma once
#include "core/io/file_access.h"
#include "scene/resources/compressed_texture.h"

// Imported cursor textures already have CPU-readable image data in the PCK.
// Reading them back from the GPU during a script's _Ready unnecessarily waits
// on rendering work before the first frame, and requires a current GL context.
inline Ref<Image> player_read_imported_cursor(const Ref<CompressedTexture2D> &texture) {
    Ref<FileAccess> file = FileAccess::open(texture->get_load_path(), FileAccess::READ);
    if (file.is_null() || file->get_length() < 36 || file->get_length() > 4 * 1024 * 1024) return Ref<Image>();
    // Official CompressedTexture2D::_load_data GST2 header (format version 1).
    if (file->get_32() != 0x32545347 || file->get_32() > CompressedTexture2D::FORMAT_VERSION) return Ref<Image>();
    const uint32_t width = file->get_32(), height = file->get_32();
    if (!width || !height || width > 256 || height > 256) return Ref<Image>();
    file->seek(36);
    Ref<Image> image = CompressedTexture2D::load_image_from_file(file, 0);
    if (image.is_null() || image->is_empty()) return Ref<Image>();
    if (image->is_compressed() && image->decompress() != OK) return Ref<Image>();
    return image;
}
