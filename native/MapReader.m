#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <string.h>
#import "MapReader.h"
#import "BotDrawer.h"

extern UIWindow *AQWGameWindow(void);

typedef int (*AQWMapExchange)(void *, const char *, char *, int);
typedef int (*AQWMapRead)(const char *, void *, AQWMapExchange, char *, int);

@interface AQWMapSession : NSObject
@property(nonatomic, assign) FREContext context;
@property(nonatomic) BOOL busy;
@property(nonatomic, copy) NSString *pending;
@property(nonatomic, strong) NSData *reply;
@property(nonatomic, strong) dispatch_semaphore_t ready;
@property(nonatomic, strong) AQWBotDrawer *drawer;
@end
@implementation AQWMapSession
@end

static AQWMapSession *sessionFor(FREContext context) {
    void *state = NULL;
    FREGetContextNativeData(context, &state);
    return (__bridge AQWMapSession *)state;
}

static NSString *stringArgument(FREObject value) {
    uint32_t length = 0;
    const uint8_t *bytes = NULL;
    if (FREGetObjectAsUTF8(value, &length, &bytes) != FRE_OK || length > 8192) return nil;
    return [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
}

static FREResult post(AQWMapSession *session, const char *code, NSString *text) {
    return FREDispatchStatusEventAsync(session.context, (const uint8_t *)code,
                                       (const uint8_t *)text.UTF8String);
}

// The worker waits here. The AIR thread services the event and returns immediately.
static int exchangeMap(void *state, const char *request, char *out, int capacity) {
    AQWMapSession *session = (__bridge AQWMapSession *)state;
    dispatch_semaphore_t ready = dispatch_semaphore_create(0);
    @synchronized (session) {
        if (!session.context) return -1;
        session.pending = [NSString stringWithUTF8String:request];
        session.reply = nil;
        session.ready = ready;
        if (post(session, "map.request", session.pending) != FRE_OK) {
            session.pending = nil;
            session.ready = nil;
            return -1;
        }
    }
    long timedOut = dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
    @synchronized (session) {
        NSData *reply = session.reply;
        session.pending = nil;
        session.reply = nil;
        session.ready = nil;
        if (timedOut || !session.context || !reply || reply.length >= (NSUInteger)capacity) return -1;
        memcpy(out, reply.bytes, reply.length);
        return (int)reply.length;
    }
}

static FREObject completeMap(FREContext context, void *unused, uint32_t argc, FREObject argv[]) {
    if (argc != 2) return NULL;
    AQWMapSession *session = sessionFor(context);
    NSString *request = stringArgument(argv[0]);
    NSString *reply = stringArgument(argv[1]);
    @synchronized (session) {
        if (reply && session.ready && !session.reply && [session.pending isEqualToString:request]) {
            session.reply = [reply dataUsingEncoding:NSUTF8StringEncoding];
            dispatch_semaphore_signal(session.ready);
        }
    }
    return NULL;
}

static AQWMapRead loadReader(NSString *root) {
    static AQWMapRead readMap;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *managed = [root stringByAppendingPathComponent:@"managed"];
        NSString *framework = [NSBundle.mainBundle.privateFrameworksPath
                               stringByAppendingPathComponent:@"AqwManagedHost.framework/AqwManagedHost"];
        if (![NSFileManager.defaultManager fileExistsAtPath:[managed stringByAppendingPathComponent:@"runtimeconfig.bin"]])
            return;
        if (setenv("AQW_MONO_BUNDLE_PATH", managed.fileSystemRepresentation, 1) != 0) return;
        void *image = dlopen(framework.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (image) readMap = (AQWMapRead)dlsym(image, "aqw_read_current_map");
        if (!readMap) NSLog(@"AQW map runtime: %s", dlerror());
    });
    return readMap;
}

static FREObject beginMap(FREContext context, void *unused, uint32_t argc, FREObject argv[]) {
    AQWMapSession *session = sessionFor(context);
    BOOL accepted;
    @synchronized (session) {
        accepted = session.context != NULL && !session.busy;
        if (accepted) session.busy = YES;
    }
    if (accepted) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                NSString *root = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"AqwMapRuntime"];
                AQWMapRead readMap = loadReader(root);
                char output[2048] = {0};
                int status = readMap ? readMap(root.fileSystemRepresentation, (__bridge void *)session,
                                               exchangeMap, output, sizeof(output)) : -1;
                NSString *result = [NSString stringWithUTF8String:output] ?: @"";
                if (status != 0 && !result.length) result = @"Unable to load or run the map reader.";
                @synchronized (session) {
                    session.busy = NO;
                    if (session.context) post(session, status == 0 ? "map.result" : "map.error", result);
                }
            }
        });
    }
    FREObject result = NULL;
    FRENewObjectFromBool(accepted, &result);
    return result;
}

static void onUI(dispatch_block_t work) {
    if (NSThread.isMainThread) work(); else dispatch_sync(dispatch_get_main_queue(), work);
}

static FREObject showTools(FREContext context, void *unused, uint32_t argc, FREObject argv[]) {
    AQWMapSession *session = sessionFor(context);
    uint32_t verify = 0;
    if (argc == 1) FREGetObjectAsBool(argv[0], &verify);
    __block BOOL shown = NO;
    onUI(^{
        UIView *host = AQWGameWindow().rootViewController.view;
        if (!host || (verify && ![AQWBotDrawer checkControls])) return;
        if (!session.drawer) {
            __weak AQWMapSession *weakSession = session;
            session.drawer = [[AQWBotDrawer alloc] initWithFrame:host.bounds
                command:^(NSString *action, NSArray *slots, BOOL autoTarget) {
                    AQWMapSession *live = weakSession;
                    NSDictionary *body = @{@"action":action, @"slots":slots ?: @[], @"auto":@(autoTarget)};
                    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
                    NSString *message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    @synchronized (live) {
                        if (live.context && post(live,"bot.command",message) != FRE_OK)
                            [live.drawer showState:@"Controls unavailable" running:NO];
                    }
                }];
        }
        if (session.drawer.superview != host) [host addSubview:session.drawer];
        [host bringSubviewToFront:session.drawer];
        if (verify) [session.drawer setExpanded:YES];
        shown = YES;
    });
    FREObject result = NULL;
    FRENewObjectFromBool(shown,&result);
    return result;
}

static FREObject updateTools(FREContext context, void *unused, uint32_t argc, FREObject argv[]) {
    if (argc != 3) return NULL;
    AQWMapSession *session = sessionFor(context);
    NSString *field = stringArgument(argv[0]), *text = stringArgument(argv[1]);
    uint32_t running = 0;
    if (!text || FREGetObjectAsBool(argv[2], &running) != FRE_OK) return NULL;
    onUI(^{
        if ([field isEqualToString:@"map"]) [session.drawer showMap:text];
        else if ([field isEqualToString:@"state"]) [session.drawer showState:text running:running != 0];
    });
    return NULL;
}

void AQWMapContextOpen(FREContext context, uint32_t *count, const FRENamedFunction **functions) {
    AQWMapSession *session = [AQWMapSession new];
    session.context = context;
    FRESetContextNativeData(context, (__bridge_retained void *)session);
    static FRENamedFunction entries[] = {
        {(const uint8_t *)"readMap", NULL, beginMap},
        {(const uint8_t *)"mapReply", NULL, completeMap},
        {(const uint8_t *)"showTools", NULL, showTools},
        {(const uint8_t *)"updateTools", NULL, updateTools},
    };
    *count = sizeof(entries) / sizeof(entries[0]);
    *functions = entries;
}

void AQWMapContextClose(void *state) {
    AQWMapSession *session = (__bridge_transfer AQWMapSession *)state;
    @synchronized (session) {
        session.context = NULL;
        if (session.ready) dispatch_semaphore_signal(session.ready);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [session.drawer removeFromSuperview]; session.drawer = nil; });
}
