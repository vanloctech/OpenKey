//
//  ViewController.m
//  ModernKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import "ViewController.h"
#import "OpenKeyManager.h"
#import "AppDelegate.h"
#import "MyTextField.h"

extern AppDelegate* appDelegate;
extern void OnSpellCheckingChanged(void);

ViewController* viewController;

#pragma mark Liquid Glass (macOS 26+)
//Restyle the storyboard controls to the native macOS 26 look. Older systems keep the classic style.
void ApplyLiquidGlassStyle(NSView* root) {
    if (@available(macOS 26.0, *)) {
        for (NSView* v in root.subviews) {
            if ([v isKindOfClass:[NSBox class]]) {
                NSBox* box = (NSBox*)v;
                //grouped section like System Settings: rounded, borderless, subtle fill
                if (box.boxType == NSBoxCustom && box.borderWidth > 0) {
                    box.borderWidth = 0;
                    box.cornerRadius = 14;
                    box.fillColor = [NSColor quaternarySystemFillColor];
                }
            } else if ([v isKindOfClass:[NSButton class]]) {
                NSButton* button = (NSButton*)v;
                if (button.bezelStyle == NSBezelStyleSmallSquare && button.bordered) {
                    button.bezelStyle = NSBezelStyleGlass;
                    button.controlSize = NSControlSizeLarge;
                }
            }
            ApplyLiquidGlassStyle(v);
        }
    }
}
extern int vFreeMark;
extern int vCheckSpelling;
extern int vUseModernOrthography;
extern int vSwitchKeyStatus;
extern int vQuickTelex;
extern int vRestoreIfWrongSpelling;
extern int vFixRecommendBrowser;
extern int vUseMacro;
extern int vUseMacroInEnglishMode;
extern int vSendKeyStepByStep;
extern int vUseSmartSwitchKey;
extern int vUpperCaseFirstChar;
extern int vTempOffSpelling;
extern int vAllowConsonantZFWJ;
extern int vQuickStartConsonant;
extern int vQuickEndConsonant;
extern int vRememberCode;
extern int vOtherLanguage;
extern int vTempOffOpenKey;
extern int vShowIconOnDock;
extern int vAutoCapsMacro;
extern int vFixChromiumBrowser;
extern int vPerformLayoutCompat;

@implementation ViewController {
    __weak IBOutlet NSButton *CustomSwitchCommand;
    __weak IBOutlet NSButton *CustomSwitchOption;
    __weak IBOutlet NSButton *CustomSwitchControl;
    __weak IBOutlet NSButton *CustomSwitchShift;
    __weak IBOutlet MyTextField *CustomSwitchKey;
    __weak IBOutlet NSButton *CustomBeepSound;
    NSArray* tabviews, *tabbuttons;
    NSRect tabViewRect;
    NSView* tabButtonBackground;
    NSSegmentedControl* tabSegment; //macOS 26+: native tab switcher replacing the tab buttons
    NSMutableArray* switchPairs;    //macOS 26+: [checkbox, NSSwitch, label] rows mirroring the storyboard checkboxes
}

- (void)viewDidLoad {
    [super viewDidLoad];
    viewController = self;
    CustomSwitchKey.Parent = self;
    
    self.appOK.hidden = YES;
    self.permissionWarning.hidden = YES;
    self.retryButton.enabled = NO;
 
    NSRect parentRect = self.viewParent.frame;
    parentRect.size.height = 490;
    self.viewParent.frame = parentRect;
    
    //set correct tabgroup
    tabviews = [NSArray arrayWithObjects:self.tabviewPrimary, self.tabviewMacro, self.tabviewSystem, self.tabviewInfo, nil];
    tabbuttons = [NSArray arrayWithObjects:self.tabbuttonPrimary, self.tabbuttonMacro, self.tabbuttonSystem, self.tabbuttonInfo, nil];
    NSButton* firstTabButton = [tabbuttons objectAtIndex:0];
    NSRect tabButtonBackgroundRect = firstTabButton.frame;
    for (NSButton* button in tabbuttons) {
        tabButtonBackgroundRect = NSUnionRect(tabButtonBackgroundRect, button.frame);
    }
    tabButtonBackgroundRect = NSInsetRect(tabButtonBackgroundRect, -2, -2);
    tabButtonBackground = [[NSView alloc] initWithFrame:tabButtonBackgroundRect];
    [tabButtonBackground setWantsLayer:YES];
    tabButtonBackground.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
    [self.view addSubview:tabButtonBackground];
    tabViewRect = self.tabviewPrimary.frame;
    for (NSBox* b in tabviews) {
        b.frame = tabViewRect;
    }
    
    [self setupLiquidGlass];
    [self showTab:0];
    
    NSArray* inputTypeData = [[NSArray alloc] initWithObjects:@"Telex", @"VNI", @"Simple Telex 1", @"Simple Telex 2", nil];
    NSArray* codeData = [OpenKeyManager getTableCodes];
    
    //preset data
    [_popupInputType removeAllItems];
    [_popupInputType addItemsWithTitles:inputTypeData];
    
    [self.popupCode removeAllItems];
    [self.popupCode addItemsWithTitles:codeData];
    
    [self initKey];
    
    [self fillData];
    
    // set version info
    self.VersionInfo.stringValue = [NSString stringWithFormat:@"Phiên bản %@ (build %@) - Ngày cập nhật %@",
    [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"],
    [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleVersion"],
    [OpenKeyManager getBuildDate]] ;
}

- (void)viewDidAppear {
    [super viewDidAppear];
    NSString* str = @"OpenKey %@ - Bộ gõ Tiếng Việt";
    self.view.window.title = [NSString stringWithFormat:str, [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"]];
}

- (void)viewWillAppear {
    [self initKey];
}

-(void)initKey {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![OpenKeyManager initEventTap]) {
            //self.permissionWarning.hidden = NO;
            //self.retryButton.enabled = YES;
        } else {
            //self.appOK.hidden = NO;
        }
    });
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

#define SETTINGS_ROW_HEIGHT 36.0
#define SETTINGS_ROW_INSET 14.0

//storyboard push button (as opposed to a checkbox)
static BOOL IsPushButton(NSButton* button) {
    return button.bezelStyle == NSBezelStylePush;
}

//Turn the checkboxes of a tab into System Settings style rows: title on the left, NSSwitch on the right,
//separators in between. The original checkboxes stay (hidden) as the model, so all existing actions keep working.
-(NSView*)buildSettingsRowsInBox:(NSBox*)box API_AVAILABLE(macos(26.0)) {
    NSMutableArray<NSButton*>* sources = [NSMutableArray array];
    for (NSView* v in box.contentView.subviews) {
        if ([v isKindOfClass:[NSButton class]] && !v.hidden)
            [sources addObject:(NSButton*)v];
    }
    if (sources.count == 0)
        return nil;
    //reading order: left column then right column, top to bottom; buttons last
    [sources sortUsingComparator:^NSComparisonResult(NSButton* a, NSButton* b) {
        int ka = IsPushButton(a), kb = IsPushButton(b);
        if (ka != kb) return ka < kb ? NSOrderedAscending : NSOrderedDescending;
        int ca = NSMinX(a.frame) > 200, cb = NSMinX(b.frame) > 200;
        if (ca != cb) return ca < cb ? NSOrderedAscending : NSOrderedDescending;
        return NSMinY(a.frame) > NSMinY(b.frame) ? NSOrderedAscending : NSOrderedDescending;
    }];
    
    CGFloat width = NSWidth(box.frame);
    CGFloat height = sources.count * SETTINGS_ROW_HEIGHT;
    NSView* list = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    NSInteger index = 0;
    for (NSButton* src in sources) {
        NSView* row = [[NSView alloc] initWithFrame:NSMakeRect(0, height - (index + 1) * SETTINGS_ROW_HEIGHT, width, SETTINGS_ROW_HEIGHT)];
        BOOL isPush = IsPushButton(src);
        NSString* text = isPush ? [src.title stringByReplacingOccurrencesOfString:@"..." withString:@""] : src.title;
        NSTextField* label = [NSTextField labelWithString:text];
        label.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.toolTip = src.toolTip ?: text;
        
        NSControl* control;
        if (isPush) {
            NSButton* button = [NSButton buttonWithTitle:([src.title containsString:@"Kiểm tra"] ? @"Kiểm tra" : @"Mở…")
                                                  target:src.target action:src.action];
            [button sizeToFit];
            control = button;
        } else {
            NSSwitch* sw = [[NSSwitch alloc] init];
            sw.controlSize = NSControlSizeSmall;
            sw.target = self;
            sw.action = @selector(onSettingsSwitch:);
            sw.tag = switchPairs.count;
            sw.toolTip = label.toolTip;
            [sw sizeToFit];
            [switchPairs addObject:@[src, sw, label]];
            control = sw;
        }
        src.hidden = YES;
        
        NSRect cf = control.frame;
        cf.origin.x = width - SETTINGS_ROW_INSET - NSWidth(cf);
        cf.origin.y = round((SETTINGS_ROW_HEIGHT - NSHeight(cf)) / 2);
        control.frame = cf;
        [label sizeToFit];
        NSRect lf = label.frame;
        lf.origin.x = SETTINGS_ROW_INSET;
        lf.size.width = NSMinX(cf) - 12 - SETTINGS_ROW_INSET;
        lf.origin.y = round((SETTINGS_ROW_HEIGHT - NSHeight(lf)) / 2);
        label.frame = lf;
        [row addSubview:label];
        [row addSubview:control];
        if (index > 0) {
            NSBox* separator = [[NSBox alloc] initWithFrame:NSMakeRect(SETTINGS_ROW_INSET, SETTINGS_ROW_HEIGHT - 1, width - 2 * SETTINGS_ROW_INSET, 1)];
            separator.boxType = NSBoxSeparator;
            [row addSubview:separator];
        }
        [list addSubview:row];
        index++;
    }
    [box.contentView addSubview:list];
    return list;
}

-(void)onSettingsSwitch:(NSSwitch*)sender {
    NSButton* checkbox = switchPairs[sender.tag][0];
    checkbox.state = sender.state;
    [NSApp sendAction:checkbox.action to:checkbox.target from:checkbox];
    [self syncSettingsSwitches]; //actions may enable/disable dependent options
}

-(void)syncSettingsSwitches {
    for (NSArray* pair in switchPairs) {
        NSButton* checkbox = pair[0];
        NSSwitch* sw = pair[1];
        NSTextField* label = pair[2];
        sw.state = checkbox.state;
        sw.enabled = checkbox.enabled;
        label.textColor = checkbox.enabled ? [NSColor labelColor] : [NSColor tertiaryLabelColor];
    }
}

-(void)setupLiquidGlass {
    if (@available(macOS 26.0, *)) {
        ApplyLiquidGlassStyle(self.view);
        switchPairs = [NSMutableArray array];
        
        //1. settings rows in each tab
        NSMutableArray* lists = [NSMutableArray array];
        CGFloat groupHeight = 0;
        for (NSBox* box in tabviews) {
            box.contentViewMargins = NSZeroSize;
            box.contentView.autoresizesSubviews = NO; //we position the content ourselves
            NSView* list = [self buildSettingsRowsInBox:box];
            [lists addObject:list ?: [NSNull null]];
            groupHeight = MAX(groupHeight, list ? NSHeight(list.frame) : NSHeight(box.frame));
        }
        
        //2. native tab switcher replacing the 4 push buttons
        NSMutableArray* labels = [NSMutableArray array];
        for (NSButton* button in tabbuttons) {
            [labels addObject:button.title];
            button.hidden = YES;
        }
        tabButtonBackground.hidden = YES;
        tabSegment = [NSSegmentedControl segmentedControlWithLabels:labels
                                                       trackingMode:NSSegmentSwitchTrackingSelectOne
                                                             target:self
                                                             action:@selector(onTabSegment:)];
        tabSegment.controlSize = NSControlSizeLarge;
        tabSegment.segmentDistribution = NSSegmentDistributionFillEqually;
        [tabSegment sizeToFit];
        tabSegment.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin;
        [self.view addSubview:tabSegment];
        
        //3. relayout top to bottom: control group, tabs, tab content, buttons
        NSBox* controlBox = nil;
        NSButton *quitButton = nil, *defaultButton = nil, *okButton = nil;
        for (NSView* v in self.view.subviews) {
            if ([v isKindOfClass:[NSBox class]] && [((NSBox*)v).title isEqualToString:@"Điều khiển"])
                controlBox = (NSBox*)v;
            if (![v isKindOfClass:[NSButton class]])
                continue;
            SEL action = ((NSButton*)v).action;
            if (action == @selector(onTerminateApp:)) quitButton = (NSButton*)v;
            else if (action == @selector(onDefaultConfig:)) defaultButton = (NSButton*)v;
            else if (action == @selector(onOK:)) okButton = (NSButton*)v;
        }
        if (controlBox == nil)
            return;
        
        const CGFloat margin = 20, gap = 14, buttonArea = 72;
        CGFloat segmentHeight = NSHeight(tabSegment.frame);
        CGFloat oldHeight = NSHeight(self.view.frame);
        CGFloat topToControlBottom = oldHeight - NSMinY(controlBox.frame);
        CGFloat newHeight = topToControlBottom + gap + segmentHeight + gap + groupHeight + buttonArea;
        NSRect viewFrame = self.view.frame;
        viewFrame.size.height = newHeight;
        self.view.frame = viewFrame; //top-anchored views follow via autoresizing
        
        CGFloat width = NSWidth(self.view.bounds);
        NSRect segmentFrame = tabSegment.frame;
        segmentFrame.size.width = MIN(MAX(NSWidth(segmentFrame), 360), width - 2 * margin);
        segmentFrame.origin.x = round((width - NSWidth(segmentFrame)) / 2);
        segmentFrame.origin.y = NSMinY(controlBox.frame) - gap - segmentHeight;
        tabSegment.frame = segmentFrame;
        
        CGFloat groupTop = NSMinY(segmentFrame) - gap;
        tabViewRect = NSMakeRect(NSMinX(controlBox.frame), groupTop - groupHeight, NSWidth(controlBox.frame), groupHeight);
        for (NSUInteger i = 0; i < tabviews.count; i++) {
            NSBox* box = tabviews[i];
            CGFloat oldContentHeight = NSHeight(box.contentView.frame);
            box.frame = tabViewRect;
            CGFloat contentHeight = NSHeight(box.contentView.frame);
            id list = lists[i];
            if (list != [NSNull null]) {
                NSRect lf = ((NSView*)list).frame;
                lf.origin.y = contentHeight - NSHeight(lf);
                ((NSView*)list).frame = lf;
            } else {
                //info tab: keep its content pinned to the top
                for (NSView* v in box.contentView.subviews) {
                    NSRect f = v.frame;
                    f.origin.y += contentHeight - oldContentHeight;
                    v.frame = f;
                }
            }
        }
        
        //4. dialog buttons: plain native buttons, default action on the right
        NSArray* buttons = @[quitButton ?: [NSNull null], defaultButton ?: [NSNull null], okButton ?: [NSNull null]];
        for (id b in buttons) {
            if (b == [NSNull null]) continue;
            NSButton* button = b;
            button.image = nil;
            button.imagePosition = NSNoImage;
            button.bezelStyle = NSBezelStyleGlass;
            button.controlSize = NSControlSizeLarge;
            button.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
            [button sizeToFit];
            NSRect f = button.frame;
            f.size.width = MAX(NSWidth(f), 110);
            f.origin.y = round((buttonArea - NSHeight(f)) / 2);
            button.frame = f;
        }
        if (okButton) {
            okButton.bezelColor = [NSColor controlAccentColor];
            okButton.keyEquivalent = @"\r";
            NSRect f = okButton.frame;
            f.origin.x = width - margin - NSWidth(f);
            okButton.frame = f;
            if (defaultButton) {
                NSRect d = defaultButton.frame;
                d.origin.x = NSMinX(f) - 12 - NSWidth(d);
                defaultButton.frame = d;
            }
        }
        if (quitButton) {
            NSRect f = quitButton.frame;
            f.origin.x = margin;
            quitButton.frame = f;
        }
        [self syncSettingsSwitches];
    }
}

-(void)onTabSegment:(NSSegmentedControl*)sender {
    [self showTab:sender.selectedSegment];
}

-(void)showTab:(NSInteger)index {
    NSRect tempRect = tabViewRect;
    tempRect.origin.y = 1000;
    for (NSBox* b in tabviews) {
        [b setHidden:YES];
        b.frame = tempRect;
    }
    for (NSButton* b in tabbuttons) {
        [b setState:NSControlStateValueOff];
    }
    NSBox* b = [tabviews objectAtIndex:index];
    [b setHidden:NO];
    b.frame = tabViewRect;
    
    NSButton* button = [tabbuttons objectAtIndex:index];
    [button setState:NSControlStateValueOn];

    [self.view addSubview:tabButtonBackground positioned:NSWindowAbove relativeTo:b];
    for (NSButton* tabButton in tabbuttons) {
        [self.view addSubview:tabButton positioned:NSWindowAbove relativeTo:nil];
    }
    if (tabSegment) {
        tabSegment.selectedSegment = index;
        [self.view addSubview:tabSegment positioned:NSWindowAbove relativeTo:nil];
        [self syncSettingsSwitches];
    }
}

- (IBAction)onTabButton:(NSButton *)sender {
    [self showTab:sender.tag];
}

- (IBAction)onInputTypeChanged:(NSPopUpButton *)sender {
    [appDelegate onInputTypeSelectedIndex:(int)[self.popupInputType indexOfSelectedItem]];
}

- (IBAction)onCodeTableChanged:(NSPopUpButton *)sender {
    [appDelegate onCodeTableChanged:(int)[self.popupCode indexOfSelectedItem]];
}

- (IBAction)onLanguageChanged:(id)sender {
    [appDelegate onInputMethodSelected];
}

- (IBAction)onRestart:(id)sender {
    self.appOK.hidden = YES;
    self.permissionWarning.hidden = YES;
    self.retryButton.enabled = NO;
    
    [self initKey];
}

- (IBAction)onFreeMark:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"FreeMark"];
    vFreeMark = (int)val;
}

- (IBAction)onModernOrthography:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"ModernOrthography"];
    vUseModernOrthography = (int)val;
}

- (IBAction)onCheckSpelling:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"Spelling"];
    vCheckSpelling = (int)val;
    [self.RestoreIfInvalidWord setEnabled:val];
    [self.AllowZWJF setEnabled:val];
    [self.TempOffSpellChecking setEnabled:val];
    OnSpellCheckingChanged();
}

- (IBAction)onShowUIOnStartup:(NSButton *)sender {
    [self setCustomValue:sender keyToSet:@"ShowUIOnStartup"];
}

- (IBAction)onRunOnStartup:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"RunOnStartup"];
    [appDelegate setRunOnStartup:val];
}

- (IBAction)onGrayIcon:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"GrayIcon"];
    [appDelegate setGrayIcon:val];
}

- (IBAction)onQuickTelex:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"QuickTelex"];
    vQuickTelex = (int)val;
}

- (IBAction)onRestoreIfInvalidWord:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"RestoreIfInvalidWord"];
    vRestoreIfWrongSpelling = (int)val;
}

- (IBAction)omTempOffSpellChecking:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"vTempOffSpelling"];
    vTempOffSpelling = (int)val;
}

- (IBAction)onAllowZFWJ:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"vAllowConsonantZFWJ"];
    vAllowConsonantZFWJ = (int)val;
}

- (IBAction)onFixRecommendBrowser:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"FixRecommendBrowser"];
    vFixRecommendBrowser = (int)val;
    [self.FixChromiumBrowser setEnabled:val];
}

- (IBAction)onControlSwitchKey:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:nil];
    vSwitchKeyStatus &= (~0x100);
    vSwitchKeyStatus |= val << 8;
    [[NSUserDefaults standardUserDefaults] setInteger:vSwitchKeyStatus forKey:@"SwitchKeyStatus"];
}

- (IBAction)onOptionSwitchKey:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:nil];
    vSwitchKeyStatus &= (~0x200);
    vSwitchKeyStatus |= val << 9;
    [[NSUserDefaults standardUserDefaults] setInteger:vSwitchKeyStatus forKey:@"SwitchKeyStatus"];
}

- (IBAction)onCommandSwitchKey:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:nil];
    vSwitchKeyStatus &= (~0x400);
    vSwitchKeyStatus |= val << 10;
    [[NSUserDefaults standardUserDefaults] setInteger:vSwitchKeyStatus forKey:@"SwitchKeyStatus"];
}

- (IBAction)onShiftSwitchKey:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:nil];
    vSwitchKeyStatus &= (~0x800);
    vSwitchKeyStatus |= val << 11;
    [[NSUserDefaults standardUserDefaults] setInteger:vSwitchKeyStatus forKey:@"SwitchKeyStatus"];
}

-(void)onMyTextFieldKeyChange:(unsigned short)keyCode character:(unsigned short)character {
    vSwitchKeyStatus &= 0xFFFFFF00;
    vSwitchKeyStatus |= keyCode;
    vSwitchKeyStatus &= 0x00FFFFFF;
    vSwitchKeyStatus |= ((unsigned int)character<<24);
    [[NSUserDefaults standardUserDefaults] setInteger:vSwitchKeyStatus forKey:@"SwitchKeyStatus"];
}

- (IBAction)onBeepSound:(NSButton *)sender {
    unsigned int val = (unsigned int)[self setCustomValue:sender keyToSet:nil];
    vSwitchKeyStatus &= (~0x8000);
    vSwitchKeyStatus |= val << 15;
    [[NSUserDefaults standardUserDefaults] setInteger:vSwitchKeyStatus forKey:@"SwitchKeyStatus"];
}

- (IBAction)onSendKeyStepByStep:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"SendKeyStepByStep"];
    vSendKeyStepByStep = (int)val;
}

- (IBAction)onPerformLayoutCompat:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"vPerformLayoutCompat"];
    vPerformLayoutCompat = (int)val;
}

- (NSInteger)setCustomValue:(NSButton*)sender keyToSet:(NSString*) key {
    NSInteger val = 0;
    if (sender.state == NSControlStateValueOn) {
        val = 1;
    } else {
        val = 0;
    }
    if (key != nil)
        [[NSUserDefaults standardUserDefaults] setInteger:val forKey:key];
    return val;
}

- (IBAction)onMacroButton:(id)sender {
    [appDelegate onMacroSelected];
}

- (IBAction)onMacroChanged:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"UseMacro"];
    vUseMacro = (int)val;
}

- (IBAction)onUseMacroInEnglishModeChanged:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"UseMacroInEnglishMode"];
    vUseMacroInEnglishMode = (int)val;
}

- (IBAction)onAutoRememberSwitchKey:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"UseSmartSwitchKey"];
    vUseSmartSwitchKey = (int)val;
}

- (IBAction)onUpperCaseFirstChar:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"UpperCaseFirstChar"];
    vUpperCaseFirstChar = (int)val;
}
- (IBAction)onQuickStartConsonant:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"vQuickStartConsonant"];
    vQuickStartConsonant = (int)val;
}

- (IBAction)onQuickEndConsonant:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"vQuickEndConsonant"];
    vQuickEndConsonant = (int)val;
}

- (IBAction)onTempOffOpenKeyByHotKey:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"vTempOffOpenKey"];
    vTempOffOpenKey = (int)val;
}

- (IBAction)onRememberTableCode:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"vRememberCode"];
    vRememberCode = (int)val;
}
- (IBAction)onOtherLanguage:(id)sender {
    
    NSInteger val = [self setCustomValue:sender keyToSet:@"vOtherLanguage"];
    vOtherLanguage = (int)val;
}


- (IBAction)onAutoCapsMacro:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"vAutoCapsMacro"];
    vAutoCapsMacro = (int)val;
}

- (IBAction)onShowIconOnDock:(id)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"vShowIconOnDock"];
    vShowIconOnDock = (int)val;
    if (!vShowIconOnDock) {
        [self.view.window close];
    }
    [appDelegate showIconOnDock:vShowIconOnDock];
}

- (IBAction)onCheckNewVersionOnStartup:(NSButton *)sender {
    NSInteger val = sender.state == NSControlStateValueOn ? 0 : 1;
    [[NSUserDefaults standardUserDefaults] setInteger:val forKey:@"DontCheckUpdate"];
}

- (IBAction)onFixChromiumBrowser:(NSButton *)sender {
    NSInteger val = [self setCustomValue:sender keyToSet:@"vFixChromiumBrowser"];
    vFixChromiumBrowser = (int)val;
}

- (IBAction)onTerminateApp:(id)sender {
    [NSApp terminate:0];
}

-(void)fillData {
    NSInteger value;
    
    NSInteger intInputMethod = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"];
    if (intInputMethod == 1) {
        self.VietButton.state = NSControlStateValueOn;
    } else if (intInputMethod == 0) {
        self.EngButton.state = NSControlStateValueOn;
    }
    
    NSInteger intInputType = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputType"];
    [self.popupInputType selectItemAtIndex:intInputType];
    
    NSInteger intCodeTable = [[NSUserDefaults standardUserDefaults] integerForKey:@"CodeTable"];
    [self.popupCode selectItemAtIndex:intCodeTable];
    
    //option
    NSInteger showui = [[NSUserDefaults standardUserDefaults] integerForKey:@"ShowUIOnStartup"];
    self.ShowUIButton.state = showui ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger freeMark = [[NSUserDefaults standardUserDefaults] integerForKey:@"FreeMark"];
    self.FreeMarkButton.state = freeMark ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger useModernOrthography = [[NSUserDefaults standardUserDefaults] integerForKey:@"ModernOrthography"];
    self.UseModernOrthography.state = useModernOrthography ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger spelling = [[NSUserDefaults standardUserDefaults] integerForKey:@"Spelling"];
    self.CheckSpellingButton.state = spelling ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger runOnStartup = [[NSUserDefaults standardUserDefaults] integerForKey:@"RunOnStartup"];
    self.RunOnStartupButton.state = runOnStartup ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger useGrayIcon = [[NSUserDefaults standardUserDefaults] integerForKey:@"GrayIcon"];
    self.UseGrayIcon.state = useGrayIcon ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger quicTelex = [[NSUserDefaults standardUserDefaults] integerForKey:@"QuickTelex"];
    self.QuickTelex.state = quicTelex ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger restoreIfInvalidWord = [[NSUserDefaults standardUserDefaults] integerForKey:@"RestoreIfInvalidWord"];
    self.RestoreIfInvalidWord.state = restoreIfInvalidWord ? NSControlStateValueOn : NSControlStateValueOff;
    [self.RestoreIfInvalidWord setEnabled:spelling];
    
    NSInteger tempOffSpelling = [[NSUserDefaults standardUserDefaults] integerForKey:@"vTempOffSpelling"];
    self.TempOffSpellChecking.state = tempOffSpelling ? NSControlStateValueOn : NSControlStateValueOff;
    [self.TempOffSpellChecking setEnabled:spelling];
    
    NSInteger allowZFWJ = [[NSUserDefaults standardUserDefaults] integerForKey:@"vAllowConsonantZFWJ"];
    self.AllowZWJF.state = allowZFWJ ? NSControlStateValueOn : NSControlStateValueOff;
    [self.AllowZWJF setEnabled:spelling];
    
    NSInteger fixRecommendBrowser = [[NSUserDefaults standardUserDefaults] integerForKey:@"FixRecommendBrowser"];
    self.FixRecommendBrowser.state = fixRecommendBrowser ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger useMacro = [[NSUserDefaults standardUserDefaults] integerForKey:@"UseMacro"];
    self.UseMacro.state = useMacro ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger useMacroInEnglish = [[NSUserDefaults standardUserDefaults] integerForKey:@"UseMacroInEnglishMode"];
    self.UseMacroInEnglishMode.state = useMacroInEnglish ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger sendKeySbS = [[NSUserDefaults standardUserDefaults] integerForKey:@"SendKeyStepByStep"];
    self.SendKeyStepByStep.state = sendKeySbS ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger useSmartSwitchKey = [[NSUserDefaults standardUserDefaults] integerForKey:@"UseSmartSwitchKey"];
    self.AutoRememberSwitchKey.state = useSmartSwitchKey ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger upperCaseFirstChar = [[NSUserDefaults standardUserDefaults] integerForKey:@"UpperCaseFirstChar"];
    self.UpperCaseFirstChar.state = upperCaseFirstChar ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger quickStartConsonant = [[NSUserDefaults standardUserDefaults] integerForKey:@"vQuickStartConsonant"];
    self.QuickStartConsonant.state = quickStartConsonant ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger quickEndConsonant = [[NSUserDefaults standardUserDefaults] integerForKey:@"vQuickEndConsonant"];
    self.QuickEndConsonant.state = quickEndConsonant ? NSControlStateValueOn : NSControlStateValueOff;
    
    value = [[NSUserDefaults standardUserDefaults] integerForKey:@"vRememberCode"];
    self.RememberTableCode.state = value ? NSControlStateValueOn : NSControlStateValueOff;
    
    value = [[NSUserDefaults standardUserDefaults] integerForKey:@"vOtherLanguage"];
    self.OtherLanguage.state = value ? NSControlStateValueOn : NSControlStateValueOff;
    
    value = [[NSUserDefaults standardUserDefaults] integerForKey:@"vTempOffOpenKey"];
    self.TempOffOpenKey.state = value ? NSControlStateValueOn : NSControlStateValueOff;
    
    value = [[NSUserDefaults standardUserDefaults] integerForKey:@"vAutoCapsMacro"];
    self.AutoCapsMacro.state = value ? NSControlStateValueOn : NSControlStateValueOff;
    
    value = [[NSUserDefaults standardUserDefaults] integerForKey:@"vShowIconOnDock"];
    self.ShowIconOnDock.state = value ? NSControlStateValueOn : NSControlStateValueOff;
    
    value = [[NSUserDefaults standardUserDefaults] integerForKey:@"DontCheckUpdate"];
    self.CheckNewVersionOnStartup.state = value ? NSControlStateValueOff :NSControlStateValueOn;
    
    value = [[NSUserDefaults standardUserDefaults] integerForKey:@"vFixChromiumBrowser"];
    self.FixChromiumBrowser.state = value ? NSControlStateValueOn : NSControlStateValueOff;
    self.FixChromiumBrowser.enabled = fixRecommendBrowser ? YES : NO;
    
    value = [[NSUserDefaults standardUserDefaults] integerForKey:@"vPerformLayoutCompat"];
    self.PerformLayoutCompat.state = value ? NSControlStateValueOn : NSControlStateValueOff;
    
    CustomSwitchControl.state = (vSwitchKeyStatus & 0x100) ? NSControlStateValueOn : NSControlStateValueOff;
    CustomSwitchOption.state = (vSwitchKeyStatus & 0x200) ? NSControlStateValueOn : NSControlStateValueOff;
    CustomSwitchCommand.state = (vSwitchKeyStatus & 0x400) ? NSControlStateValueOn : NSControlStateValueOff;
    CustomSwitchShift.state = (vSwitchKeyStatus & 0x800) ? NSControlStateValueOn : NSControlStateValueOff;
    CustomBeepSound.state = (vSwitchKeyStatus & 0x8000) ? NSControlStateValueOn : NSControlStateValueOff;
    [CustomSwitchKey setTextByChar:((vSwitchKeyStatus>>24) & 0xFF)];
    
    [self syncSettingsSwitches];
}

- (IBAction)onOK:(id)sender {
    [self.view.window close];
}

- (IBAction)onDefaultConfig:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Bạn có chắc chắn muốn thiết lập lại cấu hình mặc định?"];
    [alert addButtonWithTitle:@"Có"];
    [alert addButtonWithTitle:@"Không"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == 1000) {
            [appDelegate loadDefaultConfig];
            [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"ShowUIOnStartup"];
            self.ShowUIButton.state = NSControlStateValueOff;
            
            [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"RunOnStartup"];
            self.RunOnStartupButton.state = NSControlStateValueOn;
        }
    }];
}

- (IBAction)onHomePageLink:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString:@"https://open-key.org"]];
}

- (IBAction)onFanpageLink:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString:@"https://www.facebook.com/OpenKeyVN"]];
}

- (IBAction)onEmailLink:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString:@"mailto:maivutuyen.91@gmail.com"]];
}

- (IBAction)onSourceCode:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString:@"https://github.com/tuyenvm/OpenKey"]];
}

- (IBAction)onCheckNewVersionButton:(id)sender {
    self.CheckNewVersionButton.title = @"Đang kiểm tra...";
    self.CheckNewVersionButton.enabled = false;
    
    [OpenKeyManager checkNewVersion:self.view.window callbackFunc:^{
        self.CheckNewVersionButton.enabled = true;
        self.CheckNewVersionButton.title = @"Kiểm tra bản mới...";
    }];
}

@end
