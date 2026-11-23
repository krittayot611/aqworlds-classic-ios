#import "SkillEditor.h"
#import "SkillSets.h"

static UITableViewStyle grouped(void) {
    if (@available(iOS 13.0, *)) return UITableViewStyleInsetGrouped;
    return UITableViewStyleGrouped;
}
static UIColor *secondary(void) {
    if (@available(iOS 13.0,*)) return UIColor.secondaryLabelColor;
    return UIColor.darkGrayColor;
}
UINavigationController *AQWSkillNavigation(UIViewController *root) {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    nav.preferredContentSize = CGSizeMake(510,540);
    if (@available(iOS 13.0,*)) {
        nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        nav.navigationBar.tintColor = [UIColor colorWithRed:.98 green:.79 blue:.42 alpha:1];
    }
    return nav;
}
static UITableViewCell *cell(NSString *title, NSString *detail, BOOL link) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = title; cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.text = detail; cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.textColor = secondary();
    cell.accessoryType = link ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}
static UITableViewCell *removeCell(NSString *text) {
    UITableViewCell *row = cell(text,nil,NO); row.textLabel.textColor = UIColor.systemRedColor; return row;
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
        BOOL valid = s.length > 0 && s.length <= (NSUInteger)(number ? 4 : max);
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

@interface AQWRuleEditor : UITableViewController
@property(nonatomic,strong) NSMutableDictionary *rule;
@property(nonatomic,copy) void (^apply)(NSDictionary *);
@property(nonatomic,copy) void (^removeRule)(void);
@end
@implementation AQWRuleEditor
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Condition";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)];
}
- (void)done:(id)sender {
    if ([self.rule[@"kind"] isEqual:@"aura"] && ![self.rule[@"name"] length]) { [self editName]; return; }
    self.apply([self.rule copy]); [self.navigationController popViewControllerAnimated:YES];
}
- (void)editName {
    input(self,@"Aura name",self.rule[@"name"],NO,1,100,^(NSString *s){ self.rule[@"name"] = s; [self.tableView reloadData]; });
}
- (BOOL)aura { return [self.rule[@"kind"] isEqual:@"aura"]; }
- (BOOL)quantity { return !self.aura || [self.rule[@"op"] isEqual:@"stacks"]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return self.removeRule ? 2 : 1; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)s { return s ? 1 : 2 + self.aura + self.quantity; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)s { return s ? nil : @"Cast when"; }
- (NSString *)typeCode { return self.aura ? self.rule[@"op"] : [NSString stringWithFormat:@"%@-%@",self.rule[@"kind"],self.rule[@"op"]]; }
- (NSArray *)codes { return @[@"present",@"missing",@"stacks",@"hp-below",@"hp-above",@"mp-below",@"mp-above"]; }
- (NSArray *)names { return @[@"Aura is present",@"Aura is absent",@"Aura stacks at least",@"HP below (%)",@"HP above (%)",@"MP below (%)",@"MP above (%)"]; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)p {
    if (p.section) return removeCell(@"Remove condition");
    if (p.row == 0) return cell(@"Subject",[self.rule[@"who"] isEqual:@"self"] ? @"Self" : @"Target",YES);
    if (p.row == 1) return cell(@"Condition",self.names[[self.codes indexOfObject:self.typeCode]],YES);
    if (p.row == 2 && self.aura) return cell(@"Aura name",[self.rule[@"name"] length] ? self.rule[@"name"] : @"Enter the in-game name",YES);
    return cell(self.aura ? @"Minimum stacks" : @"Percent",[self.rule[@"value"] stringValue],YES);
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)p {
    [table deselectRowAtIndexPath:p animated:YES];
    if (p.section) { self.removeRule(); [self.navigationController popViewControllerAnimated:YES]; return; }
    if (p.row == 0) {
        pick(self,@"Subject",@[@"self",@"target"],@[@"Self",@"Target"],self.rule[@"who"],^(NSString *v){ self.rule[@"who"]=v; [table reloadData]; });
    } else if (p.row == 1) {
        pick(self,@"Condition",self.codes,self.names,self.typeCode,^(NSString *v){
            NSArray *parts = [v componentsSeparatedByString:@"-"];
            BOOL aura = parts.count == 1;
            self.rule[@"kind"] = aura ? @"aura" : parts[0];
            self.rule[@"op"] = aura ? v : parts[1];
            self.rule[@"value"] = aura ? @1 : @50;
            [table reloadData];
        });
    } else if (p.row == 2 && self.aura) [self editName];
    else input(self,self.aura ? @"Minimum stacks" : @"Percent",[self.rule[@"value"] stringValue],YES,self.aura?1:0,self.aura?999:100,
               ^(NSString *v){ self.rule[@"value"]=@(v.integerValue); [table reloadData]; });
}
@end

@interface AQWStepEditor : UITableViewController
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
- (void)done:(id)sender { self.commit(self.value); [self.navigationController popViewControllerAnimated:YES]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 3; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)s { return @[@"Hotbar",@"Conditions",@"Sequence"][s]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)s {
    if (s==0) return 2;
    if (s==1) return 1+self.rules.count+(self.rules.count<8);
    return self.canUp+self.canDown+1;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)p {
    if (p.section==0) return p.row==0 ? cell(@"Skill slot",[self.step[@"slot"] stringValue],YES) :
        cell(@"On cooldown",[self.step[@"wait"] boolValue] ? @"Wait for cooldown" : @"Skip to next skill",YES);
    if (p.section==1) {
        if (!p.row) return cell(@"Match",[self.step[@"match"] isEqual:@"any"] ? @"Any condition" : @"All conditions",YES);
        return p.row<=self.rules.count ? cell(AQWRuleTitle(self.rules[p.row-1]),nil,YES) : cell(@"＋ Add condition",nil,YES);
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
    else if (p.section==1 && !p.row)
        pick(self,@"Match",@[@"all",@"any"],@[@"All conditions",@"Any condition"],self.step[@"match"],
             ^(NSString *v){ self.step[@"match"]=v; [table reloadData]; });
    else if (p.section==1) {
        NSInteger i=p.row-1; BOOL adding=i==self.rules.count;
        AQWRuleEditor *ed=[[AQWRuleEditor alloc] initWithStyle:grouped()];
        ed.rule=[(adding ? @{@"kind":@"aura",@"who":@"self",@"op":@"present",@"name":@"",@"value":@1} : self.rules[i]) mutableCopy];
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
