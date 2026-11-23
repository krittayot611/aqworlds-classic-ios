#import <UIKit/UIKit.h>

@interface AQWChoiceList : UITableViewController
- (instancetype)initWithTitle:(NSString *)title rows:(NSArray<NSDictionary *> *)rows
                     selected:(NSString *)selected searchable:(BOOL)searchable
                       choose:(void (^)(NSString *itemID))choose;
@end

@interface AQWSkillEditor : UITableViewController
- (instancetype)initForClass:(NSString *)className profile:(NSDictionary *)profile
                       saved:(void (^)(NSDictionary *profile))saved;
@end

FOUNDATION_EXPORT UINavigationController *AQWSkillNavigation(UIViewController *root);

