#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSDictionary *AQWStep(NSNumber *slot);
FOUNDATION_EXPORT NSString *AQWRuleTitle(NSDictionary *rule);
FOUNDATION_EXPORT NSString *AQWStepSummary(NSDictionary *step);

@interface AQWSkillSets : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (NSArray<NSDictionary *> *)setsFor:(NSString *)classID;
- (NSDictionary *)selectedFor:(NSString *)classID;
- (void)select:(NSString *)setID forClass:(NSString *)classID;
- (void)save:(NSDictionary *)profile forClass:(NSString *)classID;
- (void)remove:(NSString *)setID forClass:(NSString *)classID;
- (void)migrateLegacyForEquipped:(NSString *)classID;
@end
