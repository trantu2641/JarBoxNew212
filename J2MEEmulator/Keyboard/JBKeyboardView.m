#import "JBKeyboardView.h"
#import "JBKeyboardIME.h"
#import "JBClipboardManager.h"
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, JBKeyboardPage) {
    JBKeyboardPageLetters = 0,
    JBKeyboardPageSymbols1 = 1,
    JBKeyboardPageSymbols2 = 2,
    JBKeyboardPageEmoji = 3
};

typedef NS_ENUM(NSInteger, JBOverlayMode) {
    JBOverlayModeNone = 0,
    JBOverlayModeClipboard = 1,
    JBOverlayModeResize = 2
};

typedef NS_ENUM(NSInteger, JBShiftState) {
    JBShiftStateLowercase = 0,
    JBShiftStateShifted = 1,
    JBShiftStateCapsLock = 2
};

@class JBKeyButton;
@protocol JBKeyButtonTouchDelegate <NSObject>
- (void)keyButtonDidTouchDown:(JBKeyButton *)button;
- (void)keyButtonDidTouchMove:(JBKeyButton *)button atPointInWindow:(CGPoint)pt;
- (void)keyButtonDidTouchUp:(JBKeyButton *)button;
@end

@interface JBKeyButton : UIButton
@property (nonatomic, weak) id<JBKeyButtonTouchDelegate> touchDelegate;
@property (nonatomic, copy) NSString *primaryValue;
@property (nonatomic, copy, nullable) NSString *hintDigit;
@property (nonatomic, assign) BOOL isFunctional;
@property (nonatomic, assign) BOOL isAccentAction;
@property (nonatomic, assign) BOOL didTriggerLongPress;
@property (nonatomic, strong) UILabel *hintLabel;
@end

@implementation JBKeyButton
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.layer.cornerRadius = 7.0;
        self.layer.masksToBounds = YES;
        self.exclusiveTouch = NO;
        self.multipleTouchEnabled = YES;
        self.titleLabel.font = [UIFont systemFontOfSize:25 weight:UIFontWeightRegular];
        
        _hintLabel = [[UILabel alloc] init];
        _hintLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        _hintLabel.textColor = [UIColor colorWithRed:0.60 green:0.63 blue:0.65 alpha:1.0];
        _hintLabel.textAlignment = NSTextAlignmentRight;
        [self addSubview:_hintLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.hintLabel.frame = CGRectMake(self.bounds.size.width - 14, 2, 11, 12);
    self.hintLabel.hidden = (self.hintDigit.length == 0);
    self.hintLabel.text = self.hintDigit;
}

// Bắt chạm trực tiếp ở tầng UIResponder -> phản hồi 0ms, không bị GestureRecognizer trì hoãn
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [self.touchDelegate keyButtonDidTouchDown:self];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    UITouch *t = touches.anyObject;
    if (t) {
        [self.touchDelegate keyButtonDidTouchMove:self atPointInWindow:[t locationInView:nil]];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [self.touchDelegate keyButtonDidTouchUp:self];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self.touchDelegate keyButtonDidTouchUp:self];
}
@end

@interface JBKeyboardView () <JBKeyButtonTouchDelegate>
@property (nonatomic, strong) JBKeyboardIME *ime;
@property (nonatomic, strong) NSMutableString *wordBuffer;
@property (nonatomic, strong) NSMutableString *fullTextBuffer;

@property (nonatomic, assign) JBKeyboardPage currentPage;
@property (nonatomic, assign) JBOverlayMode overlayMode;
@property (nonatomic, assign) JBShiftState shiftState;
@property (nonatomic, assign) BOOL isClipboardEditMode;

// Khung văn bản 40px phía trên
@property (nonatomic, strong) UIView *textBoxContainer;
@property (nonatomic, strong) UITextView *previewTextView;
@property (nonatomic, strong) UIButton *clearTextBtn;

@property (nonatomic, strong) UIView *toolbarView;
@property (nonatomic, strong) UIView *keysContainerView;
@property (nonatomic, strong) UIView *overlayContainerView;

@property (nonatomic, strong) UIView *accentPopupView;
@property (nonatomic, strong) NSArray<NSString *> *currentAccentVariants;
@property (nonatomic, strong) NSMutableArray<UIButton *> *accentVariantButtons;
@property (nonatomic, assign) NSInteger selectedAccentIndex;
@property (nonatomic, weak) JBKeyButton *activeLongPressButton;
@property (nonatomic, strong) NSTimer *longPressTimer;

@property (nonatomic, strong) UIButton *clipboardBtn;
@property (nonatomic, strong) UIButton *translateBtn;
@property (nonatomic, strong) UIButton *resizeBtn;
@property (nonatomic, strong) UIButton *sendTextBtn;

@property (nonatomic, strong) NSTimer *backspaceHoldDelayTimer;
@property (nonatomic, strong) NSTimer *backspaceRepeatTimer;

@property (nonatomic, strong) UILabel *resizeHeightLabel;
@property (nonatomic, strong) UIImpactFeedbackGenerator *hapticGenerator;
@property (nonatomic, assign) CFTimeInterval lastFeedbackTime;
@end

@implementation JBKeyboardView

#pragma mark - Bảng màu chuẩn Gboard Dark Material You

- (UIColor *)gboardBackgroundColor {
    return [UIColor colorWithRed:0.106 green:0.110 blue:0.118 alpha:1.0]; // #1B1C1E
}
- (UIColor *)gboardKeyColor {
    return [UIColor colorWithRed:0.176 green:0.180 blue:0.188 alpha:1.0]; // #2D2E30
}
- (UIColor *)gboardKeyHighlightColor {
    return [UIColor colorWithRed:0.30 green:0.31 blue:0.33 alpha:1.0];
}
- (UIColor *)gboardFuncKeyColor {
    return [UIColor colorWithRed:0.235 green:0.239 blue:0.251 alpha:1.0]; // #3C3D40
}
- (UIColor *)gboardAccentBlueColor {
    return [UIColor colorWithRed:0.659 green:0.780 blue:0.980 alpha:1.0]; // #A8C7FA
}
- (UIColor *)gboardAccentDarkTextColor {
    return [UIColor colorWithRed:0.024 green:0.180 blue:0.435 alpha:1.0]; // #062E6F
}

#pragma mark - Âm thanh & Rung siêu nhẹ

- (void)playKeyClickFeedback {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lastFeedbackTime < 0.02) return;
    self.lastFeedbackTime = now;
    
    AudioServicesPlaySystemSound(1104);
    [self.hapticGenerator impactOccurred];
}

#pragma mark - Init & Height Bridge

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _ime = [[JBKeyboardIME alloc] init];
        _wordBuffer = [NSMutableString string];
        _fullTextBuffer = [NSMutableString string];
        _keyboardHeight = 360.0;
        _preferredKeyboardHeight = 360.0;
        _currentPage = JBKeyboardPageLetters;
        _overlayMode = JBOverlayModeNone;
        _shiftState = JBShiftStateLowercase;
        _hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [_hapticGenerator prepare];
        
        self.preservesSuperviewLayoutMargins = NO;
        self.insetsLayoutMarginsFromSafeArea = NO;
        self.layoutMargins = UIEdgeInsetsZero;
        self.backgroundColor = [self gboardBackgroundColor];
        
        [[JBClipboardManager sharedManager] syncWithSystemPasteboard];
        
        [self setupBaseContainers];
        [self rebuildToolbar];
        [self rebuildKeyboardKeys];
    }
    return self;
}

- (NSString *)currentText {
    return [self.fullTextBuffer copy];
}

- (void)setCurrentText:(NSString *)currentText {
    [self.fullTextBuffer setString:(currentText ?: @"")];
    [self.wordBuffer setString:@""];
    [self syncPreviewTextView];
}

- (void)setKeyboardHeight:(CGFloat)keyboardHeight {
    _keyboardHeight = keyboardHeight;
    _preferredKeyboardHeight = keyboardHeight;
    [self setNeedsLayout];
}

- (void)setPreferredKeyboardHeight:(CGFloat)preferredKeyboardHeight {
    _preferredKeyboardHeight = preferredKeyboardHeight;
    _keyboardHeight = preferredKeyboardHeight;
    [self setNeedsLayout];
}

- (void)setupBaseContainers {
    // 1. Khung văn bản phía trên cao 40px
    self.textBoxContainer = [[UIView alloc] init];
    self.textBoxContainer.backgroundColor = [UIColor colorWithRed:0.13 green:0.135 blue:0.145 alpha:1.0];
    [self addSubview:self.textBoxContainer];
    
    self.previewTextView = [[UITextView alloc] init];
    self.previewTextView.backgroundColor = [self gboardKeyColor];
    self.previewTextView.textColor = [UIColor whiteColor];
    self.previewTextView.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightRegular];
    self.previewTextView.layer.cornerRadius = 8.0;
    self.previewTextView.layer.masksToBounds = YES;
    self.previewTextView.editable = NO;
    self.previewTextView.selectable = YES;
    self.previewTextView.scrollEnabled = YES;
    self.previewTextView.showsVerticalScrollIndicator = YES;
    self.previewTextView.textContainerInset = UIEdgeInsetsMake(3, 8, 3, 28);
    self.previewTextView.textContainer.lineFragmentPadding = 0;
    [self.textBoxContainer addSubview:self.previewTextView];
    
    self.clearTextBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearTextBtn.tintColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    UIImageSymbolConfiguration *clearCfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    [self.clearTextBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:clearCfg] forState:UIControlStateNormal];
    [self.clearTextBtn addTarget:self action:@selector(onTapClearTextBuffer) forControlEvents:UIControlEventTouchUpInside];
    self.clearTextBtn.hidden = YES;
    [self.textBoxContainer addSubview:self.clearTextBtn];
    
    // 2. Thanh công cụ thu gọn (30px)
    self.toolbarView = [[UIView alloc] init];
    self.toolbarView.backgroundColor = [self gboardBackgroundColor];
    [self addSubview:self.toolbarView];
    
    // 3. Khung phím bấm
    self.keysContainerView = [[UIView alloc] init];
    self.keysContainerView.backgroundColor = [self gboardBackgroundColor];
    [self addSubview:self.keysContainerView];
    
    // 4. Overlay Clipboard / Chỉnh kích thước
    self.overlayContainerView = [[UIView alloc] init];
    self.overlayContainerView.backgroundColor = [self gboardBackgroundColor];
    self.overlayContainerView.hidden = YES;
    [self addSubview:self.overlayContainerView];
}

- (void)syncPreviewTextView {
    self.previewTextView.text = self.fullTextBuffer;
    self.clearTextBtn.hidden = (self.fullTextBuffer.length == 0);
    if (self.fullTextBuffer.length > 0) {
        CGFloat bottomOffset = self.previewTextView.contentSize.height - self.previewTextView.bounds.size.height;
        if (bottomOffset > 0) {
            [self.previewTextView setContentOffset:CGPointMake(0, bottomOffset) animated:NO];
        }
    }
}

- (void)onTapClearTextBuffer {
    [self playKeyClickFeedback];
    NSUInteger len = self.fullTextBuffer.length;
    [self.fullTextBuffer setString:@""];
    [self.wordBuffer setString:@""];
    [self syncPreviewTextView];
    for (NSUInteger i = 0; i < len; i++) {
        [self.delegate keyboardViewDidTapBackspace:self];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    
    CGFloat textBoxH = 40.0;
    CGFloat toolbarH = 30.0; // Thu nhỏ gọn thanh công cụ
    
    self.textBoxContainer.frame = CGRectMake(0, 0, w, textBoxH);
    self.previewTextView.frame = CGRectMake(2, 3, w - 4, textBoxH - 6);
    self.clearTextBtn.frame = CGRectMake(w - 30, 6, 26, 28);
    
    if (self.overlayMode == JBOverlayModeClipboard) {
        self.toolbarView.hidden = YES;
        self.keysContainerView.hidden = YES;
        self.overlayContainerView.hidden = NO;
        self.overlayContainerView.frame = CGRectMake(0, textBoxH, w, h - textBoxH);
    } else {
        self.toolbarView.hidden = NO;
        self.toolbarView.frame = CGRectMake(0, textBoxH, w, toolbarH);
        
        CGRect bodyFrame = CGRectMake(0, textBoxH + toolbarH, w, h - textBoxH - toolbarH);
        self.keysContainerView.frame = bodyFrame;
        self.overlayContainerView.frame = bodyFrame;
        
        BOOL showOverlayBody = (self.overlayMode == JBOverlayModeResize);
        self.keysContainerView.hidden = showOverlayBody;
        self.overlayContainerView.hidden = !showOverlayBody;
    }
    
    [self layoutToolbarItems];
    if (!self.keysContainerView.hidden) {
        [self layoutKeyButtons];
    }
}

- (void)reloadKeyboard {
    [self reloadKeyboardLayout];
}

- (void)reloadKeyboardLayout {
    [self rebuildToolbar];
    [self rebuildKeyboardKeys];
    [self setNeedsLayout];
}

#pragma mark - Toolbar gọn nhẹ (30px)

- (void)rebuildToolbar {
    [self.toolbarView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    UIImageSymbolConfiguration *iconCfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
    
    self.clipboardBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clipboardBtn.tintColor = [UIColor colorWithWhite:0.88 alpha:1.0];
    [self.clipboardBtn setImage:[UIImage systemImageNamed:@"list.clipboard" withConfiguration:iconCfg] forState:UIControlStateNormal];
    [self.clipboardBtn addTarget:self action:@selector(onTapClipboard) forControlEvents:UIControlEventTouchUpInside];
    [self.toolbarView addSubview:self.clipboardBtn];
    
    self.translateBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.translateBtn.tintColor = [UIColor colorWithWhite:0.88 alpha:1.0];
    [self.translateBtn setImage:[UIImage systemImageNamed:@"character.book.closed" withConfiguration:iconCfg] forState:UIControlStateNormal];
    [self.translateBtn addTarget:self action:@selector(onTapToggleLanguage) forControlEvents:UIControlEventTouchUpInside];
    [self.toolbarView addSubview:self.translateBtn];
    
    self.resizeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.resizeBtn.layer.cornerRadius = 13.0;
    if (self.overlayMode == JBOverlayModeResize) {
        self.resizeBtn.backgroundColor = [self gboardAccentBlueColor];
        self.resizeBtn.tintColor = [self gboardAccentDarkTextColor];
    } else {
        self.resizeBtn.backgroundColor = [UIColor clearColor];
        self.resizeBtn.tintColor = [UIColor colorWithWhite:0.88 alpha:1.0];
    }
    [self.resizeBtn setImage:[UIImage systemImageNamed:@"gearshape.fill" withConfiguration:iconCfg] forState:UIControlStateNormal];
    [self.resizeBtn addTarget:self action:@selector(onTapResizeMode) forControlEvents:UIControlEventTouchUpInside];
    [self.toolbarView addSubview:self.resizeBtn];
    
    self.sendTextBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendTextBtn.backgroundColor = [self gboardAccentBlueColor];
    self.sendTextBtn.tintColor = [self gboardAccentDarkTextColor];
    self.sendTextBtn.layer.cornerRadius = 12.0;
    [self.sendTextBtn setImage:[UIImage systemImageNamed:@"paperplane.fill" withConfiguration:iconCfg] forState:UIControlStateNormal];
    [self.sendTextBtn addTarget:self action:@selector(onTapSendText) forControlEvents:UIControlEventTouchUpInside];
    [self.toolbarView addSubview:self.sendTextBtn];
}

- (void)layoutToolbarItems {
    CGFloat w = self.toolbarView.bounds.size.width;
    CGFloat h = self.toolbarView.bounds.size.height;
    if (w <= 0) return;
    
    CGFloat btnSize = 26.0;
    CGFloat y = (h - btnSize) * 0.5;
    CGFloat margin = 6.0;
    
    CGFloat leftAreaW = w - margin * 2 - 44.0;
    CGFloat step = leftAreaW / 3.0;
    
    self.clipboardBtn.frame = CGRectMake(margin + step * 0.5 - btnSize * 0.5, y, btnSize, btnSize);
    self.translateBtn.frame = CGRectMake(margin + step * 1.5 - btnSize * 0.5, y, btnSize, btnSize);
    self.resizeBtn.frame    = CGRectMake(margin + step * 2.5 - btnSize * 0.5, y, btnSize, btnSize);
    
    self.sendTextBtn.frame  = CGRectMake(w - margin - 38.0, (h - 24.0) * 0.5, 38.0, 24.0);
}

#pragma mark - Xây dựng bàn phím phản hồi 0ms

- (void)rebuildKeyboardKeys {
    [self.keysContainerView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    if (self.currentPage == JBKeyboardPageEmoji) {
        [self buildEmojiGrid];
        return;
    }
    
    NSArray<NSArray<NSString *> *> *rows = nil;
    NSArray<NSString *> *topHints = nil;
    
    if (self.currentPage == JBKeyboardPageLetters) {
        BOOL upper = (self.shiftState != JBShiftStateLowercase);
        rows = @[
            upper ? @[@"Q",@"W",@"E",@"R",@"T",@"Y",@"U",@"I",@"O",@"P"] : @[@"q",@"w",@"e",@"r",@"t",@"y",@"u",@"i",@"o",@"p"],
            upper ? @[@"A",@"S",@"D",@"F",@"G",@"H",@"J",@"K",@"L"] : @[@"a",@"s",@"d",@"f",@"g",@"h",@"j",@"k",@"l"],
            upper ? @[@"SHIFT",@"Z",@"X",@"C",@"V",@"B",@"N",@"M",@"BACK"] : @[@"SHIFT",@"z",@"x",@"c",@"v",@"b",@"n",@"m",@"BACK"],
            @[@"?123", @"EMOJI", @"SPACE", @".", @"RETURN"]
        ];
        topHints = @[@"1",@"2",@"3",@"4",@"5",@"6",@"7",@"8",@"9",@"0"];
    } else if (self.currentPage == JBKeyboardPageSymbols1) {
        rows = @[
            @[@"1",@"2",@"3",@"4",@"5",@"6",@"7",@"8",@"9",@"0"],
            @[@"@",@"#",@"đ",@"_",@"&",@"-",@"+",@"(",@")",@"/"],
            @[@"=\\<",@"*",@"\"",@"'",@":",@";",@"!",@"?",@"BACK"],
            @[@"ABC", @",", @"NUMPAD", @"SPACE", @".", @"RETURN"]
        ];
    } else {
        rows = @[
            @[@"~",@"`",@"|",@"•",@"√",@"π",@"÷",@"×",@"§",@"△"],
            @[@"£",@"€",@"$",@"¢",@"^",@"°",@"=",@"{",@"}",@"\\"],
            @[@"?123",@"%",@"©",@"®",@"™",@"✓",@"[",@"]",@"BACK"],
            @[@"ABC", @"<", @"NUMPAD", @"SPACE", @">", @"RETURN"]
        ];
    }
    
    for (NSInteger r = 0; r < rows.count; r++) {
        NSArray<NSString *> *rowKeys = rows[r];
        for (NSInteger c = 0; c < rowKeys.count; c++) {
            NSString *token = rowKeys[c];
            JBKeyButton *btn = [self createKeyButtonForToken:token row:r col:c];
            if (r == 0 && topHints && c < topHints.count) {
                btn.hintDigit = topHints[c];
            }
            [self.keysContainerView addSubview:btn];
        }
    }
    [self setNeedsLayout];
}

- (JBKeyButton *)createKeyButtonForToken:(NSString *)token row:(NSInteger)row col:(NSInteger)col {
    JBKeyButton *btn = [[JBKeyButton alloc] initWithFrame:CGRectZero];
    btn.tag = (row * 100) + col;
    btn.primaryValue = token;
    
    UIImageSymbolConfiguration *symCfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    
    if ([token isEqualToString:@"SHIFT"]) {
        btn.isFunctional = YES;
        btn.backgroundColor = (self.shiftState == JBShiftStateCapsLock) ? [self gboardAccentBlueColor] : [self gboardFuncKeyColor];
        btn.tintColor = (self.shiftState == JBShiftStateCapsLock) ? [self gboardAccentDarkTextColor] : [UIColor whiteColor];
        NSString *iconName = (self.shiftState == JBShiftStateCapsLock) ? @"capslock.fill" : ((self.shiftState == JBShiftStateShifted) ? @"shift.fill" : @"shift");
        [btn setImage:[UIImage systemImageNamed:iconName withConfiguration:symCfg] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapShift) forControlEvents:UIControlEventTouchDown];
    }
    else if ([token isEqualToString:@"BACK"]) {
        btn.isFunctional = YES;
        btn.backgroundColor = [self gboardFuncKeyColor];
        btn.tintColor = [UIColor whiteColor];
        [btn setImage:[UIImage systemImageNamed:@"delete.left" withConfiguration:symCfg] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onBackspaceDown:) forControlEvents:UIControlEventTouchDown];
        [btn addTarget:self action:@selector(onBackspaceUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    }
    else if ([token isEqualToString:@"?123"] || [token isEqualToString:@"ABC"] || [token isEqualToString:@"=\\<"]) {
        btn.isFunctional = YES;
        btn.backgroundColor = [self gboardFuncKeyColor];
        btn.layer.cornerRadius = ([token isEqualToString:@"?123"] || [token isEqualToString:@"ABC"]) ? 22.0 : 7.0;
        btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        [btn setTitle:token forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapModeSwitch:) forControlEvents:UIControlEventTouchDown];
    }
    else if ([token isEqualToString:@"EMOJI"]) {
        btn.isFunctional = YES;
        btn.backgroundColor = [self gboardFuncKeyColor];
        btn.tintColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        [btn setImage:[UIImage systemImageNamed:@"face.smiling" withConfiguration:symCfg] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapEmojiPage) forControlEvents:UIControlEventTouchDown];
    }
    else if ([token isEqualToString:@"NUMPAD"]) {
        btn.isFunctional = YES;
        btn.backgroundColor = [self gboardFuncKeyColor];
        btn.titleLabel.numberOfLines = 2;
        btn.titleLabel.textAlignment = NSTextAlignmentCenter;
        btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        [btn setTitle:@"1 2\n3 4" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapQuickNumpad) forControlEvents:UIControlEventTouchDown];
    }
    else if ([token isEqualToString:@"SPACE"]) {
        btn.backgroundColor = [self gboardKeyColor];
        btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        [btn setTitle:self.ime.languageDisplayName forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithWhite:0.82 alpha:1.0] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapSpace) forControlEvents:UIControlEventTouchDown];
        
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPressSpace:)];
        lp.minimumPressDuration = 0.42;
        [btn addGestureRecognizer:lp];
    }
    else if ([token isEqualToString:@"RETURN"]) {
        btn.isAccentAction = YES;
        btn.backgroundColor = [self gboardAccentBlueColor];
        btn.tintColor = [self gboardAccentDarkTextColor];
        btn.layer.cornerRadius = 22.0;
        [btn setImage:[UIImage systemImageNamed:@"return.left" withConfiguration:symCfg] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapReturn) forControlEvents:UIControlEventTouchDown];
    }
    else {
        // Phím ký tự: dùng touchDelegate trực tiếp (0ms latency, không có gesture recognizer cản trở)
        btn.backgroundColor = [self gboardKeyColor];
        btn.touchDelegate = self;
        [btn setTitle:token forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithWhite:0.95 alpha:1.0] forState:UIControlStateNormal];
    }
    
    return btn;
}

- (void)layoutKeyButtons {
    if (self.currentPage == JBKeyboardPageEmoji) return;
    
    CGFloat w = self.keysContainerView.bounds.size.width;
    CGFloat h = self.keysContainerView.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    
    CGFloat hGap = 2.5;
    CGFloat vGap = 4.0;
    CGFloat sidePad = 1.0;
    CGFloat topPad = 2.0;
    CGFloat bottomPad = 2.0;
    CGFloat rowH = (h - topPad - bottomPad - vGap * 3) / 4.0;
    
    NSMutableDictionary<NSNumber *, NSMutableArray<JBKeyButton *> *> *rowMap = [NSMutableDictionary dictionary];
    for (UIView *sub in self.keysContainerView.subviews) {
        if (![sub isKindOfClass:[JBKeyButton class]]) continue;
        JBKeyButton *b = (JBKeyButton *)sub;
        NSInteger r = b.tag / 100;
        if (!rowMap[@(r)]) rowMap[@(r)] = [NSMutableArray array];
        [rowMap[@(r)] addObject:b];
    }
    
    for (NSInteger r = 0; r < 4; r++) {
        NSArray<JBKeyButton *> *btns = [rowMap[@(r)] sortedArrayUsingComparator:^NSComparisonResult(JBKeyButton *a, JBKeyButton *b) {
            return [@(a.tag) compare:@(b.tag)];
        }];
        CGFloat y = topPad + r * (rowH + vGap);
        
        if (r == 0) {
            CGFloat keyW = (w - sidePad * 2 - hGap * 9) / 10.0;
            for (NSInteger i = 0; i < btns.count; i++) {
                btns[i].frame = CGRectMake(sidePad + i * (keyW + hGap), y, keyW, rowH);
            }
        } else if (r == 1) {
            if (self.currentPage == JBKeyboardPageLetters) {
                CGFloat keyW = (w - sidePad * 2 - hGap * 9) / 10.0;
                CGFloat rowTotalW = keyW * 9 + hGap * 8;
                CGFloat startX = (w - rowTotalW) * 0.5;
                for (NSInteger i = 0; i < btns.count; i++) {
                    btns[i].frame = CGRectMake(startX + i * (keyW + hGap), y, keyW, rowH);
                }
            } else {
                CGFloat keyW = (w - sidePad * 2 - hGap * 9) / 10.0;
                for (NSInteger i = 0; i < btns.count; i++) {
                    btns[i].frame = CGRectMake(sidePad + i * (keyW + hGap), y, keyW, rowH);
                }
            }
        } else if (r == 2) {
            CGFloat funcW = (w - sidePad * 2) * 0.135;
            NSInteger midCount = btns.count - 2;
            CGFloat midTotalW = w - sidePad * 2 - funcW * 2 - hGap * (midCount + 1);
            CGFloat midKeyW = midTotalW / MAX(1, midCount);
            
            btns.firstObject.frame = CGRectMake(sidePad, y, funcW, rowH);
            CGFloat curX = sidePad + funcW + hGap;
            for (NSInteger i = 1; i < btns.count - 1; i++) {
                btns[i].frame = CGRectMake(curX, y, midKeyW, rowH);
                curX += midKeyW + hGap;
            }
            btns.lastObject.frame = CGRectMake(w - sidePad - funcW, y, funcW, rowH);
        } else if (r == 3) {
            CGFloat returnW = 56.0;
            CGFloat modeW = 52.0;
            CGFloat smallW = 40.0;
            CGFloat dotW = 40.0;
            
            if (btns.count == 5) {
                CGFloat spaceW = w - sidePad * 2 - modeW - smallW - dotW - returnW - hGap * 4;
                CGFloat x = sidePad;
                btns[0].frame = CGRectMake(x, y, modeW, rowH); x += modeW + hGap;
                btns[1].frame = CGRectMake(x, y, smallW, rowH); x += smallW + hGap;
                btns[2].frame = CGRectMake(x, y, spaceW, rowH); x += spaceW + hGap;
                btns[3].frame = CGRectMake(x, y, dotW, rowH); x += dotW + hGap;
                btns[4].frame = CGRectMake(x, y, returnW, rowH);
            } else if (btns.count == 6) {
                CGFloat spaceW = w - sidePad * 2 - modeW - smallW * 2 - dotW - returnW - hGap * 5;
                CGFloat x = sidePad;
                btns[0].frame = CGRectMake(x, y, modeW, rowH); x += modeW + hGap;
                btns[1].frame = CGRectMake(x, y, smallW, rowH); x += smallW + hGap;
                btns[2].frame = CGRectMake(x, y, smallW, rowH); x += smallW + hGap;
                btns[3].frame = CGRectMake(x, y, spaceW, rowH); x += spaceW + hGap;
                btns[4].frame = CGRectMake(x, y, dotW, rowH); x += dotW + hGap;
                btns[5].frame = CGRectMake(x, y, returnW, rowH);
            }
        }
    }
}

#pragma mark - JBKeyButtonTouchDelegate (Phản hồi 0ms & Nhấn giữ chọn dấu)

- (void)keyButtonDidTouchDown:(JBKeyButton *)button {
    button.didTriggerLongPress = NO;
    button.backgroundColor = [self gboardKeyHighlightColor];
    [self processCharacterInputFromButton:button];
    
    // Hẹn giờ 0.36s nếu vẫn giữ ngón tay thì hiện popup dấu
    [self.longPressTimer invalidate];
    self.activeLongPressButton = button;
    self.longPressTimer = [NSTimer scheduledTimerWithTimeInterval:0.36
                                                           target:self
                                                         selector:@selector(handleLongPressTimerFired)
                                                         userInfo:nil
                                                          repeats:NO];
}

- (void)handleLongPressTimerFired {
    JBKeyButton *btn = self.activeLongPressButton;
    if (!btn) return;
    
    BOOL upper = (self.shiftState != JBShiftStateLowercase);
    NSArray<NSString *> *variants = [self.ime accentVariantsForKey:btn.primaryValue uppercase:upper];
    if (variants.count == 0 && btn.hintDigit.length > 0) {
        variants = @[btn.hintDigit];
    }
    if (variants.count > 0) {
        btn.didTriggerLongPress = YES;
        [self showAccentPopupOverButton:btn variants:variants];
    }
}

- (void)keyButtonDidTouchMove:(JBKeyButton *)button atPointInWindow:(CGPoint)pt {
    if (!button.didTriggerLongPress || !self.accentPopupView) return;
    CGPoint ptInPopup = [self.accentPopupView convertPoint:pt fromView:nil];
    [self updateAccentSelectionAtPoint:ptInPopup];
}

- (void)keyButtonDidTouchUp:(JBKeyButton *)button {
    [self.longPressTimer invalidate];
    self.longPressTimer = nil;
    button.backgroundColor = [self gboardKeyColor];
    
    if (button.didTriggerLongPress && self.selectedAccentIndex >= 0 && self.selectedAccentIndex < self.currentAccentVariants.count) {
        [self performSingleBackspace];
        NSString *chosen = self.currentAccentVariants[self.selectedAccentIndex];
        [self commitTextToTarget:chosen];
    }
    button.didTriggerLongPress = NO;
    self.activeLongPressButton = nil;
    [self dismissAccentPopup];
}

- (void)processCharacterInputFromButton:(JBKeyButton *)sender {
    NSString *raw = sender.primaryValue;
    if (raw.length == 0) return;
    [self playKeyClickFeedback];
    
    NSInteger deleteCount = 0;
    NSString *output = [self.ime processKey:raw withCurrentBuffer:self.wordBuffer deleteCount:&deleteCount];
    
    if (deleteCount > 0 && self.wordBuffer.length >= deleteCount) {
        [self.wordBuffer deleteCharactersInRange:NSMakeRange(self.wordBuffer.length - deleteCount, deleteCount)];
        if (self.fullTextBuffer.length >= deleteCount) {
            [self.fullTextBuffer deleteCharactersInRange:NSMakeRange(self.fullTextBuffer.length - deleteCount, deleteCount)];
        }
        for (NSInteger i = 0; i < deleteCount; i++) {
            [self.delegate keyboardViewDidTapBackspace:self];
        }
    }
    
    [self commitTextToTarget:output];
    
    if (self.shiftState == JBShiftStateShifted) {
        self.shiftState = JBShiftStateLowercase;
        [self updateShiftLabelsInPlace];
    }
}

// Cập nhật chữ hoa/thường ngay trên các nút có sẵn mà không cần xóa & tạo lại toàn bộ UIView
- (void)updateShiftLabelsInPlace {
    BOOL upper = (self.shiftState != JBShiftStateLowercase);
    UIImageSymbolConfiguration *symCfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    
    for (UIView *sub in self.keysContainerView.subviews) {
        if (![sub isKindOfClass:[JBKeyButton class]]) continue;
        JBKeyButton *btn = (JBKeyButton *)sub;
        if ([btn.primaryValue isEqualToString:@"SHIFT"]) {
            btn.backgroundColor = (self.shiftState == JBShiftStateCapsLock) ? [self gboardAccentBlueColor] : [self gboardFuncKeyColor];
            btn.tintColor = (self.shiftState == JBShiftStateCapsLock) ? [self gboardAccentDarkTextColor] : [UIColor whiteColor];
            NSString *iconName = (self.shiftState == JBShiftStateCapsLock) ? @"capslock.fill" : ((self.shiftState == JBShiftStateShifted) ? @"shift.fill" : @"shift");
            [btn setImage:[UIImage systemImageNamed:iconName withConfiguration:symCfg] forState:UIControlStateNormal];
        } else if (!btn.isFunctional && !btn.isAccentAction && btn.primaryValue.length == 1) {
            NSString *nextVal = upper ? [btn.primaryValue uppercaseString] : [btn.primaryValue lowercaseString];
            btn.primaryValue = nextVal;
            [btn setTitle:nextVal forState:UIControlStateNormal];
        }
    }
}

#pragma mark - Popup chọn dấu tiếng Việt

- (void)showAccentPopupOverButton:(JBKeyButton *)btn variants:(NSArray<NSString *> *)variants {
    [self dismissAccentPopup];
    self.currentAccentVariants = variants;
    self.accentVariantButtons = [NSMutableArray array];
    
    NSInteger cols = MIN(4, variants.count);
    NSInteger rows = (NSInteger)ceil((double)variants.count / (double)cols);
    CGFloat cellW = 42.0;
    CGFloat cellH = 42.0;
    CGFloat pad = 6.0;
    
    CGFloat popupW = cols * cellW + pad * 2;
    CGFloat popupH = rows * cellH + pad * 2;
    
    CGRect btnRectInSelf = [btn convertRect:btn.bounds toView:self];
    CGFloat popupX = CGRectGetMidX(btnRectInSelf) - popupW * 0.5;
    popupX = MAX(4.0, MIN(self.bounds.size.width - popupW - 4.0, popupX));
    CGFloat popupY = MAX(2.0, CGRectGetMinY(btnRectInSelf) - popupH - 4.0);
    
    UIView *popup = [[UIView alloc] initWithFrame:CGRectMake(popupX, popupY, popupW, popupH)];
    popup.backgroundColor = [UIColor colorWithRed:0.20 green:0.21 blue:0.22 alpha:1.0];
    popup.layer.cornerRadius = 16.0;
    popup.layer.shadowColor = [UIColor blackColor].CGColor;
    popup.layer.shadowOpacity = 0.45;
    popup.layer.shadowRadius = 10.0;
    popup.layer.shadowOffset = CGSizeMake(0, 4);
    
    for (NSInteger i = 0; i < variants.count; i++) {
        NSInteger r = i / cols;
        NSInteger c = i % cols;
        UIButton *itemBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        itemBtn.frame = CGRectMake(pad + c * cellW + 3, pad + r * cellH + 3, cellW - 6, cellH - 6);
        itemBtn.layer.cornerRadius = (cellW - 6) * 0.5;
        itemBtn.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
        [itemBtn setTitle:variants[i] forState:UIControlStateNormal];
        [itemBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [popup addSubview:itemBtn];
        [self.accentVariantButtons addObject:itemBtn];
    }
    
    NSInteger defaultIdx = (rows - 1) * cols + MIN(cols - 1, 1);
    if (defaultIdx >= variants.count) defaultIdx = 0;
    [self highlightAccentIndex:defaultIdx];
    
    [self addSubview:popup];
    self.accentPopupView = popup;
}

- (void)updateAccentSelectionAtPoint:(CGPoint)pt {
    for (NSInteger i = 0; i < self.accentVariantButtons.count; i++) {
        CGRect hitFrame = CGRectInset(self.accentVariantButtons[i].frame, -4, -4);
        if (CGRectContainsPoint(hitFrame, pt)) {
            if (self.selectedAccentIndex != i) {
                [self playKeyClickFeedback];
                [self highlightAccentIndex:i];
            }
            return;
        }
    }
}

- (void)highlightAccentIndex:(NSInteger)index {
    self.selectedAccentIndex = index;
    for (NSInteger i = 0; i < self.accentVariantButtons.count; i++) {
        UIButton *b = self.accentVariantButtons[i];
        if (i == index) {
            b.backgroundColor = [self gboardAccentBlueColor];
            [b setTitleColor:[self gboardAccentDarkTextColor] forState:UIControlStateNormal];
        } else {
            b.backgroundColor = [UIColor clearColor];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        }
    }
}

- (void)dismissAccentPopup {
    [self.accentPopupView removeFromSuperview];
    self.accentPopupView = nil;
    self.currentAccentVariants = nil;
    [self.accentVariantButtons removeAllObjects];
}

- (void)commitTextToTarget:(NSString *)text {
    if (text.length == 0) return;
    if ([text isEqualToString:@" "] || [text isEqualToString:@"\n"] || [text isEqualToString:@"."] || [text isEqualToString:@","]) {
        [self.wordBuffer setString:@""];
    } else {
        [self.wordBuffer appendString:text];
    }
    [self.fullTextBuffer appendString:text];
    [self syncPreviewTextView];
    [self.delegate keyboardView:self didInsertText:text];
}

- (void)onTapSpace {
    [self playKeyClickFeedback];
    [self commitTextToTarget:@" "];
}

- (void)onTapReturn {
    [self playKeyClickFeedback];
    [self commitTextToTarget:@"\n"];
    [self.delegate keyboardViewDidTapReturn:self];
}

- (void)onTapSendText {
    [self playKeyClickFeedback];
    if ([self.delegate respondsToSelector:@selector(keyboardViewDidTapSubmit:)]) {
        [self.delegate keyboardViewDidTapSubmit:self];
    } else {
        [self.delegate keyboardViewDidTapHide:self];
    }
}

- (void)onTapShift {
    [self playKeyClickFeedback];
    if (self.shiftState == JBShiftStateLowercase) {
        self.shiftState = JBShiftStateShifted;
    } else if (self.shiftState == JBShiftStateShifted) {
        self.shiftState = JBShiftStateCapsLock;
    } else {
        self.shiftState = JBShiftStateLowercase;
    }
    [self updateShiftLabelsInPlace];
}

- (void)onTapModeSwitch:(JBKeyButton *)sender {
    [self playKeyClickFeedback];
    NSString *t = sender.primaryValue;
    if ([t isEqualToString:@"?123"]) {
        self.currentPage = JBKeyboardPageSymbols1;
    } else if ([t isEqualToString:@"=\\<"]) {
        self.currentPage = JBKeyboardPageSymbols2;
    } else {
        self.currentPage = JBKeyboardPageLetters;
    }
    [self rebuildKeyboardKeys];
}

- (void)onTapEmojiPage {
    [self playKeyClickFeedback];
    self.currentPage = (self.currentPage == JBKeyboardPageEmoji) ? JBKeyboardPageLetters : JBKeyboardPageEmoji;
    [self rebuildKeyboardKeys];
}

- (void)onTapQuickNumpad {
    [self playKeyClickFeedback];
    self.currentPage = JBKeyboardPageSymbols1;
    [self rebuildKeyboardKeys];
}

#pragma mark - Backspace chuẩn 1 ký tự

- (void)onBackspaceDown:(UIButton *)sender {
    sender.backgroundColor = [self gboardKeyHighlightColor];
    [self cancelBackspaceTimers];
    [self performSingleBackspace];
    
    self.backspaceHoldDelayTimer = [NSTimer scheduledTimerWithTimeInterval:0.42
                                                                    target:self
                                                                  selector:@selector(startContinuousBackspace)
                                                                  userInfo:nil
                                                                   repeats:NO];
}

- (void)startContinuousBackspace {
    self.backspaceRepeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.08
                                                                 target:self
                                                               selector:@selector(performSingleBackspace)
                                                               userInfo:nil
                                                                repeats:YES];
}

- (void)onBackspaceUp:(UIButton *)sender {
    sender.backgroundColor = [self gboardFuncKeyColor];
    [self cancelBackspaceTimers];
}

- (void)cancelBackspaceTimers {
    [self.backspaceHoldDelayTimer invalidate];
    self.backspaceHoldDelayTimer = nil;
    [self.backspaceRepeatTimer invalidate];
    self.backspaceRepeatTimer = nil;
}

- (void)performSingleBackspace {
    [self playKeyClickFeedback];
    if (self.wordBuffer.length > 0) {
        [self.wordBuffer deleteCharactersInRange:NSMakeRange(self.wordBuffer.length - 1, 1)];
    }
    if (self.fullTextBuffer.length > 0) {
        [self.fullTextBuffer deleteCharactersInRange:NSMakeRange(self.fullTextBuffer.length - 1, 1)];
        [self syncPreviewTextView];
    }
    [self.delegate keyboardViewDidTapBackspace:self];
}

#pragma mark - Chỉnh cao thấp bàn phím (Mép dưới cố định, bàn phím nâng lên trực tiếp từ mép trên)

- (void)onTapResizeMode {
    [self playKeyClickFeedback];
    if (self.overlayMode == JBOverlayModeResize) {
        self.overlayMode = JBOverlayModeNone;
        [self rebuildToolbar];
        [self setNeedsLayout];
        return;
    }
    
    self.overlayMode = JBOverlayModeResize;
    [self rebuildToolbar];
    [self.overlayContainerView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    CGFloat w = self.bounds.size.width > 0 ? self.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    CGFloat bodyH = MAX(180.0, self.preferredKeyboardHeight - 70.0);
    
    UIView *frameBox = [[UIView alloc] initWithFrame:CGRectMake(6, 10, w - 12, bodyH - 16)];
    frameBox.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    frameBox.layer.cornerRadius = 14.0;
    frameBox.layer.borderWidth = 2.0;
    frameBox.layer.borderColor = [self gboardAccentBlueColor].CGColor;
    [self.overlayContainerView addSubview:frameBox];
    
    UILabel *guide = [[UILabel alloc] initWithFrame:CGRectMake(16, 18, frameBox.bounds.size.width - 32, 24)];
    guide.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    guide.text = [NSString stringWithFormat:@"Chiều cao: %.0f px (Kéo cạnh trên)", self.preferredKeyboardHeight];
    guide.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    guide.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    guide.textAlignment = NSTextAlignmentCenter;
    self.resizeHeightLabel = guide;
    [frameBox addSubview:guide];
    
    UIButton *minusBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    minusBtn.frame = CGRectMake(frameBox.bounds.size.width * 0.5 - 102, 52, 92, 36);
    minusBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    minusBtn.backgroundColor = [self gboardFuncKeyColor];
    minusBtn.layer.cornerRadius = 18.0;
    [minusBtn setTitle:@"Thấp hơn -" forState:UIControlStateNormal];
    [minusBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    minusBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [minusBtn addTarget:self action:@selector(onDecreaseHeight) forControlEvents:UIControlEventTouchDown];
    [frameBox addSubview:minusBtn];
    
    UIButton *plusBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    plusBtn.frame = CGRectMake(frameBox.bounds.size.width * 0.5 + 10, 52, 92, 36);
    plusBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    plusBtn.backgroundColor = [self gboardFuncKeyColor];
    plusBtn.layer.cornerRadius = 18.0;
    [plusBtn setTitle:@"Cao hơn +" forState:UIControlStateNormal];
    [plusBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    plusBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [plusBtn addTarget:self action:@selector(onIncreaseHeight) forControlEvents:UIControlEventTouchDown];
    [frameBox addSubview:plusBtn];
    
    // Tay cầm kéo cạnh trên
    UIButton *dragHandle = [UIButton buttonWithType:UIButtonTypeSystem];
    dragHandle.frame = CGRectMake((frameBox.bounds.size.width - 54) * 0.5, -14, 54, 28);
    dragHandle.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    dragHandle.backgroundColor = [self gboardAccentBlueColor];
    dragHandle.tintColor = [self gboardAccentDarkTextColor];
    dragHandle.layer.cornerRadius = 14.0;
    [dragHandle setImage:[UIImage systemImageNamed:@"arrow.up.and.down"] forState:UIControlStateNormal];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanResizeHandle:)];
    [dragHandle addGestureRecognizer:pan];
    [frameBox addSubview:dragHandle];
    
    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    doneBtn.frame = CGRectMake((frameBox.bounds.size.width - 104) * 0.5, frameBox.bounds.size.height - 44, 104, 34);
    doneBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    doneBtn.backgroundColor = [self gboardAccentBlueColor];
    doneBtn.layer.cornerRadius = 17.0;
    [doneBtn setTitle:@"Xong" forState:UIControlStateNormal];
    [doneBtn setTitleColor:[self gboardAccentDarkTextColor] forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [doneBtn addTarget:self action:@selector(onFinishResize) forControlEvents:UIControlEventTouchDown];
    [frameBox addSubview:doneBtn];
    
    [self setNeedsLayout];
}

- (void)applyNewKeyboardHeight:(CGFloat)targetHeight {
    [self playKeyClickFeedback];
    CGFloat clamped = MAX(260.0, MIN(480.0, targetHeight));
    self.preferredKeyboardHeight = clamped;
    self.resizeHeightLabel.text = [NSString stringWithFormat:@"Chiều cao: %.0f px (Kéo cạnh trên)", clamped];
    [self.delegate keyboardView:self didChangeHeight:clamped];
    [self setNeedsLayout];
}

- (void)onDecreaseHeight {
    [self applyNewKeyboardHeight:self.preferredKeyboardHeight - 26.0];
}

- (void)onIncreaseHeight {
    [self applyNewKeyboardHeight:self.preferredKeyboardHeight + 26.0];
}

- (void)onPanResizeHandle:(UIPanGestureRecognizer *)pan {
    UIView *refView = self.window ?: (self.superview ?: self);
    CGPoint delta = [pan translationInView:refView];
    [pan setTranslation:CGPointZero inView:refView];
    
    CGFloat nextH = MAX(260.0, MIN(480.0, self.preferredKeyboardHeight - delta.y));
    self.preferredKeyboardHeight = nextH;
    self.resizeHeightLabel.text = [NSString stringWithFormat:@"Chiều cao: %.0f px (Kéo cạnh trên)", nextH];
    [self.delegate keyboardView:self didChangeHeight:nextH];
    [self setNeedsLayout];
}

- (void)onFinishResize {
    [self playKeyClickFeedback];
    self.overlayMode = JBOverlayModeNone;
    [self rebuildToolbar];
    [self setNeedsLayout];
}

#pragma mark - Bảng nhớ tạm (Clipboard)

static char kClipItemAssocKey;
static char kDeletedItemAssocKey;

- (void)onTapClipboard {
    [self playKeyClickFeedback];
    [[JBClipboardManager sharedManager] syncWithSystemPasteboard];
    self.overlayMode = JBOverlayModeClipboard;
    self.isClipboardEditMode = NO;
    [self buildClipboardOverlayWithUndoItem:nil];
    [self setNeedsLayout];
}

- (void)buildClipboardOverlayWithUndoItem:(nullable JBClipboardItem *)deletedItem {
    [self.overlayContainerView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    CGFloat w = self.bounds.size.width > 0 ? self.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    CGFloat h = MAX(180.0, self.bounds.size.height - 40.0);
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium];
    
    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    backBtn.frame = CGRectMake(10, 8, 34, 34);
    backBtn.backgroundColor = [self gboardFuncKeyColor];
    backBtn.tintColor = [UIColor whiteColor];
    backBtn.layer.cornerRadius = 17.0;
    [backBtn setImage:[UIImage systemImageNamed:@"arrow.left" withConfiguration:cfg] forState:UIControlStateNormal];
    [backBtn addTarget:self action:@selector(onCloseClipboard) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayContainerView addSubview:backBtn];
    
    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(52, 8, 170, 34)];
    titleLbl.text = @"Bảng nhớ tạm";
    titleLbl.textColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    titleLbl.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    [self.overlayContainerView addSubview:titleLbl];
    
    UIButton *toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    toggleBtn.frame = CGRectMake(w - 88, 8, 34, 34);
    toggleBtn.backgroundColor = [self gboardFuncKeyColor];
    toggleBtn.tintColor = [JBClipboardManager sharedManager].isEnabled ? [self gboardAccentBlueColor] : [UIColor grayColor];
    toggleBtn.layer.cornerRadius = 17.0;
    [toggleBtn setImage:[UIImage systemImageNamed:@"switch.2" withConfiguration:cfg] forState:UIControlStateNormal];
    [toggleBtn addTarget:self action:@selector(onToggleClipboardEnabled) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayContainerView addSubview:toggleBtn];
    
    UIButton *editBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    editBtn.frame = CGRectMake(w - 44, 8, 34, 34);
    editBtn.backgroundColor = self.isClipboardEditMode ? [self gboardAccentBlueColor] : [self gboardFuncKeyColor];
    editBtn.tintColor = self.isClipboardEditMode ? [self gboardAccentDarkTextColor] : [UIColor whiteColor];
    editBtn.layer.cornerRadius = 17.0;
    [editBtn setImage:[UIImage systemImageNamed:@"pencil" withConfiguration:cfg] forState:UIControlStateNormal];
    [editBtn addTarget:self action:@selector(onToggleClipboardEdit) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayContainerView addSubview:editBtn];
    
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 48, w, h - 48)];
    [self.overlayContainerView addSubview:scroll];
    
    CGFloat curY = 4.0;
    NSArray<JBClipboardItem *> *pinned = [JBClipboardManager sharedManager].pinnedItems;
    NSArray<JBClipboardItem *> *recent = [JBClipboardManager sharedManager].recentItems;
    
    if (pinned.count > 0) {
        UILabel *sec = [[UILabel alloc] initWithFrame:CGRectMake(12, curY, w - 24, 20)];
        sec.text = @"Đã ghim";
        sec.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
        sec.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [scroll addSubview:sec];
        curY += 24.0;
        curY = [self layoutClipboardCards:pinned inScrollView:scroll startY:curY width:w];
    }
    
    if (recent.count > 0) {
        UILabel *sec = [[UILabel alloc] initWithFrame:CGRectMake(12, curY + 4, w - 24, 20)];
        sec.text = @"Gần đây";
        sec.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
        sec.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [scroll addSubview:sec];
        curY += 28.0;
        curY = [self layoutClipboardCards:recent inScrollView:scroll startY:curY width:w];
    }
    
    scroll.contentSize = CGSizeMake(w, curY + 60.0);
    
    if (deletedItem) {
        CGFloat snackW = 240.0;
        CGFloat snackH = 42.0;
        UIView *snack = [[UIView alloc] initWithFrame:CGRectMake((w - snackW) * 0.5, h - snackH - 12, snackW, snackH)];
        snack.backgroundColor = [UIColor colorWithRed:0.93 green:0.90 blue:0.96 alpha:1.0];
        snack.layer.cornerRadius = snackH * 0.5;
        
        UILabel *msg = [[UILabel alloc] initWithFrame:CGRectMake(18, 0, 140, snackH)];
        msg.text = @"Đã xoá 1 mục";
        msg.textColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        msg.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [snack addSubview:msg];
        
        UIButton *undoBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        undoBtn.frame = CGRectMake(snackW - 68, 0, 56, snackH);
        [undoBtn setTitle:@"Huỷ" forState:UIControlStateNormal];
        [undoBtn setTitleColor:[UIColor colorWithRed:0.05 green:0.35 blue:0.75 alpha:1.0] forState:UIControlStateNormal];
        undoBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        objc_setAssociatedObject(undoBtn, &kDeletedItemAssocKey, deletedItem, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [undoBtn addTarget:self action:@selector(onUndoDeleteClipboardItem:) forControlEvents:UIControlEventTouchUpInside];
        [snack addSubview:undoBtn];
        
        [self.overlayContainerView addSubview:snack];
    }
}

- (CGFloat)layoutClipboardCards:(NSArray<JBClipboardItem *> *)list inScrollView:(UIScrollView *)scroll startY:(CGFloat)startY width:(CGFloat)w {
    CGFloat pad = 10.0;
    CGFloat gap = 8.0;
    CGFloat cardW = (w - pad * 2 - gap) * 0.5;
    CGFloat cardH = 44.0;
    
    for (NSInteger i = 0; i < list.count; i++) {
        JBClipboardItem *item = list[i];
        NSInteger r = i / 2;
        NSInteger c = i % 2;
        
        UIButton *card = [UIButton buttonWithType:UIButtonTypeSystem];
        card.frame = CGRectMake(pad + c * (cardW + gap), startY + r * (cardH + gap), cardW, cardH);
        card.backgroundColor = [self gboardKeyColor];
        card.layer.cornerRadius = 12.0;
        card.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        card.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, self.isClipboardEditMode ? 34 : 10);
        card.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        card.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [card setTitle:item.text forState:UIControlStateNormal];
        [card setTitleColor:[UIColor colorWithWhite:0.94 alpha:1.0] forState:UIControlStateNormal];
        objc_setAssociatedObject(card, &kClipItemAssocKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [card addTarget:self action:@selector(onTapClipboardCard:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:card];
        
        if (self.isClipboardEditMode) {
            UIButton *delBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            delBtn.frame = CGRectMake(cardW - 30, (cardH - 26) * 0.5, 26, 26);
            delBtn.tintColor = [UIColor colorWithRed:0.95 green:0.45 blue:0.45 alpha:1.0];
            [delBtn setImage:[UIImage systemImageNamed:@"trash.fill"] forState:UIControlStateNormal];
            objc_setAssociatedObject(delBtn, &kClipItemAssocKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [delBtn addTarget:self action:@selector(onDeleteClipboardCard:) forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:delBtn];
        }
    }
    
    NSInteger rows = (NSInteger)ceil((double)list.count / 2.0);
    return startY + rows * (cardH + gap);
}

- (void)onTapClipboardCard:(UIButton *)sender {
    [self playKeyClickFeedback];
    JBClipboardItem *item = objc_getAssociatedObject(sender, &kClipItemAssocKey);
    if (!item) return;
    if (self.isClipboardEditMode) {
        [[JBClipboardManager sharedManager] togglePinForIdentifier:item.identifier];
        [self buildClipboardOverlayWithUndoItem:nil];
    } else {
        [self commitTextToTarget:item.text];
        [self onCloseClipboard];
    }
}

- (void)onDeleteClipboardCard:(UIButton *)sender {
    [self playKeyClickFeedback];
    JBClipboardItem *item = objc_getAssociatedObject(sender, &kClipItemAssocKey);
    if (!item) return;
    JBClipboardItem *removed = [[JBClipboardManager sharedManager] deleteItemWithIdentifier:item.identifier];
    [self buildClipboardOverlayWithUndoItem:removed];
}

- (void)onUndoDeleteClipboardItem:(UIButton *)sender {
    [self playKeyClickFeedback];
    JBClipboardItem *item = objc_getAssociatedObject(sender, &kDeletedItemAssocKey);
    if (item) {
        [[JBClipboardManager sharedManager] restoreDeletedItem:item atIndex:0];
        [self buildClipboardOverlayWithUndoItem:nil];
    }
}

- (void)onToggleClipboardEnabled {
    [self playKeyClickFeedback];
    [JBClipboardManager sharedManager].isEnabled = ![JBClipboardManager sharedManager].isEnabled;
    [self buildClipboardOverlayWithUndoItem:nil];
}

- (void)onToggleClipboardEdit {
    [self playKeyClickFeedback];
    self.isClipboardEditMode = !self.isClipboardEditMode;
    [self buildClipboardOverlayWithUndoItem:nil];
}

- (void)onCloseClipboard {
    [self playKeyClickFeedback];
    self.overlayMode = JBOverlayModeNone;
    [self rebuildToolbar];
    [self setNeedsLayout];
}

#pragma mark - Chuyển đổi ngôn ngữ

- (void)onLongPressSpace:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self playKeyClickFeedback];
    [self showLanguagePickerDialog];
}

- (void)onTapToggleLanguage {
    [self playKeyClickFeedback];
    self.ime.currentLanguage = (self.ime.currentLanguage == JBInputLanguageVietnamese) ? JBInputLanguageEnglish : JBInputLanguageVietnamese;
    [self rebuildKeyboardKeys];
}

- (void)showLanguagePickerDialog {
    UIView *targetHost = self.superview ?: self;
    UIView *dim = [[UIView alloc] initWithFrame:targetHost.bounds];
    dim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    dim.tag = 998877;
    
    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissLanguageDialog:)];
    [dim addGestureRecognizer:dismissTap];
    
    CGFloat cardW = MIN(310.0, targetHost.bounds.size.width - 40.0);
    CGFloat cardH = 220.0;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake((targetHost.bounds.size.width - cardW) * 0.5, (targetHost.bounds.size.height - cardH) * 0.5, cardW, cardH)];
    card.backgroundColor = [UIColor colorWithRed:0.17 green:0.16 blue:0.20 alpha:1.0];
    card.layer.cornerRadius = 24.0;
    [dim addSubview:card];
    
    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(20, 18, cardW - 40, 28)];
    header.text = @"Thay đổi bàn phím";
    header.textColor = [UIColor whiteColor];
    header.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
    header.textAlignment = NSTextAlignmentCenter;
    [card addSubview:header];
    
    UIButton *viBtn = [self createLangOptionButtonFrame:CGRectMake(14, 58, cardW - 28, 52)
                                                  title:@"Tiếng Việt (Việt Nam)"
                                               subtitle:@"QWERTY"
                                               selected:(self.ime.currentLanguage == JBInputLanguageVietnamese)];
    viBtn.tag = JBInputLanguageVietnamese;
    [viBtn addTarget:self action:@selector(onSelectLanguageFromDialog:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:viBtn];
    
    UIButton *enBtn = [self createLangOptionButtonFrame:CGRectMake(14, 118, cardW - 28, 52)
                                                  title:@"English (US)"
                                               subtitle:@"QWERTY"
                                               selected:(self.ime.currentLanguage == JBInputLanguageEnglish)];
    enBtn.tag = JBInputLanguageEnglish;
    [enBtn addTarget:self action:@selector(onSelectLanguageFromDialog:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:enBtn];
    
    [targetHost addSubview:dim];
}

- (UIButton *)createLangOptionButtonFrame:(CGRect)frame title:(NSString *)title subtitle:(NSString *)sub selected:(BOOL)selected {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    btn.layer.cornerRadius = frame.size.height * 0.5;
    btn.backgroundColor = selected ? [UIColor colorWithRed:0.82 green:0.89 blue:0.99 alpha:1.0] : [UIColor clearColor];
    
    UIColor *fg = selected ? [self gboardAccentDarkTextColor] : [UIColor colorWithWhite:0.92 alpha:1.0];
    if (selected) {
        UIImageView *check = [[UIImageView alloc] initWithFrame:CGRectMake(18, 16, 20, 20)];
        check.image = [UIImage systemImageNamed:@"checkmark"];
        check.tintColor = fg;
        [btn addSubview:check];
    }
    
    UILabel *tLbl = [[UILabel alloc] initWithFrame:CGRectMake(50, 7, frame.size.width - 60, 20)];
    tLbl.text = title;
    tLbl.textColor = fg;
    tLbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [btn addSubview:tLbl];
    
    UILabel *sLbl = [[UILabel alloc] initWithFrame:CGRectMake(50, 28, frame.size.width - 60, 16)];
    sLbl.text = sub;
    sLbl.textColor = selected ? fg : [UIColor colorWithWhite:0.65 alpha:1.0];
    sLbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    [btn addSubview:sLbl];
    
    return btn;
}

- (void)onSelectLanguageFromDialog:(UIButton *)sender {
    [self playKeyClickFeedback];
    self.ime.currentLanguage = (JBInputLanguage)sender.tag;
    UIView *targetHost = self.superview ?: self;
    [[targetHost viewWithTag:998877] removeFromSuperview];
    [self rebuildKeyboardKeys];
}

- (void)dismissLanguageDialog:(UITapGestureRecognizer *)tap {
    [tap.view removeFromSuperview];
}

#pragma mark - Bảng Emoji nhanh

- (void)buildEmojiGrid {
    NSArray<NSString *> *emojis = @[
        @"😀",@"😂",@"🤣",@"😊",@"😍",@"🥰",@"😘",@"😎",
        @"😢",@"😭",@"😡",@"😱",@"🤔",@"😴",@"🥳",@"🙏",
        @"👍",@"👎",@"👌",@"✌️",@"❤️",@"💔",@"🔥",@"✨"
    ];
    CGFloat w = self.keysContainerView.bounds.size.width > 0 ? self.keysContainerView.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    CGFloat h = self.keysContainerView.bounds.size.height > 0 ? self.keysContainerView.bounds.size.height : 250.0;
    
    CGFloat cellW = w / 8.0;
    CGFloat cellH = (h - 44.0) / 3.0;
    for (NSInteger i = 0; i < emojis.count; i++) {
        NSInteger r = i / 8;
        NSInteger c = i % 8;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(c * cellW, r * cellH, cellW, cellH);
        b.titleLabel.font = [UIFont systemFontOfSize:26];
        [b setTitle:emojis[i] forState:UIControlStateNormal];
        [b addTarget:self action:@selector(onTapEmojiChar:) forControlEvents:UIControlEventTouchDown];
        [self.keysContainerView addSubview:b];
    }
    
    UIButton *abcBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    abcBtn.frame = CGRectMake(6, h - 40, 62, 34);
    abcBtn.backgroundColor = [self gboardFuncKeyColor];
    abcBtn.layer.cornerRadius = 17.0;
    [abcBtn setTitle:@"ABC" forState:UIControlStateNormal];
    [abcBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [abcBtn addTarget:self action:@selector(onTapEmojiPage) forControlEvents:UIControlEventTouchDown];
    [self.keysContainerView addSubview:abcBtn];
}

- (void)onTapEmojiChar:(UIButton *)sender {
    [self playKeyClickFeedback];
    NSString *e = [sender titleForState:UIControlStateNormal];
    if (e.length > 0) [self commitTextToTarget:e];
}

@end
