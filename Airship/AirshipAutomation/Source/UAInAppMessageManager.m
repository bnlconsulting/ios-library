/* Copyright Airship and Contributors */

#import "UAInAppMessageManager+Internal.h"
#import "UAInAppMessageAdapterProtocol.h"
#import "UAInAppMessageBannerAdapter.h"
#import "UAInAppMessageFullScreenAdapter.h"
#import "UAInAppMessageModalAdapter.h"
#import "UAInAppMessageHTMLAdapter.h"
#import "UAInAppMessage+Internal.h"
#import "UAInAppMessageResolutionEvent+Internal.h"
#import "UAInAppMessageDisplayEvent+Internal.h"
#import "UAInAppMessageDefaultDisplayCoordinator.h"
#import "UAInAppMessageAssetManager+Internal.h"
#import "UAInAppMessageImmediateDisplayCoordinator.h"
#import "UAActiveTimer+Internal.h"
#import "UARetriable+Internal.h"
#import "UARetriablePipeline+Internal.h"
#import "UAAirshipAutomationCoreImport.h"
#import "UAAutomationEngine+Internal.h"
#import "NSObject+UAAdditions+Internal.h"

#if __has_include("AirshipKit/AirshipKit-Swift.h")
#import <AirshipKit/AirshipKit-Swift.h>
#elif __has_include("AirshipKit-Swift.h")
#import "AirshipKit-Swift.h"
#else
@import AirshipCore;
#endif
NS_ASSUME_NONNULL_BEGIN

NSString *const UAInAppMessageManagerDisplayIntervalKey = @"UAInAppMessageManagerDisplayInterval";
NSString *const UAInAppMessageDisplayCoordinatorIsReadyKey = @"isReady";

@interface UAInAppMessageScheduleData : NSObject

@property(nonatomic, strong, nonnull) id<UAInAppMessageAdapterProtocol> adapter;
@property(nonatomic, copy, nonnull) NSString *scheduleID;
@property(nonatomic, strong, nonnull) UAInAppMessage *message;
@property(nonatomic, strong, nonnull) id<UAInAppMessageDisplayCoordinator> displayCoordinator;
@property(nonatomic, copy, nullable) NSDictionary *campaigns;

+ (instancetype)dataWithAdapter:(id<UAInAppMessageAdapterProtocol>)adapter
                     scheduleID:(NSString *)scheduleID
                        message:(UAInAppMessage *)message
                      campaigns:(nullable NSDictionary *)campaigns
             displayCoordinator:(id<UAInAppMessageDisplayCoordinator>)displayCoordinator;


@end

@implementation UAInAppMessageScheduleData

- (instancetype)initWithAdapter:(id<UAInAppMessageAdapterProtocol>)adapter
                     scheduleID:(NSString *)scheduleID
                        message:(UAInAppMessage *)message
                      campaigns:(nullable NSDictionary *)campaigns
             displayCoordinator:(id<UAInAppMessageDisplayCoordinator>)displayCoordinator {

    self = [super init];

    if (self) {
        self.adapter = adapter;
        self.scheduleID = scheduleID;
        self.message = message;
        self.campaigns = campaigns;
        self.displayCoordinator = displayCoordinator;
    }

    return self;
}

+ (instancetype)dataWithAdapter:(id<UAInAppMessageAdapterProtocol>)adapter
                     scheduleID:(NSString *)scheduleID
                        message:(UAInAppMessage *)message
                      campaigns:(nullable NSDictionary *)campaigns
             displayCoordinator:(id<UAInAppMessageDisplayCoordinator>)displayCoordinator {

    return [[self alloc] initWithAdapter:adapter
                              scheduleID:scheduleID
                                 message:message
                               campaigns:campaigns
                      displayCoordinator:displayCoordinator];
}

@end

@interface UAInAppMessageManager ()

@property(nonatomic, strong) NSMutableDictionary *adapterFactories;
@property(nonatomic, strong) UAPreferenceDataStore *dataStore;
@property(nonatomic, strong) NSMutableDictionary *scheduleData;
@property(nonatomic, strong) UADispatcher *dispatcher;
@property(nonatomic, strong) UARetriablePipeline *prepareSchedulePipeline;
@property(nonatomic, strong) UAInAppMessageDefaultDisplayCoordinator *defaultDisplayCoordinator;
@property(nonatomic, strong) UAInAppMessageImmediateDisplayCoordinator *immediateDisplayCoordinator;
@property(nonatomic, strong) id<UAAnalyticsProtocol> analytics;
@property(nonatomic, strong) UAInAppMessageAssetManager *assetManager;
@property(nonatomic, strong) NSMapTable *displayCoordinatorReadyListeners;

@end

@implementation UAInAppMessageManager

+ (instancetype)managerWithDataStore:(UAPreferenceDataStore *)dataStore
                           analytics:(id<UAAnalyticsProtocol>) analytics
                          dispatcher:(UADispatcher *)dispatcher
                  displayCoordinator:(UAInAppMessageDefaultDisplayCoordinator *)displayCoordinator
                        assetManager:(UAInAppMessageAssetManager *)assetManager {

    return [[UAInAppMessageManager alloc] initWithDataStore:dataStore
                                                  analytics:analytics
                                                 dispatcher:dispatcher
                                         displayCoordinator:displayCoordinator
                                               assetManager:assetManager];
}

+ (instancetype)managerWithDataStore:(UAPreferenceDataStore *)dataStore
                           analytics:(id<UAAnalyticsProtocol>)analytics {

    return [[UAInAppMessageManager alloc] initWithDataStore:dataStore
                                                  analytics:analytics
                                                 dispatcher:UADispatcher.main
                                         displayCoordinator:[[UAInAppMessageDefaultDisplayCoordinator alloc] init]
                                               assetManager:[UAInAppMessageAssetManager assetManager]];

}

- (instancetype)initWithDataStore:(UAPreferenceDataStore *)dataStore
                        analytics:(id<UAAnalyticsProtocol>)analytics
                       dispatcher:(UADispatcher *)dispatcher
               displayCoordinator:(UAInAppMessageDefaultDisplayCoordinator *)displayCoordinator
                     assetManager:(UAInAppMessageAssetManager *)assetManager {

    self = [super init];

    if (self) {
        self.dataStore = dataStore;
        self.analytics = analytics;
        self.dispatcher = dispatcher;
        self.defaultDisplayCoordinator = displayCoordinator;
        self.assetManager = assetManager;

        self.scheduleData = [NSMutableDictionary dictionary];
        self.adapterFactories = [NSMutableDictionary dictionary];
        self.prepareSchedulePipeline = [UARetriablePipeline pipeline];
        self.immediateDisplayCoordinator = [UAInAppMessageImmediateDisplayCoordinator coordinator];

        self.defaultDisplayCoordinator.displayInterval = self.displayInterval;
        [self setDefaultAdapterFactories];

        self.displayCoordinatorReadyListeners = [NSMapTable weakToStrongObjectsMapTable];
    }

    return self;
}

- (void)setDisplayInterval:(NSTimeInterval)displayInterval {
    self.defaultDisplayCoordinator.displayInterval = displayInterval;
    [self.dataStore setInteger:displayInterval forKey:UAInAppMessageManagerDisplayIntervalKey];
}

- (NSTimeInterval)displayInterval {
    if ([self.dataStore objectForKey:UAInAppMessageManagerDisplayIntervalKey]) {
        return [self.dataStore integerForKey:UAInAppMessageManagerDisplayIntervalKey];
    }
    return kUAInAppMessageDefaultDisplayInterval;
}

// Sets the default adapter factories
- (void)setDefaultAdapterFactories {
    // Banner
    [self setFactoryBlock:^id<UAInAppMessageAdapterProtocol> _Nonnull(UAInAppMessage * _Nonnull message) {
        return [UAInAppMessageBannerAdapter adapterForMessage:message];
    } forDisplayType:UAInAppMessageDisplayTypeBanner];

    // Full Screen
    [self setFactoryBlock:^id<UAInAppMessageAdapterProtocol> _Nonnull(UAInAppMessage * _Nonnull message) {
        return [UAInAppMessageFullScreenAdapter adapterForMessage:message];
    } forDisplayType:UAInAppMessageDisplayTypeFullScreen];

    // Modal
    [self setFactoryBlock:^id<UAInAppMessageAdapterProtocol> _Nonnull(UAInAppMessage * _Nonnull message) {
        return [UAInAppMessageModalAdapter adapterForMessage:message];
    } forDisplayType:UAInAppMessageDisplayTypeModal];

    [self setFactoryBlock:^id<UAInAppMessageAdapterProtocol> _Nonnull(UAInAppMessage * _Nonnull message) {
        return [UAInAppMessageHTMLAdapter adapterForMessage:message];
    } forDisplayType:UAInAppMessageDisplayTypeHTML];
}

- (void)setFactoryBlock:(id<UAInAppMessageAdapterProtocol> (^)(UAInAppMessage* message))factory
         forDisplayType:(UAInAppMessageDisplayType)displayType {

    if (factory) {
        self.adapterFactories[@(displayType)] = factory;
    } else {
        [self.adapterFactories removeObjectForKey:@(displayType)];
    }
}

- (nullable id<UAInAppMessageAdapterProtocol>)createAdapterForMessage:(UAInAppMessage *)message scheduleID:(NSString *)scheduleID {
    id<UAInAppMessageAdapterProtocol> (^factory)(UAInAppMessage* message) = self.adapterFactories[@(message.displayType)];

    if (!factory) {
        UA_LERR(@"Factory unavailable for message: %@", message);
        return nil;
    }

    return factory(message);
}

- (void)scheduleExecutionAborted:(NSString *)scheduleID {
    UAInAppMessageScheduleData *data = self.scheduleData[scheduleID];
    if (data) {
        [self.assetManager onDisplayFinished:data.message scheduleID:scheduleID];
    }
}

- (UARetriable *)prepareMessageAssetsWithMessage:(UAInAppMessage *)message
                                      scheduleID:(NSString *)scheduleID
                                    resultHandler:(UARetriableCompletionHandler)resultHandler {
    return [UARetriable retriableWithRunBlock:^(UARetriableCompletionHandler _Nonnull handler) {
        [self.assetManager onPrepareMessage:message scheduleID:scheduleID completionHandler:^(UAInAppMessagePrepareResult result) {
            switch (result) {
                case UAInAppMessagePrepareResultSuccess:
                    handler(UARetriableResultSuccess);
                    break;
                case UAInAppMessagePrepareResultRetry:
                    handler(UARetriableResultRetry);
                    break;
                case UAInAppMessagePrepareResultCancel:
                    [self.assetManager onDisplayFinished:message scheduleID:scheduleID];
                    handler(UARetriableResultCancel);
                    break;
                case UAInAppMessagePrepareResultInvalidate:
                    handler(UARetriableResultInvalidate);
            }
        }];
    } resultHandler:resultHandler];
}

- (UARetriable *)prepareAdapter:(id<UAInAppMessageAdapterProtocol>)adapter
                     scheduleID:(NSString *)scheduleID
                  resultHandler:(UARetriableCompletionHandler)resultHandler {

    UA_WEAKIFY(self)
    return [UARetriable retriableWithRunBlock:^(UARetriableCompletionHandler handler) {
        UA_STRONGIFY(self)
        [self.assetManager assetsForScheduleID:scheduleID completionHandler:^(UAInAppMessageAssets *assets) {
            [self.dispatcher dispatchAsync:^{
                [adapter prepareWithAssets:assets completionHandler:^void(UAInAppMessagePrepareResult prepareResult) {
                    UA_LDEBUG(@"Prepare result: %ld schedule: %@", (unsigned long)prepareResult, scheduleID);
                    switch (prepareResult) {
                        case UAInAppMessagePrepareResultSuccess:
                            handler(UARetriableResultSuccess);
                            break;
                        case UAInAppMessagePrepareResultRetry:
                            handler(UARetriableResultRetry);
                            break;
                        case UAInAppMessagePrepareResultCancel:
                            handler(UARetriableResultCancel);
                            break;
                        case UAInAppMessagePrepareResultInvalidate:
                            handler(UARetriableResultInvalidate);
                            break;
                    }
                }];
            }];
        }];
    } resultHandler:resultHandler];
}

- (void)prepareMessage:(UAInAppMessage *)message
            scheduleID:(NSString *)scheduleID
             campaigns:(nullable NSDictionary *)campaigns
     completionHandler:(void (^)(UAAutomationSchedulePrepareResult))completionHandler {
    // Allow the delegate to extend the message if desired.
    id<UAInAppMessagingDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(extendMessage:)]) {
        message = [delegate extendMessage:message];
        if (!message) {
            UA_LERR(@"Error extending message");
            completionHandler(UAAutomationSchedulePrepareResultPenalize);
            return;
        }
    }

    // Create adapter
    id<UAInAppMessageAdapterProtocol> adapter = [self createAdapterForMessage:message scheduleID:scheduleID];

    if (!adapter) {
        UA_LDEBUG(@"Failed to build adapter for message: %@, skipping display for schedule: %@", message, scheduleID);
        completionHandler(UAAutomationSchedulePrepareResultPenalize);
        return;
    }

    // Display coordinator
    id<UAInAppMessageDisplayCoordinator> displayCoordinator = [self displayCoordinatorForMessage:message];

    // Prepare the assets
    UARetriable *prepareAssets = [self prepareMessageAssetsWithMessage:message scheduleID:scheduleID resultHandler:^(UARetriableResult result) {
        UAAutomationSchedulePrepareResult prepareResult = UAAutomationSchedulePrepareResultInvalidate;
        switch (result) {
            case UARetriableResultSuccess:
                return;
            case UARetriableResultRetry:
                // Allow the pipeline to retry with backoff
                return;
            case UARetriableResultCancel:
                prepareResult = UAAutomationSchedulePrepareResultCancel;
                break;
            case UARetriableResultInvalidate:
                prepareResult = UAAutomationSchedulePrepareResultInvalidate;
                break;
        }
        completionHandler(prepareResult);
    }];

    // Prepare adapter
    UA_WEAKIFY(self)
    UARetriable *prepareAdapter = [self prepareAdapter:adapter scheduleID:scheduleID resultHandler:^(UARetriableResult result) {
        UA_STRONGIFY(self)
        UAAutomationSchedulePrepareResult prepareResult = UAAutomationSchedulePrepareResultInvalidate;
        switch (result) {
            case UARetriableResultSuccess:
                prepareResult = UAAutomationSchedulePrepareResultContinue;
                self.scheduleData[scheduleID] = [UAInAppMessageScheduleData dataWithAdapter:adapter
                                                                                 scheduleID:scheduleID
                                                                                    message:message
                                                                                  campaigns:campaigns
                                                                         displayCoordinator:displayCoordinator];
                break;
            case UARetriableResultRetry:
                // Allow the pipeline to retry with backoff
                return;
            case UARetriableResultCancel:
                prepareResult = UAAutomationSchedulePrepareResultCancel;
                [self.assetManager onDisplayFinished:message scheduleID:scheduleID];
                break;
            case UARetriableResultInvalidate:
                prepareResult = UAAutomationSchedulePrepareResultInvalidate;
                [self.assetManager onDisplayFinished:message scheduleID:scheduleID];
                break;
        }
        completionHandler(prepareResult);
    }];

    [self.prepareSchedulePipeline addChainedRetriables:@[prepareAssets, prepareAdapter]];
}

- (nonnull id<UAInAppMessageDisplayCoordinator>)displayCoordinatorForMessage:(UAInAppMessage *)message {
    id<UAInAppMessageDisplayCoordinator> displayCoordinator;
    id<UAInAppMessagingDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(displayCoordinatorForMessage:)]) {
        displayCoordinator = [delegate displayCoordinatorForMessage:message];
    } else if ([message.displayBehavior isEqualToString:UAInAppMessageDisplayBehaviorImmediate]) {
        displayCoordinator = self.immediateDisplayCoordinator;
    }

    return displayCoordinator ?: self.defaultDisplayCoordinator;
}

- (UAAutomationScheduleReadyResult)isReadyToDisplay:(NSString *)scheduleID {
    UA_LTRACE(@"Checking if schedule %@ is ready to execute.", scheduleID);

    UAInAppMessageScheduleData *data = self.scheduleData[scheduleID];
    if (!data) {
        UA_LERR("No data for schedule: %@", scheduleID);
        return UAAutomationScheduleReadyResultInvalidate;
    }

    NSObject<UAInAppMessageDisplayCoordinator> *displayCoordinator = (NSObject<UAInAppMessageDisplayCoordinator>*)data.displayCoordinator;

    // If display coordinator puts back pressure on display, check again when it's ready
    if (![displayCoordinator isReady]) {
        UA_LTRACE(@"Display coordinator %@ not ready. Retrying schedule %@ later.", displayCoordinator, scheduleID);

        __block UADisposable *disposable = [displayCoordinator observeAtKeyPath:UAInAppMessageDisplayCoordinatorIsReadyKey withBlock:^(id value) {
            if ([value boolValue]) {
                [self.executionDelegate executionReadinessChanged];
                [disposable dispose];
            }
        }];

        // Cancel any active listeners
        [[self.displayCoordinatorReadyListeners objectForKey:displayCoordinator] dispose];

        // Add new listener
        [self.displayCoordinatorReadyListeners setObject:disposable forKey:displayCoordinator];

        return UAAutomationScheduleReadyResultNotReady;
    }

    if (![data.adapter isReadyToDisplay]) {
        UA_LTRACE(@"Adapter ready check failed. Schedule: %@ not ready.", scheduleID);
        return UAAutomationScheduleReadyResultNotReady;
    }

    UA_LTRACE(@"Schedule %@ ready!", scheduleID);
    return UAAutomationScheduleReadyResultContinue;
}

- (void)displayMessageWithScheduleID:(NSString *)scheduleID
                   completionHandler:(void (^)(void))completionHandler {

    UAInAppMessageScheduleData *scheduleData = self.scheduleData[scheduleID];
    if (!scheduleData) {
        completionHandler();
        return;
    }

    UAInAppMessage *message = scheduleData.message;
    id<UAInAppMessageAdapterProtocol> adapter = scheduleData.adapter;
    id<UAInAppMessageDisplayCoordinator> displayCoordinator = scheduleData.displayCoordinator;

    // Notify delegate that the message is about to be displayed
    id<UAInAppMessagingDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(messageWillBeDisplayed:scheduleID:)]) {
        [delegate messageWillBeDisplayed:message scheduleID:scheduleID];
    }

    if (message.isReportingEnabled) {
        // Display event
        UAInAppMessageDisplayEvent *event = [UAInAppMessageDisplayEvent eventWithMessageID:scheduleID message:message campaigns:scheduleData.campaigns];
        [self.analytics addEvent:event];
    }

    // Display time timer
    UAActiveTimer *timer = [[UAActiveTimer alloc] init];
    [timer start];

    // Notify the coordinator that message display has begin
    if ([displayCoordinator respondsToSelector:@selector(didBeginDisplayingMessage:)]) {
        [displayCoordinator didBeginDisplayingMessage:message];
    }

    // After display has finished, notify the coordinator as well
    completionHandler = ^{

        completionHandler();
    };

    UA_WEAKIFY(self);
    void (^displayCompletionHandler)(UAInAppMessageResolution *) = ^(UAInAppMessageResolution *resolution) {

        UA_STRONGIFY(self);
        UA_LDEBUG(@"Schedule %@ finished displaying", scheduleID);

        // Resolution event
        [timer stop];
        UAInAppMessageResolutionEvent *event = [UAInAppMessageResolutionEvent eventWithMessageID:scheduleID
                                                                   source:message.source
                                                                resolution:resolution
                                                               displayTime:timer.time
                                                                 campaigns:scheduleData.campaigns];

        if (message.isReportingEnabled) {
            [self.analytics addEvent:event];
        }

        // Cancel button
        if (resolution.type == UAInAppMessageResolutionTypeButtonClick && resolution.buttonInfo.behavior == UAInAppMessageButtonInfoBehaviorCancel) {
            [self.executionDelegate cancelScheduleWithID:scheduleID];
        }

        if (message.actions) {
            [UAActionRunner runActionsWithActionValues:message.actions
                                             situation:UASituationManualInvocation
                                              metadata:nil
                                     completionHandler:^(UAActionResult *result) {
                UA_LTRACE(@"Finished running actions for schedule %@", scheduleID);
            }];
        }

        [self.scheduleData removeObjectForKey:scheduleID];

        // Notify delegate that the message has finished displaying
        id<UAInAppMessagingDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(messageFinishedDisplaying:scheduleID:resolution:)]) {
            [delegate messageFinishedDisplaying:message scheduleID:scheduleID resolution:resolution];
        }

        // notify the asset manager
        [self.assetManager onDisplayFinished:message scheduleID:scheduleID];

        if ([displayCoordinator respondsToSelector:@selector(didFinishDisplayingMessage:)]) {
            [displayCoordinator didFinishDisplayingMessage:message];
        }

        completionHandler();
    };

    [adapter display:displayCompletionHandler];
}

- (void)messageExecutionInterrupted:(nullable UAInAppMessage *)message
                         scheduleID:(NSString *)scheduleID
                          campaigns:(nullable NSDictionary *)campaigns {
    UAInAppMessageSource source = message == nil ? UAInAppMessageSourceRemoteData : message.source;
    UAInAppMessageResolutionEvent *event = [UAInAppMessageResolutionEvent eventWithMessageID:scheduleID
                                                                                      source:source
                                                                                  resolution:[UAInAppMessageResolution userDismissedResolution]
                                                                                 displayTime:0
                                                                                   campaigns:campaigns];

    [self.analytics addEvent:event];
}

- (void)messageScheduled:(UAInAppMessage *)message
              scheduleID:(NSString *)scheduleID {
    [self.assetManager onMessageScheduled:message scheduleID:scheduleID];
}

- (void)messageExpired:(UAInAppMessage *)message
            scheduleID:(NSString *)scheduleID
        expirationDate:(NSDate *)date {
    [self.assetManager onScheduleFinished:scheduleID];
}

- (void)messageCancelled:(UAInAppMessage *)message
              scheduleID:(NSString *)scheduleID {
    [self.assetManager onScheduleFinished:scheduleID];

}

- (void)messageLimitReached:(UAInAppMessage *)message
                 scheduleID:(NSString *)scheduleID {
    [self.assetManager onScheduleFinished:scheduleID];
}

@end

NS_ASSUME_NONNULL_END
