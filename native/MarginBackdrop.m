#import <UIKit/UIKit.h>
#import <string.h>
#import "FlashRuntimeExtensions.h"

// A native view paints only the physical gutters outside AIR's SHOW_ALL canvas.
// It never changes the AIR view, game transforms, Stage coordinates or hit tests.
@interface AQWMarginBackdrop : UIView
@property(nonatomic, strong) UIImage *texture;
- (CGRect)gameRect;
@end

@implementation AQWMarginBackdrop
- (CGRect)gameRect {
    CGFloat scale = MIN(self.bounds.size.width / 960.0, self.bounds.size.height / 550.0);
    CGSize game = CGSizeMake(960.0 * scale, 550.0 * scale);
    return CGRectMake((self.bounds.size.width - game.width) / 2.0,
                      (self.bounds.size.height - game.height) / 2.0, game.width, game.height);
}
- (void)layoutSubviews { [super layoutSubviews]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    if (!self.texture || CGRectIsEmpty(self.bounds)) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    UIBezierPath *gutters = [UIBezierPath bezierPathWithRect:self.bounds];
    [gutters appendPath:[UIBezierPath bezierPathWithRect:[self gameRect]]];
    gutters.usesEvenOddFillRule = YES;
    [gutters addClip];
    CGFloat scale = MAX(self.bounds.size.width / self.texture.size.width,
                        self.bounds.size.height / self.texture.size.height);
    CGSize size = CGSizeMake(self.texture.size.width * scale, self.texture.size.height * scale);
    [self.texture drawInRect:CGRectMake((self.bounds.size.width - size.width) / 2.0,
                                       (self.bounds.size.height - size.height) / 2.0,
                                       size.width, size.height)];
    CGContextRestoreGState(context);
}
@end

static AQWMarginBackdrop *backdrop;

static UIWindow *AQWGameWindow(void) {
    UIApplication *application = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows)
                if (window.isKeyWindow) return window;
        }
    }
    for (UIWindow *window in application.windows) if (window.isKeyWindow) return window;
    for (UIWindow *window in application.windows)
        if (!window.hidden && window.windowLevel == UIWindowLevelNormal) return window;
    return nil;
}

static BOOL AQWVerifyClipping(UIImage *texture, CGSize size) {
    AQWMarginBackdrop *test = [[AQWMarginBackdrop alloc] initWithFrame:(CGRect){CGPointZero, size}];
    test.texture = texture;
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
    [test drawRect:test.bounds];
    UIImage *rendered = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    size_t width = (size_t)size.width, height = (size_t)size.height;
    uint8_t *pixels = calloc(width * height, 4);
    if (!pixels || !rendered) { free(pixels); return NO; }
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, color,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (!context) { CGColorSpaceRelease(color); free(pixels); return NO; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), rendered.CGImage);
    CGRect game = [test gameRect];
    size_t x = game.origin.x > 1 ? (size_t)(game.origin.x / 2) : width / 2;
    size_t y = game.origin.x > 1 ? height / 2 : (size_t)(game.origin.y / 2);
    BOOL valid = pixels[(y * width + x) * 4 + 3] > 0 &&
        pixels[((height / 2) * width + width / 2) * 4 + 3] == 0 &&
        fabs(game.size.width / game.size.height - 960.0 / 550.0) < 0.001;
    CGContextRelease(context); CGColorSpaceRelease(color); free(pixels);
    return valid;
}

static FREObject AQWShowMargins(FREContext context, void *data, uint32_t argc, FREObject argv[]) {
    __block NSString *result = @"unavailable";
    uint32_t verify = 0;
    if (argc > 0) FREGetObjectAsBool(argv[0], &verify);
    void (^show)(void) = ^{
        UIView *host = AQWGameWindow().rootViewController.view;
        NSString *path = [NSBundle.mainBundle pathForResource:@"Background" ofType:@"jpg"];
        UIImage *image = path ? [UIImage imageWithContentsOfFile:path] : nil;
        if (!host || !image) return;
        if (!backdrop) {
            backdrop = [[AQWMarginBackdrop alloc] initWithFrame:host.bounds];
            backdrop.opaque = NO;
            backdrop.backgroundColor = UIColor.clearColor;
            backdrop.userInteractionEnabled = NO;
            backdrop.accessibilityElementsHidden = YES;
            backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        }
        if (verify && (!AQWVerifyClipping(image, CGSizeMake(1024, 472)) ||
                       !AQWVerifyClipping(image, CGSizeMake(1024, 768)))) {
            result = @"clipping check failed"; return;
        }
        backdrop.texture = image;
        backdrop.frame = host.bounds;
        if (backdrop.superview != host) { [backdrop removeFromSuperview]; [host addSubview:backdrop]; }
        [host bringSubviewToFront:backdrop];
        [backdrop setNeedsDisplay];
        CGRect game = [backdrop gameRect];
        result = [NSString stringWithFormat:@"active; view=%.1fx%.1f; game=%.1f,%.1f,%.1f,%.1f; input=disabled",
                  host.bounds.size.width, host.bounds.size.height,
                  game.origin.x, game.origin.y, game.size.width, game.size.height];
        if (verify) result = [result stringByAppendingString:@"; clipping=verified"];
    };
    if (NSThread.isMainThread) show(); else dispatch_sync(dispatch_get_main_queue(), show);
    FREObject value = NULL;
    const char *utf8 = result.UTF8String;
    FRENewObjectFromUTF8((uint32_t)strlen(utf8), (const uint8_t *)utf8, &value);
    return value;
}
static void AQWContextInitializer(void *data, const uint8_t *type, FREContext context,
                                  uint32_t *count, const FRENamedFunction **functions) {
    static FRENamedFunction entries[] = {{(const uint8_t *)"show", NULL, &AQWShowMargins}};
    *count = 1; *functions = entries;
}
static void AQWContextFinalizer(FREContext context) {
    dispatch_async(dispatch_get_main_queue(), ^{ [backdrop removeFromSuperview]; backdrop = nil; });
}
__attribute__((visibility("default")))
void AQWMarginsInitializer(void **data, FREContextInitializer *initializer, FREContextFinalizer *finalizer) {
    *data = NULL; *initializer = &AQWContextInitializer; *finalizer = &AQWContextFinalizer;
}
__attribute__((visibility("default")))
void AQWMarginsFinalizer(void *data) {}
