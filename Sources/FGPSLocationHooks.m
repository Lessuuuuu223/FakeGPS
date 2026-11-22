#import "FGPSLocationHooks.h"

#import "FGPSConfig.h"

#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

static CLLocationCoordinate2D (*FGPSOriginalLocationCoordinate)(id, SEL);
static void (*FGPSOriginalSetDelegate)(id, SEL, id);
static CLLocation *(*FGPSOriginalManagerLocation)(id, SEL);
static void (*FGPSOriginalSetDesiredAccuracy)(id, SEL, CLLocationAccuracy);
static void (*FGPSOriginalStartUpdatingLocation)(id, SEL);
static CLLocationCoordinate2D (*FGPSOriginalUserLocationCoordinate)(id, SEL);

static NSMutableDictionary<NSValue *, NSValue *> *FGPSDelegateOriginalImplementations;

static BOOL FGPSLocationSimulationIsActive(void) {
    return FGPSLocationSpoofingEnabled() && FGPSGetSavedCoordinate(NULL);
}

static CLLocation *FGPSSyntheticLocation(void) {
    CLLocationCoordinate2D coordinate;
    if (!FGPSLocationSimulationIsActive() || !FGPSGetSavedCoordinate(&coordinate)) {
        return nil;
    }
    return [[CLLocation alloc] initWithCoordinate:coordinate
                                        altitude:0.0
                              horizontalAccuracy:5.0
                                verticalAccuracy:5.0
                                       timestamp:NSDate.date];
}

static void FGPSReplaceMethod(Class targetClass, SEL selector, id block, IMP *originalStorage) {
    Method method = class_getInstanceMethod(targetClass, selector);
    if (method == NULL) {
        return;
    }

    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(block);
    if (original == NULL || replacement == NULL) {
        return;
    }

    if (originalStorage != NULL) {
        *originalStorage = original;
    }
    method_setImplementation(method, replacement);
}

static void FGPSWrapDelegateClass(id delegate) {
    if (delegate == nil) {
        return;
    }

    SEL selector = @selector(locationManager:didUpdateLocations:);
    Class delegateClass = object_getClass(delegate);
    Method method = class_getInstanceMethod(delegateClass, selector);
    if (method == NULL) {
        return;
    }

    @synchronized (FGPSDelegateOriginalImplementations) {
        NSValue *classKey = [NSValue valueWithPointer:(__bridge const void *)delegateClass];
        if (FGPSDelegateOriginalImplementations[classKey] != nil) {
            return;
        }

        IMP originalImplementation = method_getImplementation(method);
        if (originalImplementation == NULL) {
            return;
        }

        IMP replacement = imp_implementationWithBlock(^void(id self, CLLocationManager *manager, NSArray<CLLocation *> *locations) {
            void (*original)(id, SEL, CLLocationManager *, NSArray<CLLocation *> *) =
                (void (*)(id, SEL, CLLocationManager *, NSArray<CLLocation *> *))originalImplementation;
            CLLocation *syntheticLocation = FGPSSyntheticLocation();
            if (syntheticLocation != nil) {
                original(self, selector, manager, @[syntheticLocation]);
            } else {
                original(self, selector, manager, locations);
            }
        });
        if (replacement == NULL) {
            return;
        }

        const char *types = method_getTypeEncoding(method);
        if (!class_addMethod(delegateClass, selector, replacement, types)) {
            method_setImplementation(method, replacement);
        }
        FGPSDelegateOriginalImplementations[classKey] = [NSValue valueWithPointer:originalImplementation];
    }
}

static void FGPSQueueSyntheticCallback(CLLocationManager *manager) {
    if (!FGPSLocationSimulationIsActive()) {
        return;
    }

    __weak CLLocationManager *weakManager = manager;
    dispatch_async(dispatch_get_main_queue(), ^{
        CLLocationManager *strongManager = weakManager;
        if (strongManager == nil || !FGPSLocationSimulationIsActive()) {
            return;
        }

        id<CLLocationManagerDelegate> delegate = strongManager.delegate;
        if (delegate == nil || ![delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            return;
        }

        CLLocation *syntheticLocation = FGPSSyntheticLocation();
        if (syntheticLocation != nil) {
            [delegate locationManager:strongManager didUpdateLocations:@[syntheticLocation]];
        }
    });
}

void FGPSInstallLocationHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        FGPSDelegateOriginalImplementations = [NSMutableDictionary dictionary];

        FGPSReplaceMethod(CLLocation.class, @selector(coordinate), ^CLLocationCoordinate2D(CLLocation *self) {
            CLLocationCoordinate2D original = FGPSOriginalLocationCoordinate(self, @selector(coordinate));
            CLLocationCoordinate2D coordinate;
            if (FGPSLocationSimulationIsActive() && FGPSGetSavedCoordinate(&coordinate)) {
                return coordinate;
            }
            return original;
        }, (IMP *)&FGPSOriginalLocationCoordinate);

        FGPSReplaceMethod(CLLocationManager.class, @selector(setDelegate:), ^void(CLLocationManager *self, id delegate) {
            FGPSOriginalSetDelegate(self, @selector(setDelegate:), delegate);
            FGPSWrapDelegateClass(delegate);
        }, (IMP *)&FGPSOriginalSetDelegate);

        FGPSReplaceMethod(CLLocationManager.class, @selector(location), ^CLLocation *(CLLocationManager *self) {
            CLLocation *syntheticLocation = FGPSSyntheticLocation();
            if (syntheticLocation != nil) {
                return syntheticLocation;
            }
            return FGPSOriginalManagerLocation(self, @selector(location));
        }, (IMP *)&FGPSOriginalManagerLocation);

        FGPSReplaceMethod(CLLocationManager.class, @selector(setDesiredAccuracy:), ^void(CLLocationManager *self, CLLocationAccuracy accuracy) {
            CLLocationAccuracy effectiveAccuracy = FGPSLocationSimulationIsActive() ? kCLLocationAccuracyBest : accuracy;
            FGPSOriginalSetDesiredAccuracy(self, @selector(setDesiredAccuracy:), effectiveAccuracy);
        }, (IMP *)&FGPSOriginalSetDesiredAccuracy);

        FGPSReplaceMethod(CLLocationManager.class, @selector(startUpdatingLocation), ^void(CLLocationManager *self) {
            FGPSOriginalStartUpdatingLocation(self, @selector(startUpdatingLocation));
            FGPSQueueSyntheticCallback(self);
        }, (IMP *)&FGPSOriginalStartUpdatingLocation);

        FGPSReplaceMethod(MKUserLocation.class, @selector(coordinate), ^CLLocationCoordinate2D(MKUserLocation *self) {
            CLLocationCoordinate2D original = FGPSOriginalUserLocationCoordinate(self, @selector(coordinate));
            CLLocationCoordinate2D coordinate;
            if (FGPSLocationSimulationIsActive() && FGPSGetSavedCoordinate(&coordinate)) {
                return coordinate;
            }
            return original;
        }, (IMP *)&FGPSOriginalUserLocationCoordinate);
    });
}
