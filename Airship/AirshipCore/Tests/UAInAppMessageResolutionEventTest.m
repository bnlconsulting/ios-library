/* Copyright Airship and Contributors */

#import "UABaseTest.h"
#import "UAInAppMessageResolutionEvent+Internal.h"
#import "UAInAppMessage+Internal.h"
#import "UAInAppMessageFullScreenDisplayContent.h"
#import "AirshipTests-Swift.h"

@import AirshipCore;


@interface UAInAppMessageResolutionEventTest : UABaseTest
@property(nonatomic, strong) UATestAnalytics *analytics;
@property(nonatomic, strong) UATestAirshipInstance *airship;
@property (nonatomic, strong) UAInAppMessageFullScreenDisplayContent *displayContent;
@property (nonatomic, copy) NSDictionary *renderedLocale;
@end

@implementation UAInAppMessageResolutionEventTest

- (void)setUp {
    [super setUp];

    self.analytics = [[UATestAnalytics alloc] init];
    self.analytics.conversionSendID = [NSUUID UUID].UUIDString;
    self.analytics.conversionPushMetadata = [NSUUID UUID].UUIDString;
    self.airship = [[UATestAirshipInstance alloc] init];
    self.airship.components = @[self.analytics];
    [self.airship makeShared];
    
    self.displayContent = [UAInAppMessageFullScreenDisplayContent displayContentWithBuilderBlock:^(UAInAppMessageFullScreenDisplayContentBuilder *builder) {
        builder.buttonLayout = UAInAppMessageButtonLayoutTypeJoined;

        UAInAppMessageTextInfo *heading = [UAInAppMessageTextInfo textInfoWithBuilderBlock:^(UAInAppMessageTextInfoBuilder * _Nonnull builder) {
            builder.text = @"Here is a headline!";
        }];
        builder.heading = heading;



        UAInAppMessageButtonInfo *buttonOne = [UAInAppMessageButtonInfo buttonInfoWithBuilderBlock:^(UAInAppMessageButtonInfoBuilder * _Nonnull builder) {
            builder.label = [UAInAppMessageTextInfo textInfoWithBuilderBlock:^(UAInAppMessageTextInfoBuilder * _Nonnull builder) {
                builder.text = @"Dismiss";
            }];
            builder.identifier = @"button";
        }];

        UAInAppMessageButtonInfo *buttonTwo = [UAInAppMessageButtonInfo buttonInfoWithBuilderBlock:^(UAInAppMessageButtonInfoBuilder * _Nonnull builder) {
            builder.label = [UAInAppMessageTextInfo textInfoWithBuilderBlock:^(UAInAppMessageTextInfoBuilder * _Nonnull builder) {
                builder.text = [@"" stringByPaddingToLength:31 withString:@"TEXT" startingAtIndex:0];
            }];
            builder.identifier = @"long_button_text";
        }];

        UAInAppMessageButtonInfo *buttonThree = [UAInAppMessageButtonInfo buttonInfoWithBuilderBlock:^(UAInAppMessageButtonInfoBuilder * _Nonnull builder) {
            builder.label = [UAInAppMessageTextInfo textInfoWithBuilderBlock:^(UAInAppMessageTextInfoBuilder * _Nonnull builder) {
                builder.text = [@"" stringByPaddingToLength:30 withString:@"TEXT" startingAtIndex:0];
            }];
            builder.identifier = @"exact_button_description";
        }];

        builder.buttons = @[buttonOne, buttonTwo, buttonThree];
    }];

    self.renderedLocale = @{@"language" : @"en", @"country" : @"US"};
}

/**
 * Test in-app direct open resolution event.
 */
- (void)testLegacyDirectOpenResolutionEvent {
    NSDictionary *expectedData = @{ @"id": @"message id",
                                    @"conversion_send_id": [self.analytics conversionSendID],
                                    @"conversion_metadata": [self.analytics conversionPushMetadata],
                                    @"source": @"urban-airship",
                                    @"resolution": @{ @"type": @"direct_open" }
    };


    UAInAppMessageResolutionEvent *event = [UAInAppMessageResolutionEvent legacyDirectOpenEventWithMessageID:@"message id"];
    XCTAssertEqualObjects(event.data, expectedData);
}

/**
 * Test in-app replaced resolution event.
 */
- (void)testLegacyReplacedResolutionEvent {
    NSDictionary *expectedData = @{ @"id": @"message id",
                                    @"conversion_send_id": [self.analytics conversionSendID],
                                    @"conversion_metadata": [self.analytics conversionPushMetadata],
                                    @"source": @"urban-airship",
                                    @"resolution": @{ @"type": @"replaced",
                                                      @"replacement_id": @"replacement id"}
    };

    UAInAppMessageResolutionEvent *event = [UAInAppMessageResolutionEvent legacyReplacedEventWithMessageID:@"message id" replacementID:@"replacement id"];

    XCTAssertEqualObjects(event.data, expectedData);
}

/**
 * Test in-app button clicked resolution event.
 */
- (void)testButtonClickedResolutionEvent {
    NSDictionary *expectedResolutionData = @{ @"type": @"button_click",
                                              @"button_id": self.displayContent.buttons[0].identifier,
                                              @"button_description": self.displayContent.buttons[0].label.text,
                                              @"display_time": @"3.141"};

    UAInAppMessageResolution *resolution = [UAInAppMessageResolution buttonClickResolutionWithButtonInfo:self.displayContent.buttons[0]];
    [self verifyEventWithMessageID:@"message ID"
                         campaigns:nil
                        eventBlock:^UAInAppMessageResolutionEvent *(UAInAppMessage *message) {
        return [UAInAppMessageResolutionEvent eventWithMessageID:@"message ID"
                                                          source:message.source
                                                      resolution:resolution
                                                     displayTime:3.141
                                                       campaigns:nil];
    } expectedResolutionData:expectedResolutionData];
}

/**
 * Test in-app button clicked resolution event with a label only takes the first 30 characters.
 */
- (void)testButtonClickedResolutionLongLabel {
    NSDictionary *expectedResolutionData = @{ @"type": @"button_click",
                                              @"button_id": self.displayContent.buttons[1].identifier,
                                              @"button_description": self.displayContent.buttons[1].label.text,
                                              @"display_time": @"3.141"};

    UAInAppMessageResolution *resolution = [UAInAppMessageResolution buttonClickResolutionWithButtonInfo:self.displayContent.buttons[1]];
    [self verifyEventWithMessageID:@"message ID" campaigns:nil eventBlock:^UAInAppMessageResolutionEvent *(UAInAppMessage *message) {
        return [UAInAppMessageResolutionEvent eventWithMessageID:@"message ID"
                                                          source:message.source
                                                      resolution:resolution
                                                     displayTime:3.141
                                                       campaigns:nil];
    } expectedResolutionData:expectedResolutionData];
}

/**
 * Test in-app button clicked resolution event with a label only takes the first 30 characters.
 */
- (void)testButtonClickedResolutionMaxDescriptionLength {
    NSDictionary *expectedResolutionData = @{ @"type": @"button_click",
                                              @"button_id": self.displayContent.buttons[2].identifier,
                                              @"button_description": self.displayContent.buttons[2].label.text,
                                              @"display_time": @"3.141"};

    UAInAppMessageResolution *resolution = [UAInAppMessageResolution buttonClickResolutionWithButtonInfo:self.displayContent.buttons[2]];

    [self verifyEventWithMessageID:@"message ID"
                         campaigns:@{@"categories": @[@"neat"]}
                        eventBlock:^UAInAppMessageResolutionEvent *(UAInAppMessage *message) {
        return [UAInAppMessageResolutionEvent eventWithMessageID:@"message ID"
                                                          source:message.source
                                                      resolution:resolution
                                                     displayTime:3.141
                                                       campaigns:@{@"categories": @[@"neat"]}];
    } expectedResolutionData:expectedResolutionData];
}

/**
 * Test in-app message clicked resolution event.
 */
- (void)testMessageClickedResolutionEvent {
    NSDictionary *expectedResolutionData = @{ @"type": @"message_click",
                                              @"display_time": @"3.141"};

    UAInAppMessageResolution *resolution = [UAInAppMessageResolution messageClickResolution];
    [self verifyEventWithMessageID:@"message ID"
                         campaigns:@{@"categories": @[@"neat"]}
                        eventBlock:^UAInAppMessageResolutionEvent *(UAInAppMessage *message) {
        return [UAInAppMessageResolutionEvent eventWithMessageID:@"message ID"
                                                          source:message.source
                                                      resolution:resolution
                                                     displayTime:3.141
                                                       campaigns:@{@"categories": @[@"neat"]}];
    } expectedResolutionData:expectedResolutionData];
}

/**
 * Test in-app dismisssed resolution event.
 */
- (void)testDismissedResolutionEvent {
    NSDictionary *expectedResolutionData = @{ @"type": @"user_dismissed",
                                              @"display_time": @"3.141"};

    UAInAppMessageResolution *resolution = [UAInAppMessageResolution userDismissedResolution];
    [self verifyEventWithMessageID:@"message ID"
                         campaigns:@{@"categories": @[@"neat"]}
                        eventBlock:^UAInAppMessageResolutionEvent *(UAInAppMessage *message) {
        return [UAInAppMessageResolutionEvent eventWithMessageID:@"message ID"
                                                          source:message.source
                                                      resolution:resolution
                                                     displayTime:3.141
                                                       campaigns:@{@"categories": @[@"neat"]}];
    } expectedResolutionData:expectedResolutionData];}

/**
 * Test in-app timed out resolution event.
 */
- (void)testTimedOutResolutionEvent {
    NSDictionary *expectedResolutionData = @{ @"type": @"timed_out",
                                              @"display_time": @"3.141"};

    UAInAppMessageResolution *resolution = [UAInAppMessageResolution timedOutResolution];
    [self verifyEventWithMessageID:@"message ID"
                         campaigns:@{@"categories": @[@"neat"]}
                        eventBlock:^UAInAppMessageResolutionEvent *(UAInAppMessage *message) {
        return [UAInAppMessageResolutionEvent eventWithMessageID:@"message ID"
                                                          source:message.source
                                                      resolution:resolution
                                                     displayTime:3.141
                                                       campaigns:@{@"categories": @[@"neat"]}];
    } expectedResolutionData:expectedResolutionData];
}

- (void)verifyEventWithMessageID:(NSString *)messageID
                       campaigns:(NSDictionary *)campaigns
                      eventBlock:(UAInAppMessageResolutionEvent * (^)(UAInAppMessage *))eventBlock
          expectedResolutionData:(NSDictionary *)expectedResolutionData {

    UAInAppMessage *remoteDataMessage = [UAInAppMessage messageWithBuilderBlock:^(UAInAppMessageBuilder *builder) {
        builder.source = UAInAppMessageSourceRemoteData;
        builder.displayContent = self.displayContent;
    }];

    UAInAppMessageResolutionEvent *event = eventBlock(remoteDataMessage);

    NSMutableDictionary *idPayload = [NSMutableDictionary dictionary];
    [idPayload setValue:messageID forKey:@"message_id"];
    [idPayload setValue:campaigns forKey:@"campaigns"];

    NSDictionary *expectedData = @{ @"id": idPayload,
                                    @"source": @"urban-airship",
                                    @"conversion_send_id": [self.analytics conversionSendID],
                                    @"conversion_metadata": [self.analytics conversionPushMetadata],
                                    @"resolution": expectedResolutionData,
    };

    XCTAssertEqualObjects(event.data, expectedData);
    XCTAssertEqualObjects(event.eventType, @"in_app_resolution");

    UAInAppMessage *legacyMessage = [UAInAppMessage messageWithBuilderBlock:^(UAInAppMessageBuilder *builder) {
        builder.source = UAInAppMessageSourceLegacyPush;
        builder.displayContent = self.displayContent;
    }];

    event = eventBlock(legacyMessage);

    expectedData = @{ @"id": messageID,
                      @"source": @"urban-airship",
                      @"conversion_send_id": [self.analytics conversionSendID],
                      @"conversion_metadata": [self.analytics conversionPushMetadata],
                      @"resolution": expectedResolutionData };

    XCTAssertEqualObjects(event.data, expectedData);
    XCTAssertEqualObjects(event.eventType, @"in_app_resolution");

    UAInAppMessage *appDefined = [UAInAppMessage messageWithBuilderBlock:^(UAInAppMessageBuilder *builder) {
        builder.source = UAInAppMessageSourceAppDefined;
        builder.displayContent = self.displayContent;
    }];

    event = eventBlock(appDefined);

    expectedData = @{ @"id": @{ @"message_id": messageID },
                      @"source": @"app-defined",
                      @"conversion_send_id": [self.analytics conversionSendID],
                      @"conversion_metadata": [self.analytics conversionPushMetadata],
                      @"resolution": expectedResolutionData };

    XCTAssertEqualObjects(event.data, expectedData);
    XCTAssertEqualObjects(event.eventType, @"in_app_resolution");
}

@end



