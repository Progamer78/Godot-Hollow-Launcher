#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>

@interface HollowBaselineGL : CAEAGLLayer
- (void)initializeDisplayLayer;
@end
@interface HollowFixedGL : CAEAGLLayer
- (void)initializeDisplayLayer;
- (void)startRenderDisplayLayer;
@end

@interface GraphicsDelegate : UIResponder <UIApplicationDelegate>
@property(strong, nonatomic) UIWindow *window;
@end
@implementation GraphicsDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *view = self.window.rootViewController.view;
        [EAGLContext setCurrentContext:nil];
        HollowBaselineGL *baseline = [HollowBaselineGL layer];
        baseline.frame = CGRectMake(0, 0, 128, 128);
        [view.layer addSublayer:baseline];
        [baseline initializeDisplayLayer];
        BOOL reproduced = [EAGLContext currentContext] == nil;
        [baseline removeFromSuperlayer];

        HollowFixedGL *fixed = [HollowFixedGL layer];
        fixed.frame = CGRectMake(0, 0, 128, 128);
        [view.layer addSublayer:fixed];
        [fixed initializeDisplayLayer];
        [fixed startRenderDisplayLayer];
        NSString *version = glGetString(GL_VERSION) ? [NSString stringWithUTF8String:(const char *)glGetString(GL_VERSION)] : @"";
        BOOL context = [EAGLContext currentContext] != nil && [version containsString:@"OpenGL ES 3"];
        BOOL framebuffer = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
        GLint varyings = 0; glGetIntegerv(GL_MAX_VARYING_VECTORS, &varyings);
        const char *source = "#version 300 es\nlayout(location=0) in vec2 p;void main(){gl_Position=vec4(p,0.0,1.0);}";
        GLuint shader = glCreateShader(GL_VERTEX_SHADER);
        glShaderSource(shader, 1, &source, nullptr); glCompileShader(shader);
        GLint compiled = GL_FALSE; glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
        glViewport(0, 0, 128, 128); glClearColor(0, 1, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        GLubyte pixel[4] = {}; glReadPixels(8, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        BOOL rendered = pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255;
        NSDictionary *result = @{
            @"passed": @(reproduced && context && framebuffer && compiled && rendered && varyings > 0),
            @"unpatched_override_failure_reproduced": @(reproduced), @"opengl_context": @(context),
            @"framebuffer": @(framebuffer), @"vertex_shader_compiled": @(compiled == GL_TRUE),
            @"rendered_green_pixel": @(rendered), @"varyings": @(varyings), @"version": version,
            @"scope": @"Original iOS OpenGL layer on iPhone Simulator with saved Forward+ setting; full game untested"
        };
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]
            writeToFile:[documents stringByAppendingPathComponent:@"graphics-result.json"] atomically:YES];
    });
    return YES;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(GraphicsDelegate.class)); } }
