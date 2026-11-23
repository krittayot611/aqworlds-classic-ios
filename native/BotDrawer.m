#import "BotDrawer.h"
#import <QuartzCore/QuartzCore.h>

static UIColor *ink(void) { return [UIColor colorWithRed:.07 green:.09 blue:.12 alpha:1]; }
static UIColor *surface(void) { return [UIColor colorWithRed:.13 green:.16 blue:.20 alpha:1]; }
static UIColor *gold(void) { return [UIColor colorWithRed:.98 green:.79 blue:.42 alpha:1]; }
static UIColor *muted(void) { return [UIColor colorWithRed:.74 green:.78 blue:.82 alpha:1]; }
static UIColor *coral(void) { return [UIColor colorWithRed:1 green:.63 blue:.57 alpha:1]; }

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
    view.backgroundColor = surface();
    view.layer.cornerRadius = 10;
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
@property(nonatomic) BOOL left, expanded, running, pending, autoTarget, editing;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *slots;
@property(nonatomic, strong) UIButton *handle, *quickStop, *run, *changeSide, *map, *edit, *undo;
@property(nonatomic, strong) UILabel *stateLine, *order, *dot;
@property(nonatomic, strong) NSArray<UIButton *> *targets;
@property(nonatomic, strong) UIView *card;
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, strong) UIStackView *editor;
@end

@implementation AQWBotDrawer
- (instancetype)initWithFrame:(CGRect)frame command:(AQWBotCommand)command {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.command = command;
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    self.left = [prefs boolForKey:@"aqw.drawer.left"];
    self.autoTarget = [prefs boolForKey:@"aqw.rotation.auto"];
    NSArray *saved = [prefs arrayForKey:@"aqw.rotation.slots"];
    BOOL valid = saved && saved.count <= 8;
    for (id n in saved)
        if (![@[@2,@3,@4,@5] containsObject:n]) valid = NO;
    self.slots = [(valid ? saved : @[@2,@3,@4,@5]) mutableCopy];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = UIColor.clearColor;
    self.handle = button(@"BOT", @"Open bot controls", self, @selector(toggle:));
    self.handle.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightHeavy];
    self.handle.backgroundColor = ink();
    self.handle.layer.borderWidth = 1.5;
    self.handle.layer.borderColor = gold().CGColor;
    self.handle.layer.cornerRadius = 15;
    [self.handle setTitleColor:gold() forState:UIControlStateNormal];
    self.quickStop = button(@"■", @"Stop rotation now", self, @selector(runTapped:));
    self.quickStop.backgroundColor = coral();
    [self.quickStop setTitleColor:ink() forState:UIControlStateNormal];
    [self addSubview:self.handle];
    [self addSubview:self.quickStop];

    self.card = [UIView new];
    self.card.backgroundColor = ink();
    self.card.layer.cornerRadius = 18;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = [gold() colorWithAlphaComponent:.48].CGColor;
    self.card.layer.shadowColor = UIColor.blackColor.CGColor;
    self.card.layer.shadowOpacity = .32;
    self.card.layer.shadowOffset = CGSizeMake(0, 4);
    self.card.layer.shadowRadius = 10;
    [self addSubview:self.card];
    UILabel *title = label(@"Bot controls", 21, UIFontWeightBold, UIColor.whiteColor);
    title.accessibilityTraits |= UIAccessibilityTraitHeader;
    self.changeSide = button(@"⇄", @"Move controls to the other edge", self, @selector(flip:));
    [self.changeSide.widthAnchor constraintEqualToConstant:44].active = YES;
    UIStackView *header = stack(@[title,self.changeSide], YES, 8);
    header.alignment = UIStackViewAlignmentCenter;
    self.dot = label(@"●", 12, UIFontWeightBold, muted());
    self.dot.isAccessibilityElement = NO;
    [self.dot setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    self.stateLine = label(@"Ready", 14, UIFontWeightSemibold, muted());
    self.stateLine.numberOfLines = 2;
    UIStackView *status = stack(@[self.dot,self.stateLine], YES, 7);
    self.map = button(@"Read current map  ↻", @"Read current map", self, @selector(mapTapped:));
    self.map.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.map.contentEdgeInsets = UIEdgeInsetsMake(0,12,0,12);
    self.map.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.map setTitleColor:muted() forState:UIControlStateNormal];
    UIButton *selected = button(@"Selected", @"Use the selected monster", self, @selector(targetTapped:));
    UIButton *room = button(@"Auto in room", @"Find a monster in this room", self, @selector(targetTapped:));
    room.tag = 1;
    self.targets = @[selected,room];
    UIStackView *targetRow = stack(self.targets, YES, 6);
    targetRow.distribution = UIStackViewDistributionFillEqually;

    self.edit = button(@"Edit", @"Edit skill order", self, @selector(editTapped:));
    [self.edit.widthAnchor constraintEqualToConstant:60].active = YES;
    UIStackView *orderHeading = stack(@[label(@"Skill order",15,UIFontWeightSemibold,UIColor.whiteColor),self.edit], YES, 8);
    orderHeading.alignment = UIStackViewAlignmentCenter;
    self.order = label(@"", 17, UIFontWeightSemibold, gold());
    self.order.numberOfLines = 0;
    NSMutableArray *keys = [NSMutableArray new];
    for (int n = 2; n <= 5; n++) {
        NSString *key = [@(n) stringValue];
        UIButton *b = button(key, [@"Append skill " stringByAppendingString:key], self, @selector(addSlot:));
        b.tag = n;
        [keys addObject:b];
    }
    UIStackView *keyRow = stack(keys, YES, 6);
    keyRow.distribution = UIStackViewDistributionFillEqually;
    self.undo = button(@"Undo", @"Remove last skill", self, @selector(undoSlot:));
    UIButton *reset = button(@"Reset", @"Restore skill order 2, 3, 4, 5", self, @selector(resetSlots:));
    UIStackView *actions = stack(@[self.undo,reset], YES, 6);
    actions.distribution = UIStackViewDistributionFillEqually;
    self.editor = stack(@[label(@"Tap a skill to append it.",13,UIFontWeightRegular,muted()),keyRow,actions], NO, 5);
    UIStackView *body = stack(@[self.map,label(@"Target",15,UIFontWeightSemibold,UIColor.whiteColor),
                                targetRow,orderHeading,self.order,self.editor], NO, 6);
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
    [self.run setTitleColor:ink() forState:UIControlStateNormal];
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
    self.quickStop.hidden = self.expanded || !self.running;
    self.quickStop.enabled = !self.pending;
    self.handle.accessibilityLabel = self.expanded ? @"Close bot controls" : @"Open bot controls";
    self.handle.accessibilityValue = self.running ? @"Running" : @"Stopped";
    [self.handle setTitle:self.expanded ? @"Close" : @"BOT" forState:UIControlStateNormal];
    self.handle.layer.borderColor = (self.running ? coral() : gold()).CGColor;
    [self.handle setTitleColor:self.running ? coral() : gold() forState:UIControlStateNormal];
    self.changeSide.accessibilityLabel = self.left ? @"Move controls to the right edge" : @"Move controls to the left edge";
    self.dot.textColor = self.running ? gold() : muted();
    for (UIButton *b in self.targets) {
        BOOL active = (b.tag == (NSInteger)self.autoTarget);
        b.enabled = configurable;
        b.backgroundColor = active ? gold() : surface();
        [b setTitleColor:active ? ink() : muted() forState:UIControlStateNormal];
        b.accessibilityTraits = UIAccessibilityTraitButton | (active ? UIAccessibilityTraitSelected : 0);
    }
    self.edit.enabled = configurable;
    [self.edit setTitle:self.editing ? @"Done" : @"Edit" forState:UIControlStateNormal];
    self.editor.hidden = !self.editing;
    self.undo.enabled = self.slots.count > 0;
    self.order.text = self.slots.count ? [self.slots componentsJoinedByString:@" › "] : @"Choose a skill";
    self.order.accessibilityLabel = [@"Skill order. " stringByAppendingString:self.order.text];
    NSString *verb = self.running ? @"Stop rotation" : @"Start rotation";
    [self.run setTitle:self.pending ? @"One moment…" : verb forState:UIControlStateNormal];
    self.run.accessibilityLabel = verb;
    self.run.backgroundColor = self.running ? coral() : gold();
    self.run.enabled = !self.pending && (self.running || self.slots.count > 0);
    self.run.alpha = self.run.enabled ? 1 : .55;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    if (CGRectIsEmpty(safe)) return;
    CGFloat w = CGRectGetWidth(self.bounds), h = CGRectGetHeight(self.bounds);
    CGFloat scale = MIN(w/960., h/550.);
    CGFloat sideGutter = (w - 960.*scale)/2., topGutter = (h - 550.*scale)/2.;
    CGFloat inset = self.left ? CGRectGetMinX(safe) : w-CGRectGetMaxX(safe);
    CGFloat offset = MAX(4, (sideGutter-inset-52)/2.);
    CGFloat x = self.left ? CGRectGetMinX(safe)+offset : CGRectGetMaxX(safe)-offset-52;
    CGFloat y = CGRectGetMinY(safe)+8;
    if (topGutter > CGRectGetMinY(safe)+52)
        y = CGRectGetMinY(safe) + (topGutter-CGRectGetMinY(safe)-44)/2.;
    self.handle.frame = CGRectIntegral(CGRectMake(x,y,52,44));
    self.quickStop.frame = CGRectIntegral(CGRectMake(x,y+48,52,44));
    CGFloat panelWidth = MIN(266, CGRectGetWidth(safe)-70);
    CGFloat px = self.left ? CGRectGetMaxX(self.handle.frame)+6 : CGRectGetMinX(self.handle.frame)-6-panelWidth;
    CGFloat height = MIN(self.editing ? 490 : 356, CGRectGetHeight(safe)-16);
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
    if (!expanded) self.editing = NO;
    [self refresh];
    if (expanded && changed) {
        [self mapTapped:nil];
        if (!UIAccessibilityIsReduceMotionEnabled()) {
            self.card.alpha = .25;
            [UIView animateWithDuration:.16 animations:^{ self.card.alpha = 1; }];
        }
    }
    if (changed && self.window)
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,expanded ? self.changeSide : self.handle);
}
- (void)toggle:(id)sender { [self setExpanded:!self.expanded]; }
- (void)flip:(id)sender {
    self.left = !self.left;
    [NSUserDefaults.standardUserDefaults setBool:self.left forKey:@"aqw.drawer.left"];
    [self refresh];
}
- (void)targetTapped:(UIButton *)sender {
    self.autoTarget = sender.tag == 1;
    [NSUserDefaults.standardUserDefaults setBool:self.autoTarget forKey:@"aqw.rotation.auto"];
    [self refresh];
}
- (void)editTapped:(id)sender {
    self.editing = !self.editing;
    [self refresh];
    [self layoutIfNeeded];
    if (self.editing) [self.scroll scrollRectToVisible:self.editor.frame animated:!UIAccessibilityIsReduceMotionEnabled()];
}
- (void)saveSlots {
    [NSUserDefaults.standardUserDefaults setObject:[self.slots copy] forKey:@"aqw.rotation.slots"];
    [self refresh];
}
- (void)addSlot:(UIButton *)sender {
    if (self.slots.count >= 8) { self.stateLine.text = @"8 skills max · Undo to change"; return; }
    [self.slots addObject:@(sender.tag)];
    [self saveSlots];
}
- (void)undoSlot:(id)sender { if (self.slots.count) [self.slots removeLastObject]; [self saveSlots]; }
- (void)resetSlots:(id)sender { self.slots = [@[@2,@3,@4,@5] mutableCopy]; [self saveSlots]; }
- (void)mapTapped:(id)sender { self.command(@"map",nil,NO); }
- (void)runTapped:(id)sender {
    if (self.pending || (!self.running && !self.slots.count)) return;
    self.pending = YES;
    self.editing = NO;
    [self refresh];
    self.command(self.running ? @"stop" : @"start", [self.slots copy], self.autoTarget);
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

+ (BOOL)checkControls {
    for (NSValue *size in @[[NSValue valueWithCGSize:CGSizeMake(852,393)],
                            [NSValue valueWithCGSize:CGSizeMake(568,320)],
                            [NSValue valueWithCGSize:CGSizeMake(1024,768)]]) {
        __block NSString *last;
        __block NSArray *sent;
        AQWBotDrawer *view = [[self alloc] initWithFrame:(CGRect){CGPointZero,size.CGSizeValue}
            command:^(NSString *action, NSArray *keys, BOOL autoTarget) { last = action; sent = keys; }];
        view.slots = [@[@2,@4,@2] mutableCopy];
        for (int side = 0; side < 2; side++) {
            view.left = side;
            [view setExpanded:NO];
            [view layoutIfNeeded];
            if ([view hitTest:CGPointMake(CGRectGetMidX(view.bounds),CGRectGetMidY(view.bounds)) withEvent:nil]) return NO;
            [view.handle sendActionsForControlEvents:UIControlEventTouchUpInside];
            [view layoutIfNeeded];
            if (!view.expanded || ![last isEqual:@"map"] || !CGRectContainsRect(view.bounds,view.card.frame) ||
                CGRectIntersectsRect(view.card.frame,view.handle.frame) || CGRectGetHeight(view.run.frame)<44) return NO;
            [view.run sendActionsForControlEvents:UIControlEventTouchUpInside];
            if (![last isEqual:@"start"] || ![sent isEqual:@[@2,@4,@2]]) return NO;
            [view showState:@"Running" running:YES];
            [view setExpanded:NO];
            if (view.quickStop.hidden) return NO;
            [view.quickStop sendActionsForControlEvents:UIControlEventTouchUpInside];
            if (![last isEqual:@"stop"]) return NO;
            [view showState:@"Stopped" running:NO];
        }
    }
    return YES;
}
@end
