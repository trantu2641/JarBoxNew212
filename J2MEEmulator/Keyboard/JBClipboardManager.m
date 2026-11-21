#import "JBClipboardManager.h"
#import <UIKit/UIKit.h>

@implementation JBClipboardItem
+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.identifier forKey:@"id"];
    [coder encodeObject:self.text forKey:@"text"];
    [coder encodeBool:self.isPinned forKey:@"pinned"];
    [coder encodeObject:self.timestamp forKey:@"time"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _identifier = [coder decodeObjectOfClass:[NSString class] forKey:@"id"] ?: [[NSUUID UUID] UUIDString];
        _text = [coder decodeObjectOfClass:[NSString class] forKey:@"text"] ?: @"";
        _isPinned = [coder decodeBoolForKey:@"pinned"];
        _timestamp = [coder decodeObjectOfClass:[NSDate class] forKey:@"time"] ?: [NSDate date];
    }
    return self;
}
@end

@interface JBClipboardManager ()
@property (nonatomic, strong) NSMutableArray<JBClipboardItem *> *items;
@property (nonatomic, assign) NSInteger lastChangeCount;
@end

@implementation JBClipboardManager

+ (instancetype)sharedManager {
    static JBClipboardManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[JBClipboardManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _isEnabled = YES;
        _lastChangeCount = -1;
        [self loadFromDisk];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(syncWithSystemPasteboard)
                                                     name:UIPasteboardChangedNotification
                                                   object:nil];
    }
    return self;
}

- (void)syncWithSystemPasteboard {
    if (!self.isEnabled) return;
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    if (pb.changeCount == self.lastChangeCount) return;
    self.lastChangeCount = pb.changeCount;
    
    if (pb.hasStrings && pb.string.length > 0) {
        [self addText:pb.string pinned:NO];
    }
}

- (void)addText:(NSString *)text pinned:(BOOL)pinned {
    if (text.length == 0) return;
    for (JBClipboardItem *existing in self.items) {
        if ([existing.text isEqualToString:text]) {
            existing.timestamp = [NSDate date];
            if (pinned) existing.isPinned = YES;
            [self saveToDisk];
            return;
        }
    }
    JBClipboardItem *item = [[JBClipboardItem alloc] init];
    item.identifier = [[NSUUID UUID] UUIDString];
    item.text = text;
    item.isPinned = pinned;
    item.timestamp = [NSDate date];
    [self.items insertObject:item atIndex:0];
    if (self.items.count > 40) {
        [self.items removeLastObject];
    }
    [self saveToDisk];
}

- (NSArray<JBClipboardItem *> *)pinnedItems {
    return [self.items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isPinned == YES"]];
}

- (NSArray<JBClipboardItem *> *)recentItems {
    return [self.items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isPinned == NO"]];
}

- (void)togglePinForIdentifier:(NSString *)identifier {
    for (JBClipboardItem *item in self.items) {
        if ([item.identifier isEqualToString:identifier]) {
            item.isPinned = !item.isPinned;
            break;
        }
    }
    [self saveToDisk];
}

- (nullable JBClipboardItem *)deleteItemWithIdentifier:(NSString *)identifier {
    NSUInteger idx = [self.items indexOfObjectPassingTest:^BOOL(JBClipboardItem *obj, NSUInteger i, BOOL *stop) {
        return [obj.identifier isEqualToString:identifier];
    }];
    if (idx != NSNotFound) {
        JBClipboardItem *removed = self.items[idx];
        [self.items removeObjectAtIndex:idx];
        [self saveToDisk];
        return removed;
    }
    return nil;
}

- (void)restoreDeletedItem:(JBClipboardItem *)item atIndex:(NSUInteger)index {
    if (!item) return;
    NSUInteger safeIdx = MIN(index, self.items.count);
    [self.items insertObject:item atIndex:safeIdx];
    [self saveToDisk];
}

- (void)saveToDisk {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.items requiringSecureCoding:YES error:nil];
    if (data) {
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"JB_Gboard_Clipboard_Items"];
    }
}

- (void)loadFromDisk {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:@"JB_Gboard_Clipboard_Items"];
    if (data) {
        NSSet *classes = [NSSet setWithObjects:[NSMutableArray class], [JBClipboardItem class], nil];
        NSArray *loaded = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
        if (loaded) {
            self.items = [loaded mutableCopy];
            return;
        }
    }
    self.items = [NSMutableArray array];
}

@end
