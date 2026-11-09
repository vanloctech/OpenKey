//
//  AppDelegate.m
//  ModernKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#include <libproc.h>
#import <IOKit/IOKitLib.h>
#import <UserNotifications/UserNotifications.h>
#include <sys/proc_info.h>
#import "AppDelegate.h"
#import "ViewController.h"
#import "OpenKeyManager.h"
#import "MJAccessibilityUtils.h"

AppDelegate* appDelegate;
extern ViewController* viewController;
extern void OnTableCodeChange(void);
extern void OnInputMethodChanged(void);
extern void RequestNewSession(void);
extern void OnActiveAppChanged(void);

//see document in Engine.h
int vLanguage = 1;
int vInputType = 0;
int vFreeMark = 0;
int vCodeTable = 0;
int vCheckSpelling = 1;
int vUseModernOrthography = 1;
int vQuickTelex = 0;
#define DEFAULT_SWITCH_STATUS 0x7A000206 //default option + z
int vSwitchKeyStatus = DEFAULT_SWITCH_STATUS;
int vRestoreIfWrongSpelling = 0;
int vFixRecommendBrowser = 1;
int vUseMacro = 1;
int vUseMacroInEnglishMode = 1;
int vAutoCapsMacro = 0;
int vSendKeyStepByStep = 0;
int vUseSmartSwitchKey = 1;
int vUpperCaseFirstChar = 0;
int vTempOffSpelling = 0;
int vAllowConsonantZFWJ = 0;
int vQuickStartConsonant = 0;
int vQuickEndConsonant = 0;
int vRememberCode = 1; //new on version 2.0
int vOtherLanguage = 1; //new on version 2.0
int vTempOffOpenKey = 0; //new on version 2.0

int vShowIconOnDock = 0; //new on version 2.0

int vPerformLayoutCompat = 0;

//beta feature
int vFixChromiumBrowser = 0; //new on version 2.0

extern int convertToolHotKey;
extern bool convertToolDontAlertWhenCompleted;

@interface AppDelegate ()

@end


@implementation AppDelegate {
    NSWindowController *_mainWC;
    NSWindowController *_macroWC;
    NSWindowController *_convertWC;
    NSWindowController *_aboutWC;
    
    NSStatusItem *statusItem;
    NSMenu *theMenu;
    
    NSMenuItem* menuInputMethod;
    
    NSMenuItem* mnuTelex;
    NSMenuItem* mnuVNI;
    NSMenuItem* mnuSimpleTelex1;
    NSMenuItem* mnuSimpleTelex2;
    
    NSMenuItem* mnuUnicode;
    NSMenuItem* mnuTCVN;
    NSMenuItem* mnuVNIWindows;
    
    NSMenuItem* mnuUnicodeComposite;
    NSMenuItem* mnuVietnameseLocaleCP1258;
    
    NSMenuItem* mnuQuickConvert;
    
    NSMenuItem* mnuSecureInputWarning;
    NSTimer* secureInputTimer;
    pid_t lastSecureInputPID;
    NSString* inputSourceBeforeFallback; //input source to restore when Secure Input is released
    NSString* fallbackInputSourceID;     //Apple Vietnamese input source we switched to
    NSDate* secureInputSince;            //when the current Secure Input episode started
    BOOL secureInputStuckNotified;
    BOOL openKeyStarted;
    BOOL systemSleeping;
    BOOL permissionLost;
    int permissionFailCount;
}

-(void)askPermission {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText: [NSString stringWithFormat:@"OpenKey cần bạn cấp quyền để có thể hoạt động!"]];
    [alert setInformativeText:@"Bật OpenKey trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng. Nếu OpenKey đã có trong danh sách mà vẫn không chạy, hãy xoá mục đó (nút \"−\") rồi thêm lại. OpenKey sẽ tự hoạt động ngay khi được cấp quyền."];

    [alert addButtonWithTitle:@"Không"];
    [alert addButtonWithTitle:@"Cấp quyền"];

    [alert.window makeKeyAndOrderFront:nil];
    [alert.window setLevel:NSStatusWindowLevel];

    NSModalResponse res = [alert runModal];

    if (res != NSAlertSecondButtonReturn) {
        [NSApp terminate:0];
        return;
    }
    
    MJAccessibilityOpenPanel();
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
    
    //keep running and wait until the permission is granted, then start normally
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        if (MJAccessibilityIsEnabled()) {
            [timer invalidate];
            [self startOpenKey];
        }
    }];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    appDelegate = self;
    
    [self registerSupportedNotification];
    
    //set quick tooltip
    [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: 50]
                                              forKey: @"NSInitialToolTipDelay"];
    
    //check whether this app has been launched before that or not
    //Only check instances owned by current user (for multi-user/Fast User Switching support)
    uid_t currentUID = getuid();
    NSArray<NSRunningApplication *>* runningApps = [[NSWorkspace sharedWorkspace] runningApplications];
    pid_t myPID = [[NSProcessInfo processInfo] processIdentifier];
    BOOL alreadyRunning = NO;

    for (NSRunningApplication *app in runningApps) {
        if ([app.bundleIdentifier isEqualToString:OPENKEY_BUNDLE] &&
            app.processIdentifier != myPID) {
            pid_t pid = app.processIdentifier;
            struct proc_bsdinfo proc;
            int size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &proc, sizeof(proc));
            if (size == sizeof(proc) && proc.pbi_uid == currentUID) {
                alreadyRunning = YES;
                break;
            }
        }
    }

    if (alreadyRunning) {
        [NSApp terminate:nil];
        return;
    }
    
    // check if user granted Accessabilty permission
    if (!MJAccessibilityIsEnabled()) {
        [self askPermission];
        return;
    }
    
    [self startOpenKey];
}

-(void)startOpenKey {
    vShowIconOnDock = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"vShowIconOnDock"];
    if (vShowIconOnDock)
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
    
    if (vSwitchKeyStatus & 0x8000)
        NSBeep();

    openKeyStarted = YES;
    [self createStatusBarMenu];
    [self startSecureInputWatcher];
    
    //init
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![OpenKeyManager initEventTap]) {
            [self onControlPanelSelected];
        } else {
            NSInteger showui = [[NSUserDefaults standardUserDefaults] integerForKey:@"ShowUIOnStartup"];
            if (showui == 1) {
                [self onControlPanelSelected];
            }
        }
        [self setQuickConvertString];
    });
    
    //load default config if is first launch
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"NonFirstTime"] == 0) {
        [self loadDefaultConfig];
    }
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"NonFirstTime"];
    
    //check update if enable
    NSInteger dontCheckUpdate = [[NSUserDefaults standardUserDefaults] integerForKey:@"DontCheckUpdate"];
    if (!dontCheckUpdate)
        [OpenKeyManager checkNewVersion:nil callbackFunc:nil];
    
    //correct run on startup
    NSInteger val = [[NSUserDefaults standardUserDefaults] integerForKey:@"RunOnStartup"];
    [appDelegate setRunOnStartup:val];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self onControlPanelSelected];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

-(void) createStatusBarMenu {
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.image = [NSImage imageNamed:@"Status"];
    statusItem.button.alternateImage = [NSImage imageNamed:@"StatusHighlighted"];
    
    theMenu = [[NSMenu alloc] initWithTitle:@""];
    [theMenu setAutoenablesItems:NO];
    
    mnuSecureInputWarning = [theMenu addItemWithTitle:@"" action:@selector(onWarningSelected) keyEquivalent:@""];
    mnuSecureInputWarning.target = self;
    mnuSecureInputWarning.enabled = YES;
    mnuSecureInputWarning.hidden = YES;
    
    menuInputMethod = [theMenu addItemWithTitle:@"Bật Tiếng Việt"
                                                     action:@selector(onInputMethodSelected)
                                              keyEquivalent:@""];
    [theMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* menuInputType = [theMenu addItemWithTitle:@"Kiểu gõ" action:nil keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    mnuUnicode = [theMenu addItemWithTitle:@"Unicode dựng sẵn" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuUnicode.tag = 0;
    mnuTCVN = [theMenu addItemWithTitle:@"TCVN3 (ABC)" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuTCVN.tag = 1;
    mnuVNIWindows = [theMenu addItemWithTitle:@"VNI Windows" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuVNIWindows.tag = 2;
    NSMenuItem* menuCode = [theMenu addItemWithTitle:@"Bảng mã khác" action:nil keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:@"Công cụ chuyển mã..." action:@selector(onConvertTool) keyEquivalent:@""];
    mnuQuickConvert = [theMenu addItemWithTitle:@"Chuyển mã nhanh" action:@selector(onQuickConvert) keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:@"Bảng điều khiển..." action:@selector(onControlPanelSelected) keyEquivalent:@""];
    [theMenu addItemWithTitle:@"Gõ tắt..." action:@selector(onMacroSelected) keyEquivalent:@""];
    [theMenu addItemWithTitle:@"Giới thiệu" action:@selector(onAboutSelected) keyEquivalent:@""];
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:@"Thoát" action:@selector(terminate:) keyEquivalent:@"q"];
    
    
    [self setInputTypeMenu:menuInputType];
    [self setCodeMenu:menuCode];
    
    //set menu
    [statusItem setMenu:theMenu];
    
    [self fillData];
}

-(void)setQuickConvertString {
    NSMutableString* hotKey = [NSMutableString stringWithString:@""];
    bool hasAdd = false;
    if (convertToolHotKey & 0x100) {
        [hotKey appendString:@"⌃"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x200) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⌥"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x400) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⌘"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x800) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⇧"];
        hasAdd = true;
    }
    
    unsigned short k = ((convertToolHotKey>>24) & 0xFF);
    if (k != 0xFE) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        if (k == kVK_Space)
            [hotKey appendFormat:@"%@", @"␣ "];
        else
            [hotKey appendFormat:@"%c", k];
    }
    [mnuQuickConvert setTitle: hasAdd ? [NSString stringWithFormat:@"Chuyển mã nhanh - [%@]", [hotKey uppercaseString]] : @"Chuyển mã nhanh"];
}

-(void)loadDefaultConfig {
    vLanguage = 1; [[NSUserDefaults standardUserDefaults] setInteger:vLanguage forKey:@"InputMethod"];
    vInputType = 0; [[NSUserDefaults standardUserDefaults] setInteger:vInputType forKey:@"InputType"];
    vFreeMark = 0; [[NSUserDefaults standardUserDefaults] setInteger:vFreeMark forKey:@"FreeMark"];
    vCheckSpelling = 1; [[NSUserDefaults standardUserDefaults] setInteger:vCheckSpelling forKey:@"Spelling"];
    vCodeTable = 0; [[NSUserDefaults standardUserDefaults] setInteger:vCodeTable forKey:@"CodeTable"];
    vSwitchKeyStatus = DEFAULT_SWITCH_STATUS; [[NSUserDefaults standardUserDefaults] setInteger:vCodeTable forKey:@"SwitchKeyStatus"];
    vQuickTelex = 0; [[NSUserDefaults standardUserDefaults] setInteger:vQuickTelex forKey:@"QuickTelex"];
    vUseModernOrthography = 0; [[NSUserDefaults standardUserDefaults] setInteger:vUseModernOrthography forKey:@"ModernOrthography"];
    vRestoreIfWrongSpelling = 0; [[NSUserDefaults standardUserDefaults] setInteger:vRestoreIfWrongSpelling forKey:@"RestoreIfInvalidWord"];
    vFixRecommendBrowser = 1; [[NSUserDefaults standardUserDefaults] setInteger:vFixRecommendBrowser forKey:@"FixRecommendBrowser"];
    vUseMacro = 1; [[NSUserDefaults standardUserDefaults] setInteger:vUseMacro forKey:@"UseMacro"];
    vUseMacroInEnglishMode = 0; [[NSUserDefaults standardUserDefaults] setInteger:vUseMacroInEnglishMode forKey:@"UseMacroInEnglishMode"];
    vSendKeyStepByStep = 0;[[NSUserDefaults standardUserDefaults] setInteger:vUseMacroInEnglishMode forKey:@"SendKeyStepByStep"];
    vUseSmartSwitchKey = 1;[[NSUserDefaults standardUserDefaults] setInteger:vUseSmartSwitchKey forKey:@"UseSmartSwitchKey"];
    vUpperCaseFirstChar = 0;[[NSUserDefaults standardUserDefaults] setInteger:vUpperCaseFirstChar forKey:@"UpperCaseFirstChar"];
    vTempOffSpelling = 0;[[NSUserDefaults standardUserDefaults] setInteger:vTempOffSpelling forKey:@"vTempOffSpelling"];
    vAllowConsonantZFWJ = 0;[[NSUserDefaults standardUserDefaults] setInteger:vAllowConsonantZFWJ forKey:@"vAllowConsonantZFWJ"];
    vQuickStartConsonant = 0;[[NSUserDefaults standardUserDefaults] setInteger:vQuickStartConsonant forKey:@"vQuickStartConsonant"];
    vQuickEndConsonant = 0;[[NSUserDefaults standardUserDefaults] setInteger:vQuickEndConsonant forKey:@"vQuickEndConsonant"];
    vRememberCode = 1;[[NSUserDefaults standardUserDefaults] setInteger:vRememberCode forKey:@"vRememberCode"];
    vOtherLanguage = 1;[[NSUserDefaults standardUserDefaults] setInteger:vOtherLanguage forKey:@"vOtherLanguage"];
    vTempOffOpenKey = 0;[[NSUserDefaults standardUserDefaults] setInteger:vTempOffOpenKey forKey:@"vTempOffOpenKey"];
    vShowIconOnDock = 0;[[NSUserDefaults standardUserDefaults] setInteger:vShowIconOnDock forKey:@"vShowIconOnDock"];
    vFixChromiumBrowser = 0;[[NSUserDefaults standardUserDefaults] setInteger:vFixChromiumBrowser forKey:@"vFixChromiumBrowser"];
    vPerformLayoutCompat = 0;[[NSUserDefaults standardUserDefaults] setInteger:vPerformLayoutCompat forKey:@"vPerformLayoutCompat"];

    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"GrayIcon"];
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"RunOnStartup"];

    [self fillData];
    [viewController fillData];
}

-(void)setRunOnStartup:(BOOL)val {
    CFStringRef appId = (__bridge CFStringRef)@"com.tuyenmai.OpenKeyHelper";
    SMLoginItemSetEnabled(appId, val);
}

-(void)setGrayIcon:(BOOL)val {
    [self fillData];
}

-(void)showIconOnDock:(BOOL)val {
    [NSApp setActivationPolicy: val ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
}

#pragma mark -StatusBar menu data

- (void)setInputTypeMenu:(NSMenuItem*) parent {
    //sub for Kieu Go
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@""];
    [sub setAutoenablesItems:NO];
    mnuTelex = [sub addItemWithTitle:@"Telex" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuTelex.tag = 0;
    mnuVNI = [sub addItemWithTitle:@"VNI" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuVNI.tag = 1;
    mnuSimpleTelex1 = [sub addItemWithTitle:@"Simple Telex 1" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuSimpleTelex1.tag = 2;
    mnuSimpleTelex2 = [sub addItemWithTitle:@"Simple Telex 2" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuSimpleTelex2.tag = 3;
    [theMenu setSubmenu:sub forItem:parent];
}

- (void)setCodeMenu:(NSMenuItem*) parent {
    //sub for Code
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@""];
    [sub setAutoenablesItems:NO];
    mnuUnicodeComposite = [sub addItemWithTitle:@"Unicode tổ hợp" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuUnicodeComposite.tag = 3;
    mnuVietnameseLocaleCP1258 = [sub addItemWithTitle:@"Vietnamese Locale CP 1258" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuVietnameseLocaleCP1258.tag = 4;
    
    [theMenu setSubmenu:sub forItem:parent];
}

- (void) fillData {
    //fill data
    NSInteger intInputMethod = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"];
    NSInteger grayIcon = [[NSUserDefaults standardUserDefaults] integerForKey:@"GrayIcon"];
    if (intInputMethod == 1) {
        [menuInputMethod setState:NSControlStateValueOn];
        statusItem.button.image = [NSImage imageNamed:@"Status"];
        [statusItem.button.image setTemplate:(grayIcon ? YES : NO)];
        statusItem.button.alternateImage = [NSImage imageNamed:@"StatusHighlighted"];
    } else {
        [menuInputMethod setState:NSControlStateValueOff];
        statusItem.button.image = [NSImage imageNamed:@"StatusEng"];
        [statusItem.button.image setTemplate:(grayIcon ? YES : NO)];
        statusItem.button.alternateImage = [NSImage imageNamed:@"StatusHighlightedEng"];
    }
    vLanguage = (int)intInputMethod;
    
    NSInteger intInputType = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputType"];
    [mnuTelex setState:NSControlStateValueOff];
    [mnuVNI setState:NSControlStateValueOff];
    [mnuSimpleTelex1 setState:NSControlStateValueOff];
    [mnuSimpleTelex2 setState:NSControlStateValueOff];
    if (intInputType == 0) {
        [mnuTelex setState:NSControlStateValueOn];
    } else if (intInputType == 1) {
        [mnuVNI setState:NSControlStateValueOn];
    } else if (intInputType == 2) {
        [mnuSimpleTelex1 setState:NSControlStateValueOn];
    } else if (intInputType == 3) {
        [mnuSimpleTelex2 setState:NSControlStateValueOn];
    }
    vInputType = (int)intInputType;
    
    NSInteger intSwitchKeyStatus = [[NSUserDefaults standardUserDefaults] integerForKey:@"SwitchKeyStatus"];
    vSwitchKeyStatus = (int)intSwitchKeyStatus;
    if (vSwitchKeyStatus == 0)
        vSwitchKeyStatus = DEFAULT_SWITCH_STATUS;
    
    NSInteger intCode = [[NSUserDefaults standardUserDefaults] integerForKey:@"CodeTable"];
    [mnuUnicode setState:NSControlStateValueOff];
    [mnuTCVN setState:NSControlStateValueOff];
    [mnuVNIWindows setState:NSControlStateValueOff];
    [mnuUnicodeComposite setState:NSControlStateValueOff];
    [mnuVietnameseLocaleCP1258 setState:NSControlStateValueOff];
    if (intCode == 0) {
        [mnuUnicode setState:NSControlStateValueOn];
    } else if (intCode == 1) {
        [mnuTCVN setState:NSControlStateValueOn];
    } else if (intCode == 2) {
        [mnuVNIWindows setState:NSControlStateValueOn];
    } else if (intCode == 3) {
        [mnuUnicodeComposite setState:NSControlStateValueOn];
    } else if (intCode == 4) {
        [mnuVietnameseLocaleCP1258 setState:NSControlStateValueOn];
    }
    vCodeTable = (int)intCode;
    
    //
    NSInteger intRunOnStartup = [[NSUserDefaults standardUserDefaults] integerForKey:@"RunOnStartup"];
    [self setRunOnStartup:intRunOnStartup ? YES : NO];

}

-(void)onImputMethodChanged:(BOOL)willNotify {
    NSInteger intInputMethod = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"];
    if (intInputMethod == 0)
        intInputMethod = 1;
    else
        intInputMethod = 0;
    vLanguage = (int)intInputMethod;
    [[NSUserDefaults standardUserDefaults] setInteger:intInputMethod forKey:@"InputMethod"];

    [self fillData];
    [viewController fillData];
    
    if (willNotify)
        OnInputMethodChanged();
}

#pragma mark -StatusBar menu action
- (void)onInputMethodSelected {
    [self onImputMethodChanged:YES];
}

- (void)onInputTypeSelected:(id)sender {
    NSMenuItem *menuItem = (NSMenuItem*) sender;
    [self onInputTypeSelectedIndex:(int)menuItem.tag];
}

- (void)onInputTypeSelectedIndex:(int)index {
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"InputType"];
    vInputType = index;
    [self fillData];
    [viewController fillData];
}

- (void)onCodeTableChanged:(int)index {
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"CodeTable"];
    vCodeTable = index;
    [self fillData];
    [viewController fillData];
    OnTableCodeChange();
}

- (void)onCodeSelected:(id)sender {
    NSMenuItem *menuItem = (NSMenuItem*) sender;
    [self onCodeTableChanged:(int)menuItem.tag];
}

-(void)onConvertTool {
    if (_convertWC == nil) {
        _convertWC = [[NSStoryboard storyboardWithName:@"Main" bundle:nil] instantiateControllerWithIdentifier:@"ConvertWindow"];
    }
    //[OpenKeyManager showDockIcon:YES];
    if ([_convertWC.window isVisible])
        return;
    [_convertWC.window makeKeyAndOrderFront:nil];
    [_convertWC.window setLevel:NSFloatingWindowLevel];
}

-(void)onQuickConvert {
    if ([OpenKeyManager quickConvert]) {
        if (!convertToolDontAlertWhenCompleted) {
            [OpenKeyManager showMessage: nil message:@"Chuyển mã thành công!" subMsg:@"Kết quả đã được lưu trong clipboard."];
        }
    } else {
        [OpenKeyManager showMessage: nil message:@"Không có dữ liệu trong clipboard!" subMsg:@"Hãy sao chép một đoạn text để chuyển đổi!"];
    }
}

-(void) onControlPanelSelected {
    if (_mainWC == nil) {
        _mainWC = [[NSStoryboard storyboardWithName:@"Main" bundle:nil] instantiateControllerWithIdentifier:@"OpenKey"];
    }
    //[OpenKeyManager showDockIcon:YES];
    if ([_mainWC.window isVisible]) {
        return;
    }
    [_mainWC.window makeKeyAndOrderFront:nil];
    [_mainWC.window setLevel:NSFloatingWindowLevel];
}

-(void) onMacroSelected {
    if (_macroWC == nil) {
        _macroWC = [[NSStoryboard storyboardWithName:@"Main" bundle:nil] instantiateControllerWithIdentifier:@"MacroWindow"];
    }
    //[OpenKeyManager showDockIcon:YES];
    if ([_macroWC.window isVisible])
        return;
    
    [_macroWC.window makeKeyAndOrderFront:nil];
    [_macroWC.window setLevel:NSFloatingWindowLevel];
}

-(void) onAboutSelected {
    if (_aboutWC == nil) {
        _aboutWC = [[NSStoryboard storyboardWithName:@"Main" bundle:nil] instantiateControllerWithIdentifier:@"AboutWindow"];
    }
    //[OpenKeyManager showDockIcon:YES];
    if ([_aboutWC.window isVisible])
        return;

    [_aboutWC.window makeKeyAndOrderFront:nil];
    [_aboutWC.window setLevel:NSFloatingWindowLevel];
}

#pragma mark -Short key event
-(void)onSwitchLanguage {
    [self onInputMethodSelected];
    [viewController fillData];
}

#pragma mark Secure Input watcher
//When any app enables Secure Event Input (password fields, Terminal "Secure Keyboard Entry",
//or an app that forgets to turn it off), macOS stops delivering key events to OpenKey.
//It cannot be bypassed, but we can tell the user which app is holding it.
-(pid_t)currentSecureInputPID {
    if (!IsSecureEventInputEnabled())
        return 0;
    //Note: CGSessionCopyCurrentDictionary() reports the frontmost app's PID here, not the owner.
    //The real owner is published by WindowServer in IORegistry (IOConsoleUsers).
    pid_t result = -1;
    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    if (root == MACH_PORT_NULL)
        return result;
    NSArray* users = (__bridge_transfer NSArray*)IORegistryEntryCreateCFProperty(root, CFSTR("IOConsoleUsers"), kCFAllocatorDefault, 0);
    IOObjectRelease(root);
    uid_t uid = getuid();
    for (NSDictionary* user in users) {
        if (![user isKindOfClass:[NSDictionary class]])
            continue;
        NSNumber* userID = user[@"kCGSSessionUserIDKey"];
        NSNumber* pid = user[@"kCGSSessionSecureInputPID"];
        if (pid && (!userID || userID.unsignedIntValue == uid)) {
            result = (pid_t)pid.intValue;
            break;
        }
    }
    return result;
}

-(NSString*)appNameForPID:(pid_t)pid {
    if (pid <= 0)
        return @"không xác định";
    NSRunningApplication* app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (app.localizedName)
        return [NSString stringWithFormat:@"%@ (PID %d)", app.localizedName, pid];
    char name[PROC_PIDPATHINFO_MAXSIZE] = {0};
    if (proc_name(pid, name, sizeof(name)) > 0)
        return [NSString stringWithFormat:@"%s (PID %d)", name, pid];
    return [NSString stringWithFormat:@"PID %d", pid];
}

#pragma mark Fallback to Apple's Vietnamese input source
//While Secure Input is on, macOS blocks every third-party input method (event taps and InputMethodKit
//alike) but still runs Apple's own Vietnamese input sources. Switch to one of them so the user can keep
//typing Vietnamese, and switch back when Secure Input is released.

static NSString* InputSourceID(TISInputSourceRef source) {
    return source ? (__bridge NSString*)TISGetInputSourceProperty(source, kTISPropertyInputSourceID) : nil;
}

static TISInputSourceRef CopyInputSourceWithID(NSString* sourceID) {
    if (sourceID == nil)
        return NULL;
    NSArray* list = (__bridge_transfer NSArray*)TISCreateInputSourceList((__bridge CFDictionaryRef)@{(__bridge id)kTISPropertyInputSourceID: sourceID}, false);
    if (list.count == 0)
        return NULL;
    return (TISInputSourceRef)CFRetain((__bridge CFTypeRef)list.firstObject);
}

//enabled Apple Vietnamese input mode that best matches the OpenKey input type
-(TISInputSourceRef)copyAppleVietnameseInputSource {
    NSArray* preferred = vInputType == 1
        ? @[@"com.apple.inputmethod.VietnameseIM.VietnameseVNI"]
        : @[@"com.apple.inputmethod.VietnameseIM.VietnameseSimpleTelex", @"com.apple.inputmethod.VietnameseIM.VietnameseTelex"];
    for (NSString* sourceID in preferred) {
        TISInputSourceRef source = CopyInputSourceWithID(sourceID);
        if (source)
            return source;
    }
    NSArray* list = (__bridge_transfer NSArray*)TISCreateInputSourceList((__bridge CFDictionaryRef)@{
        (__bridge id)kTISPropertyBundleID: @"com.apple.inputmethod.VietnameseIM",
        (__bridge id)kTISPropertyInputSourceIsSelectCapable: @YES}, false);
    return list.count ? (TISInputSourceRef)CFRetain((__bridge CFTypeRef)list.firstObject) : NULL;
}

//returns the localized name of the input source we switched to, nil if none is available
-(NSString*)switchToAppleVietnamese {
    if (fallbackInputSourceID)
        return nil;
    TISInputSourceRef target = [self copyAppleVietnameseInputSource];
    if (target == NULL)
        return nil;
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    NSString* currentID = InputSourceID(current);
    NSString* name = (__bridge NSString*)TISGetInputSourceProperty(target, kTISPropertyLocalizedName);
    BOOL switched = NO;
    if (![currentID isEqualToString:InputSourceID(target)] && TISSelectInputSource(target) == noErr) {
        inputSourceBeforeFallback = [currentID copy];
        fallbackInputSourceID = [InputSourceID(target) copy];
        switched = YES;
    }
    name = [name copy];
    if (current) CFRelease(current);
    CFRelease(target);
    return switched ? name : nil;
}

-(void)restoreInputSourceAfterFallback {
    if (fallbackInputSourceID == nil)
        return;
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    //only switch back if the user did not pick another input source meanwhile
    if ([InputSourceID(current) isEqualToString:fallbackInputSourceID]) {
        TISInputSourceRef previous = CopyInputSourceWithID(inputSourceBeforeFallback);
        if (previous) {
            TISSelectInputSource(previous);
            CFRelease(previous);
        }
    }
    if (current) CFRelease(current);
    inputSourceBeforeFallback = nil;
    fallbackInputSourceID = nil;
}

#pragma mark Warning UI
-(void)showWarning:(NSString*)msg hint:(NSString*)hint {
    statusItem.button.title = @"⚠";
    statusItem.button.imagePosition = NSImageLeft;
    statusItem.button.toolTip = [NSString stringWithFormat:@"%@\n%@", msg, hint];
    mnuSecureInputWarning.title = msg;
    mnuSecureInputWarning.toolTip = hint;
    mnuSecureInputWarning.hidden = NO;
}

-(void)clearWarning {
    statusItem.button.title = @"";
    statusItem.button.toolTip = nil;
    mnuSecureInputWarning.hidden = YES;
}

-(void)onWarningSelected {
    if (permissionLost) {
        MJAccessibilityOpenPanel();
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = mnuSecureInputWarning.title ?: @"";
    alert.informativeText = mnuSecureInputWarning.toolTip ?: @"";
    [alert addButtonWithTitle:@"OK"];
    [alert.window setLevel:NSStatusWindowLevel];
    [NSApp activateIgnoringOtherApps:YES];
    [alert runModal];
}

-(void)postNotification:(NSString*)title body:(NSString*)body {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                          completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (!granted)
            return; //the menu bar warning still explains the problem
        UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
        content.title = title;
        content.body = body;
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:@"OpenKeyWarning"
                                                                              content:content
                                                                              trigger:nil];
        [center addNotificationRequest:request withCompletionHandler:nil];
    }];
}

#pragma mark Secure Input advice
//what the user can do about the app currently holding Secure Input
-(NSString*)adviceForSecureInputPID:(pid_t)pid {
    if (pid <= 0)
        return @"Thoát các app đang có ô mật khẩu. Nếu vẫn bị, hãy đăng xuất hoặc khởi động lại máy.";
    if (kill(pid, 0) == -1 && errno == ESRCH)
        return @"App giữ Secure Input đã thoát nhưng macOS không nhả (lỗi của macOS). Chỉ có thể gỡ bằng cách đăng xuất hoặc khởi động lại máy.";
    
    char name[PROC_PIDPATHINFO_MAXSIZE] = {0};
    proc_name(pid, name, sizeof(name));
    if (strcmp(name, "loginwindow") == 0)
        return @"Màn hình khoá/đăng nhập không nhả Secure Input (lỗi của macOS). Thử khoá rồi mở khoá màn hình lại (⌃⌘Q); nếu vẫn bị thì đăng xuất hoặc khởi động lại máy.";
    
    NSString* bundleID = [NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier.lowercaseString ?: @"";
    if ([bundleID isEqualToString:@"com.apple.terminal"])
        return @"Tắt menu Terminal → Secure Keyboard Entry (Nhập bàn phím an toàn).";
    if ([bundleID isEqualToString:@"com.googlecode.iterm2"])
        return @"Tắt menu iTerm2 → Secure Keyboard Entry.";
    for (NSString* key in @[@"1password", @"bitwarden", @"keepass", @"lastpass", @"dashlane", @"enpass", @"com.apple.passwords", @"keychainaccess"]) {
        if ([bundleID containsString:key])
            return @"Khoá hoặc đóng cửa sổ của trình quản lý mật khẩu này.";
    }
    for (NSString* key in @[@"chrome", @"chromium", @"safari", @"firefox", @"edge", @"brave", @"opera", @"vivaldi", @"arc", @"thebrowser", @"coccoc"]) {
        if ([bundleID containsString:key])
            return @"Bấm ra ngoài ô mật khẩu hoặc đóng tab đăng nhập. Nếu vẫn bị, thoát hẳn trình duyệt (⌘Q).";
    }
    return @"Bấm ra ngoài ô mật khẩu trong app đó hoặc thoát app (⌘Q). Nếu vẫn bị, đăng xuất hoặc khởi động lại máy.";
}

#define SECURE_INPUT_STUCK_SECONDS 30

-(void)checkSecureInput {
    pid_t pid = [self currentSecureInputPID];
    if (pid == lastSecureInputPID) {
        //tell the user once if Secure Input is held for too long
        if (pid != 0 && !secureInputStuckNotified && secureInputSince &&
            -[secureInputSince timeIntervalSinceNow] >= SECURE_INPUT_STUCK_SECONDS) {
            secureInputStuckNotified = YES;
            NSString* body = [NSString stringWithFormat:@"%@ đang giữ Secure Input nên OpenKey không gõ được.%@ %@",
                              [self appNameForPID:pid],
                              fallbackInputSourceID ? @" Đang tạm dùng bộ gõ tiếng Việt của Apple." : @"",
                              [self adviceForSecureInputPID:pid]];
            [self postNotification:@"OpenKey bị chặn bởi Secure Input" body:body];
        }
        return;
    }
    BOOL justEnabled = (lastSecureInputPID == 0);
    lastSecureInputPID = pid;
    
    if (pid == 0) {
        secureInputSince = nil;
        secureInputStuckNotified = NO;
        [self restoreInputSourceAfterFallback];
        [self clearWarning];
        return;
    }
    if (justEnabled) {
        secureInputSince = [NSDate date];
        secureInputStuckNotified = NO;
    }
    
    NSString* fallbackName = nil;
    if (justEnabled && vLanguage == 1) {
        fallbackName = [self switchToAppleVietnamese];
    }
    
    NSString* holder = [self appNameForPID:pid];
    NSString* advice = [self adviceForSecureInputPID:pid];
    NSString* msg;
    NSString* hint;
    if (fallbackInputSourceID) {
        msg = [NSString stringWithFormat:@"⚠️ Secure Input bật bởi %@ — đã tạm chuyển sang bộ gõ %@ của Apple", holder,
               fallbackName ?: @"tiếng Việt"];
        hint = [NSString stringWithFormat:@"OpenKey sẽ tự chuyển lại khi Secure Input tắt.\n%@", advice];
    } else {
        msg = [NSString stringWithFormat:@"⚠️ Secure Input bật bởi %@ — không thể gõ tiếng Việt", holder];
        hint = [NSString stringWithFormat:@"%@\nThêm bộ gõ \"Vietnamese – Simple Telex\" trong Cài đặt → Bàn phím → Nguồn đầu vào để OpenKey tự chuyển sang khi bị chặn.", advice];
    }
    [self showWarning:msg hint:hint];
}

#pragma mark Watchdog: permission, event tap and Secure Input
-(void)checkAccessibilityPermission {
    if (!MJAccessibilityIsEnabled()) {
        //require two failures in a row so a transient TCC hiccup does not stop typing
        if (++permissionFailCount < 2 || permissionLost)
            return;
        permissionLost = YES;
        //a tap without permission can block keyboard input, drop it until permission is back
        [OpenKeyManager stopEventTap];
        [self restoreInputSourceAfterFallback];
        lastSecureInputPID = 0;
        [self showWarning:@"⚠️ OpenKey mất quyền Trợ năng (Accessibility) — bấm vào đây để cấp lại"
                     hint:@"Mở Cài đặt → Quyền riêng tư & Bảo mật → Trợ năng, bật OpenKey. Nếu đã bật mà vẫn báo lỗi, xoá OpenKey khỏi danh sách (nút \"−\") rồi thêm lại."];
        [self postNotification:@"OpenKey mất quyền Trợ năng"
                          body:@"OpenKey không thể gõ tiếng Việt cho tới khi được cấp lại quyền trong Cài đặt → Quyền riêng tư & Bảo mật → Trợ năng."];
        return;
    }
    permissionFailCount = 0;
    if (permissionLost) {
        permissionLost = NO;
        [self clearWarning];
        lastSecureInputPID = 0;
        [self recreateEventTap];
    }
}

-(void)recreateEventTap {
    if (!openKeyStarted || systemSleeping || permissionLost)
        return;
    if ([OpenKeyManager recreateEventTap])
        RequestNewSession();
}

-(void)checkEventTap {
    if (![OpenKeyManager isEventTapHealthy]) {
        [OpenKeyManager reEnableEventTapIfNeeded];
        if (![OpenKeyManager isEventTapHealthy])
            [self recreateEventTap];
    }
}

-(void)watchdogTick {
    if (systemSleeping)
        return;
    [self checkAccessibilityPermission];
    if (permissionLost)
        return;
    [self checkEventTap];
    [self checkSecureInput];
}

-(void)startSecureInputWatcher {
    if (secureInputTimer)
        return;
    lastSecureInputPID = 0;
    secureInputTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                        target:self
                                                      selector:@selector(watchdogTick)
                                                      userInfo:nil
                                                       repeats:YES];
    secureInputTimer.tolerance = 0.5;
    [self watchdogTick];
}

//the tap may be silently dead after wake, unlock or a user switch: rebuild it once things settle
-(void)scheduleEventTapRecreate {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self recreateEventTap];
    });
}

#pragma mark Reset OpenKey after mac computer awake
-(void)receiveWakeNote: (NSNotification*)note {
    systemSleeping = NO;
    if (openKeyStarted && !permissionLost)
        [OpenKeyManager initEventTap];
    [self scheduleEventTapRecreate];
}

-(void)receiveSleepNote: (NSNotification*)note {
    systemSleeping = YES;
    [OpenKeyManager stopEventTap];
}

-(void)receiveUnlockNote: (NSNotification*)note {
    [self scheduleEventTapRecreate];
}

-(void)receiveActiveSpaceChanged: (NSNotification*)note {
    RequestNewSession();
}

-(void)activeAppChanged: (NSNotification*)note {
    if (vUseSmartSwitchKey && [OpenKeyManager isInited]) {
        OnActiveAppChanged();
    }
}

-(void)registerSupportedNotification {
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveWakeNote:)
                                                               name: NSWorkspaceDidWakeNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveSleepNote:)
                                                               name: NSWorkspaceWillSleepNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveActiveSpaceChanged:)
                                                               name: NSWorkspaceActiveSpaceDidChangeNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(activeAppChanged:)
                                                               name: NSWorkspaceDidActivateApplicationNotification object: NULL];
    
    //screen unlocked / switched back to this user: the tap is often dead afterwards
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveUnlockNote:)
                                                               name: NSWorkspaceSessionDidBecomeActiveNotification object: NULL];
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(receiveUnlockNote:)
                                                            name: @"com.apple.screenIsUnlocked" object: NULL];
}
@end
