#import <UIKit/UIKit.h>

typedef void (^AQWBotCommand)(NSDictionary *request);

@interface AQWBotDrawer : UIView
- (instancetype)initWithFrame:(CGRect)frame command:(AQWBotCommand)command;
- (void)showState:(NSString *)detail running:(BOOL)running;
- (void)showMap:(NSString *)map;
- (void)showBag:(NSDictionary *)bag;
- (void)setExpanded:(BOOL)expanded;
+ (BOOL)checkControls;
@end
