#import "JBKeyboardView.h"
#import "JBClipboardManager.h"

@interface JBKeyButton : UIButton
@property(nonatomic, copy) NSString *output;
@end
@implementation JBKeyButton @end

@interface JBKeyboardView ()
@property(nonatomic, strong) UIStackView *rootStack;
@property(nonatomic, strong) UIView *toolbar;
@property(nonatomic, strong) UIView *suggestionBar;
@property(nonatomic, strong) UIScrollView *suggestionScroll;
@property(nonatomic, strong) NSMutableArray<JBKeyButton *> *buttons;
@property(nonatomic, strong) UIView *popupView;
@property(nonatomic, strong) UIView *overlayView;
@property(nonatomic, assign) BOOL symbolsMode;
@property(nonatomic, assign) BOOL toolsMode;
@property(nonatomic, assign) BOOL clipboardMode;
@property(nonatomic, assign) BOOL floatingMode;
@property(nonatomic, assign) BOOL editMode;
@property(nonatomic, strong) UIButton *resizeButton;
@end

@implementation JBKeyboardView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _keyboardHeight = 300.0;
        _ime = [JBKeyboardIME new];
        _vietnamese = YES;
        _buttons = [NSMutableArray array];
        self.backgroundColor = [UIColor colorWithRed:0.105 green:0.110 blue:0.120 alpha:1];
        self.layer.cornerRadius = 0;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    self.toolbar = [[UIView alloc] init];
    self.toolbar.backgroundColor = [UIColor colorWithRed:0.105 green:0.110 blue:0.120 alpha:1];
    [self addSubview:self.toolbar];

    NSArray *icons = @[@"▦", @"▣", @"G文", @"⚙", @"●"];
    for (NSInteger i = 0; i < icons.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:icons[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:(i == 4 ? 26 : 20) weight:UIFontWeightMedium];
        [b setTitleColor:[UIColor colorWithWhite:0.92 alpha:1] forState:UIControlStateNormal];
        b.backgroundColor = i == 4 ? [UIColor colorWithWhite:0.22 alpha:1] : UIColor.clearColor;
        b.layer.cornerRadius = i == 4 ? 28 : 12;
        b.tag = 500 + i;
        [b addTarget:self action:@selector(toolbarAction:) forControlEvents:UIControlEventTouchUpInside];
        [self.toolbar addSubview:b];
    }

    self.suggestionBar = [[UIView alloc] init];
    self.suggestionBar.backgroundColor = [UIColor colorWithRed:0.105 green:0.110 blue:0.120 alpha:1];
    [self addSubview:self.suggestionBar];
    self.suggestionScroll = [[UIScrollView alloc] init];
    self.suggestionScroll.showsHorizontalScrollIndicator = NO;
    [self.suggestionBar addSubview:self.suggestionScroll];

    self.rootStack = [[UIStackView alloc] init];
    self.rootStack.axis = UILayoutConstraintAxisVertical;
    self.rootStack.spacing = 8;
    self.rootStack.distribution = UIStackViewDistributionFillEqually;
    [self addSubview:self.rootStack];

    [self reloadKeyboard];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat toolbarH = 52;
    CGFloat suggestionH = 0;
    self.toolbar.frame = CGRectMake(0, 0, self.bounds.size.width, toolbarH);
    NSArray *tb = self.toolbar.subviews;
    CGFloat side = 52, gap = (self.bounds.size.width - side * tb.count) / MAX(1, tb.count + 1);
    for (NSInteger i=0;i<tb.count;i++) {
        UIView *v = tb[i];
        CGFloat x = gap + i * (side + gap);
        CGFloat w = side;
        v.frame = CGRectMake(x, 4, w, 44);
    }
    self.suggestionBar.frame = CGRectMake(0, toolbarH, self.bounds.size.width, suggestionH);
    self.suggestionScroll.frame = self.suggestionBar.bounds;
    self.rootStack.frame = CGRectMake(12, toolbarH + 4,
                                      self.bounds.size.width - 24,
                                      self.bounds.size.height - toolbarH - suggestionH - 8);
}

- (UIButton *)makeKey:(NSString *)title output:(NSString *)output {
    JBKeyButton *b = [JBKeyButton buttonWithType:UIButtonTypeSystem];
    b.output = output ?: title;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightRegular];
    [b setTitleColor:[UIColor colorWithWhite:0.91 alpha:1] forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithRed:0.19 green:0.20 blue:0.21 alpha:1];
    b.layer.cornerRadius = 7;
    b.layer.masksToBounds = YES;
    [b addTarget:self action:@selector(keyDown:) forControlEvents:UIControlEventTouchUpInside];

    if ([self alternatesForKey:output].count) {
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
        lp.minimumPressDuration = 0.25;
        [b addGestureRecognizer:lp];
    }
    [self.buttons addObject:b];
    return b;
}

- (NSArray *)alternatesForKey:(NSString *)key {
    NSDictionary *d = @{
        @"a": @[@"á",@"à",@"ả",@"ã",@"ạ",@"â",@"ă"],
        @"e": @[@"é",@"è",@"ẻ",@"ẽ",@"ẹ",@"ê"],
        @"i": @[@"í",@"ì",@"ỉ",@"ĩ",@"ị"],
        @"o": @[@"ó",@"ò",@"ỏ",@"õ",@"ọ",@"ô",@"ơ"],
        @"u": @[@"ú",@"ù",@"ủ",@"ũ",@"ụ",@"ư"],
        @"y": @[@"ý",@"ỳ",@"ỷ",@"ỹ",@"ỵ"],
        @"d": @[@"đ"],
        @".": @[@"!",@"?",@",",@"…"]
    };
    return d[key.lowercaseString] ?: @[];
}

- (void)clearRoot {
    for (UIView *v in [self.rootStack.arrangedSubviews copy]) {
        [self.rootStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    [self.buttons removeAllObjects];
}

- (void)reloadKeyboard {
    self.symbolsMode = NO;
    self.toolsMode = NO;
    self.clipboardMode = NO;
    [self.overlayView removeFromSuperview]; self.overlayView = nil;
    [self clearRoot];

    NSArray *rows = @[
        @[@"q",@"w",@"e",@"r",@"t",@"y",@"u",@"i",@"o",@"p"],
        @[@"a",@"s",@"d",@"f",@"g",@"h",@"j",@"k",@"l"],
        @[@"⇧",@"z",@"x",@"c",@"v",@"b",@"n",@"m",@"⌫"]
    ];
    for (NSArray *keys in rows) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal; row.spacing = 6; row.distribution = UIStackViewDistributionFillEqually;
        for (NSString *k in keys) {
            NSString *out = k;
            NSString *title = k;
            if (self.shift && k.length == 1 && [k rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location != NSNotFound) title = k.uppercaseString;
            UIButton *b = [self makeKey:title output:out];
            if ([k isEqualToString:@"⇧"] || [k isEqualToString:@"⌫"]) b.backgroundColor = [UIColor colorWithRed:0.25 green:0.26 blue:0.27 alpha:1];
            [row addArrangedSubview:b];
        }
        [self.rootStack addArrangedSubview:row];
    }

    UIStackView *bottom = [[UIStackView alloc] init];
    bottom.axis = UILayoutConstraintAxisHorizontal; bottom.spacing = 6;
    NSArray *keys = @[@"?123", @"◉", @"space", @".", @"↵"];
    NSArray *weights = @[@0.9,@0.75,@3.0,@0.75,@0.9];
    for (NSInteger i=0;i<keys.count;i++) {
        UIButton *b = [self makeKey:keys[i] output:keys[i]];
        if (i == 2) [b setTitle:self.vietnamese ? @"Tiếng Việt" : @"English" forState:UIControlStateNormal];
        if (i == 0 || i == 1) b.backgroundColor = [UIColor colorWithRed:0.25 green:0.26 blue:0.27 alpha:1];
        if (i == 4) { b.backgroundColor = [UIColor colorWithRed:0.42 green:0.66 blue:0.98 alpha:1]; [b setTitleColor:[UIColor colorWithRed:0.04 green:0.12 blue:0.22 alpha:1] forState:UIControlStateNormal]; }
        [bottom addArrangedSubview:b];
        [b.widthAnchor constraintEqualToAnchor:bottom.widthAnchor multiplier:[weights[i] doubleValue]/6.3].active = YES;
    }
    [self.rootStack addArrangedSubview:bottom];
    [self updateSuggestions];
}

- (void)toolbarAction:(UIButton *)sender {
    switch (sender.tag - 500) {
        case 0: [self showTools]; break;
        case 1: [self showClipboard]; break;
        case 2: self.vietnamese = !self.vietnamese; self.ime.language = self.vietnamese ? @"vi" : @"en"; self.ime.telexEnabled = self.vietnamese; [self reloadKeyboard]; break;
        case 3: [self showSettings]; break;
        case 4: [self.delegate keyboardView:self didInsertText:@"🎙"]; break;
    }
}

- (void)keyDown:(JBKeyButton *)b {
    NSString *o = b.output;
    if ([o isEqualToString:@"⌫"]) { [self.delegate keyboardViewDidDeleteBackward:self]; return; }
    if ([o isEqualToString:@"↵"]) { [self.delegate keyboardViewDidPressReturn:self]; return; }
    if ([o isEqualToString:@"⇧"]) { self.shift = !self.shift; [self reloadKeyboard]; return; }
    if ([o isEqualToString:@"?123"]) { [self showSymbols]; return; }
    if ([o isEqualToString:@"◉"]) { self.floatingMode = !self.floatingMode; self.layer.cornerRadius = self.floatingMode ? 16 : 0; return; }
    if ([o isEqualToString:@"space"]) { [self.delegate keyboardView:self didInsertText:@" "]; [self updateSuggestions]; return; }
    if ([o isEqualToString:@"."]) { [self.delegate keyboardView:self didInsertText:@"."]; return; }
    [self.delegate keyboardView:self didInsertText:o];
    if (self.shift) { self.shift = NO; [self reloadKeyboard]; }
    else [self updateSuggestions];
}

- (void)showSymbols {
    self.symbolsMode = YES; self.toolsMode = NO; self.clipboardMode = NO; [self clearRoot];
    NSArray *rows = @[
        @[@"1",@"2",@"3",@"4",@"5",@"6",@"7",@"8",@"9",@"0"],
        @[@"@",@"#",@"đ",@"_",@"&",@"-",@"+",@"(",@")",@"/"],
        @[@"=\\<",@"*",@"\"",@"'",@":",@";",@"!",@"?",@"⌫"]
    ];
    for (NSArray *keys in rows) {
        UIStackView *row = [UIStackView new]; row.axis = UILayoutConstraintAxisHorizontal; row.spacing = 6; row.distribution = UIStackViewDistributionFillEqually;
        for (NSString *k in keys) [row addArrangedSubview:[self makeKey:k output:k]];
        [self.rootStack addArrangedSubview:row];
    }
    UIStackView *bottom = [UIStackView new]; bottom.axis = UILayoutConstraintAxisHorizontal; bottom.spacing = 6; bottom.distribution = UIStackViewDistributionFillEqually;
    for (NSString *k in @[@"ABC",@",",@"12 34",@"space",@".",@"↵"]) {
        UIButton *b = [self makeKey:k output:k]; [bottom addArrangedSubview:b];
        if ([k isEqualToString:@"ABC"]) [b addTarget:self action:@selector(backToLetters:) forControlEvents:UIControlEventTouchUpInside];
    }
    [self.rootStack addArrangedSubview:bottom];
}

- (void)backToLetters:(UIButton *)sender { [self reloadKeyboard]; }

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    JBKeyButton *key = (JBKeyButton *)g.view;
    NSArray *alts = [self alternatesForKey:key.output];
    if (!alts.count) return;
    [self.popupView removeFromSuperview];
    UIView *p = [[UIView alloc] initWithFrame:CGRectZero];
    p.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.24 alpha:1];
    p.layer.cornerRadius = 18; p.layer.masksToBounds = YES;
    NSInteger cols = 4, rows = (NSInteger)ceil(alts.count / 4.0);
    CGFloat w = 72, h = 48;
    p.frame = CGRectMake(0, 0, cols*w, rows*h);
    for (NSInteger i=0;i<alts.count;i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake((i%cols)*w, (i/cols)*h, w, h);
        [b setTitle:alts[i] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithWhite:0.95 alpha:1] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:21];
        b.tag = 900+i;
        [b addTarget:self action:@selector(popupCharacter:) forControlEvents:UIControlEventTouchUpInside];
        [p addSubview:b];
    }
    self.popupView = p;
    [self addSubview:p];
    CGRect r = [key convertRect:key.bounds toView:self];
    CGFloat x = MIN(MAX(8, CGRectGetMidX(r)-p.bounds.size.width/2), self.bounds.size.width-p.bounds.size.width-8);
    CGFloat y = MAX(54, CGRectGetMinY(r)-p.bounds.size.height-8);
    p.frame = CGRectMake(x, y, p.bounds.size.width, p.bounds.size.height);
}

- (void)popupCharacter:(UIButton *)sender {
    NSArray *letters = @[];
    // Recover the visible popup's title directly; this keeps the long-press UI independent of IME internals.
    [self.delegate keyboardView:self didInsertText:sender.currentTitle ?: @""];
    [self.popupView removeFromSuperview]; self.popupView = nil;
    (void)letters;
}

- (void)showTools {
    self.toolsMode = YES; self.clipboardMode = NO; self.symbolsMode = NO;
    [self clearRoot];
    NSArray *titles = @[@"↗  Sẽ Gboard",@"⌗  Đổi kích thước",@"▣  Nổi",@"↶  Huỷ",@"◎  Ngữ tiếp theo",@"▧  Tự động điền"];
    for (NSInteger r=0;r<3;r++) {
        UIStackView *row = [UIStackView new]; row.axis=UILayoutConstraintAxisHorizontal; row.spacing=12; row.distribution=UIStackViewDistributionFillEqually;
        for (NSInteger c=0;c<2;c++) {
            NSInteger idx=r*2+c;
            UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; [b setTitle:titles[idx] forState:UIControlStateNormal];
            [b setTitleColor:[UIColor colorWithWhite:0.88 alpha:1] forState:UIControlStateNormal]; b.titleLabel.font=[UIFont systemFontOfSize:17];
            b.backgroundColor=[UIColor colorWithRed:0.22 green:0.23 blue:0.24 alpha:1]; b.layer.cornerRadius=26; b.tag=700+idx;
            [b addTarget:self action:@selector(toolButton:) forControlEvents:UIControlEventTouchUpInside]; [row addArrangedSubview:b];
        }
        [self.rootStack addArrangedSubview:row];
    }
    UIStackView *last=[UIStackView new]; last.axis=UILayoutConstraintAxisHorizontal; last.distribution=UIStackViewDistributionFillEqually;
    UIButton *edit=[UIButton buttonWithType:UIButtonTypeSystem]; [edit setTitle:@"✎" forState:UIControlStateNormal]; edit.titleLabel.font=[UIFont systemFontOfSize:28]; edit.layer.cornerRadius=28; edit.layer.borderWidth=1; edit.layer.borderColor=[UIColor colorWithWhite:0.7 alpha:1].CGColor; edit.tag=799; [edit addTarget:self action:@selector(toolButton:) forControlEvents:UIControlEventTouchUpInside]; [last addArrangedSubview:edit];
    [self.rootStack addArrangedSubview:last];
}

- (void)toolButton:(UIButton *)b {
    switch (b.tag-700) {
        case 1: self.keyboardHeight = MIN(420, self.keyboardHeight + 30); break;
        case 2: self.floatingMode = !self.floatingMode; break;
        case 3: [self.delegate keyboardViewDidDismiss:self]; return;
        case 4: self.vietnamese = !self.vietnamese; self.ime.language = self.vietnamese ? @"vi" : @"en"; self.ime.telexEnabled = self.vietnamese; break;
        case 5: [self pasteClipboardText]; break;
        default: break;
    }
    [self reloadKeyboard];
}

- (void)showClipboard {
    self.clipboardMode=YES; self.toolsMode=NO; self.symbolsMode=NO; [self clearRoot];
    UIStackView *header=[UIStackView new]; header.axis=UILayoutConstraintAxisHorizontal; header.distribution=UIStackViewDistributionFill;
    UIButton *back=[UIButton buttonWithType:UIButtonTypeSystem]; [back setTitle:@"‹  Bảng nhớ tạm" forState:UIControlStateNormal]; [back setTitleColor:[UIColor colorWithWhite:0.95 alpha:1] forState:UIControlStateNormal]; back.titleLabel.font=[UIFont systemFontOfSize:21 weight:UIFontWeightMedium]; [back addTarget:self action:@selector(reloadKeyboard) forControlEvents:UIControlEventTouchUpInside]; [header addArrangedSubview:back];
    [self.rootStack addArrangedSubview:header];
    NSArray *items=[JBClipboardManager.shared items];
    NSInteger maxItems=MIN(6, items.count);
    for (NSInteger i=0;i<maxItems;i++) {
        UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; [b setTitle:items[i] forState:UIControlStateNormal]; [b setTitleColor:[UIColor colorWithWhite:0.90 alpha:1] forState:UIControlStateNormal]; b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft; b.titleLabel.font=[UIFont systemFontOfSize:17]; b.backgroundColor=[UIColor colorWithRed:0.22 green:0.23 blue:0.24 alpha:1]; b.layer.cornerRadius=8; b.contentEdgeInsets=UIEdgeInsetsMake(0,16,0,16); b.tag=800+i; [b addTarget:self action:@selector(clipboardItem:) forControlEvents:UIControlEventTouchUpInside]; [self.rootStack addArrangedSubview:b];
    }
    if (!items.count) { UILabel *empty=[UILabel new]; empty.text=@"Chưa có nội dung đã sao chép"; empty.textColor=[UIColor colorWithWhite:0.55 alpha:1]; empty.textAlignment=NSTextAlignmentCenter; [self.rootStack addArrangedSubview:empty]; }
}

- (void)clipboardItem:(UIButton *)b { NSInteger i=b.tag-800; NSArray *items=[JBClipboardManager.shared items]; if(i<items.count){[self.delegate keyboardView:self didInsertText:items[i]]; [self reloadKeyboard];} }
- (void)pasteClipboardText { NSString *s=UIPasteboard.generalPasteboard.string; if(s.length){[[JBClipboardManager shared] addText:s]; [self.delegate keyboardView:self didInsertText:s];} }

- (void)showSettings {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Bàn phím" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:self.vietnamese?@"✓ Tiếng Việt (Việt Nam)":"Tiếng Việt" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ self.vietnamese=YES; self.ime.language=@"vi"; self.ime.telexEnabled=YES; [self reloadKeyboard]; }]];
    [a addAction:[UIAlertAction actionWithTitle:!self.vietnamese?@"✓ English (US)":"English (US)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ self.vietnamese=NO; self.ime.language=@"en"; self.ime.telexEnabled=NO; [self reloadKeyboard]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cài đặt ngôn ngữ" style:UIAlertActionStyleDefault handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *vc=self.window.rootViewController; while(vc.presentedViewController) vc=vc.presentedViewController; if(vc){a.popoverPresentationController.sourceView=self; a.popoverPresentationController.sourceRect=CGRectMake(self.bounds.size.width/2,self.bounds.size.height/2,1,1); [vc presentViewController:a animated:YES completion:nil];}
}

- (void)updateSuggestions { for(UIView *v in [self.suggestionScroll.subviews copy]) [v removeFromSuperview]; }

@end
