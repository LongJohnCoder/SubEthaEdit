//
//  SelectionOperation.m
//  SubEthaEdit
//
//  Created by Martin Ott on Fri Mar 19 2004.
//  Copyright (c) 2004 TheCodingMonkeys. All rights reserved.
//

#import "SelectionOperation.h"
#import "TextOperation.h"

@implementation SelectionOperation

+ (void)initialize {
    [TCMMMOperation registerClass:self forOperationType:@"sel"];
}

+ (SelectionOperation *)selectionOperationWithRange:(NSRange)aRange userID:(NSString *)aUserID {
    SelectionOperation *result = [[SelectionOperation new] autorelease];
    [result setSelectedRange:aRange];
    [result setUserID:aUserID];
    return result;
}

+ (void)transformOperation:(TCMMMOperation *)aClientOperation serverOperation:(TCMMMOperation *)aServerOperation {
    TextOperation *textOperation=nil;
    SelectionOperation *selectionOperation=nil;
    if ([[aClientOperation operationID] isEqualToString:[TextOperation operationID]]) {
        textOperation     =(TextOperation *)aClientOperation;
        selectionOperation=(SelectionOperation *)aServerOperation;
    } else {
        textOperation     =(TextOperation *)aServerOperation;
        selectionOperation=(SelectionOperation *)aClientOperation;
    }
    
    NSRange selectedRange=[selectionOperation selectedRange];
    if (DisjointRanges([textOperation affectedCharRange], selectedRange)) {
        if ([textOperation affectedCharRange].location <= selectedRange.location) {
            selectedRange.location += [[textOperation replacementString] length] - [textOperation affectedCharRange].length;
        }
    } else {
        NSRange intersectionRange = NSIntersectionRange([textOperation affectedCharRange], selectedRange);
        if (intersectionRange.length == [textOperation affectedCharRange].length) {
            selectedRange.length += [[textOperation replacementString] length] - [textOperation affectedCharRange].length;
        } else if (intersectionRange.length == selectedRange.length) {
            selectedRange.location = [textOperation affectedCharRange].location + [[textOperation replacementString] length];
            selectedRange.length = 0;
        } else if (selectedRange.location < [textOperation affectedCharRange].location) {
            selectedRange.length = [textOperation affectedCharRange].location - selectedRange.location;
        } else if (selectedRange.location > [textOperation affectedCharRange].location) {
            selectedRange.location = [textOperation affectedCharRange].location + [[textOperation replacementString] length];
            selectedRange.length -= intersectionRange.length;
        }
    }
    if (!NSEqualRanges(selectedRange,[selectionOperation selectedRange])) {
        [selectionOperation setSelectedRange:selectedRange];
    }
}

+ (NSString *)operationID {
    return @"sel";
}

- (id)initWithDictionaryRepresentation:(NSDictionary *)aDictionary {
    self = [super init];
    if (self) {
        I_selectedRange.location = [[aDictionary objectForKey:@"loc"] unsignedIntValue];
        I_selectedRange.length = [[aDictionary objectForKey:@"len"] unsignedIntValue];
        [self setUserID:[aDictionary objectForKey:@"uid"]];
        //NSLog(@"operation: %@", [self description]);
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    id copy = [super copyWithZone:zone];
    
    [copy setUserID:[self userID]];
    [copy setSelectedRange:[self selectedRange]];
    
    return copy;
}

- (void)dealloc {
    [I_userID release];
    [super dealloc];
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject:[self operationID] forKey:TCMMMOperationTypeKey];
    [dict setObject:[NSNumber numberWithUnsignedInt:I_selectedRange.location] forKey:@"loc"];
    [dict setObject:[NSNumber numberWithUnsignedInt:I_selectedRange.length] forKey:@"len"];
    if ([self userID]) {
        [dict setObject:[self userID] forKey:@"uid"];
    }
    return dict;
}

- (NSRange)selectedRange {
    return I_selectedRange;
}

- (void)setSelectedRange:(NSRange)aRange {
    I_selectedRange = aRange;
}

- (NSString *)userID {
    return I_userID;
}

- (void)setUserID:(NSString *)aUserID {
    [I_userID autorelease];
    I_userID = [aUserID copy];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"selectedRange: %@; byUser: %@", NSStringFromRange([self selectedRange]), [self userID]];
}

@end
