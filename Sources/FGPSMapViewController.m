#import "FGPSMapViewController.h"

#import "FGPSConfig.h"
#import "FGPSHistoryViewController.h"

#import <MapKit/MapKit.h>
#import <dispatch/dispatch.h>
#import <math.h>

static BOOL FGPSStrictDouble(NSString *text, double *outValue) {
    if (![text isKindOfClass:NSString.class]) {
        return NO;
    }

    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return NO;
    }

    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    scanner.charactersToBeSkipped = nil;
    scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    double value = 0.0;
    if (![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value)) {
        return NO;
    }

    if (outValue != NULL) {
        *outValue = value;
    }
    return YES;
}

static BOOL FGPSCoordinateIsValid(CLLocationCoordinate2D coordinate) {
    return isfinite(coordinate.latitude) && isfinite(coordinate.longitude) &&
           coordinate.latitude >= -90.0 && coordinate.latitude <= 90.0 &&
           coordinate.longitude >= -180.0 && coordinate.longitude <= 180.0 &&
           !(coordinate.latitude == 0.0 && coordinate.longitude == 0.0);
}

static NSString *FGPSCoordinateText(CLLocationCoordinate2D coordinate) {
    return [NSString stringWithFormat:@"%.6f, %.6f", coordinate.latitude, coordinate.longitude];
}

static NSString *FGPSAddressFromPlacemark(CLPlacemark *placemark) {
    NSMutableArray<NSString *> *components = [NSMutableArray array];
    NSArray<NSString *> *candidates = @[
        placemark.name ?: @"",
        placemark.locality ?: @"",
        placemark.subLocality ?: @"",
        placemark.thoroughfare ?: @"",
        placemark.subThoroughfare ?: @""
    ];
    for (NSString *component in candidates) {
        if (component.length > 0 && ![components containsObject:component]) {
            [components addObject:component];
        }
    }
    if (components.count > 0) {
        return [components componentsJoinedByString:@" "];
    }
    if (placemark.location != nil) {
        return FGPSCoordinateText(placemark.location.coordinate);
    }
    return @"未知地址";
}

static BOOL FGPSHistoryNumber(id value, double *outValue) {
    if ([value isKindOfClass:NSNumber.class]) {
        double number = [value doubleValue];
        if (!isfinite(number)) {
            return NO;
        }
        *outValue = number;
        return YES;
    }
    if ([value isKindOfClass:NSString.class]) {
        return FGPSStrictDouble(value, outValue);
    }
    return NO;
}

@interface FGPSMapViewController () <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *suggestionsTableView;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UILabel *addressInfoLabel;
@property (nonatomic, strong) UILabel *coordinateInfoLabel;
@property (nonatomic, strong) UILabel *noteInfoLabel;
@property (nonatomic, strong) UILabel *locationValueLabel;
@property (nonatomic, strong) UISwitch *locationSwitch;
@property (nonatomic, strong) UISegmentedControl *mapTypeControl;
@property (nonatomic, strong) NSTimer *searchTimer;
@property (nonatomic, strong) CLGeocoder *searchGeocoder;
@property (nonatomic, strong) CLGeocoder *reverseGeocoder;
@property (nonatomic, strong) NSArray<CLPlacemark *> *searchResults;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *history;
@property (nonatomic, strong) MKPointAnnotation *draftAnnotation;
@property (nonatomic, copy) NSString *draftAddress;
@property (nonatomic, copy) NSString *draftNote;
@property (nonatomic, assign) CLLocationCoordinate2D draftCoordinate;
@property (nonatomic, assign) BOOL hasDraft;
@property (nonatomic, assign) NSUInteger searchSequence;
@property (nonatomic, assign) NSUInteger draftSequence;

@end

@implementation FGPSMapViewController

- (void)dealloc {
    [_searchTimer invalidate];
    [_searchGeocoder cancelGeocode];
    [_reverseGeocoder cancelGeocode];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"FakeGPS";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                         target:self
                                                                                         action:@selector(closeMap)];
    self.history = [NSMutableArray arrayWithArray:FGPSLoadHistory()];
    self.searchResults = @[];
    [self setupUI];
    [self refreshCurrentValues];

    CLLocationCoordinate2D initialCoordinate = CLLocationCoordinate2DMake(39.9042, 116.4074);
    CLLocationCoordinate2D savedCoordinate;
    if (FGPSGetSavedCoordinate(&savedCoordinate)) {
        initialCoordinate = savedCoordinate;
    }
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(initialCoordinate, 500.0, 500.0) animated:NO];
}

- (void)closeMap {
    UIViewController *presentedController = self.navigationController ?: self;
    [presentedController dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshCurrentValues];
}

- (UILabel *)makeInformationLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:14.0];
    label.textColor = UIColor.secondaryLabelColor;
    label.numberOfLines = 0;
    return label;
}

- (void)styleButton:(UIButton *)button primary:(BOOL)primary {
    button.titleLabel.font = [UIFont systemFontOfSize:primary ? 17.0 : 15.0
                                                weight:primary ? UIFontWeightSemibold : UIFontWeightMedium];
    button.layer.cornerRadius = primary ? 12.0 : 10.0;
    button.layer.masksToBounds = YES;
    if (primary) {
        button.backgroundColor = UIColor.systemBlueColor;
        button.tintColor = UIColor.whiteColor;
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    } else {
        button.backgroundColor = UIColor.tertiarySystemFillColor;
        [button setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
    }
}

- (UIView *)makeCardWithContentView:(UIView *)contentView {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 14.0;
    card.layer.masksToBounds = YES;
    [card addSubview:contentView];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [contentView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [contentView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [contentView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0]
    ]];
    return card;
}

- (UIStackView *)makeSwitchRowWithLabel:(UILabel *)label control:(UISwitch *)control {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12.0;
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
    [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [control setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return row;
}

- (void)setupUI {
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索地点";
    self.searchBar.returnKeyType = UIReturnKeySearch;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.searchTextField.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    [self.view addSubview:self.searchBar];

    UIButton *historyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [historyButton setTitle:@"历史记录" forState:UIControlStateNormal];
    [historyButton addTarget:self action:@selector(showHistory) forControlEvents:UIControlEventTouchUpInside];
    [self styleButton:historyButton primary:NO];

    UIButton *coordinateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [coordinateButton setTitle:@"输入位置" forState:UIControlStateNormal];
    [coordinateButton addTarget:self action:@selector(presentCoordinateInput) forControlEvents:UIControlEventTouchUpInside];
    [self styleButton:coordinateButton primary:NO];

    UIStackView *actionStack = [[UIStackView alloc] initWithArrangedSubviews:@[historyButton, coordinateButton]];
    actionStack.translatesAutoresizingMaskIntoConstraints = NO;
    actionStack.axis = UILayoutConstraintAxisHorizontal;
    actionStack.distribution = UIStackViewDistributionFillEqually;
    actionStack.spacing = 8.0;
    [self.view addSubview:actionStack];

    self.mapView = [[MKMapView alloc] init];
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.showsUserLocation = YES;
    self.mapView.mapType = MKMapTypeStandard;
    self.mapView.layer.cornerRadius = 14.0;
    self.mapView.layer.masksToBounds = YES;
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [self.mapView addGestureRecognizer:longPress];
    [self.view addSubview:self.mapView];

    UIView *bottomPanel = [[UIView alloc] init];
    bottomPanel.translatesAutoresizingMaskIntoConstraints = NO;
    bottomPanel.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self.view addSubview:bottomPanel];

    UIScrollView *controlsScrollView = [[UIScrollView alloc] init];
    controlsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    controlsScrollView.alwaysBounceVertical = YES;
    [bottomPanel addSubview:controlsScrollView];

    self.addressInfoLabel = [self makeInformationLabel];
    self.addressInfoLabel.text = @"地址：未选择";
    self.addressInfoLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    self.addressInfoLabel.textColor = UIColor.labelColor;
    self.coordinateInfoLabel = [self makeInformationLabel];
    self.coordinateInfoLabel.text = @"经纬度：未选择";
    self.noteInfoLabel = [self makeInformationLabel];
    self.noteInfoLabel.text = @"备注：无";

    UIStackView *informationStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.addressInfoLabel,
        self.coordinateInfoLabel,
        self.noteInfoLabel
    ]];
    informationStack.axis = UILayoutConstraintAxisVertical;
    informationStack.spacing = 6.0;
    UIView *informationCard = [self makeCardWithContentView:informationStack];

    self.locationValueLabel = [self makeInformationLabel];
    self.locationValueLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    self.locationValueLabel.textColor = UIColor.labelColor;
    self.locationSwitch = [[UISwitch alloc] init];
    [self.locationSwitch addTarget:self action:@selector(locationSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *locationRow = [self makeSwitchRowWithLabel:self.locationValueLabel control:self.locationSwitch];

    UIStackView *switchStack = [[UIStackView alloc] initWithArrangedSubviews:@[locationRow]];
    switchStack.axis = UILayoutConstraintAxisVertical;
    switchStack.spacing = 4.0;
    UIView *switchCard = [self makeCardWithContentView:switchStack];

    UIButton *confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [confirmButton setTitle:@"确认位置" forState:UIControlStateNormal];
    [confirmButton addTarget:self action:@selector(confirmLocation) forControlEvents:UIControlEventTouchUpInside];
    [self styleButton:confirmButton primary:YES];
    [confirmButton.heightAnchor constraintEqualToConstant:48.0].active = YES;

    UIButton *trackingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [trackingButton setTitle:@"用户跟踪" forState:UIControlStateNormal];
    [trackingButton addTarget:self action:@selector(toggleUserTracking) forControlEvents:UIControlEventTouchUpInside];
    [self styleButton:trackingButton primary:NO];

    self.mapTypeControl = [[UISegmentedControl alloc] initWithItems:@[@"标准", @"卫星"]];
    self.mapTypeControl.selectedSegmentIndex = 0;
    [self.mapTypeControl addTarget:self action:@selector(mapTypeChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *mapActionStack = [[UIStackView alloc] initWithArrangedSubviews:@[trackingButton, self.mapTypeControl]];
    mapActionStack.axis = UILayoutConstraintAxisHorizontal;
    mapActionStack.distribution = UIStackViewDistributionFillEqually;
    mapActionStack.spacing = 12.0;
    [mapActionStack.heightAnchor constraintEqualToConstant:40.0].active = YES;

    UIStackView *controlsStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        informationCard,
        switchCard,
        confirmButton,
        mapActionStack
    ]];
    controlsStack.translatesAutoresizingMaskIntoConstraints = NO;
    controlsStack.axis = UILayoutConstraintAxisVertical;
    controlsStack.spacing = 12.0;
    controlsStack.layoutMarginsRelativeArrangement = YES;
    controlsStack.layoutMargins = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
    [controlsScrollView addSubview:controlsStack];

    self.suggestionsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.suggestionsTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.suggestionsTableView.dataSource = self;
    self.suggestionsTableView.delegate = self;
    self.suggestionsTableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.suggestionsTableView.rowHeight = UITableViewAutomaticDimension;
    self.suggestionsTableView.estimatedRowHeight = 56.0;
    self.suggestionsTableView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.suggestionsTableView.layer.cornerRadius = 14.0;
    self.suggestionsTableView.layer.masksToBounds = YES;
    self.suggestionsTableView.separatorInset = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
    self.suggestionsTableView.hidden = YES;
    [self.view addSubview:self.suggestionsTableView];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *panelHeight = [bottomPanel.heightAnchor constraintEqualToConstant:350.0];
    panelHeight.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *minimumMapHeight = [self.mapView.heightAnchor constraintGreaterThanOrEqualToConstant:180.0];
    minimumMapHeight.priority = UILayoutPriorityRequired - 1.0;

    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:4.0],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:16.0],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-16.0],

        [actionStack.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4.0],
        [actionStack.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:16.0],
        [actionStack.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-16.0],
        [actionStack.heightAnchor constraintEqualToConstant:40.0],

        [self.mapView.topAnchor constraintEqualToAnchor:actionStack.bottomAnchor constant:12.0],
        [self.mapView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:16.0],
        [self.mapView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-16.0],
        [self.mapView.bottomAnchor constraintEqualToAnchor:bottomPanel.topAnchor constant:-12.0],
        minimumMapHeight,

        [bottomPanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bottomPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bottomPanel.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],
        panelHeight,

        [controlsScrollView.topAnchor constraintEqualToAnchor:bottomPanel.topAnchor],
        [controlsScrollView.leadingAnchor constraintEqualToAnchor:bottomPanel.leadingAnchor],
        [controlsScrollView.trailingAnchor constraintEqualToAnchor:bottomPanel.trailingAnchor],
        [controlsScrollView.bottomAnchor constraintEqualToAnchor:bottomPanel.bottomAnchor],

        [controlsStack.topAnchor constraintEqualToAnchor:controlsScrollView.contentLayoutGuide.topAnchor],
        [controlsStack.leadingAnchor constraintEqualToAnchor:controlsScrollView.contentLayoutGuide.leadingAnchor],
        [controlsStack.trailingAnchor constraintEqualToAnchor:controlsScrollView.contentLayoutGuide.trailingAnchor],
        [controlsStack.bottomAnchor constraintEqualToAnchor:controlsScrollView.contentLayoutGuide.bottomAnchor],
        [controlsStack.widthAnchor constraintEqualToAnchor:controlsScrollView.frameLayoutGuide.widthAnchor],

        [self.suggestionsTableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4.0],
        [self.suggestionsTableView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:16.0],
        [self.suggestionsTableView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-16.0],
        [self.suggestionsTableView.heightAnchor constraintEqualToConstant:280.0]
    ]];
}

- (void)refreshCurrentValues {
    self.locationSwitch.on = FGPSLocationSpoofingEnabled();

    CLLocationCoordinate2D coordinate;
    if (FGPSGetSavedCoordinate(&coordinate)) {
        self.locationValueLabel.text = [NSString stringWithFormat:@"位置：%@", FGPSCoordinateText(coordinate)];
    } else {
        self.locationValueLabel.text = @"位置：未设置";
    }
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *presentedViewController = self.presentedViewController;
    if (presentedViewController != nil) {
        __weak typeof(self) weakSelf = self;
        [presentedViewController dismissViewControllerAnimated:NO completion:^{
            [weakSelf presentViewController:alert animated:YES completion:nil];
        }];
    } else {
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)showHistory {
    __weak typeof(self) weakSelf = self;
    FGPSHistoryViewController *historyViewController = [[FGPSHistoryViewController alloc] initWithHistory:self.history selectionHandler:^(NSDictionary<NSString *, id> *entry) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf applyHistoryEntry:entry];
    }];
    [self.navigationController pushViewController:historyViewController animated:YES];
}

- (void)applyHistoryEntry:(NSDictionary<NSString *, id> *)entry {
    double latitude = 0.0;
    double longitude = 0.0;
    if (!FGPSHistoryNumber(entry[@"latitude"], &latitude) ||
        !FGPSHistoryNumber(entry[@"longitude"], &longitude)) {
        return;
    }

    CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude, longitude);
    if (!FGPSCoordinateIsValid(coordinate)) {
        return;
    }

    id addressValue = entry[@"address"];
    NSString *address = [addressValue isKindOfClass:NSString.class] && [addressValue length] > 0
                            ? addressValue
                            : FGPSCoordinateText(coordinate);
    id noteValue = entry[@"note"];
    NSString *note = [noteValue isKindOfClass:NSString.class] ? noteValue : nil;
    [self cancelPendingSearch];
    [self clearSuggestions];
    [self updateDraftCoordinate:coordinate address:address note:note centered:YES];
}

- (void)presentCoordinateInput {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"输入位置"
                                                                   message:@"仅生成草稿，点击“确认位置”后保存。经纬度不能包含多余字符。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"纬度（-90 至 90）";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"经度（-180 至 180）";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"生成草稿" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong UIAlertController *strongAlert = weakAlert;
        if (strongSelf == nil || strongAlert.textFields.count < 2) {
            return;
        }

        double latitude = 0.0;
        double longitude = 0.0;
        BOOL parsed = FGPSStrictDouble(strongAlert.textFields[0].text, &latitude) &&
                      FGPSStrictDouble(strongAlert.textFields[1].text, &longitude);
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude, longitude);
        if (!parsed || !FGPSCoordinateIsValid(coordinate)) {
            [strongSelf showAlertWithTitle:@"输入无效" message:@"请输入完整的有效经纬度，范围为纬度 -90 至 90、经度 -180 至 180，且不支持 (0,0)。"];
            return;
        }
        [strongSelf updateDraftCoordinate:coordinate address:FGPSCoordinateText(coordinate) note:nil centered:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmLocation {
    if (FGPSLocationSpoofingEnabled()) {
        [self showAlertWithTitle:@"无法确认位置" message:@"请先关闭位置开关。"];
        return;
    }
    if (!self.hasDraft || !FGPSCoordinateIsValid(self.draftCoordinate)) {
        [self showAlertWithTitle:@"无法确认位置" message:@"请先搜索、长按、手动输入或从历史记录选择位置。"];
        return;
    }

    NSString *address = self.draftAddress.length > 0 ? self.draftAddress : FGPSCoordinateText(self.draftCoordinate);
    FGPSSaveCoordinate(self.draftCoordinate);
    [self.history addObject:@{
        @"address": address,
        @"latitude": @(self.draftCoordinate.latitude),
        @"longitude": @(self.draftCoordinate.longitude)
    }];
    FGPSSaveHistory(self.history);
    [self refreshCurrentValues];
    [self showAlertWithTitle:@"位置已确认" message:@"经纬度已保存，并追加到历史记录。"];
}

- (void)locationSwitchChanged:(UISwitch *)sender {
    FGPSSetLocationSpoofingEnabled(sender.on);
    [self refreshCurrentValues];
}

- (void)mapTypeChanged:(UISegmentedControl *)sender {
    self.mapView.mapType = sender.selectedSegmentIndex == 1 ? MKMapTypeSatellite : MKMapTypeStandard;
}

- (void)toggleUserTracking {
    MKUserTrackingMode mode = self.mapView.userTrackingMode == MKUserTrackingModeFollow
                                  ? MKUserTrackingModeNone
                                  : MKUserTrackingModeFollow;
    [self.mapView setUserTrackingMode:mode animated:YES];
}

- (void)handleMapLongPress:(UILongPressGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CGPoint point = [gestureRecognizer locationInView:self.mapView];
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];
    if (!FGPSCoordinateIsValid(coordinate)) {
        return;
    }
    [self updateDraftCoordinate:coordinate address:FGPSCoordinateText(coordinate) note:nil centered:YES];
    [self reverseGeocodeCurrentDraft];
}

- (void)updateDraftCoordinate:(CLLocationCoordinate2D)coordinate
                      address:(NSString *)address
                         note:(NSString *)note
                     centered:(BOOL)centered {
    if (!FGPSCoordinateIsValid(coordinate)) {
        return;
    }

    self.draftSequence += 1;
    [self.reverseGeocoder cancelGeocode];
    self.reverseGeocoder = nil;
    self.hasDraft = YES;
    self.draftCoordinate = coordinate;
    self.draftAddress = address.length > 0 ? address : FGPSCoordinateText(coordinate);
    self.draftNote = note;

    if (self.draftAnnotation == nil) {
        self.draftAnnotation = [[MKPointAnnotation alloc] init];
        self.draftAnnotation.coordinate = coordinate;
        [self.mapView addAnnotation:self.draftAnnotation];
    } else {
        self.draftAnnotation.coordinate = coordinate;
    }
    self.draftAnnotation.title = self.draftAddress;
    self.draftAnnotation.subtitle = FGPSCoordinateText(coordinate);
    self.addressInfoLabel.text = [NSString stringWithFormat:@"地址：%@", self.draftAddress];
    self.coordinateInfoLabel.text = [NSString stringWithFormat:@"经纬度：%@", FGPSCoordinateText(coordinate)];
    self.noteInfoLabel.text = [NSString stringWithFormat:@"备注：%@", self.draftNote.length > 0 ? self.draftNote : @"无"];

    if (centered) {
        [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(coordinate, 500.0, 500.0) animated:YES];
    }
}

- (void)reverseGeocodeCurrentDraft {
    if (!self.hasDraft) {
        return;
    }

    NSUInteger sequence = self.draftSequence;
    CLLocation *location = [[CLLocation alloc] initWithLatitude:self.draftCoordinate.latitude longitude:self.draftCoordinate.longitude];
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    self.reverseGeocoder = geocoder;
    __weak typeof(self) weakSelf = self;
    [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf.draftSequence != sequence || !strongSelf.hasDraft) {
                return;
            }
            strongSelf.reverseGeocoder = nil;
            CLPlacemark *placemark = placemarks.firstObject;
            if (error != nil || placemark == nil) {
                return;
            }
            NSString *address = FGPSAddressFromPlacemark(placemark);
            if (address.length == 0) {
                return;
            }
            strongSelf.draftAddress = address;
            strongSelf.draftAnnotation.title = address;
            strongSelf.addressInfoLabel.text = [NSString stringWithFormat:@"地址：%@", address];
        });
    }];
}

- (void)cancelPendingSearch {
    [self.searchTimer invalidate];
    self.searchTimer = nil;
    [self.searchGeocoder cancelGeocode];
    self.searchGeocoder = nil;
    self.searchSequence += 1;
}

- (void)clearSuggestions {
    self.searchResults = @[];
    [self.suggestionsTableView reloadData];
    self.suggestionsTableView.hidden = YES;
}

- (void)startSearchForQuery:(NSString *)rawQuery {
    NSString *query = [rawQuery copy] ?: @"";
    [self cancelPendingSearch];
    if (![self.searchBar.text isEqualToString:query]) {
        return;
    }

    NSString *trimmedQuery = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedQuery.length == 0) {
        [self clearSuggestions];
        return;
    }

    NSUInteger sequence = self.searchSequence;
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    self.searchGeocoder = geocoder;
    __weak typeof(self) weakSelf = self;
    [geocoder geocodeAddressString:trimmedQuery completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf.searchSequence != sequence ||
                ![strongSelf.searchBar.text isEqualToString:query]) {
                return;
            }
            strongSelf.searchGeocoder = nil;
            if (error != nil) {
                [strongSelf clearSuggestions];
                return;
            }

            NSMutableArray<CLPlacemark *> *validPlacemarks = [NSMutableArray array];
            for (CLPlacemark *placemark in placemarks) {
                if (placemark.location != nil && FGPSCoordinateIsValid(placemark.location.coordinate)) {
                    [validPlacemarks addObject:placemark];
                }
            }
            strongSelf.searchResults = validPlacemarks;
            [strongSelf.suggestionsTableView reloadData];
            strongSelf.suggestionsTableView.hidden = validPlacemarks.count == 0;
        });
    }];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self cancelPendingSearch];
    NSString *query = [searchBar.text copy] ?: @"";
    NSString *trimmedQuery = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedQuery.length == 0) {
        [self clearSuggestions];
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.searchTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(__unused NSTimer *timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf startSearchForQuery:query];
    }];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [self startSearchForQuery:searchBar.text ?: @""];
    [searchBar resignFirstResponder];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.searchResults.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const reuseIdentifier = @"FGPSSearchSuggestionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
        cell.textLabel.numberOfLines = 2;
        cell.detailTextLabel.numberOfLines = 2;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    }
    CLPlacemark *placemark = self.searchResults[indexPath.row];
    NSString *address = FGPSAddressFromPlacemark(placemark);
    cell.textLabel.text = placemark.name.length > 0 ? placemark.name : address;
    cell.detailTextLabel.text = address;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.searchResults.count) {
        return;
    }
    CLPlacemark *placemark = self.searchResults[indexPath.row];
    CLLocationCoordinate2D coordinate = placemark.location.coordinate;
    NSString *address = FGPSAddressFromPlacemark(placemark);
    [self cancelPendingSearch];
    [self clearSuggestions];
    self.searchBar.text = address;
    [self.searchBar resignFirstResponder];
    [self updateDraftCoordinate:coordinate address:address note:nil centered:YES];
}

@end
