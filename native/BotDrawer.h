#import <UIKit/UIKit.h>

typedef void (^AQWBotCommand)(NSString *action, NSArray<NSNumber *> *slots, BOOL autoTarget);

@interface AQWBotDrawer : UIView
- (instancetype)initWithFrame:(CGRect)frame command:(AQWBotCommand)command;
- (void)showState:(NSString *)detail running:(BOOL)running;
- (void)showMap:(NSString *)map;
- (void)setExpanded:(BOOL)expanded;
+ (BOOL)checkControls;
@end
