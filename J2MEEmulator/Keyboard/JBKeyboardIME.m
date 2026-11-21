#import "JBKeyboardIME.h"

@implementation JBKeyboardIME

- (NSString *)languageDisplayName {
    return (self.currentLanguage == JBInputLanguageVietnamese) ? @"Tiếng Việt" : @"English (US)";
}

- (NSArray<NSString *> *)accentVariantsForKey:(NSString *)baseKey uppercase:(BOOL)uppercase {
    NSString *k = baseKey.lowercaseString;
    NSDictionary<NSString *, NSArray<NSString *> *> *map = @{
        @"q": @[@"1"],
        @"w": @[@"2"],
        @"e": @[@"ễ", @"ế", @"ể", @"ệ", @"ê", @"ẽ", @"ẹ", @"ề", @"é", @"3", @"è", @"ẻ"],
        @"r": @[@"4"],
        @"t": @[@"5"],
        @"y": @[@"ỹ", @"ý", @"ỷ", @"ỵ", @"6", @"ỳ"],
        @"u": @[@"ữ", @"ứ", @"ử", @"ự", @"ư", @"ũ", @"ụ", @"ừ", @"ú", @"7", @"ù", @"ủ"],
        @"i": @[@"ĩ", @"í", @"ỉ", @"ị", @"8", @"ì"],
        @"o": @[@"ỗ", @"ố", @"ổ", @"ộ", @"ô", @"ỡ", @"ớ", @"ở", @"ợ", @"ơ", @"õ", @"ọ", @"ồ", @"ó", @"9", @"ò", @"ỏ"],
        @"p": @[@"0"],
        @"a": @[@"ẫ", @"ấ", @"ẩ", @"ậ", @"â", @"ẵ", @"ắ", @"ẳ", @"ặ", @"ă", @"ã", @"ạ", @"ầ", @"á", @"à", @"ả"],
        @"d": @[@"đ"]
    };
    NSArray<NSString *> *list = map[k];
    if (!list) return @[];
    if (!uppercase) return list;
    
    NSMutableArray *upperList = [NSMutableArray arrayWithCapacity:list.count];
    for (NSString *item in list) {
        [upperList addObject:[item uppercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"vi_VN"]]];
    }
    return upperList;
}

- (NSString *)processKey:(NSString *)keyChar withCurrentBuffer:(NSString *)buffer deleteCount:(NSInteger *)outDeleteCount {
    if (outDeleteCount) *outDeleteCount = 0;
    if (self.currentLanguage == JBInputLanguageEnglish || buffer.length == 0) {
        return keyChar;
    }
    
    // Xử lý Telex cơ bản trên ký tự cuối cùng của buffer
    NSString *lastChar = [buffer substringFromIndex:buffer.length - 1];
    NSString *lowLast = lastChar.lowercaseString;
    NSString *lowKey = keyChar.lowercaseString;
    BOOL isUpper = ![lastChar isEqualToString:lowLast];
    
    NSDictionary *telexRules = @{
        @"a+a": @"â", @"a+w": @"ă", @"e+e": @"ê", @"o+o": @"ô", @"o+w": @"ơ", @"u+w": @"ư", @"d+d": @"đ",
        @"a+s": @"á", @"a+f": @"à", @"a+r": @"ả", @"a+x": @"ã", @"a+j": @"ạ",
        @"â+s": @"ấ", @"â+f": @"ầ", @"â+r": @"ẩ", @"â+x": @"ẫ", @"â+j": @"ậ",
        @"ă+s": @"ắ", @"ă+f": @"ằ", @"ă+r": @"ẳ", @"ă+x": @"ẵ", @"ă+j": @"ặ",
        @"e+s": @"é", @"e+f": @"è", @"e+r": @"ẻ", @"e+x": @"ẽ", @"e+j": @"ẹ",
        @"ê+s": @"ế", @"ê+f": @"ề", @"ê+r": @"ể", @"ê+x": @"ễ", @"ê+j": @"ệ",
        @"i+s": @"í", @"i+f": @"ì", @"i+r": @"ỉ", @"i+x": @"ĩ", @"i+j": @"ị",
        @"o+s": @"ó", @"o+f": @"ò", @"o+r": @"ỏ", @"o+x": @"õ", @"o+j": @"ọ",
        @"ô+s": @"ố", @"ô+f": @"ồ", @"ô+r": @"ổ", @"ô+x": @"ỗ", @"ô+j": @"ộ",
        @"ơ+s": @"ớ", @"ơ+f": @"ờ", @"ơ+r": @"ở", @"ơ+x": @"ỡ", @"ơ+j": @"ợ",
        @"u+s": @"ú", @"u+f": @"ù", @"u+r": @"ủ", @"u+x": @"ũ", @"u+j": @"ụ",
        @"ư+s": @"ứ", @"ư+f": @"ừ", @"ư+r": @"ử", @"ư+x": @"ữ", @"ư+j": @"ự",
        @"y+s": @"ý", @"y+f": @"ỳ", @"y+r": @"ỷ", @"y+x": @"ỹ", @"y+j": @"ỵ"
    };
    
    NSString *pair = [NSString stringWithFormat:@"%@+%@", lowLast, lowKey];
    NSString *mapped = telexRules[pair];
    if (mapped) {
        if (outDeleteCount) *outDeleteCount = 1;
        return isUpper ? [mapped uppercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"vi_VN"]] : mapped;
    }
    return keyChar;
}

@end
