#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGPSHistoryViewController : UIViewController

- (instancetype)initWithHistory:(NSMutableArray<NSDictionary<NSString *, id> *> *)history
               selectionHandler:(void (^)(NSDictionary<NSString *, id> *entry))selectionHandler;

@end

NS_ASSUME_NONNULL_END
