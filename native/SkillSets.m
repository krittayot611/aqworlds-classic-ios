#import "SkillSets.h"

NSDictionary *AQWStep(NSNumber *slot) {
    return @{@"slot":slot, @"wait":@YES, @"match":@"all", @"rules":@[]};
}
NSString *AQWRuleTitle(NSDictionary *r) {
    NSString *subject = [r[@"who"] isEqual:@"self"] ? @"Self" : @"Target";
    if ([r[@"kind"] isEqual:@"aura"]) {
        NSString *op = r[@"op"];
        NSString *detail = [op isEqual:@"missing"] ? @"absent" : [op isEqual:@"stacks"]
            ? [NSString stringWithFormat:@"≥ %@ stacks",r[@"value"]] : @"present";
        return [NSString stringWithFormat:@"%@ · %@ %@",subject,r[@"name"],detail];
    }
    return [NSString stringWithFormat:@"%@ %@ %@ %@%%",subject,[r[@"kind"] uppercaseString],
            [r[@"op"] isEqual:@"below"] ? @"<" : @">",r[@"value"]];
}
NSString *AQWStepSummary(NSDictionary *step) {
    NSArray *rules = step[@"rules"];
    if (!rules.count) return @"Always";
    NSMutableArray *titles = [NSMutableArray array];
    for (NSDictionary *r in rules) [titles addObject:AQWRuleTitle(r)];
    return [titles componentsJoinedByString:[step[@"match"] isEqual:@"any"] ? @" OR " : @" AND "];
}

@interface AQWSkillSets ()
@property(nonatomic,strong) NSUserDefaults *defaults;
@end

@implementation AQWSkillSets
static NSString *const storage = @"aqw.skillSets.v1";
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) _defaults = defaults;
    return self;
}
- (NSDictionary *)record:(NSString *)classID {
    return classID.length ? [self.defaults dictionaryForKey:storage][classID] : nil;
}
- (NSArray<NSDictionary *> *)setsFor:(NSString *)classID {
    return [self record:classID][@"sets"] ?: @[];
}
- (NSDictionary *)selectedFor:(NSString *)classID {
    NSDictionary *record = [self record:classID];
    for (NSDictionary *profile in record[@"sets"])
        if ([profile[@"id"] isEqual:record[@"selected"]]) return profile;
    return [self setsFor:classID].firstObject;
}
- (void)write:(NSArray *)sets selected:(NSString *)selected forClass:(NSString *)classID {
    if (!classID.length) return;
    NSMutableDictionary *all = [[self.defaults dictionaryForKey:storage] mutableCopy] ?: [NSMutableDictionary new];
    all[classID] = @{@"sets":sets, @"selected":selected ?: @""};
    [self.defaults setObject:all forKey:storage];
}
- (void)select:(NSString *)setID forClass:(NSString *)classID {
    NSArray *sets = [self setsFor:classID];
    for (NSDictionary *p in sets)
        if ([p[@"id"] isEqual:setID]) { [self write:sets selected:setID forClass:classID]; break; }
}
- (void)save:(NSDictionary *)profile forClass:(NSString *)classID {
    if (!classID.length || ![profile[@"id"] length] || ![profile[@"name"] length] || ![profile[@"steps"] count]) return;
    NSMutableArray *sets = [[self setsFor:classID] mutableCopy];
    NSUInteger index = [sets indexOfObjectPassingTest:^BOOL(NSDictionary *p, NSUInteger i, BOOL *stop) {
        return [p[@"id"] isEqual:profile[@"id"]];
    }];
    if (index == NSNotFound) [sets addObject:profile]; else sets[index] = profile;
    [self write:sets selected:profile[@"id"] forClass:classID];
}
- (void)remove:(NSString *)setID forClass:(NSString *)classID {
    NSString *selected = [self selectedFor:classID][@"id"];
    NSMutableArray *sets = [[self setsFor:classID] mutableCopy];
    for (NSDictionary *p in [sets copy])
        if ([p[@"id"] isEqual:setID]) { [sets removeObject:p]; break; }
    if ([selected isEqual:setID]) selected = [sets.firstObject objectForKey:@"id"];
    [self write:sets selected:selected forClass:classID];
}
- (void)migrateLegacyForEquipped:(NSString *)classID {
    NSArray *old = [self.defaults arrayForKey:@"aqw.rotation.slots"];
    if (!classID.length || !old) return;
    if (old.count > 0 && old.count <= 8 && ![self record:classID]) {
        NSMutableArray *steps = [NSMutableArray array];
        for (id n in old) if ([@[@2,@3,@4,@5] containsObject:n]) [steps addObject:AQWStep(n)];
        if (steps.count == old.count)
            [self save:@{@"id":@"legacy", @"name":@"Previous rotation", @"steps":steps} forClass:classID];
    }
    [self.defaults removeObjectForKey:@"aqw.rotation.slots"];
}
@end
