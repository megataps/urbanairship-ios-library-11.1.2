/* Copyright Airship and Contributors */

#import "UABaseTest.h"
#import "UAInAppRemoteDataClient+Internal.h"
#import "UARemoteDataManager+Internal.h"
#import "UAirship+Internal.h"
#import "UARemoteDataPayload+Internal.h"
#import "UAUtils+Internal.h"
#import "UAPreferenceDataStore+Internal.h"
#import "UAInAppMessageManager.h"
#import "UAPush+Internal.h"
#import "UASchedule+Internal.h"
#import "UAScheduleEdits+Internal.h"
#import "NSJSONSerialization+UAAdditions.h"

NSString * const UAInAppMessagesScheduledMessagesKey = @"UAInAppRemoteDataClient.ScheduledMessages";

@interface UAInAppRemoteDataClientTest : UABaseTest
@property (nonatomic,strong) UAInAppRemoteDataClient *remoteDataClient;
@property (nonatomic, strong) UARemoteDataPublishBlock publishBlock;
@property (nonatomic, strong) id mockRemoteDataManager;
@property (nonatomic, strong) id mockScheduler;
@property (nonatomic, strong) id mockPush;

@property (nonatomic, strong) NSMutableArray<UASchedule *> *allSchedules;
@end

@implementation UAInAppRemoteDataClientTest

- (void)setUp {
    [super setUp];
    
    uaLogLevel = UALogLevelDebug;
    
    // mock remote data
    self.mockRemoteDataManager = [self mockForClass:[UARemoteDataManager class]];
    [[[self.mockRemoteDataManager expect] andDo:^(NSInvocation *invocation) {
        void *arg;
        
        // verify payload types
        [invocation getArgument:&arg atIndex:2];
        NSArray<NSString *> *types = (__bridge NSArray<NSString *> *)arg;
        XCTAssertTrue(types.count == 1);
        XCTAssertTrue([types containsObject:@"in_app_messages"]);
        
        // verify and check publishBlock
        [invocation getArgument:&arg atIndex:3];
        self.publishBlock = (__bridge UARemoteDataPublishBlock)arg;
        XCTAssertNotNil(self.publishBlock);
    }] subscribeWithTypes:OCMOCK_ANY block:OCMOCK_ANY];
    
    self.mockPush = [self mockForClass:[UAPush class]];
    [[[self.mockPush expect] andReturn:nil] channelID];

    self.mockScheduler = [self mockForClass:[UAInAppMessageManager class]];
    self.allSchedules = [NSMutableArray array];
    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        void (^completionHandler)(NSArray<UASchedule *> *) = (__bridge void (^)(NSArray<UASchedule *> *))arg;
        completionHandler(self.allSchedules);
    }] getAllSchedules:OCMOCK_ANY];
    
    self.remoteDataClient = [UAInAppRemoteDataClient clientWithScheduler:self.mockScheduler remoteDataManager:self.mockRemoteDataManager dataStore:self.dataStore push:self.mockPush];
    XCTAssertNotNil(self.remoteDataClient);
    
    // verify setup
    XCTAssertNotNil(self.remoteDataClient);
    XCTAssertNotNil(self.publishBlock);
    [self.mockPush verify];
    [self.mockRemoteDataManager verify];
}

- (void)testMetadataChange {
    NSDictionary *metadataA = @{@"cool":@"story"};
    NSDictionary *metadataB = @{@"millennial":@"potato"};

    // setup
    NSString *messageID = [NSUUID UUID].UUIDString;
    NSDictionary *simpleMessage = @{@"message": @{
                                            @"name": @"Simple Message",
                                            @"message_id": messageID,
                                            @"push_id": [NSUUID UUID].UUIDString,
                                            @"display_type": @"banner",
                                            @"display": @{
                                                    @"body" : @{
                                                            @"text" : @"hi there"
                                                            },
                                                    },
                                            },
                                    @"created": @"2017-12-04T19:07:54.564",
                                    @"last_updated": @"2017-12-04T19:07:54.564",
                                    @"triggers": @[
                                            @{
                                                @"type":@"app_init",
                                                @"goal":@1
                                                }
                                            ]
                                    };
    NSArray *inAppMessages = @[simpleMessage];
    NSUInteger expectedNumberOfScheduleInfos = inAppMessages.count;
    UARemoteDataPayload *inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                                                  timestamp:[NSDate date]
                                                                                       data:@{@"in_app_messages":inAppMessages}
                                                                                   metadata:metadataA];

    // expectations
    __block NSUInteger callsToScheduleMessages = 0;
    [[[self.mockScheduler expect] andDo:^(NSInvocation *invocation) {
        callsToScheduleMessages++;

        void *arg;
        [invocation getArgument:&arg atIndex:2];
        NSArray<UAInAppMessageScheduleInfo *> *scheduleInfos = (__bridge NSArray<UAInAppMessageScheduleInfo *> *)arg;

        XCTAssertEqual(scheduleInfos.count, expectedNumberOfScheduleInfos);

        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(NSArray<UASchedule *> *) = (__bridge void (^)(NSArray<UASchedule *> *))arg;

        for (UAInAppMessageScheduleInfo *info in scheduleInfos) {
            [self.allSchedules addObject:[UASchedule scheduleWithIdentifier:info.message.identifier info:info metadata:metadataA]];
        }

        completionHandler(self.allSchedules);
    }] scheduleMessagesWithScheduleInfo:OCMOCK_ANY metadata:metadataA completionHandler:OCMOCK_ANY];

    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];

    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(callsToScheduleMessages, 1);

    XCTestExpectation *editCalled = [self expectationWithDescription:@"Edit call should be made for metadata change"];
    [[[self.mockScheduler expect] andDo:^(NSInvocation *invocation) {
        void *arg;

        [invocation getArgument:&arg atIndex:3];
        UAInAppMessageScheduleEdits *edits = (__bridge UAInAppMessageScheduleEdits *)arg;

        XCTAssertEqualObjects(edits.metadata, [NSJSONSerialization stringWithObject:metadataB]);

        [editCalled fulfill];
        
        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(UASchedule *) = (__bridge void (^)(UASchedule *))arg;
        completionHandler(self.allSchedules[0]);
    }] editScheduleWithID:[OCMArg checkWithBlock:^BOOL(id obj) {
        NSString *scheduleID = obj;
        return [scheduleID isEqualToString:self.allSchedules[0].identifier];
    }] edits:OCMOCK_ANY completionHandler:OCMOCK_ANY];

    // setup to same message with metadata B
    inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                             timestamp:[NSDate date]
                                                                  data:@{@"in_app_messages":inAppMessages}
                                                              metadata:metadataB];
    // test
    self.publishBlock(@[inAppRemoteDataPayload]);

    [self waitForTestExpectations];

    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(callsToScheduleMessages,1);
}


- (void)testMissingInAppMessageRemoteData {
    // expectations
    __block NSUInteger callsToScheduleMessages = 0;
    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        XCTFail(@"No messages should be scheduled");
    }] scheduleMessagesWithScheduleInfo:OCMOCK_ANY metadata:OCMOCK_ANY completionHandler:OCMOCK_ANY];
    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        XCTFail(@"No messages should be cancelled");
    }] cancelMessagesWithID:OCMOCK_ANY];
    
    // test
    self.publishBlock(@[]);
    
    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(callsToScheduleMessages,0);
}

- (void)testEmptyInAppMessageList {
    // setup
    NSArray *inAppMessages = @[];
    UARemoteDataPayload *inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                                                  timestamp:[NSDate date]
                                                                                       data:@{@"in_app_messages":inAppMessages}
                                                                                       metadata:@{@"cool" : @"story"}];
    
    // expectations
    __block NSUInteger callsToScheduleMessages = 0;
    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        XCTFail(@"No messages should be scheduled");
    }] scheduleMessagesWithScheduleInfo:OCMOCK_ANY metadata:OCMOCK_ANY completionHandler:OCMOCK_ANY];
    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        XCTFail(@"No messages should be cancelled");
    }] cancelMessagesWithID:OCMOCK_ANY];
    
    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    
    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(callsToScheduleMessages,0);
}

- (void)testNonEmptyInAppMessageList {
    // setup
    NSString *messageID = [NSUUID UUID].UUIDString;
    NSDictionary *simpleMessage = @{@"message": @{
                                            @"name": @"Simple Message",
                                            @"message_id": messageID,
                                            @"push_id": [NSUUID UUID].UUIDString,
                                            @"display_type": @"banner",
                                            @"display": @{
                                                    @"body" : @{
                                                            @"text" : @"hi there"
                                                            },
                                                    },
                                            },
                                    @"created": @"2017-12-04T19:07:54.564",
                                    @"last_updated": @"2017-12-04T19:07:54.564",
                                    @"triggers": @[
                                            @{
                                                @"type":@"app_init",
                                                @"goal":@1
                                                }
                                            ]
                                    };
    NSArray *inAppMessages = @[simpleMessage];
    NSUInteger expectedNumberOfScheduleInfos = inAppMessages.count;
    UARemoteDataPayload *inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                                                  timestamp:[NSDate date]
                                                                                       data:@{@"in_app_messages":inAppMessages}
                                                                                   metadata:@{@"cool" : @"story"}];
    
    // expectations
    __block NSUInteger callsToScheduleMessages = 0;
    [[[self.mockScheduler expect] andDo:^(NSInvocation *invocation) {
        callsToScheduleMessages++;
        
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        NSArray<UAInAppMessageScheduleInfo *> *scheduleInfos = (__bridge NSArray<UAInAppMessageScheduleInfo *> *)arg;
        
        XCTAssertEqual(scheduleInfos.count, expectedNumberOfScheduleInfos);
        
        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(NSArray<UASchedule *> *) = (__bridge void (^)(NSArray<UASchedule *> *))arg;

        for (UAInAppMessageScheduleInfo *info in scheduleInfos) {
            [self.allSchedules addObject:[UASchedule scheduleWithIdentifier:info.message.identifier info:info metadata:@{}]];
        }
        completionHandler(self.allSchedules);
    }] scheduleMessagesWithScheduleInfo:OCMOCK_ANY metadata:OCMOCK_ANY completionHandler:OCMOCK_ANY];

    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];
    
    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(callsToScheduleMessages,1);
}

- (void)testSamePayloadSentTwice {
    // setup
    NSString *messageID = [NSUUID UUID].UUIDString;
    NSDictionary *simpleMessage = @{@"message": @{
                                            @"name": @"Simple Message",
                                            @"message_id": messageID,
                                            @"push_id": [NSUUID UUID].UUIDString,
                                            @"display_type": @"banner",
                                            @"display": @{
                                                    @"body" : @{
                                                            @"text" : @"hi there"
                                                            },
                                                    },
                                            },
                                    @"created": @"2017-12-04T19:07:54.564",
                                    @"last_updated": @"2017-12-04T19:07:54.564",
                                    @"triggers": @[
                                            @{
                                                @"type":@"app_init",
                                                @"goal":@1
                                                }
                                            ]
                                    };
    NSArray *inAppMessages = @[simpleMessage];
    NSUInteger expectedNumberOfScheduleInfos = inAppMessages.count;
    UARemoteDataPayload *inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                                                  timestamp:[NSDate date]
                                                                                       data:@{@"in_app_messages":inAppMessages}
                                                                                   metadata:@{@"cool" : @"story"}];
    
    // expectations
    __block NSUInteger callsToScheduleMessages = 0;
    [[[self.mockScheduler expect] andDo:^(NSInvocation *invocation) {
        callsToScheduleMessages++;
        
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        NSArray<UAInAppMessageScheduleInfo *> *scheduleInfos = (__bridge NSArray<UAInAppMessageScheduleInfo *> *)arg;
        
        XCTAssertEqual(scheduleInfos.count, expectedNumberOfScheduleInfos);
        
        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(NSArray<UASchedule *> *) = (__bridge void (^)(NSArray<UASchedule *> *))arg;
        
        for (UAInAppMessageScheduleInfo *info in scheduleInfos) {
            [self.allSchedules addObject:[UASchedule scheduleWithIdentifier:info.message.identifier info:info metadata:@{}]];
        }
        completionHandler(self.allSchedules);
    }] scheduleMessagesWithScheduleInfo:OCMOCK_ANY metadata:OCMOCK_ANY completionHandler:OCMOCK_ANY];
    
    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        XCTFail(@"No messages should be cancelled");
    }] cancelMessagesWithID:OCMOCK_ANY];
    
    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];

    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(callsToScheduleMessages,1);
        
    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    
    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(callsToScheduleMessages,1);
}

- (void)testSameMessageSentTwice {
    // setup
    NSString *messageID = [NSUUID UUID].UUIDString;
    NSDictionary *simpleMessage = @{@"message": @{
                                            @"name": @"Simple Message",
                                            @"message_id": messageID,
                                            @"push_id": [NSUUID UUID].UUIDString,
                                            @"display_type": @"banner",
                                            @"display": @{
                                                    @"body" : @{
                                                            @"text" : @"hi there"
                                                            },
                                                    },
                                            },
                                    @"created": @"2017-12-04T19:07:54.564",
                                    @"last_updated": @"2017-12-04T19:07:54.564",
                                    @"triggers": @[
                                            @{
                                                @"type":@"app_init",
                                                @"goal":@1
                                                }
                                            ]
                                    };
    NSArray *inAppMessages = @[simpleMessage];
    NSUInteger expectedNumberOfScheduleInfos = inAppMessages.count;
    UARemoteDataPayload *inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                                                  timestamp:[NSDate date]
                                                                                       data:@{@"in_app_messages":inAppMessages}
                                                                                   metadata:@{@"cool" : @"story"}];
    
    // expectations
    __block NSUInteger callsToScheduleMessages = 0;
    [[[self.mockScheduler expect] andDo:^(NSInvocation *invocation) {
        callsToScheduleMessages++;
        
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        NSArray<UAInAppMessageScheduleInfo *> *scheduleInfos = (__bridge NSArray<UAInAppMessageScheduleInfo *> *)arg;
        
        XCTAssertEqual(scheduleInfos.count, expectedNumberOfScheduleInfos);
        
        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(NSArray<UASchedule *> *) = (__bridge void (^)(NSArray<UASchedule *> *))arg;
        
        for (UAInAppMessageScheduleInfo *info in scheduleInfos) {
            [self.allSchedules addObject:[UASchedule scheduleWithIdentifier:info.message.identifier info:info metadata:@{}]];
        }
        completionHandler(self.allSchedules);
    }] scheduleMessagesWithScheduleInfo:OCMOCK_ANY metadata:OCMOCK_ANY completionHandler:OCMOCK_ANY];

    
    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];

    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(callsToScheduleMessages,1);
    
    // setup to send same message again
    inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                             timestamp:[NSDate date]
                                                                  data:@{@"in_app_messages":inAppMessages}
                                                              metadata:@{@"cool" : @"story"}];

    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];

   // verify
    [self.mockScheduler verify];
    XCTAssertEqual(callsToScheduleMessages,1);
}

- (void)testOneDeletedInAppMessage {
    // setup to add messages
    NSString *message1ID = [NSUUID UUID].UUIDString;
    NSDictionary *message1 = @{@"message": @{
                                            @"name": @"Simple Message",
                                            @"message_id": message1ID,
                                            @"push_id": [NSUUID UUID].UUIDString,
                                            @"display_type": @"banner",
                                            @"display": @{
                                                    @"body" : @{
                                                            @"text" : @"hi there"
                                                            },
                                                    },
                                            },
                                    @"created": @"2017-12-04T19:07:54.564",
                                    @"last_updated": @"2017-12-04T19:07:54.564",
                                    @"triggers": @[
                                            @{
                                                @"type":@"app_init",
                                                @"goal":@1
                                                }
                                            ]
                                    };
    NSString *message2ID = [NSUUID UUID].UUIDString;
    NSDictionary *message2 = @{@"message": @{
                                            @"name": @"Simple Message",
                                            @"message_id": message2ID,
                                            @"push_id": [NSUUID UUID].UUIDString,
                                            @"display_type": @"banner",
                                            @"display": @{
                                                    @"body" : @{
                                                            @"text" : @"hi there"
                                                            },
                                                    },
                                            },
                                    @"created": @"2017-12-04T19:07:54.564",
                                    @"last_updated": @"2017-12-04T19:07:54.564",
                                    @"triggers": @[
                                            @{
                                                @"type":@"app_init",
                                                @"goal":@1
                                                }
                                            ]
                                    };
    NSArray *inAppMessages = @[message1,message2];
    UARemoteDataPayload *inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                                                  timestamp:[NSDate date]
                                                                                       data:@{@"in_app_messages":inAppMessages}
                                                                                   metadata:@{@"cool" : @"story"}];
    __block NSUInteger scheduledMessages = 0;
    __block NSUInteger cancelledMessages = 0;
    __block NSUInteger editedMessages = 0;

    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        NSArray<UAInAppMessageScheduleInfo *> *scheduleInfos = (__bridge NSArray<UAInAppMessageScheduleInfo *> *)arg;

        scheduledMessages += scheduleInfos.count;

        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(NSArray<UASchedule *> *) = (__bridge void (^)(NSArray<UASchedule *> *))arg;
        
        for (UAInAppMessageScheduleInfo *info in scheduleInfos) {
            UASchedule *schedule = [UASchedule scheduleWithIdentifier:info.message.identifier info:info metadata:@{}];
            [self.allSchedules addObject:schedule];
        }
        completionHandler(self.allSchedules);
    }] scheduleMessagesWithScheduleInfo:OCMOCK_ANY metadata:OCMOCK_ANY completionHandler:OCMOCK_ANY];

    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        
        [invocation getArgument:&arg atIndex:2];
        NSString *scheduleID = (__bridge NSString *)arg;
        
        [invocation getArgument:&arg atIndex:3];
        UAInAppMessageScheduleEdits *edits = (__bridge UAInAppMessageScheduleEdits *)arg;
        if ([edits.end isEqualToDate:[NSDate distantPast]]) {
            cancelledMessages += 1;
        } else {
            editedMessages += 1;
        }
        
        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(UASchedule *) = (__bridge void (^)(UASchedule *))arg;
        completionHandler([self getScheduleForScheduleId:scheduleID]);
    }] editScheduleWithID:OCMOCK_ANY edits:OCMOCK_ANY completionHandler:OCMOCK_ANY];

    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];

    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(scheduledMessages, 2);
    XCTAssertEqual(cancelledMessages, 0);
    XCTAssertEqual(editedMessages, 0);

    // setup to delete one message
    scheduledMessages = 0;
    cancelledMessages = 0;
    editedMessages = 0;

    inAppMessages = @[message2];
    inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                             timestamp:[NSDate date]
                                                                  data:@{@"in_app_messages":inAppMessages}
                                                              metadata:@{@"cool" : @"story"}];

    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];

    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(scheduledMessages, 0);
    XCTAssertEqual(cancelledMessages, 1);
    XCTAssertEqual(editedMessages, 0);
}

- (void)testOneChangedInAppMessage {
    // setup to add messages
    NSString *message1ID = [NSUUID UUID].UUIDString;
    NSDictionary *message1 = @{@"message": @{
                                       @"name": @"Simple Message",
                                       @"message_id": message1ID,
                                       @"push_id": [NSUUID UUID].UUIDString,
                                       @"display_type": @"banner",
                                       @"display": @{
                                               @"body" : @{
                                                       @"text" : @"hi there"
                                                       },
                                               },
                                       },
                               @"created": @"2017-12-04T19:07:54.564",
                               @"last_updated": @"2017-12-04T19:07:54.564",
                               @"triggers": @[
                                       @{
                                           @"type":@"app_init",
                                           @"goal":@1
                                           }
                                       ]
                               };
    NSString *message2ID = [NSUUID UUID].UUIDString;
    NSDictionary *message2 = @{@"message": @{
                                       @"name": @"Simple Message",
                                       @"message_id": message2ID,
                                       @"push_id": [NSUUID UUID].UUIDString,
                                       @"display_type": @"banner",
                                       @"display": @{
                                               @"body" : @{
                                                       @"text" : @"hi there"
                                                       },
                                               },
                                       },
                               @"created": @"2017-12-04T19:07:54.564",
                               @"last_updated": @"2017-12-04T19:07:54.564",
                               @"triggers": @[
                                       @{
                                           @"type":@"app_init",
                                           @"goal":@1
                                           }
                                       ]
                               };
    NSArray *inAppMessages = @[message1,message2];
    UARemoteDataPayload *inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                                                  timestamp:[UAUtils parseISO8601DateFromString:@"2017-12-04T19:07:54.564"] // REVISIT - change this everywhere?
                                                                                       data:@{@"in_app_messages":inAppMessages}
                                                                                   metadata:@{@"cool" : @"story"}];

    __block NSUInteger scheduledMessages = 0;
    __block NSUInteger cancelledMessages = 0;
    __block NSUInteger editedMessages = 0;
    __block UASchedule *schedule1;
    __block UASchedule *schedule2;

    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        NSArray<UAInAppMessageScheduleInfo *> *scheduleInfos = (__bridge NSArray<UAInAppMessageScheduleInfo *> *)arg;
        
        scheduledMessages += scheduleInfos.count;
        
        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(NSArray<UASchedule *> *) = (__bridge void (^)(NSArray<UASchedule *> *))arg;
        
        for (UAInAppMessageScheduleInfo *info in scheduleInfos) {
            UASchedule *schedule = [UASchedule scheduleWithIdentifier:info.message.identifier info:info metadata:@{}];
            [self.allSchedules addObject:schedule];
            if ([info.message.identifier isEqualToString:message1ID]) {
                if ([info.message.identifier isEqualToString:message1ID]) {
                    schedule1 = schedule;
                } else if ([info.message.identifier isEqualToString:message2ID]) {
                    schedule2 = schedule;
                }
            }
        }
        completionHandler(self.allSchedules);
    }] scheduleMessagesWithScheduleInfo:OCMOCK_ANY metadata:OCMOCK_ANY completionHandler:OCMOCK_ANY];

    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        
        [invocation getArgument:&arg atIndex:3];
        UAInAppMessageScheduleEdits *edits = (__bridge UAInAppMessageScheduleEdits *)arg;
        if ([edits.end isEqualToDate:[NSDate distantPast]]) {
            cancelledMessages += 1;
        } else if (edits.priority) {
            editedMessages += 1;
        }
        
        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(UASchedule *) = (__bridge void (^)(UASchedule *))arg;
        completionHandler(nil); // REVISIT - return schedule
    }] editScheduleWithID:OCMOCK_ANY edits:OCMOCK_ANY completionHandler:OCMOCK_ANY];
    
    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];
    
    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(scheduledMessages, 2);
    XCTAssertEqual(cancelledMessages, 0);
    XCTAssertEqual(editedMessages, 0);
    
    // setup to change one message
    scheduledMessages = 0;
    cancelledMessages = 0;
    editedMessages = 0;
    
    NSMutableDictionary *changedMessage2 = [NSMutableDictionary dictionaryWithDictionary:message2];
    changedMessage2[@"priority"] = @1;
    NSDateFormatter *formatter = [UAUtils ISODateFormatterUTCWithDelimiter];
    NSString *now = [formatter stringFromDate:[NSDate date]];
    changedMessage2[@"last_updated"] = now;
    
    inAppMessages = @[message1, changedMessage2];
    inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                             timestamp:[NSDate date]
                                                                  data:@{@"in_app_messages":inAppMessages}
                                                              metadata:@{@"cool" : @"story"}];
    
    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];
    
    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(scheduledMessages, 0);
    XCTAssertEqual(cancelledMessages, 0);
    XCTAssertEqual(editedMessages, 1);
}

- (void)testEmptyInAppMessageListAfterNonEmptyList {
    // setup to add messages
    NSString *message1ID = [NSUUID UUID].UUIDString;
    NSDictionary *message1 = @{@"message": @{
                                       @"name": @"Simple Message",
                                       @"message_id": message1ID,
                                       @"push_id": [NSUUID UUID].UUIDString,
                                       @"display_type": @"banner",
                                       @"display": @{
                                               @"body" : @{
                                                       @"text" : @"hi there"
                                                       },
                                               },
                                       },
                               @"created": @"2017-12-04T19:07:54.564",
                               @"last_updated": @"2017-12-04T19:07:54.564",
                               @"triggers": @[
                                       @{
                                           @"type":@"app_init",
                                           @"goal":@1
                                           }
                                       ]
                               };
    NSString *message2ID = [NSUUID UUID].UUIDString;
    NSDictionary *message2 = @{@"message": @{
                                       @"name": @"Simple Message",
                                       @"message_id": message2ID,
                                       @"push_id": [NSUUID UUID].UUIDString,
                                       @"display_type": @"banner",
                                       @"display": @{
                                               @"body" : @{
                                                       @"text" : @"hi there"
                                                       },
                                               },
                                       },
                               @"created": @"2017-12-04T19:07:55.564",
                               @"last_updated": @"2017-12-04T19:07:55.564",
                               @"triggers": @[
                                       @{
                                           @"type":@"app_init",
                                           @"goal":@1
                                           }
                                       ]
                               };
    NSArray *inAppMessages = @[message1,message2];
    UARemoteDataPayload *inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                                                  timestamp:[NSDate date]
                                                                                       data:@{@"in_app_messages":inAppMessages}
                                                                                   metadata:@{@"cool" : @"story"}];
    
    __block NSUInteger scheduledMessages = 0;
    __block NSUInteger cancelledMessages = 0;

    // expectations
    [[[self.mockScheduler expect] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        NSArray<UAInAppMessageScheduleInfo *> *scheduleInfos = (__bridge NSArray<UAInAppMessageScheduleInfo *> *)arg;

        scheduledMessages += scheduleInfos.count;

        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(NSArray<UASchedule *> *) = (__bridge void (^)(NSArray<UASchedule *> *))arg;

        for (UAInAppMessageScheduleInfo *info in scheduleInfos) {
            [self.allSchedules addObject:[UASchedule scheduleWithIdentifier:info.message.identifier info:info metadata:@{}]];
        }
        completionHandler(self.allSchedules);
    }] scheduleMessagesWithScheduleInfo:OCMOCK_ANY metadata:OCMOCK_ANY completionHandler:OCMOCK_ANY];

    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        cancelledMessages += 1;
        void *arg;
        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(UASchedule *) = (__bridge void (^)(UASchedule *))arg;
        completionHandler(nil);
    }] editScheduleWithID:OCMOCK_ANY edits:OCMOCK_ANY completionHandler:OCMOCK_ANY];
    
    // test
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];

    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(scheduledMessages, 2);
    XCTAssertEqual(cancelledMessages, 0);
    
    // setup empty payload
    UARemoteDataPayload *emptyInAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                                                       timestamp:[NSDate date]
                                                                                            data:@{}
                                                                                        metadata:@{}];
    
    // test
    self.publishBlock(@[emptyInAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];

    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(cancelledMessages, 2);
}

- (void)testNewUserCutoffTime {
    // verify
    NSDate *scheduleNewUserCutoffTime = [self.remoteDataClient.scheduleNewUserCutOffTime copy];
    XCTAssertEqualWithAccuracy([scheduleNewUserCutoffTime timeIntervalSinceNow], 0, 1, @"after first init, schedule new user cut off time should be approximately now");

    // setup
    self.remoteDataClient = nil;
    
    // test
    self.remoteDataClient = [UAInAppRemoteDataClient clientWithScheduler:self.mockScheduler remoteDataManager:self.mockRemoteDataManager dataStore:self.dataStore push:self.mockPush];
    XCTAssertNotNil(self.remoteDataClient);

    // verify
    XCTAssertEqualObjects(self.remoteDataClient.scheduleNewUserCutOffTime, scheduleNewUserCutoffTime, @"after second init, schedule new user cut off time should stay the same.");
}

- (void)testExistingUserCutoffTime {
    // start with empty data store (new app install)
    [self.dataStore removeAll];

    // an existing user already has a channelID
    self.mockPush = [self mockForClass:[UAPush class]];
    [[[self.mockPush expect] andReturn:@"sample-channel-id"] channelID];
    
    // test
    self.remoteDataClient = [UAInAppRemoteDataClient clientWithScheduler:self.mockScheduler remoteDataManager:self.mockRemoteDataManager dataStore:self.dataStore push:self.mockPush];
    XCTAssertNotNil(self.remoteDataClient);

    // verify
    XCTAssertEqualObjects(self.remoteDataClient.scheduleNewUserCutOffTime, [NSDate distantPast], @"existing users should get a cut-off time in the distant past");
}

// This test reproduces a potential out-of-sync issue
- (void)testCacheAndScheduleStoreOutOfSync {
    // start with empty data store (new app install)
    [self.dataStore removeAll];
    
    // Simulate receiving some IAM from remote data to initialize cache and schedule automation store
    NSString *message1ID = [NSUUID UUID].UUIDString;
    NSDictionary *message1 = @{@"message": @{
                                       @"name": @"Simple Message",
                                       @"message_id": message1ID,
                                       @"push_id": [NSUUID UUID].UUIDString,
                                       @"display_type": @"banner",
                                       @"display": @{
                                               @"body" : @{
                                                       @"text" : @"hi there"
                                                       },
                                               },
                                       },
                               @"created": @"2017-12-04T19:07:54.564",
                               @"last_updated": @"2017-12-04T19:07:54.564",
                               @"triggers": @[
                                       @{
                                           @"type":@"app_init",
                                           @"goal":@1
                                           }
                                       ]
                               };
    NSString *message2ID = [NSUUID UUID].UUIDString;
    NSDictionary *message2 = @{@"message": @{
                                       @"name": @"Simple Message",
                                       @"message_id": message2ID,
                                       @"push_id": [NSUUID UUID].UUIDString,
                                       @"display_type": @"banner",
                                       @"display": @{
                                               @"body" : @{
                                                       @"text" : @"hi there"
                                                       },
                                               },
                                       },
                               @"created": @"2017-12-04T19:07:55.564",
                               @"last_updated": @"2017-12-04T19:07:55.564",
                               @"triggers": @[
                                       @{
                                           @"type":@"app_init",
                                           @"goal":@1
                                           }
                                       ]
                               };
    NSArray *inAppMessages = @[message1,message2];
    UARemoteDataPayload *inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                                                  timestamp:[NSDate date]
                                                                                       data:@{@"in_app_messages":inAppMessages}
                                                                                   metadata:@{@"cool" : @"story"}];
    
    __block NSUInteger scheduledMessages = 0;
    __block NSUInteger cancelledMessages = 0;
    __block NSUInteger editedMessages = 0;
    
    // expectations
    [[[self.mockScheduler expect] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        NSArray<UAInAppMessageScheduleInfo *> *scheduleInfos = (__bridge NSArray<UAInAppMessageScheduleInfo *> *)arg;
        
        scheduledMessages += scheduleInfos.count;
        
        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(NSArray<UASchedule *> *) = (__bridge void (^)(NSArray<UASchedule *> *))arg;
        
        for (UAInAppMessageScheduleInfo *info in scheduleInfos) {
            UASchedule *schedule = [UASchedule scheduleWithIdentifier:[NSUUID UUID].UUIDString info:info metadata:@{}];
            [self.allSchedules addObject:schedule];
        }
        completionHandler(self.allSchedules);
    }] scheduleMessagesWithScheduleInfo:OCMOCK_ANY metadata:OCMOCK_ANY completionHandler:OCMOCK_ANY];
    
    [[[self.mockScheduler stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        
        [invocation getArgument:&arg atIndex:2];
        NSString *scheduleID = (__bridge NSString *)arg;
        
        [invocation getArgument:&arg atIndex:3];
        UAInAppMessageScheduleEdits *edits = (__bridge UAInAppMessageScheduleEdits *)arg;
        if ([edits.end isEqualToDate:[NSDate distantPast]]) {
            cancelledMessages += 1;
        } else {
            editedMessages += 1;
        }
        
        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(UASchedule *) = (__bridge void (^)(UASchedule *))arg;
        for (UASchedule *schedule in self.allSchedules) {
            if ([scheduleID isEqualToString:schedule.identifier]) {
                completionHandler(schedule);
                return;
            }
        }
        XCTFail(@"Unknown scheduleID");
        completionHandler(nil);
    }] editScheduleWithID:OCMOCK_ANY edits:OCMOCK_ANY completionHandler:OCMOCK_ANY];

    // test - receive in-app messages
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];
    
    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(scheduledMessages, 2);
    XCTAssertEqual(cancelledMessages, 0);
    XCTAssertEqual(editedMessages, 0);

    // Make cache and schedule automation store out of sync by setting up a cache with only one of the IAM
    XCTAssertNil([self.dataStore dictionaryForKey:UAInAppMessagesScheduledMessagesKey]);
    
    NSMutableDictionary *simulatedScheduleIDMap = [NSMutableDictionary dictionary];
    simulatedScheduleIDMap[message2ID] = [self getScheduleForMessageId:message2ID].identifier;
    
    [self.dataStore setObject:simulatedScheduleIDMap forKey:UAInAppMessagesScheduledMessagesKey];
    
    // Simulate customer cancellation of that IAM
    inAppMessages = @[message2];
    inAppRemoteDataPayload = [[UARemoteDataPayload alloc] initWithType:@"in_app_messages"
                                                             timestamp:[NSDate date]
                                                                  data:@{@"in_app_messages":inAppMessages}
                                                              metadata:@{@"cool" : @"story"}];
    
    scheduledMessages = 0;
    cancelledMessages = 0;
    editedMessages = 0;
    
    // test - customer cancels message 1
    self.publishBlock(@[inAppRemoteDataPayload]);
    [self.remoteDataClient.operationQueue waitUntilAllOperationsAreFinished];
    
    // verify
    [self.mockScheduler verify];
    XCTAssertEqual(scheduledMessages, 0);
    XCTAssertEqual(cancelledMessages, 1);
    XCTAssertEqual(editedMessages, 0);
    
    // cache should have been removed, as it is no longer used
    XCTAssertNil([self.dataStore dictionaryForKey:UAInAppMessagesScheduledMessagesKey]);
}

- (UASchedule *)getScheduleForScheduleId:(NSString *)scheduleId {
    for (UASchedule *schedule in self.allSchedules) {
        if ([scheduleId isEqualToString:schedule.identifier]) {
            return schedule;
        }
    }
    return nil;
}

- (UASchedule *)getScheduleForMessageId:(NSString *)messageId {
    for (UASchedule *schedule in self.allSchedules) {
        UAInAppMessage *message = ((UAInAppMessageScheduleInfo *)schedule.info).message;
        if ([messageId isEqualToString:message.identifier]) {
            return schedule;
        }
    }
    return nil;
}

@end
