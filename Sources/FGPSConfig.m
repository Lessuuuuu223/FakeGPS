#import "FGPSConfig.h"

#import <math.h>

NSString *const FGPSLocationEnabledKey = @"LocationSpoofingEnabled";
NSString *const FGPSLatitudeKey = @"latitude";
NSString *const FGPSLongitudeKey = @"longitude";
NSString *const FGPSLocationHistoryKey = @"LocationHistory";
NSString *const FGPSLocationChangedNotification = @"LocationSpoofingChanged";

static NSUserDefaults *FGPSDefaults(void) {
    return NSUserDefaults.standardUserDefaults;
}

BOOL FGPSLocationSpoofingEnabled(void) {
    return [FGPSDefaults() boolForKey:FGPSLocationEnabledKey];
}

void FGPSSetLocationSpoofingEnabled(BOOL enabled) {
    [FGPSDefaults() setBool:enabled forKey:FGPSLocationEnabledKey];
    [NSNotificationCenter.defaultCenter postNotificationName:FGPSLocationChangedNotification object:nil];
}

BOOL FGPSGetSavedCoordinate(CLLocationCoordinate2D *outCoordinate) {
    id latitudeValue = [FGPSDefaults() objectForKey:FGPSLatitudeKey];
    id longitudeValue = [FGPSDefaults() objectForKey:FGPSLongitudeKey];
    if (![latitudeValue isKindOfClass:NSNumber.class] ||
        ![longitudeValue isKindOfClass:NSNumber.class]) {
        return NO;
    }

    double latitude = [latitudeValue doubleValue];
    double longitude = [longitudeValue doubleValue];
    if (!isfinite(latitude) || !isfinite(longitude) ||
        latitude < -90.0 || latitude > 90.0 ||
        longitude < -180.0 || longitude > 180.0 ||
        (latitude == 0.0 && longitude == 0.0)) {
        return NO;
    }

    if (outCoordinate != NULL) {
        *outCoordinate = CLLocationCoordinate2DMake(latitude, longitude);
    }
    return YES;
}

void FGPSSaveCoordinate(CLLocationCoordinate2D coordinate) {
    [FGPSDefaults() setObject:@(coordinate.latitude) forKey:FGPSLatitudeKey];
    [FGPSDefaults() setObject:@(coordinate.longitude) forKey:FGPSLongitudeKey];
}

NSArray<NSDictionary<NSString *, id> *> *FGPSLoadHistory(void) {
    id storedValue = [FGPSDefaults() objectForKey:FGPSLocationHistoryKey];
    if (![storedValue isKindOfClass:NSArray.class]) {
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *history = [NSMutableArray array];
    for (id entry in (NSArray *)storedValue) {
        if ([entry isKindOfClass:NSDictionary.class]) {
            [history addObject:[entry copy]];
        }
    }
    return history;
}

void FGPSSaveHistory(NSArray<NSDictionary<NSString *, id> *> *history) {
    NSArray *immutableHistory = [[NSArray alloc] initWithArray:history copyItems:YES];
    [FGPSDefaults() setObject:immutableHistory forKey:FGPSLocationHistoryKey];
}

void FGPSClearHistory(void) {
    [FGPSDefaults() removeObjectForKey:FGPSLocationHistoryKey];
}
