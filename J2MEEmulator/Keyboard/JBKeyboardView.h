#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class JBKeyboardView;

@protocol JBKeyboardViewDelegate <NSObject>
- (void)keyboardView:(JBKeyboardView *)keyboardView didInsertText:(NSString *)text;
- (void)keyboardViewDidTapBackspace:(JBKeyboardView *)keyboardView;
- (void)keyboardViewDidTapReturn:(JBKeyboardView *)keyboardView;
- (void)keyboardViewDidTapSubmit:(JBKeyboardView *)keyboardView;
- (void)keyboardViewDidTapHide:(JBKeyboardView *)keyboardView;
- (void)keyboardView:(JBKeyboardView *)keyboardView didChangeHeight:(CGFloat)newHeight;
- (void)keyboardView:(JBKeyboardView *)keyboardView didToggleFloatingMode:(BOOL)isFloating;
@end

@interface JBKeyboardView : UIView

@property (nonatomic, weak, nullable) id<JBKeyboardViewDelegate> delegate;
@property (nonatomic, assign) CGFloat keyboardHeight;
@property (nonatomic, assign) CGFloat preferredKeyboardHeight;
@property (nonatomic, assign) BOOL isFloatingMode;
@property (nonatomic, copy) NSString *currentText;

- (void)reloadKeyboard;
- (void)reloadKeyboardLayout;

@end

NS_ASSUME_NONNULL_END
