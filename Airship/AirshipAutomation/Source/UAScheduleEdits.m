/* Copyright Airship and Contributors */

#import "UAScheduleEdits+Internal.h"
#import "UAAirshipAutomationCoreImport.h"
#import "UAInAppMessage.h"
#import "UAScheduleAudience.h"
#import "UASchedule.h"

@implementation UAScheduleEditsBuilder

@end

@interface UAScheduleEdits ()
@property(nonatomic, strong, nullable) NSNumber *priority;
@property(nonatomic, strong, nullable) NSNumber *limit;
@property(nonatomic, strong, nullable) NSDate *start;
@property(nonatomic, strong, nullable) NSDate *end;
@property(nonatomic, strong, nullable) NSNumber *editGracePeriod;
@property(nonatomic, strong, nullable) NSNumber *interval;
@property(nonatomic, strong, nullable) id data;
@property(nonatomic, strong, nullable) NSNumber *type;
@property(nonatomic, copy, nullable) NSDictionary *metadata;
@property(nonatomic, strong, nullable) UAScheduleAudience *audience;

@end

@implementation UAScheduleEdits


+ (instancetype)editsWithMessage:(UAInAppMessage *)message
                    builderBlock:(void(^)(UAScheduleEditsBuilder *builder))builderBlock {
    UAScheduleEditsBuilder *builder = [[UAScheduleEditsBuilder alloc] init];
    if (builderBlock) {
        builderBlock(builder);
    }

    return [[self alloc] initWithData:message type:@(UAScheduleTypeInAppMessage) builder:builder];
}

+ (instancetype)editsWithActions:(NSDictionary *)actions
                    builderBlock:(void(^)(UAScheduleEditsBuilder *builder))builderBlock {
    UAScheduleEditsBuilder *builder = [[UAScheduleEditsBuilder alloc] init];
    if (builderBlock) {
        builderBlock(builder);
    }

    return [[self alloc] initWithData:actions type:@(UAScheduleTypeActions) builder:builder];
}

+ (instancetype)editsWithBuilderBlock:(void(^)(UAScheduleEditsBuilder *builder))builderBlock {
    UAScheduleEditsBuilder *builder = [[UAScheduleEditsBuilder alloc] init];
    if (builderBlock) {
        builderBlock(builder);
    }

    return [[self alloc] initWithData:nil type:nil builder:builder];
}


- (instancetype)initWithData:(id)data
                        type:(NSNumber *)type
                     builder:(UAScheduleEditsBuilder *)builder {
    self = [super init];
    if (self) {
        self.data = data;
        self.type = type;
        self.priority = builder.priority;
        self.limit = builder.limit;
        self.start = builder.start;
        self.end = builder.end;
        self.editGracePeriod = builder.editGracePeriod;
        self.interval = builder.interval;
        self.metadata = builder.metadata;
        self.audience = builder.audience;
    }

    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Data: %@\n"
            "Type: %@\n"
            "Priority: %@\n"
            "Limit: %@\n"
            "Start: %@\n"
            "End: %@\n"
            "Edit Grace Period: %@\n"
            "Interval: %@\n"
            "Metadata: %@\n"
            "Audience: %@",
            self.data,
            self.type,
            self.priority,
            self.limit,
            self.start,
            self.end,
            self.editGracePeriod,
            self.interval,
            self.metadata,
            self.audience];
}

@end


