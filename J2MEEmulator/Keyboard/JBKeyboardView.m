#import "JBKeyboardView.h"
#import "JBKeyboardIME.h"
#import "JBClipboardManager.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, JBKeyboardPage) {
    JBKeyboardPageLetters = 0,
    JBKeyboardPageSymbols1 = 1,
    JBKeyboardPageSymbols2 = 2,
    JBKeyboardPageEmoji = 3
};

typedef NS_ENUM(NSInteger, JBOverlayMode) {
    JBOverlayModeNone = 0,
    JBOverlayModeFeatureGrid = 1,
    JBOverlayModeClipboard = 2,
    JBOverlayModeResize = 3,
    JBOverlayModeLanguagePicker = 4
};

typedef NS_ENUM(NSInteger, JBShiftState) {
    JBShiftStateLowercase = 0,
    JBShiftStateShifted = 1,
    JBShiftStateCapsLock = 2
};

@interface JBKeyButton : UIButton
@property (nonatomic, copy) NSString *primaryValue;
@property (nonatomic, copy, nullable) NSString *hintDigit;
@property (nonatomic, assign) BOOL isFunctional;
@property (nonatomic, assign) BOOL isAccentAction;
@property (nonatomic, strong) UILabel *hintLabel;
@end

@implementation JBKeyButton
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.layer.cornerRadius = 8.0;
        self.layer.masksToBounds = YES;
        self.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightRegular];
        
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
    self.hintLabel.frame = CGRectMake(self.bounds.size.width - 15, 3, 11, 12);
    self.hintLabel.hidden = (self.hintDigit.length == 0);
    self.hintLabel.text = self.hintDigit;
}
@end

@interface JBKeyboardView ()
@property (nonatomic, strong) JBKeyboardIME *ime;
@property (nonatomic, strong) NSMutableString *wordBuffer;
@property (nonatomic, strong) NSMutableArray<NSString *> *undoHistory;

@property (nonatomic, assign) JBKeyboardPage currentPage;
@property (nonatomic, assign) JBOverlayMode overlayMode;
@property (nonatomic, assign) JBShiftState shiftState;
@property (nonatomic, assign) BOOL isClipboardEditMode;

@property (nonatomic, strong) UIView *toolbarView;
@property (nonatomic, strong) UIView *keysContainerView;
@property (nonatomic, strong) UIView *overlayContainerView;

@property (nonatomic, strong) UIView *accentPopupView;
@property (nonatomic, strong) NSArray<NSString *> *currentAccentVariants;
@property (nonatomic, strong) NSMutableArray<UIButton *> *accentVariantButtons;
@property (nonatomic, assign) NSInteger selectedAccentIndex;

@property (nonatomic, strong) UIButton *menuGridBtn;
@property (nonatomic, strong) UIButton *clipboardBtn;
@property (nonatomic, strong) UIButton *translateBtn;
@property (nonatomic, strong) UIButton *settingsBtn;
@property (nonatomic, strong) UIButton *micOrHideBtn;

@property (nonatomic, strong) NSTimer *backspaceTimer;
@end

@implementation JBKeyboardView

#pragma mark - Bảng màu chuẩn Gboard Dark Material You

- (UIColor *)gboardBackgroundColor {
    return [UIColor colorWithRed:0.106 green:0.110 blue:0.118 alpha:1.0]; // #1B1C1E
}
- (UIColor *)gboardKeyColor {
    return [UIColor colorWithRed:0.176 green:0.180 blue:0.188 alpha:1.0]; // #2D2E30
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
- (UIColor *)gboardActiveMenuCircleColor {
    return [UIColor colorWithRed:0.000 green:0.290 blue:0.467 alpha:1.0]; // #004A77
}

#pragma mark - Init & Height Bridge

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _ime = [[JBKeyboardIME alloc] init];
        _wordBuffer = [NSMutableString string];
        _undoHistory = [NSMutableArray array];
        _keyboardHeight = 278.0;
        _preferredKeyboardHeight = 278.0;
        _currentPage = JBKeyboardPageLetters;
        _overlayMode = JBOverlayModeNone;
        _shiftState = JBShiftStateLowercase;
        
        self.backgroundColor = [self gboardBackgroundColor];
        [[JBClipboardManager sharedManager] syncWithSystemPasteboard];
        
        [self setupBaseContainers];
        [self rebuildToolbar];
        [self rebuildKeyboardKeys];
    }
    return self;
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
    self.toolbarView = [[UIView alloc] init];
    self.toolbarView.backgroundColor = [self gboardBackgroundColor];
    [self addSubview:self.toolbarView];
    
    self.keysContainerView = [[UIView alloc] init];
    self.keysContainerView.backgroundColor = [self gboardBackgroundColor];
    [self addSubview:self.keysContainerView];
    
    self.overlayContainerView = [[UIView alloc] init];
    self.overlayContainerView.backgroundColor = [self gboardBackgroundColor];
    self.overlayContainerView.hidden = YES;
    [self addSubview:self.overlayContainerView];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    
    CGFloat toolbarH = 44.0;
    if (self.overlayMode == JBOverlayModeClipboard) {
        self.toolbarView.hidden = YES;
        self.keysContainerView.hidden = YES;
        self.overlayContainerView.hidden = NO;
        self.overlayContainerView.frame = self.bounds;
    } else {
        self.toolbarView.hidden = NO;
        self.toolbarView.frame = CGRectMake(0, 0, w, toolbarH);
        
        CGRect bodyFrame = CGRectMake(0, toolbarH, w, h - toolbarH);
        self.keysContainerView.frame = bodyFrame;
        self.overlayContainerView.frame = bodyFrame;
        
        BOOL showOverlayBody = (self.overlayMode == JBOverlayModeFeatureGrid || self.overlayMode == JBOverlayModeResize);
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

#pragma mark - Toolbar

- (void)rebuildToolbar {
    [self.toolbarView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    UIImageSymbolConfiguration *iconCfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    
    self.menuGridBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.menuGridBtn.layer.cornerRadius = 18.0;
    if (self.overlayMode == JBOverlayModeFeatureGrid) {
        self.menuGridBtn.backgroundColor = [self gboardActiveMenuCircleColor];
        self.menuGridBtn.tintColor = [self gboardAccentBlueColor];
        [self.menuGridBtn setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:iconCfg] forState:UIControlStateNormal];
    } else {
        self.menuGridBtn.backgroundColor = [UIColor clearColor];
        self.menuGridBtn.tintColor = [UIColor colorWithWhite:0.88 alpha:1.0];
        [self.menuGridBtn setImage:[UIImage systemImageNamed:@"square.grid.2x2.fill" withConfiguration:iconCfg] forState:UIControlStateNormal];
    }
    [self.menuGridBtn addTarget:self action:@selector(onTapMenuGrid) forControlEvents:UIControlEventTouchUpInside];
    [self.toolbarView addSubview:self.menuGridBtn];
    
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
    
    self.settingsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.settingsBtn.tintColor = [UIColor colorWithWhite:0.88 alpha:1.0];
    [self.settingsBtn setImage:[UIImage systemImageNamed:@"gearshape.fill" withConfiguration:iconCfg] forState:UIControlStateNormal];
    [self.settingsBtn addTarget:self action:@selector(onTapResizeMode) forControlEvents:UIControlEventTouchUpInside];
    [self.toolbarView addSubview:self.settingsBtn];
    
    self.micOrHideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.micOrHideBtn.backgroundColor = [self gboardFuncKeyColor];
    self.micOrHideBtn.tintColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    self.micOrHideBtn.layer.cornerRadius = 18.0;
    [self.micOrHideBtn setImage:[UIImage systemImageNamed:@"keyboard.chevron.compact.down" withConfiguration:iconCfg] forState:UIControlStateNormal];
    [self.micOrHideBtn addTarget:self action:@selector(onTapHideKeyboard) forControlEvents:UIControlEventTouchUpInside];
    [self.toolbarView addSubview:self.micOrHideBtn];
}

- (void)layoutToolbarItems {
    CGFloat w = self.toolbarView.bounds.size.width;
    CGFloat h = self.toolbarView.bounds.size.height;
    if (w <= 0) return;
    
    CGFloat btnSize = 36.0;
    CGFloat y = (h - btnSize) * 0.5;
    CGFloat margin = 12.0;
    CGFloat usableW = w - margin * 2 - btnSize;
    CGFloat step = usableW / 4.0;
    
    self.menuGridBtn.frame = CGRectMake(margin, y, btnSize, btnSize);
    self.clipboardBtn.frame = CGRectMake(margin + step, y, btnSize, btnSize);
    self.translateBtn.frame = CGRectMake(margin + step * 2, y, btnSize, btnSize);
    self.settingsBtn.frame = CGRectMake(margin + step * 3, y, btnSize, btnSize);
    self.micOrHideBtn.frame = CGRectMake(w - margin - btnSize, y, btnSize, btnSize);
}

#pragma mark - Xây dựng bàn phím

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
    
    UIImageSymbolConfiguration *symCfg = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightMedium];
    
    if ([token isEqualToString:@"SHIFT"]) {
        btn.isFunctional = YES;
        btn.backgroundColor = (self.shiftState == JBShiftStateCapsLock) ? [self gboardAccentBlueColor] : [self gboardFuncKeyColor];
        btn.tintColor = (self.shiftState == JBShiftStateCapsLock) ? [self gboardAccentDarkTextColor] : [UIColor whiteColor];
        NSString *iconName = (self.shiftState == JBShiftStateCapsLock) ? @"capslock.fill" : ((self.shiftState == JBShiftStateShifted) ? @"shift.fill" : @"shift");
        [btn setImage:[UIImage systemImageNamed:iconName withConfiguration:symCfg] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapShift) forControlEvents:UIControlEventTouchUpInside];
    }
    else if ([token isEqualToString:@"BACK"]) {
        btn.isFunctional = YES;
        btn.backgroundColor = [self gboardFuncKeyColor];
        btn.tintColor = [UIColor whiteColor];
        [btn setImage:[UIImage systemImageNamed:@"delete.left" withConfiguration:symCfg] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onBackspaceDown) forControlEvents:UIControlEventTouchDown];
        [btn addTarget:self action:@selector(onBackspaceUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    }
    else if ([token isEqualToString:@"?123"] || [token isEqualToString:@"ABC"] || [token isEqualToString:@"=\\<"]) {
        btn.isFunctional = YES;
        btn.backgroundColor = [self gboardFuncKeyColor];
        btn.layer.cornerRadius = ([token isEqualToString:@"?123"] || [token isEqualToString:@"ABC"]) ? 22.0 : 8.0;
        btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        [btn setTitle:token forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapModeSwitch:) forControlEvents:UIControlEventTouchUpInside];
    }
    else if ([token isEqualToString:@"EMOJI"]) {
        btn.isFunctional = YES;
        btn.backgroundColor = [self gboardFuncKeyColor];
        btn.tintColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        [btn setImage:[UIImage systemImageNamed:@"face.smiling" withConfiguration:symCfg] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapEmojiPage) forControlEvents:UIControlEventTouchUpInside];
    }
    else if ([token isEqualToString:@"NUMPAD"]) {
        btn.isFunctional = YES;
        btn.backgroundColor = [self gboardFuncKeyColor];
        btn.titleLabel.numberOfLines = 2;
        btn.titleLabel.textAlignment = NSTextAlignmentCenter;
        btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        [btn setTitle:@"1 2\n3 4" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapQuickNumpad) forControlEvents:UIControlEventTouchUpInside];
    }
    else if ([token isEqualToString:@"SPACE"]) {
        btn.backgroundColor = [self gboardKeyColor];
        btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        [btn setTitle:self.ime.languageDisplayName forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithWhite:0.82 alpha:1.0] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapSpace) forControlEvents:UIControlEventTouchUpInside];
        
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPressSpace:)];
        lp.minimumPressDuration = 0.35;
        [btn addGestureRecognizer:lp];
    }
    else if ([token isEqualToString:@"RETURN"]) {
        btn.isAccentAction = YES;
        btn.backgroundColor = [self gboardAccentBlueColor];
        btn.tintColor = [self gboardAccentDarkTextColor];
        btn.layer.cornerRadius = 22.0;
        [btn setImage:[UIImage systemImageNamed:@"magnifyingglass" withConfiguration:symCfg] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapReturn) forControlEvents:UIControlEventTouchUpInside];
    }
    else {
        btn.backgroundColor = [self gboardKeyColor];
        [btn setTitle:token forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithWhite:0.95 alpha:1.0] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(onTapCharacterKey:) forControlEvents:UIControlEventTouchUpInside];
        
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPressCharacterKey:)];
        lp.minimumPressDuration = 0.28;
        [btn addGestureRecognizer:lp];
    }
    
    return btn;
}

- (void)layoutKeyButtons {
    if (self.currentPage == JBKeyboardPageEmoji) return;
    
    CGFloat w = self.keysContainerView.bounds.size.width;
    CGFloat h = self.keysContainerView.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    
    CGFloat hGap = 5.0;
    CGFloat vGap = 7.0;
    CGFloat sidePad = 4.0;
    CGFloat topPad = 4.0;
    CGFloat bottomPad = 6.0;
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
            CGFloat returnW = 54.0;
            CGFloat modeW = 52.0;
            CGFloat smallW = 38.0;
            CGFloat dotW = 38.0;
            
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

#pragma mark - Popup nhấn giữ chọn dấu tiếng Việt & số

- (void)onLongPressCharacterKey:(UILongPressGestureRecognizer *)gesture {
    JBKeyButton *btn = (JBKeyButton *)gesture.view;
    if (![btn isKindOfClass:[JBKeyButton class]]) return;
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        BOOL upper = (self.shiftState != JBShiftStateLowercase);
        NSArray<NSString *> *variants = [self.ime accentVariantsForKey:btn.primaryValue uppercase:upper];
        if (variants.count == 0) {
            if (btn.hintDigit.length > 0) {
                variants = @[btn.hintDigit];
            } else {
                return;
            }
        }
        [self showAccentPopupOverButton:btn variants:variants];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint pt = [gesture locationInView:self.accentPopupView];
        [self updateAccentSelectionAtPoint:pt];
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        if (self.selectedAccentIndex >= 0 && self.selectedAccentIndex < self.currentAccentVariants.count) {
            NSString *chosen = self.currentAccentVariants[self.selectedAccentIndex];
            [self commitTextToTarget:chosen];
            if (self.shiftState == JBShiftStateShifted) {
                self.shiftState = JBShiftStateLowercase;
                [self rebuildKeyboardKeys];
            }
        }
        [self dismissAccentPopup];
    } else if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        [self dismissAccentPopup];
    }
}

- (void)showAccentPopupOverButton:(JBKeyButton *)btn variants:(NSArray<NSString *> *)variants {
    [self dismissAccentPopup];
    self.currentAccentVariants = variants;
    self.accentVariantButtons = [NSMutableArray array];
    
    NSInteger cols = MIN(4, variants.count);
    NSInteger rows = (NSInteger)ceil((double)variants.count / (double)cols);
    CGFloat cellW = 44.0;
    CGFloat cellH = 44.0;
    CGFloat pad = 8.0;
    
    CGFloat popupW = cols * cellW + pad * 2;
    CGFloat popupH = rows * cellH + pad * 2;
    
    CGRect btnRectInSelf = [btn convertRect:btn.bounds toView:self];
    CGFloat popupX = CGRectGetMidX(btnRectInSelf) - popupW * 0.5;
    popupX = MAX(6.0, MIN(self.bounds.size.width - popupW - 6.0, popupX));
    CGFloat popupY = CGRectGetMinY(btnRectInSelf) - popupH - 4.0;
    
    UIView *popup = [[UIView alloc] initWithFrame:CGRectMake(popupX, popupY, popupW, popupH)];
    popup.backgroundColor = [UIColor colorWithRed:0.20 green:0.21 blue:0.22 alpha:1.0];
    popup.layer.cornerRadius = 18.0;
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
            [self highlightAccentIndex:i];
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

#pragma mark - Xử lý nhập liệu & Telex

- (void)onTapCharacterKey:(JBKeyButton *)sender {
    NSString *raw = sender.primaryValue;
    if (raw.length == 0) return;
    
    NSInteger deleteCount = 0;
    NSString *output = [self.ime processKey:raw withCurrentBuffer:self.wordBuffer deleteCount:&deleteCount];
    
    if (deleteCount > 0 && self.wordBuffer.length >= deleteCount) {
        [self.wordBuffer deleteCharactersInRange:NSMakeRange(self.wordBuffer.length - deleteCount, deleteCount)];
        for (NSInteger i = 0; i < deleteCount; i++) {
            [self.delegate keyboardViewDidTapBackspace:self];
        }
    }
    
    [self commitTextToTarget:output];
    
    if (self.shiftState == JBShiftStateShifted) {
        self.shiftState = JBShiftStateLowercase;
        [self rebuildKeyboardKeys];
    }
}

- (void)commitTextToTarget:(NSString *)text {
    if (text.length == 0) return;
    if ([text isEqualToString:@" "] || [text isEqualToString:@"."] || [text isEqualToString:@","]) {
        [self.wordBuffer setString:@""];
    } else {
        [self.wordBuffer appendString:text];
    }
    [self.undoHistory addObject:text];
    [self.delegate keyboardView:self didInsertText:text];
}

- (void)onTapSpace {
    [self commitTextToTarget:@" "];
}

- (void)onTapReturn {
    [self.wordBuffer setString:@""];
    [self.delegate keyboardViewDidTapReturn:self];
}

- (void)onTapShift {
    if (self.shiftState == JBShiftStateLowercase) {
        self.shiftState = JBShiftStateShifted;
    } else if (self.shiftState == JBShiftStateShifted) {
        self.shiftState = JBShiftStateCapsLock;
    } else {
        self.shiftState = JBShiftStateLowercase;
    }
    [self rebuildKeyboardKeys];
}

- (void)onTapModeSwitch:(JBKeyButton *)sender {
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
    self.currentPage = (self.currentPage == JBKeyboardPageEmoji) ? JBKeyboardPageLetters : JBKeyboardPageEmoji;
    [self rebuildKeyboardKeys];
}

- (void)onTapQuickNumpad {
    self.currentPage = JBKeyboardPageSymbols1;
    [self rebuildKeyboardKeys];
}

- (void)onBackspaceDown {
    [self performSingleBackspace];
    [self.backspaceTimer invalidate];
    self.backspaceTimer = [NSTimer scheduledTimerWithTimeInterval:0.09 target:self selector:@selector(performSingleBackspace) userInfo:nil repeats:YES];
}

- (void)onBackspaceUp {
    [self.backspaceTimer invalidate];
    self.backspaceTimer = nil;
}

- (void)performSingleBackspace {
    if (self.wordBuffer.length > 0) {
        [self.wordBuffer deleteCharactersInRange:NSMakeRange(self.wordBuffer.length - 1, 1)];
    }
    [self.delegate keyboardViewDidTapBackspace:self];
}

#pragma mark - Menu mở rộng 6 chức năng

- (void)onTapMenuGrid {
    if (self.overlayMode == JBOverlayModeFeatureGrid) {
        self.overlayMode = JBOverlayModeNone;
    } else {
        self.overlayMode = JBOverlayModeFeatureGrid;
        [self buildFeatureGridOverlay];
    }
    [self rebuildToolbar];
    [self setNeedsLayout];
}

- (void)buildFeatureGridOverlay {
    [self.overlayContainerView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    NSArray<NSDictionary *> *items = @[
        @{@"title": @"Chia sẻ Gboard", @"icon": @"point.3.connected.trianglepath.dotted", @"tag": @1},
        @{@"title": @"Đổi kích thước", @"icon": @"viewfinder", @"tag": @2},
        @{@"title": @"Nổi", @"icon": @"keyboard", @"tag": @3},
        @{@"title": @"Huỷ", @"icon": @"arrow.uturn.left", @"tag": @4},
        @{@"title": @"Ngôn ngữ tiếp theo", @"icon": @"globe", @"tag": @5},
        @{@"title": @"Tự động điền", @"icon": @"rectangle.and.pencil.and.ellipsis", @"tag": @6}
    ];
    
    CGFloat w = self.bounds.size.width > 0 ? self.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    CGFloat bodyH = self.preferredKeyboardHeight - 44.0;
    CGFloat padX = 16.0;
    CGFloat gapX = 12.0;
    CGFloat gapY = 12.0;
    CGFloat pillW = (w - padX * 2 - gapX) * 0.5;
    CGFloat pillH = 48.0;
    
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    
    for (NSInteger i = 0; i < items.count; i++) {
        NSInteger r = i / 2;
        NSInteger c = i % 2;
        NSDictionary *info = items[i];
        
        UIButton *pill = [UIButton buttonWithType:UIButtonTypeSystem];
        pill.frame = CGRectMake(padX + c * (pillW + gapX), 12.0 + r * (pillH + gapY), pillW, pillH);
        pill.backgroundColor = [self gboardFuncKeyColor];
        pill.layer.cornerRadius = pillH * 0.5;
        pill.tintColor = [UIColor colorWithWhite:0.93 alpha:1.0];
        pill.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        pill.contentEdgeInsets = UIEdgeInsetsMake(0, 18, 0, 14);
        pill.titleEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 0);
        pill.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        pill.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        pill.tag = [info[@"tag"] integerValue];
        
        [pill setImage:[UIImage systemImageNamed:info[@"icon"] withConfiguration:cfg] forState:UIControlStateNormal];
        [pill setTitle:info[@"title"] forState:UIControlStateNormal];
        [pill addTarget:self action:@selector(onTapFeaturePill:) forControlEvents:UIControlEventTouchUpInside];
        [self.overlayContainerView addSubview:pill];
    }
    
    UIButton *editPill = [UIButton buttonWithType:UIButtonTypeSystem];
    editPill.frame = CGRectMake(w - padX - 68, MAX(180, bodyH - 42), 68, 32);
    editPill.layer.cornerRadius = 16.0;
    editPill.layer.borderWidth = 1.0;
    editPill.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:1.0].CGColor;
    editPill.tintColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    [editPill setImage:[UIImage systemImageNamed:@"pencil" withConfiguration:cfg] forState:UIControlStateNormal];
    [self.overlayContainerView addSubview:editPill];
}

- (void)onTapFeaturePill:(UIButton *)sender {
    switch (sender.tag) {
        case 1: {
            [[UIPasteboard generalPasteboard] setString:@"JarBox Gboard Keyboard"];
            self.overlayMode = JBOverlayModeNone;
            break;
        }
        case 2: {
            [self onTapResizeMode];
            return;
        }
        case 3: {
            self.isFloatingMode = !self.isFloatingMode;
            self.overlayMode = JBOverlayModeNone;
            [self.delegate keyboardView:self didToggleFloatingMode:self.isFloatingMode];
            break;
        }
        case 4: {
            if (self.undoHistory.count > 0) {
                NSString *last = self.undoHistory.lastObject;
                [self.undoHistory removeLastObject];
                for (NSInteger i = 0; i < last.length; i++) {
                    [self performSingleBackspace];
                }
            }
            self.overlayMode = JBOverlayModeNone;
            break;
        }
        case 5: {
            [self onTapToggleLanguage];
            self.overlayMode = JBOverlayModeNone;
            break;
        }
        case 6: {
            JBClipboardItem *first = [JBClipboardManager sharedManager].pinnedItems.firstObject ?: [JBClipboardManager sharedManager].recentItems.firstObject;
            if (first.text.length > 0) {
                [self commitTextToTarget:first.text];
            }
            self.overlayMode = JBOverlayModeNone;
            break;
        }
        default:
            self.overlayMode = JBOverlayModeNone;
            break;
    }
    [self rebuildToolbar];
    [self rebuildKeyboardKeys];
    [self setNeedsLayout];
}

#pragma mark - Đổi kích thước bàn phím

- (void)onTapResizeMode {
    self.overlayMode = JBOverlayModeResize;
    [self rebuildToolbar];
    [self.overlayContainerView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    CGFloat w = self.bounds.size.width > 0 ? self.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    CGFloat bodyH = self.preferredKeyboardHeight - 44.0;
    
    UIView *frameBox = [[UIView alloc] initWithFrame:CGRectMake(12, 8, w - 24, bodyH - 16)];
    frameBox.layer.cornerRadius = 14.0;
    frameBox.layer.borderWidth = 2.0;
    frameBox.layer.borderColor = [self gboardAccentBlueColor].CGColor;
    [self.overlayContainerView addSubview:frameBox];
    
    UILabel *guide = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, frameBox.bounds.size.width - 40, 44)];
    guide.text = @"Kéo tay cầm trên cùng để thay đổi chiều cao bàn phím";
    guide.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    guide.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    guide.textAlignment = NSTextAlignmentCenter;
    guide.numberOfLines = 2;
    [frameBox addSubview:guide];
    
    UIButton *dragHandle = [UIButton buttonWithType:UIButtonTypeSystem];
    dragHandle.frame = CGRectMake((frameBox.bounds.size.width - 44) * 0.5, -14, 44, 28);
    dragHandle.backgroundColor = [self gboardAccentBlueColor];
    dragHandle.tintColor = [self gboardAccentDarkTextColor];
    dragHandle.layer.cornerRadius = 14.0;
    [dragHandle setImage:[UIImage systemImageNamed:@"arrow.up.and.down"] forState:UIControlStateNormal];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanResizeHandle:)];
    [dragHandle addGestureRecognizer:pan];
    [frameBox addSubview:dragHandle];
    
    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    doneBtn.frame = CGRectMake((frameBox.bounds.size.width - 110) * 0.5, frameBox.bounds.size.height - 52, 110, 38);
    doneBtn.backgroundColor = [self gboardAccentBlueColor];
    doneBtn.layer.cornerRadius = 19.0;
    [doneBtn setTitle:@"Xong" forState:UIControlStateNormal];
    [doneBtn setTitleColor:[self gboardAccentDarkTextColor] forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [doneBtn addTarget:self action:@selector(onFinishResize) forControlEvents:UIControlEventTouchUpInside];
    [frameBox addSubview:doneBtn];
    
    [self setNeedsLayout];
}

- (void)onPanResizeHandle:(UIPanGestureRecognizer *)pan {
    CGPoint delta = [pan translationInView:self];
    [pan setTranslation:CGPointZero inView:self];
    CGFloat nextH = MAX(220.0, MIN(380.0, self.preferredKeyboardHeight - delta.y));
    self.preferredKeyboardHeight = nextH;
    [self.delegate keyboardView:self didChangeHeight:nextH];
    [self onTapResizeMode];
}

- (void)onFinishResize {
    self.overlayMode = JBOverlayModeNone;
    [self rebuildToolbar];
    [self setNeedsLayout];
}

#pragma mark - Bảng nhớ tạm (Clipboard)

static char kClipItemAssocKey;
static char kDeletedItemAssocKey;

- (void)onTapClipboard {
    [[JBClipboardManager sharedManager] syncWithSystemPasteboard];
    self.overlayMode = JBOverlayModeClipboard;
    self.isClipboardEditMode = NO;
    [self buildClipboardOverlayWithUndoItem:nil];
    [self setNeedsLayout];
}

- (void)buildClipboardOverlayWithUndoItem:(nullable JBClipboardItem *)deletedItem {
    [self.overlayContainerView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    CGFloat w = self.bounds.size.width > 0 ? self.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    CGFloat h = self.bounds.size.height > 0 ? self.bounds.size.height : self.preferredKeyboardHeight;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium];
    
    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    backBtn.frame = CGRectMake(12, 10, 36, 36);
    backBtn.backgroundColor = [self gboardFuncKeyColor];
    backBtn.tintColor = [UIColor whiteColor];
    backBtn.layer.cornerRadius = 18.0;
    [backBtn setImage:[UIImage systemImageNamed:@"arrow.left" withConfiguration:cfg] forState:UIControlStateNormal];
    [backBtn addTarget:self action:@selector(onCloseClipboard) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayContainerView addSubview:backBtn];
    
    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(58, 10, 170, 36)];
    titleLbl.text = @"Bảng nhớ tạm";
    titleLbl.textColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    titleLbl.font = [UIFont systemFontOfSize:19 weight:UIFontWeightMedium];
    [self.overlayContainerView addSubview:titleLbl];
    
    UIButton *toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    toggleBtn.frame = CGRectMake(w - 94, 10, 36, 36);
    toggleBtn.backgroundColor = [self gboardFuncKeyColor];
    toggleBtn.tintColor = [JBClipboardManager sharedManager].isEnabled ? [self gboardAccentBlueColor] : [UIColor grayColor];
    toggleBtn.layer.cornerRadius = 18.0;
    [toggleBtn setImage:[UIImage systemImageNamed:@"switch.2" withConfiguration:cfg] forState:UIControlStateNormal];
    [toggleBtn addTarget:self action:@selector(onToggleClipboardEnabled) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayContainerView addSubview:toggleBtn];
    
    UIButton *editBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    editBtn.frame = CGRectMake(w - 48, 10, 36, 36);
    editBtn.backgroundColor = self.isClipboardEditMode ? [self gboardAccentBlueColor] : [self gboardFuncKeyColor];
    editBtn.tintColor = self.isClipboardEditMode ? [self gboardAccentDarkTextColor] : [UIColor whiteColor];
    editBtn.layer.cornerRadius = 18.0;
    [editBtn setImage:[UIImage systemImageNamed:@"pencil" withConfiguration:cfg] forState:UIControlStateNormal];
    [editBtn addTarget:self action:@selector(onToggleClipboardEdit) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayContainerView addSubview:editBtn];
    
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 54, w, h - 54)];
    [self.overlayContainerView addSubview:scroll];
    
    CGFloat curY = 4.0;
    NSArray<JBClipboardItem *> *pinned = [JBClipboardManager sharedManager].pinnedItems;
    NSArray<JBClipboardItem *> *recent = [JBClipboardManager sharedManager].recentItems;
    
    if (pinned.count > 0) {
        UILabel *sec = [[UILabel alloc] initWithFrame:CGRectMake(14, curY, w - 28, 20)];
        sec.text = @"Đã ghim";
        sec.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
        sec.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [scroll addSubview:sec];
        curY += 26.0;
        curY = [self layoutClipboardCards:pinned inScrollView:scroll startY:curY width:w];
    }
    
    if (recent.count > 0) {
        UILabel *sec = [[UILabel alloc] initWithFrame:CGRectMake(14, curY + 4, w - 28, 20)];
        sec.text = @"Gần đây";
        sec.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
        sec.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [scroll addSubview:sec];
        curY += 30.0;
        curY = [self layoutClipboardCards:recent inScrollView:scroll startY:curY width:w];
    }
    
    scroll.contentSize = CGSizeMake(w, curY + 64.0);
    
    if (deletedItem) {
        CGFloat snackW = 240.0;
        CGFloat snackH = 44.0;
        UIView *snack = [[UIView alloc] initWithFrame:CGRectMake((w - snackW) * 0.5, h - snackH - 14, snackW, snackH)];
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
    CGFloat pad = 12.0;
    CGFloat gap = 10.0;
    CGFloat cardW = (w - pad * 2 - gap) * 0.5;
    CGFloat cardH = 46.0;
    
    for (NSInteger i = 0; i < list.count; i++) {
        JBClipboardItem *item = list[i];
        NSInteger r = i / 2;
        NSInteger c = i % 2;
        
        UIButton *card = [UIButton buttonWithType:UIButtonTypeSystem];
        card.frame = CGRectMake(pad + c * (cardW + gap), startY + r * (cardH + gap), cardW, cardH);
        card.backgroundColor = [self gboardKeyColor];
        card.layer.cornerRadius = 12.0;
        card.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        card.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, self.isClipboardEditMode ? 36 : 12);
        card.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        card.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [card setTitle:item.text forState:UIControlStateNormal];
        [card setTitleColor:[UIColor colorWithWhite:0.94 alpha:1.0] forState:UIControlStateNormal];
        objc_setAssociatedObject(card, &kClipItemAssocKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [card addTarget:self action:@selector(onTapClipboardCard:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:card];
        
        if (self.isClipboardEditMode) {
            UIButton *delBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            delBtn.frame = CGRectMake(cardW - 32, (cardH - 26) * 0.5, 26, 26);
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
    JBClipboardItem *item = objc_getAssociatedObject(sender, &kClipItemAssocKey);
    if (!item) return;
    JBClipboardItem *removed = [[JBClipboardManager sharedManager] deleteItemWithIdentifier:item.identifier];
    [self buildClipboardOverlayWithUndoItem:removed];
}

- (void)onUndoDeleteClipboardItem:(UIButton *)sender {
    JBClipboardItem *item = objc_getAssociatedObject(sender, &kDeletedItemAssocKey);
    if (item) {
        [[JBClipboardManager sharedManager] restoreDeletedItem:item atIndex:0];
        [self buildClipboardOverlayWithUndoItem:nil];
    }
}

- (void)onToggleClipboardEnabled {
    [JBClipboardManager sharedManager].isEnabled = ![JBClipboardManager sharedManager].isEnabled;
    [self buildClipboardOverlayWithUndoItem:nil];
}

- (void)onToggleClipboardEdit {
    self.isClipboardEditMode = !self.isClipboardEditMode;
    [self buildClipboardOverlayWithUndoItem:nil];
}

- (void)onCloseClipboard {
    self.overlayMode = JBOverlayModeNone;
    [self rebuildToolbar];
    [self setNeedsLayout];
}

#pragma mark - Hộp thoại Thay đổi bàn phím

- (void)onLongPressSpace:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self showLanguagePickerDialog];
}

- (void)onTapToggleLanguage {
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
    
    CGFloat cardW = MIN(310.0, targetHost.bounds.size.width - 48.0);
    CGFloat cardH = 230.0;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake((targetHost.bounds.size.width - cardW) * 0.5, (targetHost.bounds.size.height - cardH) * 0.5, cardW, cardH)];
    card.backgroundColor = [UIColor colorWithRed:0.17 green:0.16 blue:0.20 alpha:1.0];
    card.layer.cornerRadius = 26.0;
    [dim addSubview:card];
    
    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(24, 20, cardW - 48, 30)];
    header.text = @"Thay đổi bàn phím";
    header.textColor = [UIColor whiteColor];
    header.font = [UIFont systemFontOfSize:21 weight:UIFontWeightRegular];
    header.textAlignment = NSTextAlignmentCenter;
    [card addSubview:header];
    
    UIButton *viBtn = [self createLangOptionButtonFrame:CGRectMake(16, 62, cardW - 32, 54)
                                                  title:@"Tiếng Việt (Việt Nam)"
                                               subtitle:@"QWERTY"
                                               selected:(self.ime.currentLanguage == JBInputLanguageVietnamese)];
    viBtn.tag = JBInputLanguageVietnamese;
    [viBtn addTarget:self action:@selector(onSelectLanguageFromDialog:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:viBtn];
    
    UIButton *enBtn = [self createLangOptionButtonFrame:CGRectMake(16, 122, cardW - 32, 54)
                                                  title:@"English (US)"
                                               subtitle:@"QWERTY"
                                               selected:(self.ime.currentLanguage == JBInputLanguageEnglish)];
    enBtn.tag = JBInputLanguageEnglish;
    [enBtn addTarget:self action:@selector(onSelectLanguageFromDialog:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:enBtn];
    
    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(24, 186, cardW - 48, 24)];
    footer.text = @"Cài đặt ngôn ngữ";
    footer.textColor = [self gboardAccentBlueColor];
    footer.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    footer.textAlignment = NSTextAlignmentRight;
    [card addSubview:footer];
    
    [targetHost addSubview:dim];
}

- (UIButton *)createLangOptionButtonFrame:(CGRect)frame title:(NSString *)title subtitle:(NSString *)sub selected:(BOOL)selected {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    btn.layer.cornerRadius = frame.size.height * 0.5;
    btn.backgroundColor = selected ? [UIColor colorWithRed:0.82 green:0.89 blue:0.99 alpha:1.0] : [UIColor clearColor];
    
    UIColor *fg = selected ? [self gboardAccentDarkTextColor] : [UIColor colorWithWhite:0.92 alpha:1.0];
    if (selected) {
        UIImageView *check = [[UIImageView alloc] initWithFrame:CGRectMake(18, 17, 20, 20)];
        check.image = [UIImage systemImageNamed:@"checkmark"];
        check.tintColor = fg;
        [btn addSubview:check];
    }
    
    UILabel *tLbl = [[UILabel alloc] initWithFrame:CGRectMake(52, 8, frame.size.width - 64, 20)];
    tLbl.text = title;
    tLbl.textColor = fg;
    tLbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [btn addSubview:tLbl];
    
    UILabel *sLbl = [[UILabel alloc] initWithFrame:CGRectMake(52, 29, frame.size.width - 64, 16)];
    sLbl.text = sub;
    sLbl.textColor = selected ? fg : [UIColor colorWithWhite:0.65 alpha:1.0];
    sLbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    [btn addSubview:sLbl];
    
    return btn;
}

- (void)onSelectLanguageFromDialog:(UIButton *)sender {
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
    CGFloat h = self.keysContainerView.bounds.size.height > 0 ? self.keysContainerView.bounds.size.height : 230.0;
    
    CGFloat cellW = w / 8.0;
    CGFloat cellH = (h - 46.0) / 3.0;
    for (NSInteger i = 0; i < emojis.count; i++) {
        NSInteger r = i / 8;
        NSInteger c = i % 8;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(c * cellW, r * cellH, cellW, cellH);
        b.titleLabel.font = [UIFont systemFontOfSize:26];
        [b setTitle:emojis[i] forState:UIControlStateNormal];
        [b addTarget:self action:@selector(onTapEmojiChar:) forControlEvents:UIControlEventTouchUpInside];
        [self.keysContainerView addSubview:b];
    }
    
    UIButton *abcBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    abcBtn.frame = CGRectMake(8, h - 42, 64, 36);
    abcBtn.backgroundColor = [self gboardFuncKeyColor];
    abcBtn.layer.cornerRadius = 18.0;
    [abcBtn setTitle:@"ABC" forState:UIControlStateNormal];
    [abcBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [abcBtn addTarget:self action:@selector(onTapEmojiPage) forControlEvents:UIControlEventTouchUpInside];
    [self.keysContainerView addSubview:abcBtn];
}

- (void)onTapEmojiChar:(UIButton *)sender {
    NSString *e = [sender titleForState:UIControlStateNormal];
    if (e.length > 0) [self commitTextToTarget:e];
}

- (void)onTapHideKeyboard {
    [self.delegate keyboardViewDidTapHide:self];
}

@end
