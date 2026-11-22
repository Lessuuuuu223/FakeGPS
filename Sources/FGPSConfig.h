#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const FGPSLocationEnabledKey;
extern NSString *const FGPSLatitudeKey;
extern NSString *const FGPSLongitudeKey;
extern NSString *const FGPSAltitudeEnabledKey;
extern NSString *const FGPSAltitudeKey;
extern NSString *const FGPSLocationHistoryKey;
extern NSString *const FGPSLocationChangedNotification;
extern NSString *const FGPSAltitudeChangedNotification;

BOOL FGPSLocationSpoofingEnabled(void);
void FGPSSetLocationSpoofingEnabled(BOOL enabled);
BOOL FGPSAltitudeSpoofingEnabled(void);
void FGPSSetAltitudeSpoofingEnabled(BOOL enabled);

BOOL FGPSGetSavedCoordinate(CLLocationCoordinate2D * _Nullable outCoordinate);
void FGPSSaveCoordinate(CLLocationCoordinate2D coordinate);
BOOL FGPSGetSavedAltitude(double * _Nullable outAltitude);
void FGPSSaveAltitude(double altitude);

NSArray<NSDictionary<NSString *, id> *> *FGPSLoadHistory(void);
void FGPSSaveHistory(NSArray<NSDictionary<NSString *, id> *> *history);
void FGPSClearHistory(void);

NS_ASSUME_NONNULL_END
