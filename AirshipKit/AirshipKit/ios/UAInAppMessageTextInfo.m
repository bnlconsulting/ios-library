/* Copyright 2017 Urban Airship and Contributors */

#import "UAInAppMessageTextInfo+Internal.h"
#import <UIKit/UIKit.h>
#import "UAGlobal.h"
#import "UAColorUtils+Internal.h"

NS_ASSUME_NONNULL_BEGIN
NSString *const UAInAppMessageTextInfoDomain = @"com.urbanairship.in_app_message_text_info";

// JSON keys and values
NSString *const UAInAppMessageTextInfoTextKey = @"text";
NSString *const UAInAppMessageTextInfoFontFamiliesKey = @"font_family";
NSString *const UAInAppMessageTextInfoColorKey = @"color";
NSString *const UAInAppMessageTextInfoSizeKey = @"size";
NSString *const UAInAppMessageTextInfoAlignmentKey = @"alignment";
NSString *const UAInAppMessageTextInfoStyleKey = @"style";

NSString *const UAInAppMessageTextInfoAlignmentRightValue = @"right";
NSString *const UAInAppMessageTextInfoAlignmentCenterValue = @"center";
NSString *const UAInAppMessageTextInfoAlignmentLeftValue = @"left";

NSString *const UAInAppMessageTextInfoStyleBoldValue = @"bold";
NSString *const UAInAppMessageTextInfoStyleItalicValue = @"italic";
NSString *const UAInAppMessageTextInfoStyleUnderlineValue = @"underline";

@interface UAInAppMessageTextInfo ()
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSArray<NSString *> *fontFamilies;
@property(nonatomic, strong) UIColor *color;
@property(nonatomic, assign) NSUInteger size;
@property(nonatomic, assign) NSTextAlignment alignment;
@property(nonatomic, assign) UAInAppMessageTextInfoStyleType style;
@end

@implementation UAInAppMessageTextInfoBuilder

- (instancetype)init {
    if (self = [super init]) {
        self.color = [UIColor blackColor];
        self.size = 14;
        self.alignment = NSTextAlignmentLeft;
    }
    return self;
}

- (BOOL)isValid {
    if (!self.text) {
        UA_LERR(@"In-app text infos require text");
        return NO;
    }

    return YES;
}

@end

@implementation UAInAppMessageTextInfo

- (instancetype)initWithBuilder:(UAInAppMessageTextInfoBuilder *)builder {
    self = [super self];

    if (![builder isValid]) {
        UA_LERR(@"UAInAppMessageTextInfo could not be initialized, builder has missing or invalid parameters.");
        return nil;
    }

    if (self) {
        self.text = builder.text;
        self.color = builder.color;
        self.size = builder.size;
        self.alignment = builder.alignment;
        self.style = builder.style;
        self.fontFamilies = builder.fontFamilies;
    }

    return self;
}


+ (nullable instancetype)textInfoWithBuilderBlock:(void(^)(UAInAppMessageTextInfoBuilder *builder))builderBlock {
    UAInAppMessageTextInfoBuilder *builder = [[UAInAppMessageTextInfoBuilder alloc] init];

    if (builderBlock) {
        builderBlock(builder);
    }

    return [[UAInAppMessageTextInfo alloc] initWithBuilder:builder];
}

+ (nullable instancetype)textInfoWithJSON:(id)json error:(NSError **)error {
    UAInAppMessageTextInfoBuilder *builder = [[UAInAppMessageTextInfoBuilder alloc] init];
    
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            NSString *msg = [NSString stringWithFormat:@"Attempted to deserialize invalid object: %@", json];
            *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                          code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                      userInfo:@{NSLocalizedDescriptionKey:msg}];
        }
        return nil;
    }
    
    id textInfo = json[UAInAppMessageTextInfoTextKey];
    if (textInfo) {
        if (![textInfo isKindOfClass:[NSString class]]) {
            if (error) {
                NSString *msg = [NSString stringWithFormat:@"In-app message text info text must be a string. Invalid value: %@", textInfo];
                *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                              code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                          userInfo:@{NSLocalizedDescriptionKey:msg}];
            }
            return nil;
        }
        builder.text = textInfo;
    }
    
    id textColor = json[UAInAppMessageTextInfoColorKey];
    if (textColor) {
        if (![textColor isKindOfClass:[NSString class]]) {
            if (error) {
                NSString *msg = [NSString stringWithFormat:@"In-app message text color must be a hex string. Invalid value: %@", textColor];
                *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                              code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                          userInfo:@{NSLocalizedDescriptionKey:msg}];
            }
            return nil;
        }
        builder.color = [UAColorUtils colorWithHexString:textColor];
    }
    
    id textSize = json[UAInAppMessageTextInfoSizeKey];
    if (textSize) {
        if (![textSize isKindOfClass:[NSNumber class]]) {
            if (error) {
                NSString *msg = [NSString stringWithFormat:@"In-app message text size must be a number. Invalid value: %@", textSize];
                *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                              code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                          userInfo:@{NSLocalizedDescriptionKey:msg}];
            }
            return nil;
        }
        builder.size = [textSize unsignedIntegerValue];
    }

    id alignmentContents = json[UAInAppMessageTextInfoAlignmentKey];
    if (alignmentContents) {
        if (![alignmentContents isKindOfClass:[NSString class]]) {
            if (error) {
                NSString *msg = [NSString stringWithFormat:@"Alignment must be a string."];
                *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                              code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                          userInfo:@{NSLocalizedDescriptionKey:msg}];
            }
            return nil;
        }
        
        alignmentContents = [alignmentContents lowercaseString];
        
        if ([UAInAppMessageTextInfoAlignmentLeftValue isEqualToString:alignmentContents]) {
            builder.alignment = NSTextAlignmentLeft;
        } else if ([UAInAppMessageTextInfoAlignmentCenterValue isEqualToString:alignmentContents]) {
            builder.alignment = NSTextAlignmentCenter;
        } else if ([UAInAppMessageTextInfoAlignmentRightValue isEqualToString:alignmentContents]) {
            builder.alignment = NSTextAlignmentRight;
        } else {
            if (error) {
                NSString *msg = [NSString stringWithFormat:@"Invalid in-app message text alignment: %@", alignmentContents];
                *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                              code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                          userInfo:@{NSLocalizedDescriptionKey:msg}];
            }
            return nil;
        }
    }

    id stylesArr = json[UAInAppMessageTextInfoStyleKey];
    if (stylesArr) {
        if (![stylesArr isKindOfClass:[NSArray class]]) {
            if (error) {
                NSString *msg = [NSString stringWithFormat:@"Styles must be an array. Invalid value %@", stylesArr];
                *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                              code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                          userInfo:@{NSLocalizedDescriptionKey:msg}];
            }
            return nil;
        }
        
        for (id styleStr in stylesArr) {
            if (![styleStr isKindOfClass:[NSString class]]) {
                if (error) {
                    NSString *msg = [NSString stringWithFormat:@"style types must be strings. Invalid value %@", styleStr];
                    *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                                  code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                              userInfo:@{NSLocalizedDescriptionKey:msg}];
                }
                return nil;
            }
            
            if ([UAInAppMessageTextInfoStyleBoldValue isEqualToString:styleStr]) {
                builder.style |= UAInAppMessageTextInfoStyleBold;
            } else if ([UAInAppMessageTextInfoStyleItalicValue isEqualToString:styleStr]) {
                builder.style |= UAInAppMessageTextInfoStyleItalic;
            } else if ([UAInAppMessageTextInfoStyleUnderlineValue isEqualToString:styleStr]) {
                builder.style |= UAInAppMessageTextInfoStyleUnderline;
            } else {
                if (error) {
                    NSString *msg = [NSString stringWithFormat:@"Invalid in-app message style: %@", styleStr];
                    *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                                  code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                              userInfo:@{NSLocalizedDescriptionKey:msg}];
                }
                return nil;
            }
        }
    }

    id fontFamilies = json[UAInAppMessageTextInfoFontFamiliesKey];
    if (fontFamilies) {
        if (![fontFamilies isKindOfClass:[NSArray class]]) {
            if (error) {
                NSString *msg = [NSString stringWithFormat:@"Font families must be an array. Invalid value %@", fontFamilies];
                *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                              code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                          userInfo:@{NSLocalizedDescriptionKey:msg}];
            }
            return nil;
        }
        
        for (id fontFamily in fontFamilies) {
            if (![fontFamily isKindOfClass:[NSString class]]) {
                if (error) {
                    NSString *msg = [NSString stringWithFormat:@"A font family must be a string. Invalid value %@", fontFamily];
                    *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                                  code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                              userInfo:@{NSLocalizedDescriptionKey:msg}];
                }
                return nil;
            }
        }
        builder.fontFamilies = fontFamilies;
    }

    if (![builder isValid]) {
        if (error) {
            NSString *msg = [NSString stringWithFormat:@"Invalid text info: %@", json];
            *error =  [NSError errorWithDomain:UAInAppMessageTextInfoDomain
                                          code:UAInAppMessageTextInfoErrorCodeInvalidJSON
                                      userInfo:@{NSLocalizedDescriptionKey:msg}];
        }

        return nil;
    }

    return [[UAInAppMessageTextInfo alloc] initWithBuilder:builder];
}

- (NSDictionary *)toJSON {
    NSMutableDictionary *json = [NSMutableDictionary dictionary];

    [json setValue:self.text forKey:UAInAppMessageTextInfoTextKey];
    [json setValue:[UAColorUtils hexStringWithColor:self.color] forKey:UAInAppMessageTextInfoColorKey];
    [json setValue:@(self.size) forKey:UAInAppMessageTextInfoSizeKey];

    switch (self.alignment) {
        case NSTextAlignmentCenter:
            [json setValue:UAInAppMessageTextInfoAlignmentCenterValue forKey:UAInAppMessageTextInfoAlignmentKey];
            break;
        case NSTextAlignmentRight:
            [json setValue:UAInAppMessageTextInfoAlignmentRightValue forKey:UAInAppMessageTextInfoAlignmentKey];
            break;
        case NSTextAlignmentLeft:
        default:
            [json setValue:UAInAppMessageTextInfoAlignmentLeftValue forKey:UAInAppMessageTextInfoAlignmentKey];
            break;
    }

    NSArray *styles = [UAInAppMessageTextInfo styleJsonArrayFromStyle:self.style];
    if (styles.count) {
        [json setValue:styles forKey:UAInAppMessageTextInfoStyleKey];
    }

    if (self.fontFamilies.count) {
        [json setValue:self.fontFamilies forKey:UAInAppMessageTextInfoFontFamiliesKey];
    }

    return [json copy];
}


#pragma mark - NSObject

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[UAInAppMessageTextInfo class]]) {
        return NO;
    }

    return [self isEqualToInAppMessageTextInfo:(UAInAppMessageTextInfo *)object];
}

- (BOOL)isEqualToInAppMessageTextInfo:(UAInAppMessageTextInfo *)info {
    if (![self.text isEqualToString:info.text]) {
        return NO;
    }

    if (info.color != self.color && ![[UAColorUtils hexStringWithColor:self.color] isEqualToString:[UAColorUtils hexStringWithColor:info.color]]) {
        return NO;
    }

    if (info.size != self.size) {
        return NO;
    }

    if (info.alignment != self.alignment) {
        return NO;
    }

    if (info.style != self.style) {
        return NO;
    }

    if (info.fontFamilies != self.fontFamilies && ![self.fontFamilies isEqualToArray:info.fontFamilies]) {
        return NO;
    }

    return YES;
}

- (NSUInteger)hash {
    NSUInteger result = 1;
    result = 31 * result + [self.text hash];
    result = 31 * result + [self.color hash];
    result = 31 * result + self.size;
    result = 31 * result + self.alignment;
    result = 31 * result + self.style;
    result = 31 * result + [self.fontFamilies hash];

    return result;
}

+(NSArray *)styleJsonArrayFromStyle:(UAInAppMessageTextInfoStyleType)style {
    NSMutableArray *mutableArray = [NSMutableArray array];

    if ((style & UAInAppMessageTextInfoStyleBold) == UAInAppMessageTextInfoStyleBold) {
        [mutableArray addObject:UAInAppMessageTextInfoStyleBoldValue];
    }

    if ((style & UAInAppMessageTextInfoStyleItalic) == UAInAppMessageTextInfoStyleItalic) {
        [mutableArray addObject:UAInAppMessageTextInfoStyleItalicValue];
    }

    if ((style & UAInAppMessageTextInfoStyleUnderline) == UAInAppMessageTextInfoStyleUnderline) {
        [mutableArray addObject:UAInAppMessageTextInfoStyleUnderlineValue];
    }

    return [mutableArray copy];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<UAInAppMessageTextInfo: %@>", [self toJSON]];
}

@end

NS_ASSUME_NONNULL_END
