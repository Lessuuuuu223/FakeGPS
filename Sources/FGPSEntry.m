#import "FGPSLocationHooks.h"
#import "FGPSMapViewController.h"

#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <math.h>

static const CGFloat FGPSFloatingButtonSize = 52.0;
static const CGFloat FGPSFloatingButtonMargin = 8.0;
static NSArray *FGPSEntryObservers;

@interface FGPSFloatingController : NSObject
+ (instancetype)sharedController;
- (void)installForWindow:(UIWindow *)window;
- (void)refreshFloatingWindow;
- (void)openMapFromFloatingWindow:(UIWindow *)floatingWindow;
@end

@interface FGPSFloatingOverlayView : UIView
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, assign) CGPoint dragStartCenter;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) BOOL snapsToLeadingEdge;
@property (nonatomic, assign) BOOL hasPositionedButton;
@property (nonatomic, assign) BOOL suppressTap;
@end

@implementation FGPSFloatingOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        self.floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatingButton.frame = CGRectMake(0.0, 0.0, FGPSFloatingButtonSize, FGPSFloatingButtonSize);
        self.floatingButton.backgroundColor = UIColor.systemBlueColor;
        self.floatingButton.tintColor = UIColor.whiteColor;
        self.floatingButton.layer.cornerRadius = FGPSFloatingButtonSize / 2.0;
        self.floatingButton.layer.shadowColor = UIColor.blackColor.CGColor;
        self.floatingButton.layer.shadowOpacity = 0.25;
        self.floatingButton.layer.shadowOffset = CGSizeMake(0.0, 2.0);
        self.floatingButton.layer.shadowRadius = 4.0;
        self.floatingButton.accessibilityLabel = @"打开 FakeGPS";
        UIImage *locationImage = [[UIImage systemImageNamed:@"location.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [self.floatingButton setImage:locationImage forState:UIControlStateNormal];
        [self.floatingButton addTarget:self action:@selector(floatingButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.floatingButton];

        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        panGesture.cancelsTouchesInView = NO;
        [self.floatingButton addGestureRecognizer:panGesture];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint pointInButton = [self convertPoint:point toView:self.floatingButton];
    if ([self.floatingButton pointInside:pointInButton withEvent:event]) {
        return self.floatingButton;
    }
    return nil;
}

- (CGPoint)clampedCenter:(CGPoint)center {
    UIEdgeInsets insets = self.safeAreaInsets;
    CGFloat halfWidth = CGRectGetWidth(self.floatingButton.bounds) / 2.0;
    CGFloat halfHeight = CGRectGetHeight(self.floatingButton.bounds) / 2.0;
    CGFloat minX = insets.left + FGPSFloatingButtonMargin + halfWidth;
    CGFloat maxX = CGRectGetWidth(self.bounds) - insets.right - FGPSFloatingButtonMargin - halfWidth;
    CGFloat minY = insets.top + FGPSFloatingButtonMargin + halfHeight;
    CGFloat maxY = CGRectGetHeight(self.bounds) - insets.bottom - FGPSFloatingButtonMargin - halfHeight;

    if (maxX < minX) {
        minX = maxX = CGRectGetMidX(self.bounds);
    }
    if (maxY < minY) {
        minY = maxY = CGRectGetMidY(self.bounds);
    }
    center.x = MIN(MAX(center.x, minX), maxX);
    center.y = MIN(MAX(center.y, minY), maxY);
    return center;
}

- (void)snapButtonToEdgeAnimated:(BOOL)animated {
    if (CGRectIsEmpty(self.bounds)) {
        return;
    }

    UIEdgeInsets insets = self.safeAreaInsets;
    CGFloat halfWidth = CGRectGetWidth(self.floatingButton.bounds) / 2.0;
    CGPoint targetCenter = self.floatingButton.center;
    targetCenter.x = self.snapsToLeadingEdge
                         ? insets.left + FGPSFloatingButtonMargin + halfWidth
                         : CGRectGetWidth(self.bounds) - insets.right - FGPSFloatingButtonMargin - halfWidth;
    targetCenter = [self clampedCenter:targetCenter];

    if (animated) {
        [UIView animateWithDuration:0.20
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.floatingButton.center = targetCenter;
        }
                         completion:nil];
    } else {
        self.floatingButton.center = targetCenter;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.dragging) {
        return;
    }
    if (!self.hasPositionedButton) {
        self.hasPositionedButton = YES;
        self.floatingButton.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    }
    [self snapButtonToEdgeAnimated:NO];
}

- (void)finishDragging {
    self.dragging = NO;
    self.snapsToLeadingEdge = self.floatingButton.center.x < CGRectGetMidX(self.bounds);
    [self snapButtonToEdgeAnimated:YES];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.suppressTap = NO;
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)gestureRecognizer {
    switch (gestureRecognizer.state) {
        case UIGestureRecognizerStateBegan:
            self.dragging = YES;
            self.suppressTap = NO;
            self.dragStartCenter = self.floatingButton.center;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [gestureRecognizer translationInView:self];
            if (hypot(translation.x, translation.y) > 3.0) {
                self.suppressTap = YES;
            }
            CGPoint center = CGPointMake(self.dragStartCenter.x + translation.x,
                                         self.dragStartCenter.y + translation.y);
            self.floatingButton.center = [self clampedCenter:center];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self finishDragging];
            break;
        default:
            break;
    }
}

- (void)floatingButtonTapped {
    if (!self.suppressTap && self.window != nil) {
        [FGPSFloatingController.sharedController openMapFromFloatingWindow:self.window];
    }
}

@end

@interface FGPSFloatingWindow : UIWindow
@end

@implementation FGPSFloatingWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) {
        return nil;
    }
    return hitView;
}

@end

@interface FGPSFloatingViewController : UIViewController
@end

@implementation FGPSFloatingViewController

- (void)loadView {
    self.view = [[FGPSFloatingOverlayView alloc] initWithFrame:CGRectZero];
}

@end

@interface FGPSFloatingController ()
@property (nonatomic, strong) NSMapTable<UIWindowScene *, FGPSFloatingWindow *> *floatingWindows;
@property (nonatomic, strong) NSMapTable<UIWindowScene *, UIWindow *> *hostWindows;
@property (nonatomic, strong) NSMapTable<UIWindowScene *, UINavigationController *> *mapNavigationControllers;
@end

@implementation FGPSFloatingController

+ (instancetype)sharedController {
    static FGPSFloatingController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [[FGPSFloatingController alloc] init];
    });
    return controller;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _floatingWindows = [NSMapTable strongToStrongObjectsMapTable];
        _hostWindows = [NSMapTable strongToWeakObjectsMapTable];
        _mapNavigationControllers = [NSMapTable strongToWeakObjectsMapTable];
    }
    return self;
}

- (UIWindow *)keyApplicationWindowForScene:(UIWindowScene *)scene {
    for (UIWindow *window in scene.windows) {
        if (window.isKeyWindow && window.windowLevel == UIWindowLevelNormal && ![window isKindOfClass:FGPSFloatingWindow.class]) {
            return window;
        }
    }
    return nil;
}

- (NSArray<UIWindow *> *)keyApplicationWindows {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }
        UIWindow *window = [self keyApplicationWindowForScene:(UIWindowScene *)scene];
        if (window != nil) {
            [windows addObject:window];
        }
    }
    return windows;
}

- (void)removeScene:(UIWindowScene *)scene {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self removeScene:scene];
        });
        return;
    }
    FGPSFloatingWindow *floatingWindow = [self.floatingWindows objectForKey:scene];
    floatingWindow.hidden = YES;
    [self.floatingWindows removeObjectForKey:scene];
    [self.hostWindows removeObjectForKey:scene];
    [self.mapNavigationControllers removeObjectForKey:scene];
}

- (void)installForWindow:(UIWindow *)window {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self installForWindow:window];
        });
        return;
    }
    if (![window isKindOfClass:UIWindow.class] || [window isKindOfClass:FGPSFloatingWindow.class] ||
        window.windowLevel != UIWindowLevelNormal || window.windowScene == nil) {
        return;
    }

    UIWindowScene *scene = window.windowScene;
    [self.hostWindows setObject:window forKey:scene];
    FGPSFloatingWindow *floatingWindow = [self.floatingWindows objectForKey:scene];
    if (floatingWindow == nil) {
        floatingWindow = [[FGPSFloatingWindow alloc] initWithWindowScene:scene];
        floatingWindow.windowLevel = UIWindowLevelAlert - 1.0;
        floatingWindow.backgroundColor = UIColor.clearColor;
        floatingWindow.opaque = NO;
        floatingWindow.rootViewController = [[FGPSFloatingViewController alloc] init];
        [self.floatingWindows setObject:floatingWindow forKey:scene];
    }

    floatingWindow.frame = scene.coordinateSpace.bounds;
    floatingWindow.rootViewController.view.frame = floatingWindow.bounds;
    floatingWindow.hidden = NO;
}

- (void)refreshFloatingWindow {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshFloatingWindow];
        });
        return;
    }
    NSArray<UIWindow *> *windows = [self keyApplicationWindows];
    if (windows.count == 0) {
        windows = self.hostWindows.objectEnumerator.allObjects;
    }
    for (UIWindow *window in windows) {
        [self installForWindow:window];
    }
}

- (UIViewController *)topViewControllerWithRoot:(UIViewController *)rootViewController {
    UIViewController *topViewController = rootViewController;
    while (topViewController != nil) {
        if ([topViewController isKindOfClass:UINavigationController.class]) {
            UIViewController *visible = [(UINavigationController *)topViewController visibleViewController];
            if (visible != nil && visible != topViewController) {
                topViewController = visible;
                continue;
            }
        }
        if ([topViewController isKindOfClass:UITabBarController.class]) {
            UIViewController *selected = [(UITabBarController *)topViewController selectedViewController];
            if (selected != nil && selected != topViewController) {
                topViewController = selected;
                continue;
            }
        }
        UIViewController *presented = topViewController.presentedViewController;
        if (presented != nil && !presented.isBeingDismissed) {
            topViewController = presented;
            continue;
        }
        break;
    }
    return topViewController;
}

- (void)openMapFromFloatingWindow:(UIWindow *)floatingWindow {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self openMapFromFloatingWindow:floatingWindow];
        });
        return;
    }

    UIWindowScene *scene = floatingWindow.windowScene;
    if (scene == nil) {
        return;
    }
    UINavigationController *existingController = [self.mapNavigationControllers objectForKey:scene];
    if (existingController.presentingViewController != nil || existingController.isBeingDismissed) {
        return;
    }

    UIWindow *hostWindow = [self keyApplicationWindowForScene:scene] ?: [self.hostWindows objectForKey:scene];
    UIViewController *presenter = [self topViewControllerWithRoot:hostWindow.rootViewController];
    if (presenter == nil || [presenter isKindOfClass:FGPSMapViewController.class]) {
        return;
    }

    FGPSMapViewController *mapViewController = [[FGPSMapViewController alloc] init];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:mapViewController];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self.mapNavigationControllers setObject:navigationController forKey:scene];
    [presenter presentViewController:navigationController animated:YES completion:nil];
}

@end

static void FGPSInstallFloatingEntry(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationCenter *notificationCenter = NSNotificationCenter.defaultCenter;
        id windowObserver = [notificationCenter addObserverForName:UIWindowDidBecomeKeyNotification
                                                             object:nil
                                                              queue:NSOperationQueue.mainQueue
                                                         usingBlock:^(NSNotification *notification) {
            if ([notification.object isKindOfClass:UIWindow.class]) {
                [FGPSFloatingController.sharedController installForWindow:(UIWindow *)notification.object];
            }
        }];
        id activeObserver = [notificationCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                             object:nil
                                                              queue:NSOperationQueue.mainQueue
                                                         usingBlock:^(__unused NSNotification *notification) {
            [FGPSFloatingController.sharedController refreshFloatingWindow];
        }];
        id sceneObserver = [notificationCenter addObserverForName:UISceneDidDisconnectNotification
                                                            object:nil
                                                             queue:NSOperationQueue.mainQueue
                                                        usingBlock:^(NSNotification *notification) {
            if ([notification.object isKindOfClass:UIWindowScene.class]) {
                [FGPSFloatingController.sharedController removeScene:(UIWindowScene *)notification.object];
            }
        }];
        FGPSEntryObservers = @[windowObserver, activeObserver, sceneObserver];

        dispatch_async(dispatch_get_main_queue(), ^{
            [FGPSFloatingController.sharedController refreshFloatingWindow];
        });
    });
}

__attribute__((constructor)) static void FGPSInitialize(void) {
    @autoreleasepool {
        FGPSInstallLocationHooks();
        FGPSInstallFloatingEntry();
    }
}
