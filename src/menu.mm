#import "menu.h"

#import <UIKit/UIKit.h>

#include "game.hpp"
#import "logger.h"

// ============================================================
// Cửa sổ overlay: chỉ nhận chạm trên các view của menu,
// mọi chạm còn lại xuyên xuống game.
// ============================================================
@interface SWWindow : UIWindow
@end

@implementation SWWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

// ============================================================
// Helpers dựng giao diện
// ============================================================
static UILabel *SWMakeLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

static UIButton *SWMakeButton(NSString *title, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    button.layer.cornerRadius = 8;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:36].active = YES;
    return button;
}

static UIStackView *SWMakeStack(UILayoutConstraintAxis axis, CGFloat spacing) {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = axis;
    stack.spacing = spacing;
    return stack;
}

static UISegmentedControl *SWMakeSegments(NSArray<NSString *> *items, NSInteger tag, id target, SEL action) {
    UISegmentedControl *segments = [[UISegmentedControl alloc] initWithItems:items];
    segments.selectedSegmentIndex = 0;
    segments.tag = tag;
    if (action) [segments addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    return segments;
}

// ============================================================
// Màn hình chính của overlay
// ============================================================
@interface SWMenuViewController : UIViewController
@end

@implementation SWMenuViewController {
    UIButton *_fab;
    UIView *_panel;
    UIScrollView *_scroll;
    UILabel *_statusLabel;
    UILabel *_resultLabel;
    UISegmentedControl *_spawnTeam;
    UISegmentedControl *_spawnCount;
    UIView *_logContainer;
    UITextView *_logText;
    NSTimer *_timer;
    game::GoldMode _friendlyGold;
    game::GoldMode _enemyGold;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    [self buildFab];
    [self buildPanel];
    [self buildLogView];

    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                              target:self
                                            selector:@selector(tick)
                                            userInfo:nil
                                             repeats:YES];
}

#pragma mark - Dựng giao diện

- (void)buildFab {
    _fab = [UIButton buttonWithType:UIButtonTypeSystem];
    _fab.frame = CGRectMake(16, 56, 46, 46);
    _fab.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    _fab.layer.cornerRadius = 23;
    _fab.layer.borderWidth = 1;
    _fab.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.5].CGColor;
    [_fab setTitle:@"SW" forState:UIControlStateNormal];
    [_fab setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _fab.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [_fab addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFab:)];
    [_fab addGestureRecognizer:pan];
    [self.view addSubview:_fab];
}

- (void)buildPanel {
    _panel = [[UIView alloc] init];
    _panel.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _panel.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
    _panel.layer.cornerRadius = 14;
    _panel.clipsToBounds = YES;
    _panel.hidden = YES;
    [self.view addSubview:_panel];

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.alwaysBounceVertical = YES;
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_panel addSubview:_scroll];

    UIStackView *stack = SWMakeStack(UILayoutConstraintAxisVertical, 8);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor constant:-12],
        [stack.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor constant:-24],
    ]];

    UIColor *dim = [UIColor colorWithWhite:1 alpha:0.6];

    // --- Tiêu đề + nút đóng ---
    UIStackView *titleRow = SWMakeStack(UILayoutConstraintAxisHorizontal, 8);
    titleRow.alignment = UIStackViewAlignmentCenter;
    UILabel *title = SWMakeLabel(@"Stick War Mod", 17, UIFontWeightBold, [UIColor whiteColor]);
    UIButton *close = SWMakeButton(@"✕", self, @selector(closePanel));
    [close.widthAnchor constraintEqualToConstant:40].active = YES;
    [titleRow addArrangedSubview:title];
    [titleRow addArrangedSubview:close];
    [stack addArrangedSubview:titleRow];

    _statusLabel = SWMakeLabel(@"", 11, UIFontWeightRegular, dim);
    [stack addArrangedSubview:_statusLabel];

    // --- Vàng ---
    NSArray<NSString *> *goldItems = @[ @"Tắt", @"Vô hạn", @"Còn 9" ];
    [stack addArrangedSubview:SWMakeLabel(@"VÀNG", 11, UIFontWeightBold, dim)];
    [stack addArrangedSubview:SWMakeLabel(@"Phe ta", 13, UIFontWeightMedium, [UIColor whiteColor])];
    [stack addArrangedSubview:SWMakeSegments(goldItems, 0, self, @selector(goldChanged:))];
    [stack addArrangedSubview:SWMakeLabel(@"Phe địch", 13, UIFontWeightMedium, [UIColor whiteColor])];
    [stack addArrangedSubview:SWMakeSegments(goldItems, 1, self, @selector(goldChanged:))];

    // --- Triệu hồi lính ---
    [stack addArrangedSubview:SWMakeLabel(@"TRIỆU HỒI LÍNH", 11, UIFontWeightBold, dim)];
    [stack addArrangedSubview:SWMakeLabel(@"Cho phe", 13, UIFontWeightMedium, [UIColor whiteColor])];
    _spawnTeam = SWMakeSegments(@[ @"Ta", @"Địch" ], 0, self, nil);
    [stack addArrangedSubview:_spawnTeam];
    [stack addArrangedSubview:SWMakeLabel(@"Số lượng mỗi lần bấm", 13, UIFontWeightMedium, [UIColor whiteColor])];
    _spawnCount = SWMakeSegments(@[ @"1", @"5", @"10", @"25" ], 0, self, nil);
    [stack addArrangedSubview:_spawnCount];

    UIStackView *row = nil;
    for (int i = 0; i < game::kUnitKindCount; i++) {
        if (i % 3 == 0) {
            row = SWMakeStack(UILayoutConstraintAxisHorizontal, 6);
            row.distribution = UIStackViewDistributionFillEqually;
            [stack addArrangedSubview:row];
        }
        NSString *label = [NSString stringWithUTF8String:game::unit_label(static_cast<game::UnitKind>(i))];
        UIButton *button = SWMakeButton(label, self, @selector(spawnTapped:));
        button.tag = i;
        [row addArrangedSubview:button];
    }

    [stack addArrangedSubview:SWMakeButton(@"Nới giới hạn dân số +50", self, @selector(extendPopulationTapped))];

    _resultLabel = SWMakeLabel(@"", 12, UIFontWeightMedium, [UIColor colorWithRed:0.55 green:0.9 blue:0.6 alpha:1]);
    [stack addArrangedSubview:_resultLabel];

    // --- Chân trang ---
    [stack addArrangedSubview:SWMakeButton(@"Xem log", self, @selector(showLog))];
    [stack addArrangedSubview:SWMakeLabel(@"Chỉ dùng khi chơi offline.", 10, UIFontWeightRegular, dim)];
}

- (void)buildLogView {
    _logContainer = [[UIView alloc] initWithFrame:_panel.bounds];
    _logContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _logContainer.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.98];
    _logContainer.hidden = YES;
    [_panel addSubview:_logContainer];

    CGSize size = _panel.bounds.size;
    _logText = [[UITextView alloc] initWithFrame:CGRectMake(8, 8, size.width - 16, size.height - 60)];
    _logText.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _logText.backgroundColor = [UIColor clearColor];
    _logText.textColor = [UIColor colorWithRed:0.55 green:1 blue:0.6 alpha:1];
    _logText.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _logText.editable = NO;
    [_logContainer addSubview:_logText];

    UIButton *copy = SWMakeButton(@"Sao chép", self, @selector(copyLog));
    UIButton *back = SWMakeButton(@"Quay lại", self, @selector(hideLog));
    UIStackView *buttons = SWMakeStack(UILayoutConstraintAxisHorizontal, 8);
    buttons.distribution = UIStackViewDistributionFillEqually;
    buttons.frame = CGRectMake(8, size.height - 44, size.width - 16, 36);
    buttons.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [buttons addArrangedSubview:copy];
    [buttons addArrangedSubview:back];
    [_logContainer addSubview:buttons];
}

#pragma mark - Bố cục

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat margin = 10;
    CGFloat availableWidth = CGRectGetWidth(self.view.bounds) - safe.left - safe.right - 2 * margin;
    CGFloat availableHeight = CGRectGetHeight(self.view.bounds) - safe.top - safe.bottom - 2 * margin;
    _panel.frame = CGRectMake(safe.left + margin, safe.top + margin, MIN(320.0, availableWidth), MIN(440.0, availableHeight));
    _scroll.frame = _panel.bounds;

    // Giữ nút nổi trong màn hình sau khi xoay.
    CGRect bounds = self.view.bounds;
    CGPoint center = _fab.center;
    center.x = MAX(CGRectGetMinX(bounds) + 23, MIN(CGRectGetMaxX(bounds) - 23, center.x));
    center.y = MAX(CGRectGetMinY(bounds) + 23, MIN(CGRectGetMaxY(bounds) - 23, center.y));
    _fab.center = center;
}

#pragma mark - Thao tác

- (void)dragFab:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.view];
    CGRect bounds = self.view.bounds;
    CGPoint center = CGPointMake(pan.view.center.x + translation.x, pan.view.center.y + translation.y);
    center.x = MAX(23, MIN(CGRectGetWidth(bounds) - 23, center.x));
    center.y = MAX(23, MIN(CGRectGetHeight(bounds) - 23, center.y));
    pan.view.center = center;
    [pan setTranslation:CGPointZero inView:self.view];
}

- (void)openPanel {
    _panel.hidden = NO;
    _fab.hidden = YES;
    [self refreshStatus];
}

- (void)closePanel {
    _panel.hidden = YES;
    _fab.hidden = NO;
    _logContainer.hidden = YES;
}

- (void)goldChanged:(UISegmentedControl *)sender {
    game::GoldMode mode = static_cast<game::GoldMode>(sender.selectedSegmentIndex);
    if (sender.tag == 0) {
        _friendlyGold = mode;
    } else {
        _enemyGold = mode;
    }
    SWLLog(@"Vàng phe %@: chế độ %ld", sender.tag == 0 ? @"ta" : @"địch", (long)sender.selectedSegmentIndex);
}

- (void)spawnTapped:(UIButton *)sender {
    if (!game::in_match()) {
        _resultLabel.text = @"Chưa vào trận, hãy bắt đầu một màn chơi trước.";
        [self refreshStatus];
        return;
    }

    static const int kCounts[] = {1, 5, 10, 25};
    NSInteger countIndex = MAX(0, MIN(3, _spawnCount.selectedSegmentIndex));
    int count = kCounts[countIndex];
    game::Side side = (_spawnTeam.selectedSegmentIndex == 0) ? game::Side::Friendly : game::Side::Enemy;
    game::UnitKind kind = static_cast<game::UnitKind>(sender.tag);

    int created = game::spawn(side, kind, count);
    NSString *label = [NSString stringWithUTF8String:game::unit_label(kind)];
    _resultLabel.text = [NSString stringWithFormat:@"Đã triệu hồi %d/%d %@", created, count, label];
}

- (void)extendPopulationTapped {
    BOOL ok = game::extend_population(50);
    _resultLabel.text = ok ? @"Đã nới giới hạn dân số +50." : @"Chưa nới được dân số (chưa vào trận?).";
}

- (void)showLog {
    _logText.text = SWLLogDump();
    _logContainer.hidden = NO;
    if (_logText.text.length > 1) {
        [_logText scrollRangeToVisible:NSMakeRange(_logText.text.length - 1, 1)];
    }
}

- (void)hideLog {
    _logContainer.hidden = YES;
}

- (void)copyLog {
    [UIPasteboard generalPasteboard].string = SWLLogDump();
    _resultLabel.text = @"Đã sao chép log.";
    _logContainer.hidden = YES;
}

#pragma mark - Định kỳ

- (void)refreshStatus {
    BOOL inMatch = game::in_match();
    NSString *detail = [NSString stringWithUTF8String:game::status_text()];
    _statusLabel.text = [NSString stringWithFormat:@"IL2CPP %@ • %@", game::api_ready() ? @"✓" : @"✗", detail];
    _statusLabel.textColor = inMatch ? [UIColor colorWithRed:0.55 green:0.9 blue:0.6 alpha:1]
                                     : [UIColor colorWithRed:1 green:0.82 blue:0.4 alpha:1];
}

- (void)tick {
    // Ép vàng bằng cách gọi lại Team.set_Gold; không hook hay vá mã.
    game::apply_gold_mode(game::Side::Friendly, _friendlyGold);
    game::apply_gold_mode(game::Side::Enemy, _enemyGold);
    if (!_panel.hidden) [self refreshStatus];
}

@end

// ============================================================
// Cài đặt cửa sổ
// ============================================================
static SWWindow *sWindow = nil;
static int sAttempts = 0;

static void SWTryInstall(void) {
    if (sWindow) return;

    UIApplication *app = [UIApplication sharedApplication];
    UIWindowScene *scene = nil;
    for (UIScene *candidate in app.connectedScenes) {
        if (![candidate isKindOfClass:[UIWindowScene class]]) continue;
        if (candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }

    // Có scene nhưng chưa active: đợi thêm (tối đa ~30 giây), rồi dùng scene đầu tiên.
    if (!scene && app.connectedScenes.count > 0) {
        if (++sAttempts < 30) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SWTryInstall();
            });
            return;
        }
        for (UIScene *candidate in app.connectedScenes) {
            if ([candidate isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)candidate;
                break;
            }
        }
    }

    SWWindow *window = scene ? [[SWWindow alloc] initWithWindowScene:scene]
                             : [[SWWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    window.windowLevel = UIWindowLevelAlert + 100;
    window.backgroundColor = [UIColor clearColor];
    window.rootViewController = [[SWMenuViewController alloc] init];
    window.hidden = NO;  // không makeKeyAndVisible: không giành key window của Unity
    sWindow = window;

    SWLLog(@"Menu đã gắn vào màn hình (%@)", scene ? @"UIScene" : @"không scene");
    game::setup();
}

void SWMenuInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SWTryInstall();
    });
}
