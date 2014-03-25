//  SEEFindAndReplaceContext.m
//  SubEthaEdit
//
//  Created by Dominik Wagner on 24.03.14.
//  Copyright (c) 2014 TheCodingMonkeys. All rights reserved.

// this file needs arc - add -fobjc-arc in the compile build phase
#if !__has_feature(objc_arc)
#error ARC must be enabled!
#endif


#import "SEEFindAndReplaceContext.h"
#import "FullTextStorage.h"
#import "FoldableTextStorage.h"

typedef NS_ENUM(uint8_t, SEESearchRangeDirection) {
	kSEESearchRangeDirectionForward,
	kSEESearchRangeDirectionBackward,
};

@interface SEEFindAndReplaceSubRange : NSObject
@property (nonatomic, strong) FullTextStorage *textStorage;
@property (nonatomic) NSRange range;
+ (instancetype)subRangeWithTextStorage:(FullTextStorage *)aFullTextStorage range:(NSRange)aRange;
+ (instancetype)subRangeWithCurrentSelectionOfTextView:(SEETextView *)aTextView;
@property (nonatomic, readonly) BOOL isRangeLocationAtBeginningOfLine;
@property (nonatomic, readonly) BOOL isRangeMaxAtEndOfLine;
@end

@interface SEEFindAndReplaceContext ()

- (void)signalErrorWithDescription:(NSString *)aDescription;

@end

@implementation SEEFindAndReplaceContext

+ (instancetype)contextWithTextView:(NSTextView *)aTextView state:(SEEFindAndReplaceState *)aState {
	SEEFindAndReplaceContext *result = [SEEFindAndReplaceContext new];
	result.targetTextView = (SEETextView *)aTextView;
	result.findAndReplaceState = aState;
	return result;
}

- (PlainTextEditor *)targetPlainTextEditor {
	PlainTextEditor *result = self.targetTextView.editor;
	return result;
}

- (BOOL)textFinderActionWantsToReplaceText {
	NSInteger textFinderActionType = self.currentTextFinderActionType;
	BOOL result = ((textFinderActionType==NSFindPanelActionReplace) ||
				   (textFinderActionType==NSFindPanelActionReplaceAndFind) ||
				   (textFinderActionType==NSFindPanelActionReplaceAll));
	return result;
}

#pragma mark - helpers

- (void)signalErrorWithDescription:(NSString *)aDescription {
	self.localizedErrorDescriptionString = aDescription;
	[[FindReplaceController sharedInstance] signalErrorWithDescription:aDescription];
}

- (NSString *)pasteboardFindString {
	NSString *result = nil;
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSFindPboard];
    if ([[pasteboard types] containsObject:NSStringPboardType]) {
        result = [pasteboard stringForType:NSStringPboardType];
	}
	return result;
}

- (void)saveFindStringToFindPasteboard {
	NSString *currentFindString = self.findAndReplaceState.findString;
	NSString *pasteboardFindString = [self pasteboardFindString];
	if (currentFindString && ![currentFindString isEqualToString:pasteboardFindString]) {
		NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSFindPboard];
		[pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
		[pasteboard setString:currentFindString forType:NSStringPboardType];
	}
}


/*! @return YES if valid, NO if invalid. currentTextFinderActionType must be set. also has side effects: prepares regexes if necessary */

- (BOOL)validityCheckAndPrepare {
	if (self.findAndReplaceState.findString.length == 0) {
		[self signalErrorWithDescription:NSLocalizedString(@"FIND_REPLACE_ERROR_INVALID_FIND_STRING", @"invalid find string, (e.g. zero length find strings)")];
		return NO;
	}
	
	// compile search regex
	SEEFindAndReplaceState *state = self.findAndReplaceState;
	OgreSyntax regexSyntax = state.useRegex ? state.regularExpressionSyntax : OgreSimpleMatchingSyntax;
	if (![OGRegularExpression isValidExpressionString:state.findString
											  options:state.regexOptions
											   syntax:regexSyntax
									  escapeCharacter:state.regularExpressionEscapeCharacter]) {
		NSString *errorString = state.useRegex ? NSLocalizedString(@"Invalid regex",@"InvalidRegex") : NSLocalizedString(@"FIND_REPLACE_ERROR_INVALID_FIND_STRING", @"invalid find string, (e.g. zero length find strings)");
		[self signalErrorWithDescription:errorString];
		return NO;
	}
	
	OGRegularExpression *regex = nil;
	@try{
		regex = [OGRegularExpression regularExpressionWithString:state.findString
														 options:state.regexOptions
														  syntax:regexSyntax
												 escapeCharacter:state.regularExpressionEscapeCharacter];
	} @catch (NSException *exception) {
		NSString *errorString = state.useRegex ? NSLocalizedString(@"Invalid regex",@"InvalidRegex") : NSLocalizedString(@"FIND_REPLACE_ERROR_INVALID_FIND_STRING", @"invalid find string, (e.g. zero length find strings)");
		[self signalErrorWithDescription:errorString];
		NSLog(@"%s exception during regex build:%@",__FUNCTION__,exception);
		return NO;
	}
	self.findExpression = regex;
	
	
	return YES;
}

- (SEEFindAndReplaceSubRange *)nextSubrange:(SEEFindAndReplaceSubRange *)aPreviousSubrange direction:(SEESearchRangeDirection)aDirection {
	
	SEEFindAndReplaceSubRange *result = nil;
	
	// get all the search ranges for the current document
	FullTextStorage *fullTextStorage = aPreviousSubrange.textStorage;
	NSArray *rangesArray = [self.targetTextView searchScopeRanges];
	NSRange nextRange = NSMakeRange(NSNotFound, 0);
	if (aDirection == kSEESearchRangeDirectionForward) {
		NSUInteger location = NSMaxRange(aPreviousSubrange.range);
		for (NSValue *rangeValue in rangesArray) {
			NSRange searchScopeRange = rangeValue.rangeValue;
			if (NSLocationInRange(location, searchScopeRange)) {
				nextRange.location = location;
				nextRange.length = NSMaxRange(searchScopeRange) - location;
				break;
			} else if (searchScopeRange.location >= location) {
				nextRange = searchScopeRange;
				break;
			}
		}
		if (nextRange.location != NSNotFound) {
			result = [SEEFindAndReplaceSubRange subRangeWithTextStorage:fullTextStorage range:nextRange];
		}
	} else if (aDirection == kSEESearchRangeDirectionBackward) {
		NSUInteger location = aPreviousSubrange.range.location;
		for (NSValue *rangeValue in rangesArray.reverseObjectEnumerator) {
			NSRange searchScopeRange = rangeValue.rangeValue;
			if (NSLocationInRange(location, searchScopeRange) &&
				searchScopeRange.location < location) {
				nextRange.location = searchScopeRange.location;
				nextRange.length = location - searchScopeRange.location;
				break;
			} else if (searchScopeRange.location < location) {
				nextRange = searchScopeRange;
				break;
			}
		}
		if (nextRange.location != NSNotFound) {
			result = [SEEFindAndReplaceSubRange subRangeWithTextStorage:fullTextStorage range:nextRange];
		}
		
	}
	return result;
}

#pragma mark -
- (BOOL)performCurrentTextFinderAction {
	BOOL result = NO;
	NSInteger textFinderActionType = self.currentTextFinderActionType;
	if (textFinderActionType == NSTextFinderActionNextMatch) {
		result = [self findNextForward:YES];
	} else if (textFinderActionType == NSTextFinderActionPreviousMatch) {
		result = [self findNextForward:NO];
	}
	/*
if (aTextFinderActionType==NSTextFinderActionNextMatch) {
	if (isFindStringNotZeroLength) {
		[self find:findString forward:YES];
	} else {
		[self signalErrorWithDescription:nil];
	}
} else if (aTextFinderActionType==NSTextFinderActionPreviousMatch) {
	if (isFindStringNotZeroLength) {
		[self find:findString forward:NO];
	} else {
		[self signalErrorWithDescription:nil];
	}
} else if (aTextFinderActionType==NSTextFinderActionReplaceAll) {
	[self replaceAllInTextView:target findAndReplaceState:self.globalFindAndReplaceState ranges:searchScopeRanges];
} else if (aTextFinderActionType==NSTextFinderActionReplace) {
	[self replaceSelection];
} else if (aTextFinderActionType==NSTextFinderActionReplaceAndFind) {
	[self replaceSelection];
	if (isFindStringNotZeroLength) {
		[self find:findString forward:YES ];
	} else {
		[self signalErrorWithDescription:nil];
	}
} else if (aTextFinderActionType==TCMTextFinderActionFindAll) {
	if (!isFindStringNotZeroLength) {
		[self signalErrorWithDescription:nil];
		return;
	}
	if ((![OGRegularExpression isValidExpressionString:findString])&&
		(![self currentOgreSyntax]==OgreSimpleMatchingSyntax)) {
		[self signalErrorWithDescription:NSLocalizedString(@"Invalid regex",@"InvalidRegex")];
		return;
	}
	
	OGRegularExpression *regex = nil;
	@try{
		regex = [OGRegularExpression regularExpressionWithString:[self currentFindString]
														 options:[self currentOgreOptions]
														  syntax:[self currentOgreSyntax]
												 escapeCharacter:[self currentOgreEscapeCharacter]];
	} @catch (NSException *exception) {
		[self signalErrorWithDescription:NSLocalizedString(@"Invalid regex",@"InvalidRegex")];
	}
	if (regex) {
		NSRange scope = [searchScopeRanges.firstObject rangeValue];
		FindAllController *findall = [[FindAllController alloc] initWithRegex:regex andRange:scope];
		[(PlainTextDocument *)[[target editor] document] addFindAllController:findall];
		if ([self currentOgreSyntax]==OgreSimpleMatchingSyntax) [self saveFindStringToPasteboard];
		[findall findAll:self];
	}
}
	 */
	return result;
}

- (BOOL)findNextForward:(BOOL)isForward {
	self.currentTextFinderActionType = (isForward ? NSTextFinderActionNextMatch : NSTextFinderActionPreviousMatch);
	BOOL result = [self validityCheckAndPrepare];
	if (result) {
		if (self.findAndReplaceState.useRegex == NO) {
			[self saveFindStringToFindPasteboard];
		}
		
		SEEFindAndReplaceSubRange *subrange = [SEEFindAndReplaceSubRange subRangeWithCurrentSelectionOfTextView:self.targetTextView];
		SEEFindAndReplaceSubRange *startSubRange = subrange;
		
		SEESearchRangeDirection direction = isForward ? kSEESearchRangeDirectionForward : kSEESearchRangeDirectionBackward;
		NSRange fullFoundRange = {NSNotFound,0};
		
		BOOL isWrapRun = NO;
		BOOL shouldStop = YES;
		if (self.findAndReplaceState.shouldWrap) {
			shouldStop = NO;
		}
		while (YES) {
			while ((subrange = [self nextSubrange:subrange direction:direction])) {
				unsigned searchTimeOptions = subrange.isRangeLocationAtBeginningOfLine ? 0 : OgreNotBOLOption;
				if (!subrange.isRangeMaxAtEndOfLine) {
					searchTimeOptions |= OgreNotEOLOption;
				}
				
				// get all the matches we can find in that range
				NSEnumerator *enumerator = nil;
				@try{
					enumerator=[self.findExpression matchEnumeratorInString:subrange.textStorage.string options:searchTimeOptions range:subrange.range];
				} @catch (NSException *exception) {
					[self signalErrorWithDescription:nil];
					NSLog(@"%s exception while finding:%@",__FUNCTION__,exception);
					return NO;
				}
				
				OGRegularExpressionMatch *match = nil;
				match = [enumerator nextObject];
				if (!isForward) {
					OGRegularExpressionMatch *nextMatch = nil;
					while ((nextMatch = [enumerator nextObject])) {
						match = nextMatch;
					}
				}
				
				if (match) {
					// we found something
					fullFoundRange = [match rangeOfMatchedString];
					[self.targetPlainTextEditor selectRangeInBackground:fullFoundRange];
					return YES;
				}
				
				// break wrapping run if we run over the original start position
				if (isWrapRun) {
					if (isForward) {
						if (NSMaxRange(subrange.range) > NSMaxRange(startSubRange.range)) {
							break; // do not run over again
						}
					} else {
						if (subrange.range.location < startSubRange.range.location) {
							break;
						}
					}
				}
				
			}
			
			// exit or wrap
			if (shouldStop) {
				break;
			} else { // wrap
				FullTextStorage *fullTextStorage = [(FoldableTextStorage *)self.targetTextView.textStorage fullTextStorage];
				NSRange range = isForward ? NSMakeRange(0, 0) : NSMakeRange(fullTextStorage.length, 0);
				subrange = [SEEFindAndReplaceSubRange subRangeWithTextStorage:fullTextStorage range:range];
				isWrapRun = YES;
				shouldStop = YES;
			}
		}
		
		// if we arrive here we failed
		result = NO;
		[self signalErrorWithDescription:NSLocalizedString(@"Not found.",@"Find string not found")];
	}
	
	return result;
}

@end

@implementation SEEFindAndReplaceSubRange
+ (instancetype)subRangeWithTextStorage:(FullTextStorage *)aFullTextStorage range:(NSRange)aRange {
	SEEFindAndReplaceSubRange *result = [SEEFindAndReplaceSubRange new];
	result.textStorage = aFullTextStorage;
	result.range = aRange;
	return result;
}

+ (instancetype)subRangeWithCurrentSelectionOfTextView:(SEETextView *)aTextView {
	NSRange range = aTextView.selectedRange;
	FoldableTextStorage *foldableTextStorage = (FoldableTextStorage *)aTextView.textStorage;
	range = [foldableTextStorage fullRangeForFoldedRange:range];
	SEEFindAndReplaceSubRange *result = [SEEFindAndReplaceSubRange subRangeWithTextStorage:foldableTextStorage.fullTextStorage range:range];
	return result;
}

- (BOOL)isRangeLocationAtBeginningOfLine {
	BOOL result = YES;
	
	NSUInteger location = self.range.location;
	if (location > 0) {
		unichar previousCharacter = [self.textStorage.string characterAtIndex:location - 1];
		switch (previousCharacter) { // check if previous character is a newline character
			case 0x2028:
			case 0x2029:
			case '\n':
			case '\r':
				break;
			default:
				result = NO;
		}
	}
	return result;
}

- (BOOL)isRangeMaxAtEndOfLine {
	BOOL result = YES;
	
	NSUInteger location = NSMaxRange(self.range);
	NSString *string = self.textStorage.string;
	if (string.length > 0 &&
		location < string.length) {
		unichar previousCharacter = [self.textStorage.string characterAtIndex:location];
		switch (previousCharacter) { // check if previous character is a newline character
			case 0x2028:
			case 0x2029:
			case '\n':
			case '\r':
				break;
			default:
				result = NO;
		}
	}
	return result;
}

@end

