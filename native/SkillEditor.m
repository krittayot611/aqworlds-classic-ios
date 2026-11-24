#import "SkillEditor.h"
#import "SkillSets.h"
#import "SkillTheme.h"

static UITableViewStyle grouped(void) {
    if (@available(iOS 13.0, *)) return UITableViewStyleInsetGrouped;
    return UITableViewStyleGrouped;
}
@implementation AQWSkillTable
- (void)viewDidLoad {
    [super viewDidLoad];
    UITableView *table = self.tableView;
    table.backgroundColor = AQWCharcoal();
    table.separatorColor = AQWKeyline();
    table.tintColor = AQWSilver();
    table.rowHeight = UITableViewAutomaticDimension;
    table.estimatedRowHeight = 52;
    table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
}
- (void)tableView:(UITableView *)table willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)view).textLabel.textColor = AQWSecondary();
}
- (void)tableView:(UITableView *)table willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)view).textLabel.textColor = AQWSecondary();
}
@end
UINavigationController *AQWSkillNavigation(UIViewController *root) {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    nav.preferredContentSize = CGSizeMake(510,540);
    if (@available(iOS 13.0,*)) nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.barTintColor = AQWCharcoal();
    nav.navigationBar.tintColor = AQWSilver();
    nav.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName:UIColor.whiteColor};
    if (@available(iOS 13.0,*)) {
        UINavigationBarAppearance *bar = [UINavigationBarAppearance new];
        [bar configureWithOpaqueBackground]; bar.backgroundColor = AQWCharcoal();
        bar.shadowColor = AQWKeyline(); bar.titleTextAttributes = nav.navigationBar.titleTextAttributes;
        nav.navigationBar.standardAppearance = bar;
        nav.navigationBar.compactAppearance = bar;
        nav.navigationBar.scrollEdgeAppearance = bar;
    }
    return nav;
}
static UITableViewCell *cell(NSString *title, NSString *detail, BOOL link) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = title; cell.textLabel.numberOfLines = 0;
    cell.backgroundColor = AQWPanel(); cell.tintColor = AQWSilver();
    cell.textLabel.textColor = UIColor.whiteColor;
    UIView *selected = [UIView new]; selected.backgroundColor = AQWKeyline(); cell.selectedBackgroundView = selected;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.text = detail; cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.textColor = AQWSecondary();
    cell.accessoryType = link ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}
static UITableViewCell *removeCell(NSString *text) {
    UITableViewCell *row = cell(text,nil,NO); row.textLabel.textColor = AQWStopColor(); return row;
}
static void input(UIViewController *from, NSString *title, NSString *initial, BOOL number,
                  NSInteger min, NSInteger max, void (^use)(NSString *)) {
    NSString *hint = number ? [NSString stringWithFormat:@"%ld–%ld",(long)min,(long)max] : nil;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:hint preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.text = initial; f.clearButtonMode = UITextFieldViewModeWhileEditing;
        f.autocapitalizationType = UITextAutocapitalizationTypeWords;
        if (number) f.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weak = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *s = [weak.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL valid = s.length > 0 && s.length <= (number ? [@(max) stringValue].length : (NSUInteger)max);
        if (number) valid = valid && [s rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound &&
            s.integerValue >= min && s.integerValue <= max;
        if (valid) { use(s); return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *err = [UIAlertController alertControllerWithTitle:number ? @"Check the number" : @"Enter a name"
                message:number ? hint : [NSString stringWithFormat:@"Use 1–%ld characters.",(long)max] preferredStyle:UIAlertControllerStyleAlert];
            [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            if (from.view.window) [from presentViewController:err animated:YES completion:nil];
        });
    }]];
    [from presentViewController:a animated:YES completion:nil];
}

@interface AQWChoiceList () <UISearchBarDelegate>
@property(nonatomic,copy) NSArray *rows, *visibleRows;
@property(nonatomic,copy) NSString *selected;
@property(nonatomic,copy) void (^choose)(NSString *);
@property(nonatomic) BOOL searchable;
@end
@implementation AQWChoiceList
- (instancetype)initWithTitle:(NSString *)title rows:(NSArray *)rows selected:(NSString *)selected searchable:(BOOL)searchable choose:(void (^)(NSString *))choose {
    if ((self = [super initWithStyle:grouped()])) {
        self.title = title; _rows = rows; _visibleRows = rows; _selected = selected; _searchable = searchable; _choose = choose;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.navigationController.viewControllers.firstObject == self)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close:)];
    if (self.searchable) {
        UISearchBar *search = [UISearchBar new]; search.placeholder = @"Search bag classes";
        search.delegate = self; [search sizeToFit]; self.tableView.tableHeaderView = search;
        self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    }
}
- (void)close:(id)sender { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
    self.visibleRows = text.length ? [self.rows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *r, NSDictionary *bindings) {
        return [r[@"name"] localizedCaseInsensitiveContainsString:text];
    }]] : self.rows;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.visibleRows.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)p {
    NSDictionary *r = self.visibleRows[p.row]; UITableViewCell *c = cell(r[@"name"],r[@"detail"],NO);
    if ([r[@"id"] isEqual:self.selected]) c.accessoryType = UITableViewCellAccessoryCheckmark;
    return c;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)p {
    NSString *key = self.visibleRows[p.row][@"id"];
    if (self.navigationController.viewControllers.firstObject == self) {
        void (^callback)(NSString *) = self.choose;
        [self dismissViewControllerAnimated:YES completion:^{ callback(key); }];
    } else {
        self.choose(key); [self.navigationController popViewControllerAnimated:YES];
    }
}
@end

static void pick(UIViewController *owner, NSString *title, NSArray *ids, NSArray *names, NSString *current, void (^use)(NSString *)) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i=0; i<ids.count; i++) [rows addObject:@{@"id":ids[i],@"name":names[i]}];
    AQWChoiceList *list = [[AQWChoiceList alloc] initWithTitle:title rows:rows selected:current searchable:NO choose:use];
    [owner.navigationController pushViewController:list animated:YES];
}

@interface AQWRuleEditor : AQWSkillTable <UITextFieldDelegate>
@property(nonatomic,strong) NSMutableDictionary *rule;
@property(nonatomic,copy) void (^apply)(NSDictionary *);
@property(nonatomic,copy) void (^removeRule)(void);
@end

@implementation AQWRuleEditor
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Condition";
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)];
}
- (BOOL)aura { return [self.rule[@"kind"] isEqual:@"aura"]; }
- (BOOL)party { return [self.rule[@"kind"] isEqual:@"partyhp"]; }
- (BOOL)usesValue { return !self.aura || ![@[@"present",@"missing"] containsObject:self.rule[@"op"]]; }
- (NSInteger)maximum { return self.aura ? 999 : [self.rule[@"unit"] isEqual:@"raw"] ? INT32_MAX : 100; }
- (NSArray *)fields {
    NSMutableArray *fields = [NSMutableArray array];
    if (!self.party) [fields addObject:@"who"];
    if (self.aura) [fields addObject:@"name"];
    [fields addObject:@"op"];
    if (!self.aura) [fields addObject:@"unit"];
    if (self.usesValue) [fields addObject:@"value"];
    return fields;
}
- (void)done:(id)sender {
    NSString *field = self.aura && ![self.rule[@"name"] length] ? @"name" :
        self.usesValue && !self.rule[@"value"] ? @"value" : nil;
    if (field) {
        NSIndexPath *p = [NSIndexPath indexPathForRow:[self.fields indexOfObject:field] inSection:1];
        [self.tableView scrollToRowAtIndexPath:p atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        [self.tableView layoutIfNeeded];
        UITableViewCell *row = [self.tableView cellForRowAtIndexPath:p];
        row.detailTextLabel.text = [field isEqual:@"name"] ? @"Enter an aura name" : [NSString stringWithFormat:@"Use 0–%ld",(long)self.maximum];
        row.detailTextLabel.textColor = AQWStopColor();
        [row setNeedsLayout];
        [row.accessoryView becomeFirstResponder];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,[field isEqual:@"name"] ? @"Enter the in-game aura name" :
            [NSString stringWithFormat:@"Enter a whole number from 0 to %ld",(long)self.maximum]);
        return;
    }
    [self.view endEditing:YES];
    self.apply([self.rule copy]); [self.navigationController popViewControllerAnimated:YES];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return self.removeRule ? 3 : 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 1 ? self.fields.count : 1; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Rule type" : section == 1 ? @"Cast when" : nil;
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if (section != 1) return nil;
    if (self.party) return @"Matches any living party member in your room, excluding you.";
    if (self.aura) return @"Use the in-game aura name. Uppercase and lowercase both work.";
    return @"# uses points. % uses the current maximum.";
}
- (NSArray *)codesFor:(NSString *)field {
    if ([field isEqual:@"kind"]) return @[@"hp",@"mp",@"partyhp",@"aura"];
    if ([field isEqual:@"who"]) return @[@"self",@"target"];
    if ([field isEqual:@"unit"]) return @[@"raw",@"percent"];
    if (self.aura) return @[@"present",@"missing",@"lte",@"gte"];
    NSString *op = self.rule[@"op"];
    return [@[@"below",@"above"] containsObject:op] ? @[@"lte",@"gte",op] : @[@"lte",@"gte"];
}
- (UITableViewCell *)segments:(NSString *)field title:(NSString *)title {
    NSDictionary *labels = @{@"hp":@"Health",@"mp":@"Mana",@"partyhp":@"Party HP",@"aura":@"Aura",@"self":@"Self",@"target":@"Target",
        @"raw":@"#",@"percent":@"%",@"present":@"Present",@"missing":@"Absent",@"lte":@"≤",@"gte":@"≥",@"below":@"<",@"above":@">"};
    NSArray *codes = [self codesFor:field];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *code in codes) [items addObject:labels[code]];
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:items];
    if (self.aura && [field isEqual:@"op"]) control.apportionsSegmentWidthsByContent = YES;
    control.accessibilityIdentifier = field; control.accessibilityLabel = title ?: @"Rule type";
    control.tintColor = AQWSilver();
    if (@available(iOS 13.0,*)) { control.selectedSegmentTintColor = AQWSilver(); control.backgroundColor = AQWCharcoal(); }
    [control setTitleTextAttributes:@{NSForegroundColorAttributeName:AQWSilver()} forState:UIControlStateNormal];
    [control setTitleTextAttributes:@{NSForegroundColorAttributeName:AQWCharcoal(), NSFontAttributeName:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]} forState:UIControlStateSelected];
    NSString *current = self.rule[field];
    if ([field isEqual:@"unit"] && !current) current=@"percent";
    if ([field isEqual:@"op"] && [current isEqual:@"stacks"]) current=@"gte";
    NSUInteger index = [codes indexOfObject:current];
    control.selectedSegmentIndex = index == NSNotFound ? UISegmentedControlNoSegment : (NSInteger)index;
    [control addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged];
    UITableViewCell *row = cell(title,nil,NO);
    row.selectionStyle = UITableViewCellSelectionStyleNone;
    if (title) {
        CGFloat width = codes.count > 2 ? 190 : 120;
        control.frame = CGRectMake(0,0,width,44); row.accessoryView = control;
    } else {
        control.translatesAutoresizingMaskIntoConstraints = NO;
        [row.contentView addSubview:control];
        UILayoutGuide *margin = row.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [control.leadingAnchor constraintEqualToAnchor:margin.leadingAnchor],
            [control.trailingAnchor constraintEqualToAnchor:margin.trailingAnchor],
            [control.topAnchor constraintEqualToAnchor:row.contentView.topAnchor constant:4],
            [control.bottomAnchor constraintEqualToAnchor:row.contentView.bottomAnchor constant:-4],
            [control.heightAnchor constraintEqualToConstant:44]
        ]];
    }
    return row;
}
- (void)change:(UISegmentedControl *)control {
    NSString *field = control.accessibilityIdentifier, *choice = [self codesFor:field][control.selectedSegmentIndex];
    if ([field isEqual:@"kind"]) {
        BOOL wasAura = self.aura;
        self.rule[@"kind"] = choice;
        if (self.party) self.rule[@"who"] = @"party";
        else if ([self.rule[@"who"] isEqual:@"party"]) self.rule[@"who"] = @"self";
        if (self.aura != wasAura) {
            self.rule[@"op"] = self.aura ? @"gte" : @"lte";
            self.rule[@"value"] = self.aura ? @1 : @50;
            if (self.aura) [self.rule removeObjectForKey:@"unit"];
            else { self.rule[@"unit"] = @"percent"; [self.rule removeObjectForKey:@"name"]; }
        }
    } else {
        self.rule[field] = choice;
        if ([field isEqual:@"op"] && !self.aura && !self.rule[@"unit"]) self.rule[@"unit"] = @"percent";
        if ([field isEqual:@"unit"] && [self.rule[@"value"] integerValue] > self.maximum) [self.rule removeObjectForKey:@"value"];
    }
    [self.tableView reloadData];
}
- (UITableViewCell *)entry:(NSString *)field {
    BOOL name = [field isEqual:@"name"];
    NSString *title = name ? @"Aura name" : self.aura ? @"Stacks" : [self.rule[@"unit"] isEqual:@"raw"] ? @"Points" : @"Percent";
    UITableViewCell *row = cell(title,nil,NO);
    UITextField *entry = [[UITextField alloc] initWithFrame:CGRectMake(0,0,name ? 170 : 135,44)];
    entry.accessibilityIdentifier = field; entry.accessibilityLabel = title; entry.textAlignment = NSTextAlignmentRight;
    entry.textColor = UIColor.whiteColor; entry.tintColor = AQWSilver(); entry.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    entry.keyboardAppearance = UIKeyboardAppearanceDark; entry.delegate = self; entry.returnKeyType = UIReturnKeyDone;
    entry.autocorrectionType = UITextAutocorrectionTypeNo;
    entry.keyboardType = name ? UIKeyboardTypeDefault : UIKeyboardTypeNumberPad;
    NSString *hint = name ? @"In-game name" : [NSString stringWithFormat:@"0–%ld",(long)self.maximum];
    entry.attributedPlaceholder = [[NSAttributedString alloc] initWithString:hint attributes:@{NSForegroundColorAttributeName:AQWSecondary()}];
    entry.text = name ? self.rule[field] : [self.rule[field] stringValue];
    [entry addTarget:self action:@selector(typed:) forControlEvents:UIControlEventEditingChanged];
    row.accessoryView = entry; return row;
}
- (void)typed:(UITextField *)entry {
    NSString *text = [entry.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL name = [entry.accessibilityIdentifier isEqual:@"name"];
    BOOL valid = text.length > 0 && (name ? text.length <= 100 :
        text.length <= 10 && [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location == NSNotFound &&
        text.longLongValue <= self.maximum);
    entry.textColor = valid || !text.length ? UIColor.whiteColor : AQWStopColor();
    if (valid) {
        self.rule[entry.accessibilityIdentifier] = name ? (id)text : @(text.longLongValue);
        if (!name && self.aura && [self.rule[@"op"] isEqual:@"stacks"]) self.rule[@"op"] = @"gte";
    } else [self.rule removeObjectForKey:entry.accessibilityIdentifier];
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)p { return p.section == 0 ? 54 : 52; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)p {
    if (p.section == 0) return [self segments:@"kind" title:nil];
    if (p.section == 2) return removeCell(@"Remove condition");
    NSString *field = self.fields[p.row];
    if ([field isEqual:@"name"] || [field isEqual:@"value"]) return [self entry:field];
    NSDictionary *titles = @{@"op":@"Compare",@"who":@"Subject",@"unit":@"Unit"};
    return [self segments:field title:titles[field]];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)p {
    [table deselectRowAtIndexPath:p animated:YES];
    if (p.section == 2) { self.removeRule(); [self.navigationController popViewControllerAnimated:YES]; return; }
    [[table cellForRowAtIndexPath:p].accessoryView becomeFirstResponder];
}
@end

@interface AQWStepEditor : AQWSkillTable
@property(nonatomic,strong) NSMutableDictionary *step;
@property(nonatomic,strong) NSMutableArray *rules;
@property(nonatomic,copy) void (^commit)(NSDictionary *);
@property(nonatomic,copy) void (^move)(NSInteger direction);
@property(nonatomic) BOOL canUp, canDown;
@end
@implementation AQWStepEditor
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Edit skill";
    self.rules = [self.step[@"rules"] mutableCopy];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)];
}
- (NSDictionary *)value { self.step[@"rules"]=[self.rules copy]; return [self.step copy]; }
- (void)toggleRules:(UISwitch *)control { self.step[@"rulesEnabled"] = @(control.on); }
- (void)done:(id)sender { self.commit(self.value); [self.navigationController popViewControllerAnimated:YES]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 3; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)s { return @[@"Hotbar",@"Conditions",@"Sequence"][s]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)s {
    if (s==0) return 2;
    if (s==1) return 2+self.rules.count+(self.rules.count<8);
    return self.canUp+self.canDown+1;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)p {
    if (p.section==0) return p.row==0 ? cell(@"Skill slot",[self.step[@"slot"] stringValue],YES) :
        cell(@"On cooldown",[self.step[@"wait"] boolValue] ? @"Wait for cooldown" : @"Skip to next skill",YES);
    if (p.section==1) {
        if (!p.row) {
            UITableViewCell *row=cell(@"Use rules",nil,NO);
            UISwitch *control=[UISwitch new]; control.on=![self.step[@"rulesEnabled"] isEqual:@NO];
            control.onTintColor=AQWKeyline(); control.accessibilityLabel=@"Use rules";
            [control addTarget:self action:@selector(toggleRules:) forControlEvents:UIControlEventValueChanged];
            row.accessoryView=control; row.selectionStyle=UITableViewCellSelectionStyleNone; return row;
        }
        if (p.row==1) return cell(@"Match",[self.step[@"match"] isEqual:@"any"] ? @"Any condition" : @"All conditions",YES);
        return p.row-2<self.rules.count ? cell(AQWRuleTitle(self.rules[p.row-2]),nil,YES) : cell(@"Add condition",@"Health, Mana, Party HP or a named aura",YES);
    }
    if (self.canUp && p.row==0) return cell(@"Move earlier",nil,NO);
    if (self.canDown && p.row==self.canUp) return cell(@"Move later",nil,NO);
    return removeCell(@"Remove skill");
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)p {
    [table deselectRowAtIndexPath:p animated:YES];
    if (p.section==0 && p.row==0)
        pick(self,@"Skill slot",@[@"2",@"3",@"4",@"5"],@[@"Skill 2",@"Skill 3",@"Skill 4",@"Skill 5"],[self.step[@"slot"] stringValue],
             ^(NSString *v){ self.step[@"slot"]=@(v.integerValue); [table reloadData]; });
    else if (p.section==0)
        pick(self,@"On cooldown",@[@"wait",@"skip"],@[@"Wait for cooldown",@"Skip to next skill"],[self.step[@"wait"] boolValue] ? @"wait" : @"skip",
             ^(NSString *v){ self.step[@"wait"]=@([v isEqual:@"wait"]); [table reloadData]; });
    else if (p.section==1 && p.row==0) {
        UISwitch *control=(UISwitch *)[table cellForRowAtIndexPath:p].accessoryView;
        [control setOn:!control.on animated:YES]; [self toggleRules:control];
    } else if (p.section==1 && p.row==1)
        pick(self,@"Match",@[@"all",@"any"],@[@"All conditions",@"Any condition"],self.step[@"match"],
             ^(NSString *v){ self.step[@"match"]=v; [table reloadData]; });
    else if (p.section==1) {
        NSInteger i=p.row-2; BOOL adding=i==self.rules.count;
        AQWRuleEditor *ed=[[AQWRuleEditor alloc] initWithStyle:grouped()];
        ed.rule=[(adding ? @{@"kind":@"hp",@"who":@"self",@"op":@"lte",@"unit":@"percent",@"value":@50} : self.rules[i]) mutableCopy];
        ed.apply=^(NSDictionary *r){ if (adding) [self.rules addObject:r]; else self.rules[i]=r; [table reloadData]; };
        if (!adding) ed.removeRule=^{ [self.rules removeObjectAtIndex:i]; [table reloadData]; };
        [self.navigationController pushViewController:ed animated:YES];
    } else {
        NSInteger direction = self.canUp && p.row==0 ? -1 : self.canDown && p.row==self.canUp ? 1 : 0;
        if (direction) self.commit(self.value);
        self.move(direction); [self.navigationController popViewControllerAnimated:YES];
    }
}
@end

@interface AQWSkillEditor ()
@property(nonatomic,copy) NSString *name, *setID, *className;
@property(nonatomic,strong) NSMutableArray *steps;
@property(nonatomic,copy) void (^saved)(NSDictionary *);
@end
@implementation AQWSkillEditor
- (instancetype)initForClass:(NSString *)className profile:(NSDictionary *)profile saved:(void (^)(NSDictionary *))saved {
    if ((self=[super initWithStyle:grouped()])) {
        self.title = profile ? @"Edit skill set" : @"New skill set"; _className=className;
        _name=profile[@"name"] ?: @"New set"; _setID=profile[@"id"] ?: NSUUID.UUID.UUIDString;
        _steps=[(profile[@"steps"] ?: @[AQWStep(@2),AQWStep(@3),AQWStep(@4),AQWStep(@5)]) mutableCopy]; _saved=saved;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save:)];
}
- (void)cancel:(id)sender { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)save:(id)sender {
    if (!self.steps.count) return;
    self.saved(@{@"id":self.setID,@"name":self.name,@"steps":[self.steps copy]});
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)s { return s ? @"Skill order" : self.className; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)s { return s ? self.steps.count+(self.steps.count<32) : 1; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)p {
    if (!p.section) return cell(@"Set name",self.name,YES);
    if (p.row==self.steps.count) return cell(@"＋ Add skill",nil,YES);
    NSDictionary *step=self.steps[p.row];
    return cell([NSString stringWithFormat:@"%ld.   Skill %@",(long)p.row+1,step[@"slot"]],AQWStepSummary(step),YES);
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)p {
    [table deselectRowAtIndexPath:p animated:YES];
    if (!p.section) {
        input(self,@"Set name",self.name,NO,1,60,^(NSString *s){self.name=s; [table reloadData];}); return;
    }
    NSInteger i=p.row;
    if (i==self.steps.count) {
        pick(self,@"Add skill",@[@"2",@"3",@"4",@"5"],@[@"Skill 2",@"Skill 3",@"Skill 4",@"Skill 5"],nil,^(NSString *slot){
            [self.steps addObject:AQWStep(@(slot.integerValue))]; self.navigationItem.rightBarButtonItem.enabled=YES; [table reloadData];
        }); return;
    }
    AQWStepEditor *ed=[[AQWStepEditor alloc] initWithStyle:grouped()];
    ed.step=[self.steps[i] mutableCopy]; ed.canUp=i>0; ed.canDown=i+1<self.steps.count;
    ed.commit=^(NSDictionary *v){self.steps[i]=v; [table reloadData];};
    ed.move=^(NSInteger d){
        if (!d) [self.steps removeObjectAtIndex:i]; else [self.steps exchangeObjectAtIndex:i withObjectAtIndex:i+d];
        self.navigationItem.rightBarButtonItem.enabled=self.steps.count>0; [table reloadData];
    };
    [self.navigationController pushViewController:ed animated:YES];
}
@end
