// TailscaleMenu.m — menu-bar status item for tailscaled on legacy macOS.
//
// Deliberately conservative ObjC so one x86_64 binary runs on 10.6 AND 10.9:
//   no ARC, no blocks, no @autoreleasepool, no NSJSONSerialization (10.7+),
//   no props beyond ancient AppKit.  Pure NSStatusItem + NSMenu + NSTask.
//
// Talks to:  /usr/local/bin/tailscale (falls back to /opt/local/bin/tailscale)
//            --socket=/var/run/tailscaled.socket
// Selftest:  ./TailscaleMenu --selftest   (parse + menu structure to stdout)

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

static NSString *kSocket = @"/var/run/tailscaled.socket";

@interface AppController : NSObject {
    NSStatusItem *statusItem;
    NSMenu *menu;
    NSTimer *timer;
    NSMutableArray *peerLines;   // parsed "ip name owner os" rows
    NSString *selfLine;          // first row: this machine
    NSString *notice;            // "Logged out." / auth URL / error
    NSString *loginURL;
    BOOL wantRunning;
}
- (void)pollStatus:(NSTimer *)t;
- (void)menuNeedsUpdate:(NSMenu *)m;
- (void)toggle:(id)sender;
- (void)copyRow:(id)sender;
- (void)copySelfIP:(id)sender;
- (void)openLogin:(id)sender;
- (void)openAdmin:(id)sender;
- (void)quit:(id)sender;
@end

static NSString *TSBinary(void) {
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/local/bin/tailscale"])
        return @"/usr/local/bin/tailscale";
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:@"/opt/local/bin/tailscale"])
        return @"/opt/local/bin/tailscale";
    return nil;
}

// Run tailscale <args>, return stdout (nil on failure). Small outputs only.
static NSString *RunTS(NSArray *args) {
    NSString *bin = TSBinary();
    if (!bin) return nil;
    NSTask *t = [[[NSTask alloc] init] autorelease];
    [t setLaunchPath:bin];
    NSMutableArray *a = [NSMutableArray arrayWithObject:@"--socket"];
    [a addObject:kSocket];
    [a addObjectsFromArray:args];
    [t setArguments:a];
    NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
    [env setObject:@"/usr/local/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
             forKey:@"PATH"];
    [t setEnvironment:env];
    [env release];
    NSPipe *p = [NSPipe pipe];
    [t setStandardOutput:p];
    [t setStandardError:[NSPipe pipe]];   // keep stderr out of Console spam
    [t launch];
    NSData *d = [[[p fileHandleForReading] readDataToEndOfFile] retain];
    [t waitUntilExit];
    NSString *s = [[[NSString alloc] initWithData:d
                                         encoding:NSUTF8StringEncoding] autorelease];
    [d release];
    return s;
}

// Pull "https://login.tailscale.com/a/..." out of arbitrary output.
static NSString *FindLoginURL(NSString *s) {
    if (!s) return nil;
    NSScanner *sc = [NSScanner scannerWithString:s];
    NSString *url = nil;
    while ([sc scanUpToString:@"https://" intoString:NULL]) {
        NSString *rest = [s substringFromIndex:sc.scanLocation];
        NSRange sp = [rest rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *cand = (sp.location == NSNotFound) ? rest
                                                     : [rest substringToIndex:sp.location];
        if ([cand hasPrefix:@"https://login.tailscale.com/"])
            return cand;
        [sc setScanLocation:sc.scanLocation + 6];
    }
    return url;
}

// Split a status row on any whitespace run (tailscale pads columns with spaces).
static NSArray *SplitFields(NSString *row) {
    NSMutableArray *out = [NSMutableArray array];
    NSScanner *sc = [NSScanner scannerWithString:row];
    [sc setCharactersToBeSkipped:[NSCharacterSet whitespaceCharacterSet]];
    NSString *tok = nil;
    while ([sc scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet]
                              intoString:&tok]) {
        [out addObject:tok];
        [tok release];
        tok = nil;
    }
    return out;
}

@implementation AppController

- (id)init {
    return [self initWithUI:YES];
}

- (id)initWithUI:(BOOL)ui {
    self = [super init];
    if (self) {
        peerLines = [[NSMutableArray alloc] init];
        menu = [[NSMenu alloc] initWithTitle:@"Tailscale"];
        [menu setDelegate:self];
        [self pollStatus:nil];
        if (ui) {
            statusItem = [[[NSStatusBar systemStatusBar]
                            statusItemWithLength:NSVariableStatusItemLength] retain];
            [statusItem setHighlightMode:YES];
            [statusItem setMenu:menu];
            // rebuild on open + refresh every 12s
            timer = [NSTimer scheduledTimerWithTimeInterval:12.0 target:self
                                                    selector:@selector(pollStatus:)
                                                    userInfo:nil repeats:YES];
        }
    }
    return self;
}

- (void)dealloc {
    [timer invalidate];
    [statusItem release];
    [menu release];
    [peerLines release];
    [selfLine release];
    [notice release];
    [loginURL release];
    [super dealloc];
}

- (void)pollStatus:(NSTimer *)t {
    (void)t;
    NSString *out = RunTS([NSArray arrayWithObject:@"status"]);
    [peerLines removeAllObjects];
    [selfLine release]; selfLine = nil;
    [notice release]; notice = nil;
    [loginURL release]; loginURL = nil;

    if (!out) {
        notice = [@"tailscale binary not found" retain];
    } else if ([out hasPrefix:@"Logged out"]) {
        notice = [@"Logged out" retain];
        loginURL = [FindLoginURL(out) retain];
    } else {
        NSArray *rows = [out componentsSeparatedByString:@"\n"];
        NSUInteger i = 0;
        for (NSString *row in rows) {
            if ([row length] == 0) continue;
            NSArray *f = SplitFields(row);
            // "100.x.y.z  name  owner@  os  ..."  (tab or space separated)
            if ([(NSString *)[f objectAtIndex:0] hasPrefix:@"100."]) {
                if (i == 0) selfLine = [[f objectAtIndex:1] copy];
                else [peerLines addObject:row];
                i++;
            } else if (i == 0 && [row rangeOfString:@"https://"].location != NSNotFound) {
                notice = [@"Needs login" retain];
                loginURL = [FindLoginURL(row) retain];
            }
        }
        if (!selfLine && !notice) notice = [@"No state" retain];
    }
    [self refreshIcon];
}

- (void)refreshIcon {
    NSString *n = notice ? NSImageNameStatusUnavailable
                         : NSImageNameStatusAvailable;
    // logged in but peers unreachable is fine; "partially" if no self line
    if (!notice && !selfLine) n = NSImageNameStatusPartiallyAvailable;
    NSImage *img = [NSImage imageNamed:n];
    [statusItem setTitle:(selfLine && !notice) ? @"" : @"TS"];
    [statusItem setImage:img];
}

- (void)menuNeedsUpdate:(NSMenu *)m {
    (void)m;
    [menu removeAllItems];
    NSMenuItem *it;

    if (notice) {
        it = [[NSMenuItem alloc] initWithTitle:notice action:nil keyEquivalent:@""];
        [it setEnabled:NO];
        [menu addItem:[it autorelease]];
        if (loginURL) {
            it = [[NSMenuItem alloc] initWithTitle:@"Authenticate in Browser…"
                                            action:@selector(openLogin:)
                                     keyEquivalent:@""];
            [it setTarget:self];
            [menu addItem:[it autorelease]];
        }
    } else if (selfLine) {
        NSString *ip = [selfLine stringByAppendingString:@" — connected"];
        it = [[NSMenuItem alloc] initWithTitle:ip action:nil keyEquivalent:@""];
        [it setEnabled:NO];
        [menu addItem:[it autorelease]];
    }

    it = [[NSMenuItem alloc] initWithTitle:notice ? @"Connect…" : @"Disconnect"
                                    action:@selector(toggle:)
                             keyEquivalent:@""];
    [it setTarget:self];
    [menu addItem:[it autorelease]];
    [menu addItem:[NSMenuItem separatorItem]];

    if ([peerLines count] > 0) {
        for (NSString *row in peerLines) {
            NSArray *f = SplitFields(row);
            if ([f count] < 2) continue;
            NSString *title = [NSString stringWithFormat:@"%@  (%@)",
                               [f objectAtIndex:1], [f objectAtIndex:0]];
            NSMenuItem *pi = [[NSMenuItem alloc] initWithTitle:title
                                                         action:@selector(copyRow:)
                                                  keyEquivalent:@""];
            [pi setTarget:self];
            [pi setRepresentedObject:[f objectAtIndex:0]];
            [pi setToolTip:@"Click to copy this peer's Tailscale IP"];
            [menu addItem:[pi autorelease]];
        }
        [menu addItem:[NSMenuItem separatorItem]];
    }

    it = [[NSMenuItem alloc] initWithTitle:@"Copy This Machine's IP"
                                    action:@selector(copySelfIP:)
                             keyEquivalent:@""];
    [it setTarget:self];
    [menu addItem:[it autorelease]];
    it = [[NSMenuItem alloc] initWithTitle:@"Admin Console…"
                                    action:@selector(openAdmin:)
                             keyEquivalent:@""];
    [it setTarget:self];
    [menu addItem:[it autorelease]];
    [menu addItem:[NSMenuItem separatorItem]];
    it = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit:)
                             keyEquivalent:@"q"];
    [it setTarget:self];
    [menu addItem:[it autorelease]];
}

- (void)toggle:(id)sender {
    (void)sender;
    if (notice) {
        wantRunning = YES;
        // up without a key prints an auth URL; don't block the UI long
        NSString *out = RunTS([NSArray arrayWithObjects:@"up", @"--timeout=8s", nil]);
        loginURL = [FindLoginURL(out) retain];
        if (loginURL) notice = [@"Needs login" retain];
    } else {
        RunTS([NSArray arrayWithObject:@"down"]);
    }
    [self pollStatus:nil];
}

- (void)copyRow:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pb setString:[(NSMenuItem *)sender representedObject]
              forType:NSStringPboardType];
}

- (void)copySelfIP:(id)sender {
    (void)sender;
    NSString *out = RunTS([NSArray arrayWithObject:@"ip"]);
    if (!out) return;
    NSString *ip = [out stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pb setString:ip forType:NSStringPboardType];
}

- (void)openLogin:(id)sender { (void)sender; [self openURL:loginURL]; }
- (void)openAdmin:(id)sender {
    (void)sender;
    [self openURL:[NSString stringWithFormat:@"https://login.tailscale.com/admin/machines"]];
}

- (void)openURL:(NSString *)u {
    if (!u) return;
    NSURL *url = [NSURL URLWithString:u];
    if (!url) return;
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)quit:(id)sender {
    (void)sender;
    [NSApp terminate:self];
}

@end

static void SelfTest(void) {
    // Exercise parse + menu build without a GUI session (no NSStatusBar).
    NSString *out = RunTS([NSArray arrayWithObject:@"status"]);
    printf("== raw status ==\n%s", out ? [out UTF8String] : "(tailscale not found)");
    AppController *c = [[AppController alloc] initWithUI:NO];
    [c menuNeedsUpdate:nil];
    NSArray *items = [c valueForKeyPath:@"menu.itemArray"];
    printf("\n== menu (%d items) ==\n", (int)[items count]);
    for (NSMenuItem *it in items) {
        const char *t = [[it title] UTF8String];
        if (t && t[0]) printf("  %s\n", t);
        else printf("  ---\n");
    }
    exit(0);
}

int main(int argc, const char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--selftest") == 0) SelfTest();
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    AppController *c = [[AppController alloc] init];
    (void)c;
    [NSApp run];
    [pool release];
    return 0;
}
