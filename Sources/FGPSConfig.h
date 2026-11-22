#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const FGPSLocationEnabledKey;
extern NSString *const FGPSLatitudeKey;
extern NSString *const FGPSLongitudeKey;
extern NSString *const FGPSLocationHistoryKey;
extern NSString *const FGPSLocationChangedNotification;

BOOL FGPSLocationSpoofingEnabled(void);
void FGPSSetLocationSpoofingEnabled(BOOL enabled);

BOOL FGPSGetSavedCoordinate(CLLocationCoordinate2D * _Nullable outCoordinate);
void FGPSSaveCoordinate(CLLocationCoordinate2D coordinate);

NSArray<NSDictionary<NSString *, id> *> *FGPSLoadHistory(void);
void FGPSSaveHistory(NSArray<NSDictionary<NSString *, id> *> *history);
void FGPSClearHistory(void);

NS_ASSUME_NONNULL_END
