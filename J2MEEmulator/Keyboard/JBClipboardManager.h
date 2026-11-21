#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface JBClipboardItem : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) BOOL isPinned;
@property (nonatomic, strong) NSDate *timestamp;
@end

@interface JBClipboardManager : NSObject

@property (nonatomic, assign) BOOL isEnabled;
@property (nonatomic, readonly) NSArray<JBClipboardItem *> *pinnedItems;
@property (nonatomic, readonly) NSArray<JBClipboardItem *> *recentItems;

+ (instancetype)sharedManager;
- (void)syncWithSystemPasteboard;
- (void)addText:(NSString *)text pinned:(BOOL)pinned;
- (void)togglePinForIdentifier:(NSString *)identifier;
- (nullable JBClipboardItem *)deleteItemWithIdentifier:(NSString *)identifier;
- (void)restoreDeletedItem:(JBClipboardItem *)item atIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
