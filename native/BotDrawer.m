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
@property(nonatomic,strong) NSArray<NSDictionary *> *classes;
@property(nonatomic,copy) NSString *classID, *equipped;
@property(nonatomic,strong) NSNumber *session;
@property(nonatomic,weak) UIViewController *modal;
@property(nonatomic,strong) UIButton *handle, *quickRun, *run, *map, *chooseClass, *chooseSet, *addSet, *editSet, *deleteSet;
@property(nonatomic,strong) UILabel *stateLine, *order, *dot;
@property(nonatomic,strong) NSArray<UIButton *> *targets;
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UIScrollView *scroll;
@end

@implementation AQWBotDrawer
- (instancetype)initWithFrame:(CGRect)frame command:(AQWBotCommand)command {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.command = command;
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    self.autoTarget = [prefs boolForKey:@"aqw.rotation.auto"];
    self.sets = [[AQWSkillSets alloc] initWithDefaults:prefs];
    self.classes = @[];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = UIColor.clearColor;
    self.handle = button(@"Skills", @"Open skill automation", self, @selector(toggle:));
    self.handle.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.handle.backgroundColor = AQWCharcoal();
    self.handle.layer.borderWidth = 1;
    self.handle.layer.borderColor = AQWSilver().CGColor;
    self.handle.layer.cornerRadius = 12;
    [self.handle setTitleColor:AQWSilver() forState:UIControlStateNormal];
    self.quickRun = button(@"▶", @"Start skill set", self, @selector(runTapped:));
    self.quickRun.backgroundColor = AQWStopColor();
    [self.quickRun setTitleColor:AQWCharcoal() forState:UIControlStateNormal];
    [self addSubview:self.handle];
    [self addSubview:self.quickRun];

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
    self.map = button(@"Read current map  ↻", @"Read current map", self, @selector(mapTapped:));
    self.map.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.map.contentEdgeInsets = UIEdgeInsetsMake(0,12,0,12);
    self.map.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.map setTitleColor:AQWSecondary() forState:UIControlStateNormal];
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
    self.order = label(@"",14,UIFontWeightMedium,AQWSilver()); self.order.numberOfLines = 2;
    UIStackView *body = stack(@[label(@"Bag class",13,UIFontWeightSemibold,AQWSecondary()),self.chooseClass,
        label(@"Skill set",13,UIFontWeightSemibold,AQWSecondary()),self.chooseSet,self.order,actions,
        label(@"Target",13,UIFontWeightSemibold,AQWSecondary()),targetRow,self.map],NO,5);
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
    [self.run setTitleColor:AQWCharcoal() forState:UIControlStateNormal];
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
    self.quickRun.hidden = self.expanded || (!self.running && !canStart);
    self.quickRun.enabled = !self.pending;
    self.handle.accessibilityLabel = self.expanded ? @"Close skill automation" : @"Open skill automation";
    self.handle.accessibilityValue = self.running ? @"Running" : @"Stopped";
    [self.handle setTitle:self.expanded ? @"Close" : @"Skills" forState:UIControlStateNormal];
    self.handle.layer.borderColor = (self.running ? AQWStopColor() : AQWSecondary()).CGColor;
    [self.handle setTitleColor:self.running ? AQWStopColor() : AQWSilver() forState:UIControlStateNormal];
    self.dot.textColor = self.running ? [UIColor colorWithRed:.58 green:.83 blue:.69 alpha:1] : AQWSecondary();
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
    self.editSet.enabled = self.deleteSet.enabled = configurable && profile;
    for (UIButton *b in @[self.chooseClass,self.chooseSet,self.addSet,self.editSet,self.deleteSet]) b.alpha = b.enabled ? 1 : .48;
    self.order.hidden = !profile;
    self.order.text = [[profile[@"steps"] valueForKey:@"slot"] componentsJoinedByString:@"  ›  "];
    NSString *verb = self.running ? @"Stop" : [self.classID isEqual:self.equipped] || !name ? @"Start" : @"Equip & start";
    [self.run setTitle:self.pending ? @"One moment…" : verb forState:UIControlStateNormal];
    self.run.accessibilityLabel = verb;
    self.run.backgroundColor = self.quickRun.backgroundColor = self.running ? AQWStopColor() : AQWSilver();
    self.quickRun.accessibilityLabel = verb;
    [self.quickRun setTitle:self.running ? @"■" : @"▶" forState:UIControlStateNormal];
    self.run.enabled = !self.pending && (self.running || canStart);
    self.run.alpha = self.run.enabled ? 1 : .48;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    if (CGRectIsEmpty(safe)) return;
    CGFloat w = CGRectGetWidth(self.bounds), h = CGRectGetHeight(self.bounds);
    CGFloat scale = MIN(w/960., h/550.);
    CGFloat sideGutter = (w - 960.*scale)/2., topGutter = (h - 550.*scale)/2.;
    CGFloat x = CGRectGetMaxX(safe)-56;
    CGFloat y = CGRectGetMinY(safe)+8;
    if (sideGutter >= 64) {
        // The upper corner is clear of the centered landscape camera cutout.
        // Use the actual artwork gutter so the collapsed tab stays off the game.
        CGFloat offset = (sideGutter-52)/2.;
        x = w-offset-52;
        y = MAX(y,MIN(24., h*.08));
    } else if (topGutter > CGRectGetMinY(safe)+52)
        y = CGRectGetMinY(safe) + (topGutter-CGRectGetMinY(safe)-44)/2.;
    self.handle.frame = CGRectIntegral(CGRectMake(x,y,52,44));
    self.quickRun.frame = CGRectIntegral(CGRectMake(x,y+48,52,44));
    CGFloat panelWidth = MIN(286, CGRectGetWidth(safe)-70);
    CGFloat px = CGRectGetMinX(self.handle.frame)-6-panelWidth;
    CGFloat height = MIN(478, CGRectGetHeight(safe)-16);
    CGFloat py = MAX(CGRectGetMinY(safe)+8,MIN(y,CGRectGetMaxY(safe)-height-8));
    self.card.frame = CGRectIntegral(CGRectMake(px,py,panelWidth,height));
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
        [self mapTapped:nil];
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
    BOOL lost = ![self className:self.classID];
    if (changed || lost || (listChanged && self.pickingClass)) {
        if (self.modal.presentingViewController) [self.modal dismissViewControllerAnimated:NO completion:nil];
        self.modal = nil; self.pickingClass = NO;
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
- (void)openEditor:(NSDictionary *)profile {
    NSString *key = self.classID, *name = [self className:key]; NSNumber *session = self.session;
    if (!name || self.running || self.pending) return;
    self.pickingClass = NO;
    AQWSkillEditor *editor = [[AQWSkillEditor alloc] initForClass:name profile:profile saved:^(NSDictionary *value){
        if (![self.session isEqual:session] || ![self className:key]) return;
        [self.sets save:value forClass:key]; self.stateLine.text = @"Set saved on this device"; [self refresh];
    }];
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
- (void)mapTapped:(id)sender { self.command(@{@"action":@"map"}); }
- (void)runTapped:(id)sender {
    if (self.pending) return;
    NSDictionary *profile = [self.sets selectedFor:self.classID];
    if (!self.running && (!profile || ![self className:self.classID] || !self.session)) return;
    self.pending = YES; [self refresh];
    self.command(self.running ? @{@"action":@"stop"} :
        @{@"action":@"start", @"session":self.session, @"classId":self.classID, @"auto":@(self.autoTarget), @"steps":profile[@"steps"]});
}
- (void)showMap:(NSString *)map {
    NSString *display = map.length ? map : @"No map yet";
    [self.map setTitle:[NSString stringWithFormat:@"%@  ↻",display] forState:UIControlStateNormal];
    self.map.accessibilityLabel = [NSString stringWithFormat:@"Current map. %@. Refresh map",display];
}
- (void)showState:(NSString *)detail running:(BOOL)running {
    self.running = running; self.pending = NO;
    self.stateLine.text = detail;
    [self refresh];
}

static UIControl *ruleField(UITableViewController *editor, NSString *key) {
    UITableView *table=editor.tableView;
    for (NSInteger section=0; section<2; section++) {
        for (NSInteger i=0; i<[editor tableView:table numberOfRowsInSection:section]; i++) {
            UITableViewCell *row=[editor tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:section]];
            if ([row.accessoryView.accessibilityIdentifier isEqual:key]) return (UIControl *)row.accessoryView;
            for (UIView *item in row.contentView.subviews)
                if ([item.accessibilityIdentifier isEqual:key]) return (UIControl *)item;
        }
    }
    return nil;
}
static BOOL selectRuleSegment(UITableViewController *editor, NSString *key, NSString *title) {
    UISegmentedControl *control=(UISegmentedControl *)ruleField(editor,key);
    for (NSUInteger i=0; i<control.numberOfSegments; i++) if ([[control titleForSegmentAtIndex:i] isEqual:title]) {
        control.selectedSegmentIndex=i; [control sendActionsForControlEvents:UIControlEventValueChanged]; return YES;
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
static void captureRuleForm(UITableViewController *page) {
    page.view.frame=CGRectMake(0,0,510,430);
    [page.view layoutIfNeeded];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:page.view.bounds.size];
    UIImage *preview=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [page.view.layer renderInContext:context.CGContext];
    }];
    NSURL *documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    [UIImagePNGRepresentation(preview) writeToURL:[documents URLByAppendingPathComponent:@"aqw-condition-editor.png"] atomically:YES];
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
    AQWSkillSets *sets = [[AQWSkillSets alloc] initWithDefaults:defaults];
    [defaults setObject:@[@2,@4,@2] forKey:@"aqw.rotation.slots"];
    [sets migrateLegacyForEquipped:@"10"]; [sets migrateLegacyForEquipped:@"20"];
    NSArray *steps = [sets selectedFor:@"10"][@"steps"];
    if (![[steps valueForKey:@"slot"] isEqual:@[@2,@4,@2]] || [sets setsFor:@"20"].count) return NO;
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
    [step tableView:step.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:1]];
    UITableViewController *rule=(UITableViewController *)nav.topViewController;
    [rule loadViewIfNeeded];
    if ([rule isEqual:step] || ![rule.title isEqual:@"Condition"]) return NO;
    if (!selectRuleSegment(rule,@"kind",@"Mana") || !selectRuleSegment(rule,@"unit",@"#") ||
        !selectRuleSegment(rule,@"op",@"≥")) return NO;
    typeRuleField(rule,@"value",@"12500");
    captureRuleForm(rule); finishPage(rule);
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
    if (![[saved[@"steps"] firstObject][@"rules"] isEqual:expected] ||
        ![[saved[@"steps"] valueForKey:@"slot"] isEqual:[steps valueForKey:@"slot"]]) return NO;
    [sets save:saved forClass:@"10"];
    steps=[[[AQWSkillSets alloc] initWithDefaults:defaults] selectedFor:@"10"][@"steps"];
    if (![[steps firstObject][@"rules"] isEqual:expected]) return NO;
    NSDictionary *a = @{@"id":@"10",@"name":@"Healer"}, *b = @{@"id":@"20",@"name":@"Mage"};
    for (NSValue *size in @[[NSValue valueWithCGSize:CGSizeMake(852,393)],
                            [NSValue valueWithCGSize:CGSizeMake(568,320)],
                            [NSValue valueWithCGSize:CGSizeMake(1024,768)]]) {
        __block NSDictionary *last;
        AQWBotDrawer *view = [[self alloc] initWithFrame:(CGRect){CGPointZero,size.CGSizeValue}
            command:^(NSDictionary *request){ last=request; }];
        view.sets = [[AQWSkillSets alloc] initWithDefaults:defaults];
        [view showBag:@{@"session":@1,@"classes":@[a],@"equipped":@"10"}];
        if (![view.classID isEqual:@"10"] || !view.run.enabled) return NO;
        [view showBag:@{@"session":@2,@"classes":@[b],@"equipped":@"20"}];
        if ([view className:@"10"] || ![view.classID isEqual:@"20"] || view.run.enabled) return NO;
        [view showBag:@{@"session":@3,@"classes":@[b,a],@"equipped":@"10"}];
        [view setExpanded:NO]; [view layoutIfNeeded];
        if (CGRectGetMidX(view.handle.frame) <= CGRectGetMidX(view.bounds)) return NO;
        CGFloat gutter = (CGRectGetWidth(view.bounds)-CGRectGetHeight(view.bounds)*960./550.)/2.;
        if (gutter >= 64 && CGRectGetMinX(view.handle.frame)<CGRectGetWidth(view.bounds)-gutter) return NO;
        if ([view hitTest:CGPointMake(CGRectGetMidX(view.bounds),CGRectGetMidY(view.bounds)) withEvent:nil]) return NO;
        [view.handle sendActionsForControlEvents:UIControlEventTouchUpInside]; [view layoutIfNeeded];
        if (!view.expanded || ![last[@"action"] isEqual:@"map"] || !CGRectContainsRect(view.bounds,view.card.frame) ||
            CGRectIntersectsRect(view.card.frame,view.handle.frame) || CGRectGetHeight(view.run.frame)<44) return NO;
        [view.run sendActionsForControlEvents:UIControlEventTouchUpInside];
        if (![last[@"action"] isEqual:@"start"] || ![last[@"classId"] isEqual:@"10"] ||
            ![last[@"steps"] isEqual:steps] || ![last[@"session"] isEqual:@3]) return NO;
        [view showState:@"Running" running:YES]; [view setExpanded:NO];
        if (view.quickRun.hidden) return NO;
        [view.quickRun sendActionsForControlEvents:UIControlEventTouchUpInside];
        if (![last[@"action"] isEqual:@"stop"]) return NO;
        [view showState:@"Stopped" running:NO];
        if (view.quickRun.hidden || !view.quickRun.enabled) return NO;
        [view showBag:@{@"session":@4,@"classes":@[],@"equipped":@""}];
        if (view.run.enabled || !view.quickRun.hidden || view.chooseClass.enabled) return NO;
    }
    [sets remove:@"legacy" forClass:@"10"]; [sets migrateLegacyForEquipped:@"10"];
    return [sets setsFor:@"10"].count==0;
}
@end
