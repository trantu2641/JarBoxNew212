#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, JBInputLanguage) {
    JBInputLanguageVietnamese = 0,
    JBInputLanguageEnglish = 1
};

@interface JBKeyboardIME : NSObject

@property (nonatomic, assign) JBInputLanguage currentLanguage;
@property (nonatomic, readonly) NSString *languageDisplayName; // "Tiếng Việt" hoặc "English (US)"

- (NSString *)processKey:(NSString *)keyChar withCurrentBuffer:(NSString *)buffer deleteCount:(NSInteger *)outDeleteCount;
- (NSArray<NSString *> *)accentVariantsForKey:(NSString *)baseKey uppercase:(BOOL)uppercase;

@end

NS_ASSUME_NONNULL_END
