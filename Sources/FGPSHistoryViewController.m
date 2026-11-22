#import "FGPSHistoryViewController.h"

#import "FGPSConfig.h"

#import <math.h>

static BOOL FGPSHistoryDisplayNumber(id value, double *outValue) {
    if (![value isKindOfClass:NSNumber.class] && ![value isKindOfClass:NSString.class]) {
        return NO;
    }
    double number = [value doubleValue];
    if (!isfinite(number)) {
        return NO;
    }
    *outValue = number;
    return YES;
}

@interface FGPSHistoryViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *history;
@property (nonatomic, copy) void (^selectionHandler)(NSDictionary<NSString *, id> *entry);

@end

@implementation FGPSHistoryViewController

- (instancetype)initWithHistory:(NSMutableArray<NSDictionary<NSString *, id> *> *)history
               selectionHandler:(void (^)(NSDictionary<NSString *, id> *entry))selectionHandler {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _history = history;
        _selectionHandler = [selectionHandler copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"历史记录";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(confirmClearHistory)];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor]
    ]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.history.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const reuseIdentifier = @"FGPSHistoryCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    NSDictionary<NSString *, id> *entry = self.history[indexPath.row];
    id addressValue = entry[@"address"];
    cell.textLabel.text = [addressValue isKindOfClass:NSString.class] && [addressValue length] > 0
                              ? addressValue
                              : @"未知地址";

    double latitude = 0.0;
    double longitude = 0.0;
    BOOL validCoordinate = FGPSHistoryDisplayNumber(entry[@"latitude"], &latitude) &&
                           FGPSHistoryDisplayNumber(entry[@"longitude"], &longitude);
    NSString *coordinateText = validCoordinate
                                   ? [NSString stringWithFormat:@"%.6f, %.6f", latitude, longitude]
                                   : @"无效坐标";
    id noteValue = entry[@"note"];
    NSString *note = [noteValue isKindOfClass:NSString.class] ? noteValue : @"";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n备注：%@", coordinateText, note];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.history.count) {
        return;
    }

    NSDictionary<NSString *, id> *entry = self.history[indexPath.row];
    if (self.selectionHandler != nil) {
        self.selectionHandler(entry);
    }
    if (self.navigationController != nil) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
     trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    NSUInteger row = indexPath.row;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                                title:@"删除"
                                                                              handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf != nil && row < strongSelf.history.count) {
            [strongSelf.history removeObjectAtIndex:row];
            FGPSSaveHistory(strongSelf.history);
            [strongSelf.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
                                        withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        completionHandler(YES);
    }];

    UIContextualAction *noteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                              title:@"备注"
                                                                            handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf != nil && row < strongSelf.history.count) {
            [strongSelf presentNoteEditorForRow:row];
        }
        completionHandler(YES);
    }];
    noteAction.backgroundColor = UIColor.systemBlueColor;
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, noteAction]];
}

- (void)presentNoteEditorForRow:(NSUInteger)row {
    if (row >= self.history.count) {
        return;
    }

    NSDictionary<NSString *, id> *entry = self.history[row];
    id existingNoteValue = entry[@"note"];
    NSString *existingNote = [existingNoteValue isKindOfClass:NSString.class] ? existingNoteValue : @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"编辑备注"
                                                                   message:@"备注可为空，最多 30 个 UTF-16 code units。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = existingNote;
        textField.placeholder = @"备注";
        textField.delegate = weakSelf;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong UIAlertController *strongAlert = weakAlert;
        if (strongSelf == nil || strongAlert.textFields.count == 0 || row >= strongSelf.history.count) {
            return;
        }

        NSString *note = strongAlert.textFields[0].text ?: @"";
        if (note.length > 30) {
            return;
        }
        NSMutableDictionary<NSString *, id> *updatedEntry = [strongSelf.history[row] mutableCopy];
        updatedEntry[@"note"] = note;
        strongSelf.history[row] = updatedEntry;
        FGPSSaveHistory(strongSelf.history);
        [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
                                    withRowAnimation:UITableViewRowAnimationAutomatic];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *updatedText = [(textField.text ?: @"") stringByReplacingCharactersInRange:range withString:string];
    return updatedText.length <= 30;
}

- (void)confirmClearHistory {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空历史记录"
                                                                   message:@"确定要清空全部历史记录吗？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf.history removeAllObjects];
        FGPSClearHistory();
        [strongSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
