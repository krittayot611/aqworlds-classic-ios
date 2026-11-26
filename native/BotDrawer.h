#import <UIKit/UIKit.h>

typedef void (^AQWBotCommand)(NSDictionary *request);

@interface AQWBotDrawer : UIView
- (instancetype)initWithFrame:(CGRect)frame command:(AQWBotCommand)command;
- (void)attachBesideGame:(UIView *)game;
- (void)showState:(NSString *)detail running:(BOOL)running;
- (void)showMap:(NSString *)map;
- (void)showTravel:(NSString *)text active:(BOOL)active;
- (void)showNotice:(NSString *)text;
- (void)showDestinations:(NSDictionary *)panel;
- (void)showBag:(NSDictionary *)bag;
- (void)setExpanded:(BOOL)expanded;
+ (BOOL)checkControls;
@end
