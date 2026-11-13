"""Keep iOS graphics initialization consistent with the selected driver."""
from pathlib import Path


def patch(engine: Path):
    path = engine / "platform/ios/display_layer_ios.mm"
    text = path.read_text(encoding="utf-8")
    start = text.index('\t// Create GL ES 3 context\n')
    end = text.index('\n\tif (![EAGLContext setCurrentContext:context])', start)
    text = text[:start] + '''\t// This layer is created only for the selected opengl3 driver. The
\t// project's saved rendering_method can still be forward_plus or mobile
\t// when --rendering-method selects Compatibility (or Metal falls back).
\tcontext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
\tif (!context) {
\t\tNSLog(@"Failed to create OpenGL ES 3.0 context!");
\t\treturn;
\t}
''' + text[end:]
    path.write_text(text, encoding="utf-8", newline="\n")
