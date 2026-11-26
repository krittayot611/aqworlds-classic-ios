#import "BotDrawer.h"
#import "SkillEditor.h"
#import "SkillSets.h"
#import <QuartzCore/QuartzCore.h>
#import "SkillTheme.h"

static UILabel *label(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *view = [UILabel new];
    view.text = text;
    view.textColor = color;
    UIFont *font = [UIFont systemFontOfSize:size weight:weight];
    view.font = [[UIFontMetrics defaultMetrics] scaledFontForFont:font maximumPointSize:size + 6];
    view.adjustsFontForContentSizeCategory = YES;
    return view;
}

static UIButton *button(NSString *title, NSString *spoken, id target, SEL action) {
    UIButton *view = [UIButton buttonWithType:UIButtonTypeSystem];
    [view setTitle:title forState:UIControlStateNormal];
    [view setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    view.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    view.backgroundColor = AQWPanel();
    view.layer.cornerRadius = 10;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = AQWKeyline().CGColor;
    view.accessibilityLabel = spoken;
    [view addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [view.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return view;
}

static UIStackView *stack(NSArray<UIView *> *views, BOOL horizontal, CGFloat spacing) {
    UIStackView *view = [[UIStackView alloc] initWithArrangedSubviews:views];
    view.axis = horizontal ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    view.spacing = spacing;
    return view;
}

@interface AQWBotDrawer ()
@property(nonatomic, copy) AQWBotCommand command;
@property(nonatomic) BOOL expanded, running, pending, autoTarget, pickingClass;
@property(nonatomic,strong) AQWSkillSets *sets;
@property(nonatomic,strong) NSUserDefaults *preferences;
@property(nonatomic,strong) NSArray<NSDictionary *> *classes;
@property(nonatomic,copy) NSString *classID, *equipped;
@property(nonatomic,strong) NSNumber *session;
@property(nonatomic,weak) UIViewController *modal;
@property(nonatomic,weak) AQWChoiceList *mapList;
@property(nonatomic,copy) NSString *requestedMapTool;
@property(nonatomic,strong) UIButton *handle, *mobsButton, *bookmarkButton, *cancelTravel, *run, *chooseClass, *chooseSet, *addSet, *editSet, *deleteSet;
@property(nonatomic,strong) UILabel *stateLine, *travelNotice, *dot;
@property(nonatomic,strong) NSArray<UIButton *> *targets;
@property(nonatomic,strong) UIView *card, *dock;
@property(nonatomic,weak) UIView *gameSurface;
@property(nonatomic) CGAffineTransform originalTransform;
@property(nonatomic,strong) UIStackView *setActions;
@property(nonatomic,strong) UIScrollView *scroll;
@end

// Exercise sheet rows without interrupting the hosted game during the simulator check.
@interface AQWMapControlFixture : AQWBotDrawer
@property(nonatomic,strong) AQWChoiceList *captured;
@property(nonatomic) UIEdgeInsets testInsets;
@end
@implementation AQWMapControlFixture
- (UIEdgeInsets)safeAreaInsets { return self.testInsets; }
- (void)presentTool:(UIViewController *)page {
    if (![page isKindOfClass:UINavigationController.class]) return;
    UINavigationController *nav = (UINavigationController *)page;
    self.captured = (AQWChoiceList *)nav.topViewController;
    [nav setViewControllers:@[[UIViewController new]] animated:NO];
}
@end

@implementation AQWBotDrawer
- (instancetype)initWithFrame:(CGRect)frame command:(AQWBotCommand)command {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.command = command;
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    self.preferences = prefs;
    self.autoTarget = [prefs boolForKey:@"aqw.rotation.auto"];
    self.sets = [[AQWSkillSets alloc] initWithDefaults:prefs];
    self.classes = @[];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = UIColor.clearColor;
    self.handle = button(@"Skills", @"Open skill automation", self, @selector(toggle:));
    self.mobsButton = button(@"Mobs", @"Mobs, find a monster on this map", self, @selector(mobsTapped:));
    self.bookmarkButton = button(@"Bookmark", @"Bookmark, save or visit a location", self, @selector(marksTapped:));
    self.dock = [UIView new];
    self.dock.backgroundColor = AQWCharcoal();
    self.dock.userInteractionEnabled = NO;
    [self addSubview:self.dock];
    self.cancelTravel = button(@"Cancel", @"Cancel map travel", self, @selector(cancelTapped:));
    self.cancelTravel.hidden = YES;
    for (UIButton *control in @[self.handle,self.mobsButton,self.bookmarkButton,self.cancelTravel]) {
        control.titleLabel.font = [[UIFontMetrics defaultMetrics] scaledFontForFont:
            [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold] maximumPointSize:18];
        control.titleLabel.adjustsFontForContentSizeCategory = YES;
        control.titleLabel.adjustsFontSizeToFitWidth = YES;
        control.titleLabel.minimumScaleFactor = .83;
        control.contentEdgeInsets = UIEdgeInsetsMake(0,3,0,3);
        control.backgroundColor = AQWCharcoal();
        control.layer.cornerRadius = 9;
        control.layer.borderWidth = 0;
        control.layer.borderColor = AQWSecondary().CGColor;
        [self addSubview:control];
    }
    if (@available(iOS 15.0,*)) {
        NSArray *tiles = @[self.handle,self.mobsButton,self.bookmarkButton];
        NSArray *icons = @[@"slider.horizontal.3",@"scope",@"bookmark"];
        for (NSUInteger i=0;i<tiles.count;i++) {
            UIButton *tile=tiles[i];
            UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
            config.title = [tile titleForState:UIControlStateNormal];
            config.image = [UIImage systemImageNamed:icons[i]];
            config.imagePlacement = NSDirectionalRectEdgeTop;
            config.imagePadding = 3;
            config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium];
            config.baseForegroundColor = UIColor.whiteColor;
            config.contentInsets = NSDirectionalEdgeInsetsMake(2,0,2,0);
            config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *incoming) {
                NSMutableDictionary *out = [incoming mutableCopy]; out[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2]; return out;
            };
            tile.configuration = config;
        }
    }
    self.travelNotice = label(@"",14,UIFontWeightSemibold,UIColor.whiteColor);
    self.travelNotice.numberOfLines = 0;
    self.travelNotice.textAlignment = NSTextAlignmentCenter;
    self.travelNotice.backgroundColor = AQWCharcoal();
    self.travelNotice.layer.cornerRadius = 10;
    self.travelNotice.clipsToBounds = YES;
    self.travelNotice.userInteractionEnabled = NO;
    self.travelNotice.hidden = YES;
    [self addSubview:self.travelNotice];

    self.card = [UIView new];
    self.card.backgroundColor = AQWCharcoal();
    self.card.layer.cornerRadius = 18;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = AQWKeyline().CGColor;
    self.card.layer.shadowColor = UIColor.blackColor.CGColor;
    self.card.layer.shadowOpacity = .32;
    self.card.layer.shadowOffset = CGSizeMake(0, 4);
    self.card.layer.shadowRadius = 10;
    [self addSubview:self.card];
    UILabel *title = label(@"Skill automation", 20, UIFontWeightBold, UIColor.whiteColor);
    title.accessibilityTraits |= UIAccessibilityTraitHeader;
    UIStackView *header = stack(@[title], YES, 9);
    if (@available(iOS 13.0,*)) {
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"]];
        icon.contentMode = UIViewContentModeScaleAspectFit; icon.tintColor = AQWSilver();
        [icon.widthAnchor constraintEqualToConstant:22].active = YES;
        [icon.heightAnchor constraintEqualToConstant:22].active = YES;
        [header insertArrangedSubview:icon atIndex:0];
    }
    header.alignment = UIStackViewAlignmentCenter;
    self.dot = label(@"●", 12, UIFontWeightBold, AQWSecondary());
    self.dot.isAccessibilityElement = NO;
    [self.dot setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    self.stateLine = label(@"Ready", 14, UIFontWeightSemibold, AQWSecondary());
    self.stateLine.numberOfLines = 2;
    UIStackView *status = stack(@[self.dot,self.stateLine], YES, 7);
    UIButton *selected = button(@"Selected", @"Use the selected monster", self, @selector(targetTapped:));
    UIButton *room = button(@"Auto in room", @"Find a monster in this room", self, @selector(targetTapped:));
    room.tag = 1;
    self.targets = @[selected,room];
    UIStackView *targetRow = stack(self.targets, YES, 6);
    targetRow.distribution = UIStackViewDistributionFillEqually;

    self.chooseClass = button(@"Choose class", @"Choose bag class", self, @selector(classTapped:));
    self.chooseSet = button(@"Choose set", @"Choose saved skill set", self, @selector(setTapped:));
    for (UIButton *b in @[self.chooseClass,self.chooseSet]) {
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.contentEdgeInsets = UIEdgeInsetsMake(0,12,0,12);
        b.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    self.addSet = button(@"＋ Add", @"Add skill set", self, @selector(addTapped:));
    self.editSet = button(@"Edit", @"Edit skill set", self, @selector(editTapped:));
    self.deleteSet = button(@"Delete", @"Delete selected skill set", self, @selector(deleteTapped:));
    [self.deleteSet setTitleColor:AQWStopColor() forState:UIControlStateNormal];
    UIStackView *actions = stack(@[self.addSet,self.editSet,self.deleteSet], YES, 5);
    actions.distribution = UIStackViewDistributionFillEqually;
    self.setActions = actions;
    UIStackView *body = stack(@[label(@"Bag class",13,UIFontWeightSemibold,AQWSecondary()),self.chooseClass,
        label(@"Skill set",13,UIFontWeightSemibold,AQWSecondary()),self.chooseSet,actions,
        label(@"Target",13,UIFontWeightSemibold,AQWSecondary()),targetRow],NO,5);
    self.scroll = [UIScrollView new];
    self.scroll.showsHorizontalScrollIndicator = NO;
    self.scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self.scroll addSubview:body];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [body.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],
        [body.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor],
        [body.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor],
        [body.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor]
    ]];
    self.run = button(@"Start rotation", @"Start rotation", self, @selector(runTapped:));
    self.run.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    UIStackView *content = stack(@[header,status,self.scroll,self.run], NO, 8);
    [self.card addSubview:content];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:12],
        [content.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:14],
        [content.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-14],
        [content.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-12]
    ]];
    [self refresh];
    return self;
}

- (void)refresh {
    BOOL configurable = !self.running && !self.pending;
    self.card.hidden = !self.expanded;
    NSDictionary *profile = [self.sets selectedFor:self.classID];
    NSString *name = [self className:self.classID];
    BOOL canStart = name.length && profile && self.session;
    self.handle.accessibilityLabel = self.expanded ? @"Close skill automation" : @"Open skill automation";
    self.handle.accessibilityValue = self.running ? @"Running" : @"Stopped";
    self.handle.accessibilityTraits = UIAccessibilityTraitButton | (self.expanded ? UIAccessibilityTraitSelected : 0);
    self.handle.backgroundColor = self.expanded ? AQWPanel() : AQWCharcoal();
    [self.handle setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.handle.layer.borderColor = (self.running ? AQWSilver() : AQWSecondary()).CGColor;
    self.dot.text = self.running ? @"●" : @"○";
    self.dot.textColor = self.running ? AQWSilver() : AQWSecondary();
    for (UIButton *b in self.targets) {
        BOOL active = (b.tag == (NSInteger)self.autoTarget);
        b.enabled = configurable;
        b.backgroundColor = active ? AQWSilver() : AQWPanel();
        [b setTitleColor:active ? AQWCharcoal() : AQWSecondary() forState:UIControlStateNormal];
        b.accessibilityTraits = UIAccessibilityTraitButton | (active ? UIAccessibilityTraitSelected : 0);
    }
    [self.chooseClass setTitle:name.length ? [name stringByAppendingString:@"  ▾"] : @"No bag classes" forState:UIControlStateNormal];
    self.chooseClass.accessibilityValue = name;
    [self.chooseSet setTitle:profile ? [profile[@"name"] stringByAppendingString:@"  ▾"] : @"No saved sets" forState:UIControlStateNormal];
    self.chooseSet.accessibilityValue = profile[@"name"];
    self.chooseClass.enabled = configurable && self.classes.count > 0;
    self.chooseSet.enabled = configurable && profile;
    self.addSet.enabled = configurable && self.classes.count > 0;
    self.setActions.hidden = self.classes.count == 0 || self.running;
    self.editSet.enabled = self.deleteSet.enabled = configurable && profile;
    for (UIButton *b in @[self.chooseClass,self.chooseSet,self.addSet,self.editSet,self.deleteSet]) b.alpha = b.enabled ? 1 : .48;
    NSString *verb = self.running ? @"Stop" : [self.classID isEqual:self.equipped] || !name ? @"Start" : @"Equip & start";
    NSString *symbol = self.running ? @"■" : @"▶";
    NSString *buttonTitle = self.pending ? @"One moment…" : [NSString stringWithFormat:@"%@  %@",symbol,verb];
    [self.run setTitle:buttonTitle forState:UIControlStateNormal];
    self.run.accessibilityLabel = verb;
    {
        UIButton *control = self.run;
        control.backgroundColor = self.running ? AQWPanel() : AQWSilver();
        control.layer.borderColor = AQWSilver().CGColor;
        control.layer.borderWidth = self.running ? 1 : 0;
        [control setTitleColor:self.running ? AQWSilver() : AQWCharcoal() forState:UIControlStateNormal];
    }
    self.run.enabled = !self.pending && (self.running || canStart);
    self.run.alpha = self.run.enabled ? 1 : .48;
    [self setNeedsLayout];
}

- (void)attachBesideGame:(UIView *)game {
    UIView *container=game.superview;
    if (!container) return;
    if (self.superview != container) {
        [self removeFromSuperview];
        self.originalTransform=game.transform;
        self.gameSurface=game;
        self.frame=container.bounds;
        [container insertSubview:self aboveSubview:game];
    }
    [self setNeedsLayout];
    [self layoutIfNeeded];
}
- (void)removeFromSuperview {
    if (self.gameSurface) self.gameSurface.transform=self.originalTransform;
    self.gameSurface=nil;
    [super removeFromSuperview];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    if (CGRectIsEmpty(safe)) return;
    CGFloat width = CGRectGetWidth(safe), height = CGRectGetHeight(safe);
    BOOL regular = self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular && height >= 600;
    CGFloat gap = regular ? 8 : 4, tileWidth = regular ? 90 : 74, tileHeight = regular ? 64 : 50;
    CGFloat right = CGRectGetMaxX(safe) - 4, x = floor(right - tileWidth);
    CGFloat top = CGRectGetMinY(safe) + 6, y = top;
    CGFloat dockLeft = x-4;
    self.dock.frame = CGRectMake(dockLeft,0,CGRectGetMaxX(self.bounds)-dockLeft,CGRectGetHeight(self.bounds));
    for (UIButton *control in @[self.handle,self.mobsButton,self.bookmarkButton,self.cancelTravel]) {
        if (control.hidden) continue;
        control.frame = CGRectMake(x,y,tileWidth,tileHeight);
        y += tileHeight + gap;
    }
    CGFloat panelWidth = MIN(regular ? 340 : 284, width - tileWidth - 18);
    CGFloat panelHeight = MIN(400,height - 12);
    self.card.frame = CGRectMake(x - 6 - panelWidth,top,panelWidth,panelHeight);
    self.travelNotice.frame = CGRectMake(x,y,tileWidth,MAX(0,MIN(140,CGRectGetMaxY(safe)-y-4)));
    UIView *game = self.gameSurface;
    if (game && !CGRectIsEmpty(game.bounds)) {
        CGFloat end = self.expanded ? CGRectGetMinX(self.card.frame)-4 : dockLeft-2;
        CGRect available = CGRectMake(CGRectGetMinX(safe),CGRectGetMinY(safe),MAX(1,end-CGRectGetMinX(safe)),height);
        CGFloat oldScale = MIN(CGRectGetWidth(game.bounds)/960.,CGRectGetHeight(game.bounds)/550.);
        CGFloat factor = MIN(1.,MIN(available.size.width/960.,height/550.)/oldScale);
        CGPoint center = [self convertPoint:CGPointMake(CGRectGetMidX(available),CGRectGetMidY(available)) toView:game.superview];
        CGAffineTransform t=CGAffineTransformScale(self.originalTransform,factor,factor);
        t.tx += center.x-game.center.x; t.ty += center.y-game.center.y;
        game.transform=t;
    }

}

// Transparent pixels around the controls belong to the game.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
- (void)setExpanded:(BOOL)expanded {
    BOOL changed = _expanded != expanded;
    _expanded = expanded;
    [self refresh];
    if (expanded && changed) {
        self.command(@{@"action":@"bag"});
        self.requestedMapTool = nil;
        if (!UIAccessibilityIsReduceMotionEnabled()) {
            self.card.alpha = .25;
            [UIView animateWithDuration:.16 animations:^{ self.card.alpha = 1; }];
        }
    }
    if (changed && self.window)
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,expanded ? self.chooseClass : self.handle);
}
- (void)toggle:(id)sender { [self setExpanded:!self.expanded]; }
- (void)targetTapped:(UIButton *)sender {
    self.autoTarget = sender.tag == 1;
    [NSUserDefaults.standardUserDefaults setBool:self.autoTarget forKey:@"aqw.rotation.auto"];
    [self refresh];
}
- (NSString *)className:(NSString *)key {
    for (NSDictionary *entry in self.classes) if ([entry[@"id"] isEqual:key]) return entry[@"name"];
    return nil;
}
- (void)showBag:(NSDictionary *)bag {
    if (![bag[@"classes"] isKindOfClass:NSArray.class] || ![bag[@"session"] isKindOfClass:NSNumber.class]) return;
    BOOL changed = ![self.session isEqual:bag[@"session"]];
    BOOL listChanged = ![self.classes isEqual:bag[@"classes"]];
    self.session = bag[@"session"]; self.classes = bag[@"classes"]; self.equipped = bag[@"equipped"];
    for (NSDictionary *entry in self.classes) {
        NSArray *names = entry[@"skills"];
        if (names.count != 4) continue;
        NSString *key = [@"aqw.skills.names." stringByAppendingString:entry[@"id"]];
        if (![names isEqual:[self.preferences arrayForKey:key]])
            [self.preferences setObject:names forKey:key];
    }
    BOOL lost = ![self className:self.classID];
    if (changed || (!self.mapList && (lost || (listChanged && self.pickingClass)))) {
        if (self.modal.presentingViewController) [self.modal dismissViewControllerAnimated:NO completion:nil];
        self.modal = nil; self.mapList = nil; self.pickingClass = NO;
        if (changed) self.requestedMapTool = nil;
    }
    if (changed || lost) {
        self.classID = [self className:self.equipped] ? self.equipped : self.classes.firstObject[@"id"];
        self.pending = NO;
        self.stateLine.text = self.classes.count ? @"Choose a set or add one" : @"Enter a map to see your classes";
    }
    if ([self className:self.equipped]) [self.sets migrateLegacyForEquipped:self.equipped];
    [self refresh];
}
- (void)presentTool:(UIViewController *)vc {
    UIViewController *host = self.window.rootViewController;
    if (!host || host.presentedViewController) return;
    self.modal = vc;
    [host presentViewController:vc animated:YES completion:nil];
}
- (void)pickClassThen:(void (^)(void))next {
    if (self.running || self.pending || !self.classes.count) return;
    NSNumber *session = self.session;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *entry in self.classes) {
        NSMutableDictionary *r = [entry mutableCopy];
        if ([r[@"id"] isEqual:self.equipped]) r[@"detail"] = @"Equipped";
        [rows addObject:r];
    }
    self.pickingClass = YES;
    AQWChoiceList *list = [[AQWChoiceList alloc] initWithTitle:@"Choose bag class" rows:rows selected:self.classID searchable:YES choose:^(NSString *key){
        if (![self.session isEqual:session] || ![self className:key]) return;
        self.pickingClass = NO; self.classID = key; self.stateLine.text = @"Ready"; [self refresh]; if (next) next();
    }];
    [self presentTool:AQWSkillNavigation(list)];
}
- (void)classTapped:(id)sender { [self pickClassThen:nil]; }
- (void)setTapped:(id)sender {
    NSString *key = self.classID; NSNumber *session = self.session;
    NSArray *sets = [self.sets setsFor:key];
    if (!sets.count) return;
    self.pickingClass = NO;
    AQWChoiceList *list = [[AQWChoiceList alloc] initWithTitle:@"Choose skill set" rows:sets selected:[self.sets selectedFor:key][@"id"] searchable:NO choose:^(NSString *setID){
        if (![self.session isEqual:session] || ![self.classID isEqual:key]) return;
        [self.sets select:setID forClass:key]; [self refresh];
    }];
    [self presentTool:AQWSkillNavigation(list)];
}
- (NSArray *)selectedAbilityNames {
    for (NSDictionary *entry in self.classes)
        if ([entry[@"id"] isEqual:self.classID]) {
            NSArray *live = entry[@"skills"];
            NSString *key = [@"aqw.skills.names." stringByAppendingString:self.classID];
            return live.count == 4 ? live : [self.preferences arrayForKey:key];
        }
    return nil;
}
- (void)openEditor:(NSDictionary *)profile {
    NSString *key = self.classID, *name = [self className:key]; NSNumber *session = self.session;
    if (!name || self.running || self.pending) return;
    self.pickingClass = NO;
    AQWSkillEditor *editor = [[AQWSkillEditor alloc] initForClass:name profile:profile saved:^(NSDictionary *value){
        if (![self.session isEqual:session] || ![self className:key]) return;
        [self.sets save:value forClass:key]; self.stateLine.text = @"Set saved on this device"; [self refresh];
    }];
    editor.abilityNames = [self selectedAbilityNames];
    [self presentTool:AQWSkillNavigation(editor)];
}
- (void)addTapped:(id)sender { [self pickClassThen:^{ [self openEditor:nil]; }]; }
- (void)editTapped:(id)sender { [self openEditor:[self.sets selectedFor:self.classID]]; }
- (void)deleteTapped:(id)sender {
    NSString *key = self.classID, *name = [self className:key]; NSNumber *session = self.session;
    NSDictionary *profile = [self.sets selectedFor:key];
    if (!profile || !name) return;
    NSString *msg = [NSString stringWithFormat:@"Remove “%@” for %@ from this device?",profile[@"name"],name];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Delete skill set?" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        if (![self.session isEqual:session] || ![self className:key]) return;
        [self.sets remove:profile[@"id"] forClass:key]; self.stateLine.text = @"Set deleted"; [self refresh];
    }]];
    self.pickingClass = NO; [self presentTool:a];
}
- (void)removeBookmark:(NSDictionary *)entry {
    NSString *key = @"aqw.map.bookmarks";
    NSMutableArray *saved = [[self.preferences arrayForKey:key] mutableCopy];
    [saved removeObject:entry];
    if (saved) [self.preferences setObject:saved forKey:key];
    [self showNotice:@"Bookmark deleted"];
}
- (void)requestMapTool:(NSString *)mode {
    [self setExpanded:NO];
    self.requestedMapTool = mode;
    self.pickingClass = NO;
    self.command(@{@"action":@"map"});
    self.command(@{@"action":mode,@"session":self.session ?: @0});
}
- (void)mobsTapped:(id)sender { [self requestMapTool:@"mobs"]; }
- (void)marksTapped:(id)sender { [self requestMapTool:@"marks"]; }
- (void)cancelTapped:(id)sender { self.command(@{@"action":@"cancelTravel"}); }
- (void)showTravel:(NSString *)text active:(BOOL)active {
    self.cancelTravel.hidden = !active;
    [self showNotice:text];
}
- (void)hideNotice { self.travelNotice.hidden = YES; }
- (void)showNotice:(NSString *)text {
    self.travelNotice.text = text; self.travelNotice.hidden = !text.length;
    [self bringSubviewToFront:self.travelNotice];
    [self setNeedsLayout];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideNotice) object:nil];
    if (self.cancelTravel.hidden) [self performSelector:@selector(hideNotice) withObject:nil afterDelay:5];
    if (text.length && self.window) UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,text);
}
- (void)showDestinations:(NSDictionary *)panel {
    NSNumber *session = panel[@"session"];
    if (![session isEqual:self.session]) return;
    NSDictionary *here = panel[@"location"];
    BOOL mobs = [panel[@"mode"] isEqual:@"mobs"];
    NSUserDefaults *prefs = self.preferences;
    NSString *key = @"aqw.map.bookmarks";
    NSArray *entries = mobs ? panel[@"rows"] : [prefs arrayForKey:key] ?: @[];
    BOOL marked = NO;
    for (NSDictionary *entry in entries) {
        if ([entry[@"area"] isEqual:here[@"area"]] && [entry[@"cell"] isEqual:here[@"cell"]] &&
            [entry[@"pad"] isEqual:here[@"pad"]]) { marked = YES; break; }
    }
    if ([panel[@"mode"] isEqual:@"saveMark"]) {
        if (!marked) [prefs setObject:[entries arrayByAddingObject:here] forKey:key];
        [self showNotice:marked ? @"Location already marked" : @"Location marked on this device"]; return;
    }
    if (![self.requestedMapTool isEqual:panel[@"mode"]]) return;
    NSMutableArray *rows = [NSMutableArray array];
    if (!mobs && !marked)
        [rows addObject:@{@"id":@"save",@"name":@"＋ Mark current location",
            @"detail":[NSString stringWithFormat:@"%@ · %@, %@",here[@"area"],here[@"cell"],here[@"pad"]]}];
    [entries enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger index, BOOL *stop) {
        NSString *detail = mobs ? [NSString stringWithFormat:@"%@ · #%@",entry[@"cell"],entry[@"id"]] :
            [NSString stringWithFormat:@"%@, %@",entry[@"cell"],entry[@"pad"]];
        [rows addObject:mobs ? @{@"id":entry[@"id"],@"name":entry[@"name"],@"detail":detail} :
            @{@"id":@(index).stringValue,@"name":entry[@"area"],@"detail":detail,@"removable":entry}];
    }];
    NSString *contextText = [NSString stringWithFormat:@"%@ · %@, %@",here[@"area"],here[@"cell"],here[@"pad"]];
    if (mobs) contextText = [contextText stringByAppendingFormat:@"   ·   %lu %@",(unsigned long)rows.count,
        rows.count == 1 ? @"spawn" : @"spawns"];
    void (^choose)(NSString *) = ^(NSString *choice) {
        if (![session isEqual:self.session]) return;
        if ([choice isEqual:@"save"]) {
            self.command(@{@"action":@"saveMark",@"session":session}); return;
        }
        if (mobs) {
            for (NSDictionary *spawn in entries) if ([spawn[@"id"] isEqual:choice]) {
                self.command(@{@"action":@"travel",@"session":session,
                    @"dest":@{@"area":here[@"area"],@"cell":spawn[@"cell"]},@"mob":choice});
                break;
            }
            return;
        }
        NSDictionary *entry = entries[choice.integerValue];
        self.command(@{@"action":@"travel",@"session":session,@"dest":entry});
    };
    AQWChoiceList *list = self.mapList;
    BOOL visible = list && list.view.window;
    if (!visible) list = [[AQWChoiceList alloc] initWithTitle:mobs ? @"Mobs" : @"Bookmark"
        rows:rows selected:nil searchable:mobs choose:choose];
    __weak AQWBotDrawer *drawer = self;
    if (!mobs) list.removeItem = ^(NSDictionary *entry) {
        if (![session isEqual:drawer.session]) return;
        [drawer removeBookmark:entry];
        [drawer showDestinations:panel];
    };
    list.refreshList = ^{ [drawer requestMapTool:mobs ? @"mobs" : @"marks"]; };
    [list updateRows:rows context:contextText choose:choose];
    if (!visible) { self.mapList = list; [self presentTool:AQWSkillNavigation(list)]; }
}
- (void)runTapped:(id)sender {
    if (self.pending) return;
    NSDictionary *profile = [self.sets selectedFor:self.classID];
    if (!self.running && (!profile || ![self className:self.classID] || !self.session)) return;
    self.pending = YES; [self refresh];
    self.command(self.running ? @{@"action":@"stop"} :
        @{@"action":@"start", @"session":self.session, @"classId":self.classID, @"auto":@(self.autoTarget), @"steps":profile[@"steps"]});
}
- (void)showMap:(NSString *)map {
    self.mobsButton.accessibilityValue = self.bookmarkButton.accessibilityValue = map;
}
- (void)showState:(NSString *)detail running:(BOOL)running {
    self.running = running; self.pending = NO;
    self.stateLine.text = detail;
    [self refresh];
}

static UIView *ruleField(UITableViewController *editor, NSString *key) {
    UITableView *table=editor.tableView;
    for (NSInteger section=0; section<2; section++) {
        for (NSInteger i=0; i<[editor tableView:table numberOfRowsInSection:section]; i++) {
            UITableViewCell *row=[editor tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:section]];
            if ([row.accessoryView.accessibilityIdentifier isEqual:key]) return row.accessoryView;
            for (UIView *item in row.contentView.subviews)
                if ([item.accessibilityIdentifier isEqual:key]) return item;
        }
    }
    return nil;
}
static BOOL selectRuleSegment(UITableViewController *editor, NSString *key, NSString *title) {
    UIStackView *options=(UIStackView *)ruleField(editor,key);
    for (UIButton *option in options.arrangedSubviews) if ([[option titleForState:UIControlStateNormal] isEqual:title]) {
        [option sendActionsForControlEvents:UIControlEventTouchUpInside];
        UIStackView *updated=(UIStackView *)ruleField(editor,key);
        for (UIButton *selected in updated.arrangedSubviews) if (selected.accessibilityTraits & UIAccessibilityTraitSelected)
            return [[selected titleForState:UIControlStateNormal] isEqual:title] && [selected.backgroundColor isEqual:AQWSilver()]
                && [[selected titleColorForState:UIControlStateNormal] isEqual:AQWCharcoal()];
        return NO;
    }
    return NO;
}
static void typeRuleField(UITableViewController *editor, NSString *key, NSString *text) {
    UITextField *entry=(UITextField *)ruleField(editor,key);
    entry.text=text; [entry sendActionsForControlEvents:UIControlEventEditingChanged];
}
static void finishPage(UIViewController *page) {
    UIBarButtonItem *item=page.navigationItem.rightBarButtonItem;
    [UIApplication.sharedApplication sendAction:item.action to:item.target from:item forEvent:nil];
}
static void captureView(UIView *view, NSString *filename) {
    [view layoutIfNeeded];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
    UIImage *preview=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [view.layer renderInContext:context.CGContext];
    }];
    NSURL *documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    [UIImagePNGRepresentation(preview) writeToURL:[documents URLByAppendingPathComponent:filename] atomically:YES];
}
static void captureTable(UITableViewController *page, NSString *filename) {
    page.view.frame=CGRectMake(0,0,510,430);
    [page.tableView reloadData];
    captureView(page.view,filename);
}
static NSIndexPath *skillRow(NSInteger index) {
    return [NSIndexPath indexPathForRow:index inSection:1];
}
static UISwitch *stepSwitch(UITableViewController *page, NSInteger section, NSInteger row) {
    NSIndexPath *path=[NSIndexPath indexPathForRow:row inSection:section];
    UIView *control=[page tableView:page.tableView cellForRowAtIndexPath:path].accessoryView;
    return [control isKindOfClass:UISwitch.class] ? (UISwitch *)control : nil;
}
static BOOL performSwipeDelete(UIContextualAction *action, UITableView *table) {
    if (!action) return NO;
    __block BOOL removed=NO;
    action.handler(action,table,^(BOOL done){ removed=done; });
    return removed;
}
static BOOL checkStepEditing(void) {
    __block NSDictionary *saved;
    AQWSkillEditor *editor=[[AQWSkillEditor alloc] initForClass:@"Healer" profile:nil saved:^(NSDictionary *value){ saved=value; }];
    UINavigationController *nav=AQWSkillNavigation(editor);
    UITableView *table=editor.tableView;
    if ([editor tableView:table numberOfRowsInSection:1]!=5) return NO;
    [editor tableView:table didSelectRowAtIndexPath:skillRow(4)]; // Add a second occurrence of slot 2.
    AQWChoiceList *slots=(AQWChoiceList *)nav.topViewController;
    [slots tableView:slots.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    if (nav.topViewController!=editor || [editor tableView:table numberOfRowsInSection:1]!=6) return NO;
    [editor tableView:table didSelectRowAtIndexPath:skillRow(4)];
    UITableViewController *step=(UITableViewController *)nav.topViewController;
    UISwitch *cooldown=stepSwitch(step,0,1), *conditions=stepSwitch(step,1,0);
    if (!cooldown || !conditions || cooldown.on || conditions.on) return NO;
    captureTable(step,@"aqw-skill-options.png");
    cooldown=stepSwitch(step,0,1); conditions=stepSwitch(step,1,0);
    for (UISwitch *control in @[cooldown,conditions]) {
        control.on=YES; [control sendActionsForControlEvents:UIControlEventValueChanged];
    }
    finishPage(step);
    if (nav.topViewController!=editor || saved) return NO;
    if ([editor tableView:table trailingSwipeActionsConfigurationForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]] ||
        [editor tableView:table trailingSwipeActionsConfigurationForRowAtIndexPath:skillRow(5)]) return NO;
    UISwipeActionsConfiguration *swipe=[editor tableView:table trailingSwipeActionsConfigurationForRowAtIndexPath:skillRow(0)];
    UIContextualAction *remove=swipe.actions.firstObject;
    if (!remove || remove.style!=UIContextualActionStyleDestructive || ![remove.title isEqual:@"Delete"] ||
        swipe.performsFirstActionWithFullSwipe || [editor tableView:table numberOfRowsInSection:1]!=6) return NO;
    if (!performSwipeDelete(remove,table) || performSwipeDelete(remove,table) || saved) return NO;
    finishPage(editor);
    NSArray *steps=saved[@"steps"];
    if (![[steps valueForKey:@"slot"] isEqual:@[@3,@4,@5,@2]] ||
        ![[steps valueForKey:@"wait"] isEqual:@[@NO,@NO,@NO,@YES]] ||
        ![[steps valueForKey:@"rulesEnabled"] isEqual:@[@NO,@NO,@NO,@YES]]) return NO;
    for (NSUInteger i=0; i<steps.count; i++) {
        swipe=[editor tableView:table trailingSwipeActionsConfigurationForRowAtIndexPath:skillRow(0)];
        if (!performSwipeDelete(swipe.actions.firstObject,table)) return NO;
    }
    if (editor.navigationItem.rightBarButtonItem.enabled || [editor tableView:table numberOfRowsInSection:1]!=1) return NO;
    [editor tableView:table didSelectRowAtIndexPath:skillRow(0)];
    slots=(AQWChoiceList *)nav.topViewController;
    [slots tableView:slots.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    if (!editor.navigationItem.rightBarButtonItem.enabled) return NO;
    finishPage(editor);
    return [saved[@"steps"] isEqual:@[AQWStep(@3)]];
}

+ (BOOL)checkControls {
    NSString *suite = [@"aqw.profileTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    BOOL animated=UIView.areAnimationsEnabled;
    [UIView setAnimationsEnabled:NO];
    @try { return [self checkControlsWithDefaults:defaults]; }
    @finally { [UIView setAnimationsEnabled:animated]; [defaults removePersistentDomainForName:suite]; }
}
+ (BOOL)checkControlsWithDefaults:(NSUserDefaults *)defaults {
    if (!checkStepEditing()) return NO;
    AQWSkillSets *sets = [[AQWSkillSets alloc] initWithDefaults:defaults];
    [defaults setObject:@[@2,@4,@2] forKey:@"aqw.rotation.slots"];
    [sets migrateLegacyForEquipped:@"10"]; [sets migrateLegacyForEquipped:@"20"];
    NSArray *steps = [sets selectedFor:@"10"][@"steps"];
    if (![[steps valueForKey:@"slot"] isEqual:@[@2,@4,@2]] || ![[steps valueForKey:@"wait"] isEqual:@[@YES,@YES,@YES]] ||
        [sets setsFor:@"20"].count) return NO;
    NSDictionary *other = @{@"id":@"second",@"name":@"Boss",@"steps":@[AQWStep(@5)]};
    [sets save:other forClass:@"10"]; [sets select:@"legacy" forClass:@"10"];
    if (![[sets selectedFor:@"10"][@"id"] isEqual:@"legacy"] || [sets setsFor:@"10"].count!=2) return NO;
    [sets remove:@"second" forClass:@"10"];
    if ([sets setsFor:@"10"].count!=1) return NO;
    __block NSDictionary *saved;
    AQWSkillEditor *editor = [[AQWSkillEditor alloc] initForClass:@"Healer" profile:[sets selectedFor:@"10"]
                                                           saved:^(NSDictionary *value){ saved = value; }];
    UINavigationController *nav = AQWSkillNavigation(editor); [editor loadViewIfNeeded];
    if ([editor tableView:editor.tableView numberOfRowsInSection:1]!=4) return NO;
    [editor tableView:editor.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    UITableViewController *step = (UITableViewController *)nav.topViewController;
    [step loadViewIfNeeded];
    if ([step isEqual:editor] || [step numberOfSectionsInTableView:step.tableView]!=3) return NO;
    UISwitch *rules=stepSwitch(step,1,0);
    if (rules.on || !stepSwitch(step,0,1).on) return NO;
    rules.on=YES; [rules sendActionsForControlEvents:UIControlEventValueChanged];
    [step tableView:step.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:1]];
    UITableViewController *rule=(UITableViewController *)nav.topViewController;
    [rule loadViewIfNeeded];
    if ([rule isEqual:step] || ![rule.title isEqual:@"Condition"]) return NO;
    if (!selectRuleSegment(rule,@"kind",@"Mana") || !selectRuleSegment(rule,@"unit",@"#") ||
        !selectRuleSegment(rule,@"op",@"≥")) return NO;
    typeRuleField(rule,@"value",@"12500");
    captureTable(rule,@"aqw-condition-editor.png"); finishPage(rule);
    if (nav.topViewController!=step) return NO;
    [step tableView:step.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:1]];
    rule=(UITableViewController *)nav.topViewController; [rule loadViewIfNeeded];
    if (!selectRuleSegment(rule,@"kind",@"Party HP") || ruleField(rule,@"who")) return NO;
    typeRuleField(rule,@"value",@"35"); finishPage(rule);
    [step tableView:step.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:4 inSection:1]];
    rule=(UITableViewController *)nav.topViewController; [rule loadViewIfNeeded];
    if (!selectRuleSegment(rule,@"kind",@"Aura") || !selectRuleSegment(rule,@"who",@"Target") ||
        !selectRuleSegment(rule,@"op",@"≤")) return NO;
    typeRuleField(rule,@"name",@"  Battle Focus  "); typeRuleField(rule,@"value",@"2"); finishPage(rule);
    finishPage(step); finishPage(editor);
    NSArray *expected=@[
        @{@"kind":@"mp",@"who":@"self",@"op":@"gte",@"unit":@"raw",@"value":@12500},
        @{@"kind":@"partyhp",@"who":@"party",@"op":@"lte",@"unit":@"percent",@"value":@35},
        @{@"kind":@"aura",@"who":@"target",@"op":@"lte",@"name":@"Battle Focus",@"value":@2}];
    if (![[saved[@"steps"] firstObject][@"rules"] isEqual:expected] || ![[saved[@"steps"] firstObject][@"rulesEnabled"] boolValue] ||
        ![[saved[@"steps"] valueForKey:@"slot"] isEqual:[steps valueForKey:@"slot"]]) return NO;
    [sets save:saved forClass:@"10"];
    steps=[[[AQWSkillSets alloc] initWithDefaults:defaults] selectedFor:@"10"][@"steps"];
    if (![[steps firstObject][@"rules"] isEqual:expected]) return NO;
    NSDictionary *a = @{@"id":@"10",@"name":@"Healer"}, *b = @{@"id":@"20",@"name":@"Mage"};
    for (NSValue *size in @[[NSValue valueWithCGSize:CGSizeMake(852,393)],
                            [NSValue valueWithCGSize:CGSizeMake(568,320)],
                            [NSValue valueWithCGSize:CGSizeMake(1024,768)]]) {
        __block NSDictionary *last;
        AQWMapControlFixture *view = [[AQWMapControlFixture alloc] initWithFrame:(CGRect){CGPointZero,size.CGSizeValue}
            command:^(NSDictionary *request){ last=request; }];
        if (size.CGSizeValue.width == 852) view.testInsets = UIEdgeInsetsMake(0,47,21,47);
        UIView *container=[[UIView alloc] initWithFrame:view.bounds];
        UIView *surface=[[UIView alloc] initWithFrame:view.bounds];
        [container addSubview:surface];
        [view attachBesideGame:surface];
        CGRect bounds=surface.bounds;
        CGFloat fit=MIN(bounds.size.width/960.,bounds.size.height/550.);
        CGRect canvas=CGRectMake((bounds.size.width-960.*fit)/2,(bounds.size.height-550.*fit)/2,960.*fit,550.*fit);
        CGRect visible=[surface convertRect:canvas toView:view];
        if (CGRectIntersectsRect(visible,view.dock.frame) || !CGRectContainsRect(view.bounds,visible)) return NO;
        view.sets = [[AQWSkillSets alloc] initWithDefaults:defaults];
        view.preferences = defaults;
        [view showBag:@{@"session":@1,@"classes":@[a],@"equipped":@"10"}];
        if (![view.classID isEqual:@"10"] || !view.run.enabled) return NO;
        [view showBag:@{@"session":@2,@"classes":@[b],@"equipped":@"20"}];
        if ([view className:@"10"] || ![view.classID isEqual:@"20"] || view.run.enabled) return NO;
        [view showBag:@{@"session":@3,@"classes":@[b,a],@"equipped":@"10"}];
        if (![AQWAbilityLabel(@[@"Blue Impact"],2) isEqual:@"1: Blue Impact"] ||
            ![AQWAbilityLabel(nil,5) hasPrefix:@"4:"] || ![AQWAbilityLabel(nil,0) length]) return NO;
        NSDictionary *mark = @{@"area":@"fixture-1234",@"cell":@"r1",@"pad":@"left"};
        NSDictionary *secondMark = @{@"area":@"fixture-5678",@"cell":@"r1",@"pad":@"left"};
        for (NSDictionary *location in @[mark, mark, secondMark]) {
            [view showDestinations:@{@"session":@3,@"mode":@"saveMark",@"location":location}];
        }
        if (![[defaults arrayForKey:@"aqw.map.bookmarks"] isEqual:@[mark,secondMark]]) return NO;
        [view removeBookmark:mark]; [view removeBookmark:secondMark];
        if ([defaults arrayForKey:@"aqw.map.bookmarks"].count) return NO;
        [view layoutIfNeeded];
        CGRect safe = UIEdgeInsetsInsetRect(view.bounds,view.safeAreaInsets);
        for (UIButton *item in @[view.handle,view.mobsButton,view.bookmarkButton]) {
            CGRect f=item.frame;
            if (item.superview != view || item.hidden || CGRectGetWidth(f)<44 || CGRectGetHeight(f)<44 ||
                !CGRectContainsRect(safe,f) || [view hitTest:CGPointMake(CGRectGetMidX(f),CGRectGetMidY(f)) withEvent:nil]!=item) return NO;
        }
        [view.mobsButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        if (view.expanded || ![last[@"action"] isEqual:@"mobs"]) return NO;
        NSArray *mobs=@[@{@"id":@"31",@"name":@"Wolf",@"cell":@"Enter"},@{@"id":@"42",@"name":@"Wolf",@"cell":@"r7"}];
        [view showDestinations:@{@"mode":@"mobs",@"session":@3,@"location":mark,@"rows":mobs}];
        AQWChoiceList *list=view.captured;
        if (![list.title isEqual:@"Mobs"] || [list tableView:list.tableView numberOfRowsInSection:0]!=2) return NO;
        UISearchBar *search=(UISearchBar *)list.tableView.tableHeaderView;
        [search.delegate searchBar:search textDidChange:@"r7"];
        if ([list tableView:list.tableView numberOfRowsInSection:0]!=1) return NO;
        [list tableView:list.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        if (![last[@"action"] isEqual:@"travel"] || ![last[@"mob"] isEqual:@"42"] ||
            ![last[@"dest"] isEqual:@{@"area":mark[@"area"],@"cell":@"r7"}] || ![last[@"session"] isEqual:@3]) return NO;
        [view showDestinations:@{@"mode":@"mobs",@"session":@3,@"location":mark,@"rows":@[]}];
        list=view.captured;
        if (![[list tableView:list.tableView titleForFooterInSection:0] containsString:@"No monsters"]) return NO;
        [view.bookmarkButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        if (view.expanded || ![last[@"action"] isEqual:@"marks"]) return NO;
        [view showDestinations:@{@"mode":@"marks",@"session":@3,@"location":mark}];
        list=view.captured;
        if (![list.title isEqual:@"Bookmark"]) return NO;
        [list tableView:list.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        if (![last[@"action"] isEqual:@"saveMark"]) return NO;
        [view showDestinations:@{@"mode":@"saveMark",@"session":@3,@"location":secondMark}];
        [view showDestinations:@{@"mode":@"marks",@"session":@3,@"location":mark}];
        list = view.captured;
        NSIndexPath *savedLocation = [NSIndexPath indexPathForRow:1 inSection:0];
        UISwipeActionsConfiguration *removeMark = [list tableView:list.tableView trailingSwipeActionsConfigurationForRowAtIndexPath:savedLocation];
        if (!removeMark.actions.count || removeMark.performsFirstActionWithFullSwipe ||
            [list tableView:list.tableView canEditRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]]) return NO;
        [list tableView:list.tableView didSelectRowAtIndexPath:savedLocation];
        if (![last[@"action"] isEqual:@"travel"] || ![last[@"dest"] isEqual:secondMark]) return NO;
        UIContextualAction *deleteMark = removeMark.actions.firstObject;
        deleteMark.handler(deleteMark,list.tableView,^(BOOL done){});
        if ([defaults arrayForKey:@"aqw.map.bookmarks"].count) return NO;
        view.captured=nil;
        [view showTravel:@"Joining fixture-1234" active:YES];
        [view layoutIfNeeded];
        if (view.cancelTravel.hidden || view.cancelTravel.superview!=view || view.travelNotice.hidden ||
            !CGRectContainsRect(safe,view.cancelTravel.frame)) return NO;
        [view.cancelTravel sendActionsForControlEvents:UIControlEventTouchUpInside];
        if (![last[@"action"] isEqual:@"cancelTravel"]) return NO;
        [view showTravel:@"Travel stopped" active:NO];
        if (!view.cancelTravel.hidden) return NO;
        [view setExpanded:NO]; [view layoutIfNeeded];
        if (CGRectGetMidX(view.handle.frame) <= CGRectGetMidX(view.bounds)) return NO;
        if (size.CGSizeValue.width==852 || size.CGSizeValue.width==1024)
            captureView(view,size.CGSizeValue.width==852 ? @"aqw-rail-phone.png" : @"aqw-rail-tablet.png");
        if ([view hitTest:CGPointMake(CGRectGetMidX(view.bounds),CGRectGetMidY(view.bounds)) withEvent:nil]) return NO;
        [view.handle sendActionsForControlEvents:UIControlEventTouchUpInside]; [view layoutIfNeeded];
        if (!view.expanded || ![last[@"action"] isEqual:@"bag"] || !CGRectContainsRect(safe,view.card.frame) ||
            CGRectIntersectsRect(view.card.frame,view.handle.frame) || CGRectGetHeight(view.run.frame)<44) return NO;
        [view.run sendActionsForControlEvents:UIControlEventTouchUpInside];
        if (![last[@"action"] isEqual:@"start"] || ![last[@"classId"] isEqual:@"10"] ||
            ![last[@"steps"] isEqual:steps] || ![last[@"session"] isEqual:@3]) return NO;
        [view showState:@"Running" running:YES];
        for (UIButton *control in @[view.run])
            if (![control.backgroundColor isEqual:AQWPanel()] || ![[control titleColorForState:UIControlStateNormal] isEqual:AQWSilver()] ||
                ![control.accessibilityLabel isEqual:@"Stop"]) return NO;
        if (![view.dot.text isEqual:@"●"] || ![view.run isDescendantOfView:view.card]) return NO;
        if (size.CGSizeValue.width==1024) { [view layoutIfNeeded]; captureView(view.card,@"aqw-running-controls.png"); }
        [view setExpanded:NO];
        if (!view.card.hidden) return NO;
        [view setExpanded:YES];
        [view.run sendActionsForControlEvents:UIControlEventTouchUpInside];
        if (![last[@"action"] isEqual:@"stop"]) return NO;
        [view showState:@"Stopped" running:NO];
        [view showBag:@{@"session":@4,@"classes":@[],@"equipped":@""}];
        if (view.run.enabled || view.chooseClass.enabled) return NO;
        [view removeFromSuperview];
        if (!CGAffineTransformIsIdentity(surface.transform)) return NO;
    }
    [sets remove:@"legacy" forClass:@"10"]; [sets migrateLegacyForEquipped:@"10"];
    return [sets setsFor:@"10"].count==0;
}
@end
