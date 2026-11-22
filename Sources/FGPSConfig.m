#import "FGPSConfig.h"

#import <math.h>

NSString *const FGPSLocationEnabledKey = @"LocationSpoofingEnabled";
NSString *const FGPSLatitudeKey = @"latitude";
NSString *const FGPSLongitudeKey = @"longitude";
NSString *const FGPSAltitudeEnabledKey = @"AltitudeSpoofingEnabled";
NSString *const FGPSAltitudeKey = @"altitude";
NSString *const FGPSLocationHistoryKey = @"LocationHistory";
NSString *const FGPSLocationChangedNotification = @"LocationSpoofingChanged";
NSString *const FGPSAltitudeChangedNotification = @"AltitudeSpoofingChanged";

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

BOOL FGPSAltitudeSpoofingEnabled(void) {
    return [FGPSDefaults() boolForKey:FGPSAltitudeEnabledKey];
}

void FGPSSetAltitudeSpoofingEnabled(BOOL enabled) {
    [FGPSDefaults() setBool:enabled forKey:FGPSAltitudeEnabledKey];
    [NSNotificationCenter.defaultCenter postNotificationName:FGPSAltitudeChangedNotification object:nil];
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

BOOL FGPSGetSavedAltitude(double *outAltitude) {
    id value = [FGPSDefaults() objectForKey:FGPSAltitudeKey];
    if (![value isKindOfClass:NSNumber.class]) {
        return NO;
    }

    double altitude = [value doubleValue];
    if (!isfinite(altitude) || altitude < -500.0 || altitude > 10000.0) {
        return NO;
    }

    if (outAltitude != NULL) {
        *outAltitude = altitude;
    }
    return YES;
}

void FGPSSaveAltitude(double altitude) {
    [FGPSDefaults() setObject:@(altitude) forKey:FGPSAltitudeKey];
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
