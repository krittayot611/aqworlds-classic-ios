#import <UIKit/UIKit.h>

@interface AQWSkillTable : UITableViewController
@end

@interface AQWChoiceList : AQWSkillTable
@property(nonatomic,copy) void (^refreshList)(void);
@property(nonatomic,copy) void (^cancelJump)(void);
@property(nonatomic,copy) NSString *feedback;
@property(nonatomic,copy) void (^removeItem)(NSDictionary *item);
- (void)updateRows:(NSArray *)rows context:(NSString *)context choose:(void (^)(NSString *))choose;
- (instancetype)initWithTitle:(NSString *)title rows:(NSArray<NSDictionary *> *)rows
                     selected:(NSString *)selected searchable:(BOOL)searchable
                       choose:(void (^)(NSString *itemID))choose;
@end

@interface AQWSkillEditor : AQWSkillTable
@property(nonatomic,copy) NSArray *abilityNames;
- (instancetype)initForClass:(NSString *)className profile:(NSDictionary *)profile
                       saved:(void (^)(NSDictionary *profile))saved;
@end

FOUNDATION_EXPORT NSString *AQWAbilityLabel(NSArray *names, NSInteger slot);
FOUNDATION_EXPORT UINavigationController *AQWSkillNavigation(UIViewController *root);

