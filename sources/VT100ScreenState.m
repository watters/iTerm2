//
//  VT100ScreenState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/21.
//

#import "VT100ScreenState.h"
#import "VT100ScreenState+Private.h"

#import "DebugLogging.h"
#import "IntervalTree.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermEchoProbe.h"
#import "iTermOrderEnforcer.h"
#import "iTermTextExtractor.h"
#import "LineBuffer.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "VT100RemoteHost.h"
#import "VT100WorkingDirectory.h"

static const int kDefaultMaxScrollbackLines = 1000;

// State restoration dictionary keys
NSString *const kScreenStateKey = @"Screen State";

NSString *const kScreenStateTabStopsKey = @"Tab Stops";
NSString *const kScreenStateTerminalKey = @"Terminal State";
NSString *const kScreenStateLineDrawingModeKey = @"Line Drawing Modes";
NSString *const kScreenStateNonCurrentGridKey = @"Non-current Grid";
NSString *const kScreenStateCurrentGridIsPrimaryKey = @"Showing Primary Grid";
NSString *const kScreenStateIntervalTreeKey = @"Interval Tree";
NSString *const kScreenStateSavedIntervalTreeKey = @"Saved Interval Tree";
NSString *const kScreenStateCommandStartXKey = @"Command Start X";
NSString *const kScreenStateCommandStartYKey = @"Command Start Y";
NSString *const kScreenStateNextCommandOutputStartKey = @"Output Start";
NSString *const kScreenStateCursorVisibleKey = @"Cursor Visible";
NSString *const kScreenStateTrackCursorLineMovementKey = @"Track Cursor Line";
NSString *const kScreenStateLastCommandOutputRangeKey = @"Last Command Output Range";
NSString *const kScreenStateShellIntegrationInstalledKey = @"Shell Integration Installed";
NSString *const kScreenStateLastCommandMarkKey = @"Last Command Mark";
NSString *const kScreenStatePrimaryGridStateKey = @"Primary Grid State";
NSString *const kScreenStateAlternateGridStateKey = @"Alternate Grid State";
NSString *const kScreenStateCursorCoord = @"Cursor Coord";
NSString *const kScreenStateProtectedMode = @"Protected Mode";

@implementation VT100ScreenState

@synthesize audibleBell = _audibleBell;
@synthesize showBellIndicator = _showBellIndicator;
@synthesize flashBell = _flashBell;
@synthesize postUserNotifications = _postUserNotifications;
@synthesize cursorBlinks = _cursorBlinks;
@synthesize collectInputForPrinting = _collectInputForPrinting;
@synthesize printBuffer = _printBuffer;
@synthesize allowTitleReporting = _allowTitleReporting;
@synthesize lastBell = _lastBell;
@synthesize animatedLines = _animatedLines;
@synthesize pasteboardString = _pasteboardString;
@synthesize intervalTree = _intervalTree;
@synthesize primaryGrid = _primaryGrid;
@synthesize altGrid = _altGrid;
@synthesize currentGrid = _currentGrid;
@synthesize realCurrentGrid = _realCurrentGrid;
@synthesize savedIntervalTree = _savedIntervalTree;
@synthesize wraparoundMode = _wraparoundMode;
@synthesize ansi = _ansi;
@synthesize insert = _insert;
@synthesize unlimitedScrollback = _unlimitedScrollback;
@synthesize scrollbackOverflow = _scrollbackOverflow;
@synthesize commandStartCoord = _commandStartCoord;
@synthesize markCache = _markCache;
@synthesize maxScrollbackLines = _maxScrollbackLines;
@synthesize tabStops = _tabStops;
@synthesize charsetUsesLineDrawingMode = _charsetUsesLineDrawingMode;
@synthesize lastCharacter = _lastCharacter;
@synthesize lastCharacterIsDoubleWidth = _lastCharacterIsDoubleWidth;
@synthesize lastExternalAttribute = _lastExternalAttribute;
@synthesize saveToScrollbackInAlternateScreen = _saveToScrollbackInAlternateScreen;
@synthesize cursorVisible = _cursorVisible;
@synthesize shellIntegrationInstalled = _shellIntegrationInstalled;
@synthesize lastCommandOutputRange = _lastCommandOutputRange;
@synthesize currentPromptRange = _currentPromptRange;
@synthesize startOfRunningCommandOutput = _startOfRunningCommandOutput;
@synthesize protectedMode = _protectedMode;
@synthesize initialSize = _initialSize;
@synthesize cumulativeScrollbackOverflow = _cumulativeScrollbackOverflow;
@synthesize linebuffer = _linebuffer;
@synthesize trackCursorLineMovement = _trackCursorLineMovement;
@synthesize appendToScrollbackWithStatusBar = _appendToScrollbackWithStatusBar;
@synthesize normalization = _normalization;
@synthesize intervalTreeObserver = _intervalTreeObserver;
@synthesize lastCommandMark = _lastCommandMark;
@synthesize colorMap = _colorMap;
@synthesize temporaryDoubleBuffer = _temporaryDoubleBuffer;
@synthesize fakePromptDetectedAbsLine = _fakePromptDetectedAbsLine;
@synthesize lastPromptLine = _lastPromptLine;
@synthesize shouldExpectPromptMarks = _shouldExpectPromptMarks;
@synthesize needsRedraw = _needsRedraw;
@synthesize echoProbeIsActive = _echoProbeIsActive;
@synthesize terminalSoftAlternateScreenMode = _terminalSoftAlternateScreenMode;
@synthesize terminalMouseMode = _terminalMouseMode;
@synthesize terminalEncoding = _terminalEncoding;
@synthesize terminalSendReceiveMode = _terminalSendReceiveMode;
@synthesize terminalOutput = _terminalOutput;
@synthesize terminalAllowPasteBracketing = _terminalAllowPasteBracketing;
@synthesize terminalBracketedPasteMode = _terminalBracketedPasteMode;
@synthesize terminalSendModifiers = _terminalSendModifiers;
@synthesize terminalKeyReportingFlags = _terminalKeyReportingFlags;
@synthesize terminalReportFocus = _terminalReportFocus;
@synthesize terminalReportKeyUp = _terminalReportKeyUp;
@synthesize terminalCursorMode = _terminalCursorMode;
@synthesize terminalKeypadMode = _terminalKeypadMode;
@synthesize terminalReceivingFile = _terminalReceivingFile;
@synthesize terminalMetaSendsEscape = _terminalMetaSendsEscape;
@synthesize terminalReverseVideo = _terminalReverseVideo;
@synthesize terminalAlternateScrollMode = _terminalAlternateScrollMode;
@synthesize terminalAutorepeatMode = _terminalAutorepeatMode;
@synthesize terminalCharset = _terminalCharset;
@synthesize terminalPreviousMouseMode = _terminalPreviousMouseMode;
@synthesize terminalForegroundColorCode = _terminalForegroundColorCode;
@synthesize terminalBackgroundColorCode = _terminalBackgroundColorCode;
@synthesize terminalState = _terminalState;
@synthesize config = _config;

- (instancetype)initForMutationOnQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _animatedLines = [NSMutableIndexSet indexSet];
        _intervalTree = [[IntervalTree alloc] init];
        _savedIntervalTree = [[IntervalTree alloc] init];
        _commandStartCoord = VT100GridAbsCoordMake(-1, -1);
        _markCache = [[NSMutableDictionary alloc] init];
        _maxScrollbackLines = kDefaultMaxScrollbackLines;
        _tabStops = [[NSMutableSet alloc] init];
        _charsetUsesLineDrawingMode = [NSMutableSet set];
        _cursorVisible = YES;
        _lastCommandOutputRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        _startOfRunningCommandOutput = VT100GridAbsCoordMake(-1, -1);
        _initialSize = VT100GridSizeMake(-1, -1);
        _linebuffer = [[LineBuffer alloc] init];
        _colorMap = [[iTermColorMap alloc] init];
        _temporaryDoubleBuffer = [[iTermTemporaryDoubleBufferedGridController alloc] initWithQueue:queue];
        _fakePromptDetectedAbsLine = -1;
    }
    return self;
}

#warning TODO: Test this
- (instancetype)initWithState:(VT100ScreenMutableState *)source {
    self = [super init];
    if (self) {
        _queue = dispatch_get_main_queue();
        _audibleBell = source.audibleBell;
        _showBellIndicator = source.showBellIndicator;
        _flashBell = source.flashBell;
        _postUserNotifications = source.postUserNotifications;
        _cursorBlinks = source.cursorBlinks;
        _collectInputForPrinting = source.collectInputForPrinting;
        _printBuffer = [source.printBuffer copy];
        _allowTitleReporting = source.allowTitleReporting;
        _lastBell = source.lastBell;
        _wraparoundMode = source.wraparoundMode;
        _ansi = source.ansi;
        _insert = source.insert;
        _unlimitedScrollback = source.unlimitedScrollback;
        _scrollbackOverflow = source.scrollbackOverflow;
        _commandStartCoord = source.commandStartCoord;
        _maxScrollbackLines = source.maxScrollbackLines;
        _lastCharacter = source.lastCharacter;
        _lastCharacterIsDoubleWidth = source.lastCharacterIsDoubleWidth;
        _lastExternalAttribute = source.lastExternalAttribute;
        _saveToScrollbackInAlternateScreen = source.saveToScrollbackInAlternateScreen;
        _cursorVisible = source.cursorVisible;
        _shellIntegrationInstalled = source.shellIntegrationInstalled;
        _lastCommandOutputRange = source.lastCommandOutputRange;
        _currentPromptRange = source.currentPromptRange;
        _startOfRunningCommandOutput = source.startOfRunningCommandOutput;
        _protectedMode = source.protectedMode;
        _initialSize = source.initialSize;
        _cumulativeScrollbackOverflow = source.cumulativeScrollbackOverflow;
        _trackCursorLineMovement = source.trackCursorLineMovement;
        _appendToScrollbackWithStatusBar = source.appendToScrollbackWithStatusBar;
        _normalization = source.normalization;
        _fakePromptDetectedAbsLine = source.fakePromptDetectedAbsLine;
        _lastPromptLine = source.lastPromptLine;
        _needsRedraw = source.needsRedraw;

        _intervalTreeObserver = source.intervalTreeObserver;
#warning TODO: I need a read-only protocol for VT100ScreenMark.
#warning TODO: Copying marks messes up the registry since one key now can refer to two objects. The command history tool breaks scrolling to the selected command because it picks the wrong one.
        _lastCommandMark = [source.lastCommandMark copy];
        _shouldExpectPromptMarks = source.shouldExpectPromptMarks;

        _linebuffer = [source.linebuffer copy];
        NSMutableDictionary<NSNumber *, id<iTermMark>> *temp = [NSMutableDictionary dictionary];
        [source.markCache enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id<iTermMark>  _Nonnull obj, BOOL * _Nonnull stop) {
            NSDictionary *encoded = [obj dictionaryValue];
            Class theClass = [obj class];
            // TODO: This is going to be really slow. Marks being mutable is going to be a problem.
            // I think that very few kinds of marks are actually mutable, and in those cases a journal
            // might provide a cheap way to update an existing copy.
#warning TODO: Copying marks messes up the registry since one key now can refer to two objects. The command history tool breaks scrolling to the selected command because it picks the wrong one.
            temp[key] = [[theClass alloc] initWithDictionary:encoded];
        }];
        _markCache = temp;
        _echoProbeIsActive = source.echoProbe.isActive;

        _terminalSoftAlternateScreenMode = source.terminalSoftAlternateScreenMode;
        _terminalMouseMode = source.terminalMouseMode;
        _terminalEncoding = source.terminalEncoding;
        _terminalSendReceiveMode = source.terminalSendReceiveMode;
        _terminalOutput = [source.terminalOutput copy];
        _terminalAllowPasteBracketing = source.terminalAllowPasteBracketing;
        _terminalBracketedPasteMode = source.terminalBracketedPasteMode;
        _terminalSendModifiers = source.terminalSendModifiers;
        _terminalKeyReportingFlags = source.terminalKeyReportingFlags;
        _terminalReportFocus = source.terminalReportFocus;
        _terminalReportKeyUp = source.terminalReportKeyUp;
        _terminalCursorMode = source.terminalCursorMode;
        _terminalKeypadMode = source.terminalKeypadMode;
        _terminalReceivingFile = source.terminalReceivingFile;
        _terminalMetaSendsEscape = source.terminalMetaSendsEscape;
        _terminalReverseVideo = source.terminalReverseVideo;
        _terminalAlternateScrollMode = source.terminalAlternateScrollMode;
        _terminalAutorepeatMode = source.terminalAutorepeatMode;
        _terminalCharset = source.terminalCharset;
        _terminalPreviousMouseMode = source.terminalPreviousMouseMode;
        _terminalForegroundColorCode = source.terminalForegroundColorCode;
        _terminalBackgroundColorCode = source.terminalBackgroundColorCode;
        _terminalState = [source.terminalState copy];

        _animatedLines = [source.animatedLines copy];
        _pasteboardString = [source.pasteboardString copy];
#warning TODO: This is a shallow copy, leading to shared mutable state.
        _intervalTree = [source.intervalTree copy];
        _savedIntervalTree = [source.savedIntervalTree copy];
        _tabStops = [source.tabStops copy];
        _charsetUsesLineDrawingMode = [source.charsetUsesLineDrawingMode copy];
        _colorMap = [source.colorMap copy];
        _temporaryDoubleBuffer = [source.unconditionalTemporaryDoubleBuffer copy];
        _config = [source.config copy];
        DLog(@"Copy mutable to immutable");
    }
    return self;
}

- (void)dealloc {
    [_temporaryDoubleBuffer reset];
}

#pragma mark - Grid

- (int)cursorY {
    return self.currentGrid.cursorY + 1;
}

- (int)cursorX {
    return self.currentGrid.cursorX + 1;
}

- (int)width {
    return self.currentGrid.size.width;
}

- (int)height {
    return self.currentGrid.size.height;
}

- (BOOL)cursorOutsideLeftRightMargin {
    return (self.currentGrid.useScrollRegionCols && (self.currentGrid.cursorX < self.currentGrid.leftMargin ||
                                                     self.currentGrid.cursorX > self.currentGrid.rightMargin));
}

- (BOOL)cursorOutsideTopBottomMargin {
    return (self.currentGrid.cursorY < self.currentGrid.topMargin ||
            self.currentGrid.cursorY > self.currentGrid.bottomMargin);
}


- (int)lineNumberOfCursor {
    return self.numberOfLines - self.height + self.currentGrid.cursorY;
}

#pragma mark - Scollback

- (int)numberOfScrollbackLines {
    return [self.linebuffer numLinesWithWidth:self.currentGrid.size.width];
}

#pragma mark - Interval Tree

- (VT100GridCoordRange)coordRangeForInterval:(Interval *)interval {
    VT100GridCoordRange result;
    const int w = self.width + 1;
    result.start.y = interval.location / w - self.cumulativeScrollbackOverflow;
    result.start.x = interval.location % w;
    result.end.y = interval.limit / w - self.cumulativeScrollbackOverflow;
    result.end.x = interval.limit % w;

    if (result.start.y < 0) {
        result.start.y = 0;
        result.start.x = 0;
    }
    if (result.start.x == self.width) {
        result.start.y += 1;
        result.start.x = 0;
    }
    return result;
}

- (VT100GridRange)lineNumberRangeOfInterval:(Interval *)interval {
    VT100GridCoordRange range = [self coordRangeForInterval:interval];
    return VT100GridRangeMake(range.start.y, range.end.y - range.start.y + 1);
}

- (Interval *)intervalForGridCoordRange:(VT100GridCoordRange)range {
    return [self intervalForGridCoordRange:range
                                     width:self.width
                               linesOffset:self.cumulativeScrollbackOverflow];
}

- (Interval *)intervalForGridCoordRange:(VT100GridCoordRange)range
                                  width:(int)width
                            linesOffset:(long long)linesOffset {
    VT100GridCoord start = range.start;
    VT100GridCoord end = range.end;
    long long si = start.y;
    si += linesOffset;
    si *= (width + 1);
    si += start.x;
    long long ei = end.y;
    ei += linesOffset;
    ei *= (width + 1);
    ei += end.x;
    if (ei < si) {
        long long temp = ei;
        ei = si;
        si = temp;
    }
    return [Interval intervalWithLocation:si length:ei - si];
}

- (id)objectOnOrBeforeLine:(int)line ofClass:(Class)cls {
    long long pos = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                            line + 1,
                                                                            0,
                                                                            line + 1)].location;
    if (pos < 0) {
        return nil;
    }
    NSEnumerator *enumerator = [self.intervalTree reverseEnumeratorAt:pos];
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:@[ cls ]];
    } while (objects && !objects.count);
    if (objects.count) {
        // We want the last object because they are sorted chronologically.
        return [objects lastObject];
    } else {
        return nil;
    }
}

- (VT100RemoteHost *)remoteHostOnLine:(int)line {
    return (VT100RemoteHost *)[self objectOnOrBeforeLine:line ofClass:[VT100RemoteHost class]];
}


#pragma mark - Combined Grid And Scrollback

- (int)numberOfLines {
    return [self.linebuffer numLinesWithWidth:self.currentGrid.size.width] + self.currentGrid.size.height;
}

- (iTermImmutableMetadata)metadataOnLine:(int)lineNumber {
    ITBetaAssert(lineNumber >= 0, @"Negative index to getLineAtIndex");
    const int width = self.currentGrid.size.width;
    int numLinesInLineBuffer = [self.linebuffer numLinesWithWidth:width];
    if (lineNumber >= numLinesInLineBuffer) {
        return [self.currentGrid immutableMetadataAtLineNumber:lineNumber - numLinesInLineBuffer];
    } else {
        return [self.linebuffer metadataForLineNumber:lineNumber width:width];
    }
}

- (const screen_char_t *)getLineAtIndex:(int)theIndex {
    return [self getLineAtIndex:theIndex withBuffer:[self.currentGrid resultLine]];
}

- (const screen_char_t *)getLineAtIndex:(int)theIndex withBuffer:(screen_char_t *)buffer {
    ITBetaAssert(theIndex >= 0, @"Negative index to getLineAtIndex");
    int numLinesInLineBuffer = [self.linebuffer numLinesWithWidth:self.currentGrid.size.width];
    if (theIndex >= numLinesInLineBuffer) {
        // Get a line from the circular screen buffer
        return [self.currentGrid screenCharsAtLineNumber:(theIndex - numLinesInLineBuffer)];
    } else {
        // Get a line from the scrollback buffer.
        screen_char_t continuation;
        int cont = [self.linebuffer copyLineToBuffer:buffer
                                               width:self.currentGrid.size.width
                                             lineNum:theIndex
                                        continuation:&continuation];
        if (cont == EOL_SOFT &&
            theIndex == numLinesInLineBuffer - 1 &&
            [self.currentGrid screenCharsAtLineNumber:0][1].code == DWC_RIGHT &&
            buffer[self.currentGrid.size.width - 1].code == 0) {
            // The last line in the scrollback buffer is actually a split DWC
            // if the first char on the screen is double-width and the buffer is soft-wrapped without
            // a last char.
            cont = EOL_DWC;
        }
        if (cont == EOL_DWC) {
            buffer[self.currentGrid.size.width - 1].code = DWC_SKIP;
            buffer[self.currentGrid.size.width - 1].complexChar = NO;
        }
        buffer[self.currentGrid.size.width] = continuation;
        buffer[self.currentGrid.size.width].code = cont;

        return buffer;
    }
}

- (iTermStringLine *)stringLineAsStringAtAbsoluteLineNumber:(long long)absoluteLineNumber
                                                   startPtr:(long long *)startAbsLineNumber {
    long long lineNumber = absoluteLineNumber - self.totalScrollbackOverflow;
    if (lineNumber < 0) {
        return nil;
    }
    if (lineNumber >= self.numberOfLines) {
        return nil;
    }
    // Search backward for start of line
    int i;
    NSMutableData *data = [NSMutableData data];
    *startAbsLineNumber = self.totalScrollbackOverflow;

    // Max radius of lines to search above and below absoluteLineNumber
    const int kMaxRadius = [iTermAdvancedSettingsModel triggerRadius];
    BOOL foundStart = NO;
    for (i = lineNumber - 1; i >= 0 && i >= lineNumber - kMaxRadius; i--) {
        const screen_char_t *line = [self getLineAtIndex:i];
        if (line[self.width].code == EOL_HARD) {
            *startAbsLineNumber = i + self.totalScrollbackOverflow + 1;
            foundStart = YES;
            break;
        }
        [data replaceBytesInRange:NSMakeRange(0, 0)
                        withBytes:line
                           length:self.width * sizeof(screen_char_t)];
    }
    if (!foundStart) {
        *startAbsLineNumber = i + self.totalScrollbackOverflow + 1;
    }
    BOOL done = NO;
    for (i = lineNumber; !done && i < self.numberOfLines && i < lineNumber + kMaxRadius; i++) {
        const screen_char_t *line = [self getLineAtIndex:i];
        int length = self.width;
        done = line[length].code == EOL_HARD;
        if (done) {
            // Remove trailing newlines
            while (length > 0 && line[length - 1].code == 0 && !line[length - 1].complexChar) {
                --length;
            }
        }
        [data appendBytes:line length:length * sizeof(screen_char_t)];
    }

    return [[iTermStringLine alloc] initWithScreenChars:data.mutableBytes
                                                 length:data.length / sizeof(screen_char_t)];
}

- (void)enumerateLinesInRange:(NSRange)range
                        block:(void (^)(int,
                                        ScreenCharArray *,
                                        iTermImmutableMetadata,
                                        BOOL *))block {
    NSInteger i = range.location;
    const NSInteger lastLine = NSMaxRange(range);
    const NSInteger numLinesInLineBuffer = [self.linebuffer numLinesWithWidth:self.currentGrid.size.width];
    const int width = self.width;
    while (i < lastLine) {
        if (i < numLinesInLineBuffer) {
            [self.linebuffer enumerateLinesInRange:NSMakeRange(i, lastLine - i)
                                             width:width
                                             block:block];
            i = numLinesInLineBuffer;
            continue;
        }
        BOOL stop = NO;
        const int screenIndex = i - numLinesInLineBuffer;
        block(i,
              [self screenCharArrayAtScreenIndex:screenIndex],
              [self.currentGrid immutableMetadataAtLineNumber:screenIndex],
              &stop);
        if (stop) {
            return;
        }
        i += 1;
    }
}

- (int)numberOfLinesDroppedWhenEncodingContentsIncludingGrid:(BOOL)includeGrid
                                                     encoder:(id<iTermEncoderAdapter>)encoder
                                              intervalOffset:(long long *)intervalOffsetPtr {
    // We want 10k lines of history at 80 cols, and fewer for small widths, to keep the size
    // reasonable.
    const int maxLines80 = [iTermAdvancedSettingsModel maxHistoryLinesToRestore];
    const int effectiveWidth = self.width ?: 80;
    const int maxArea = maxLines80 * (includeGrid ? 80 : effectiveWidth);
    const int maxLines = MAX(1000, maxArea / effectiveWidth);

    // Make a copy of the last blocks of the line buffer; enough to contain at least |maxLines|.
    LineBuffer *temp = [self.linebuffer copyWithMinimumLines:maxLines
                                                     atWidth:effectiveWidth];

    // Offset for intervals so 0 is the first char in the provided contents.
    int linesDroppedForBrevity = ([self.linebuffer numLinesWithWidth:effectiveWidth] -
                                  [temp numLinesWithWidth:effectiveWidth]);
    long long intervalOffset =
    -(linesDroppedForBrevity + self.cumulativeScrollbackOverflow) * (self.width + 1);

    if (includeGrid) {
        int numLines;
        if ([iTermAdvancedSettingsModel runJobsInServers]) {
            numLines = self.currentGrid.size.height;
        } else {
            numLines = [self.currentGrid numberOfLinesUsed];
        }
        [self.currentGrid appendLines:numLines toLineBuffer:temp];
    }

    [temp encode:encoder maxLines:maxLines80];
    *intervalOffsetPtr = intervalOffset;
    return linesDroppedForBrevity;
}

#pragma mark - Shell Integration

- (VT100ScreenMark *)lastCommandMark {
    DLog(@"Searching for last command mark...");
    if (_lastCommandMark) {
        DLog(@"Return cached mark %@", _lastCommandMark);
        return _lastCommandMark;
    }
    NSEnumerator *enumerator = [self.intervalTree reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    int numChecked = 0;
    while (objects && numChecked < 500) {
        for (id<IntervalTreeObject> obj in objects) {
            if ([obj isKindOfClass:[VT100ScreenMark class]]) {
                VT100ScreenMark *mark = (VT100ScreenMark *)obj;
                if (mark.command) {
                    DLog(@"Found mark %@ in line number range %@", mark,
                         VT100GridRangeDescription([self lineNumberRangeOfInterval:obj.entry.interval]));
                    _lastCommandMark = mark;
                    return mark;
                }
            }
            ++numChecked;
        }
        objects = [enumerator nextObject];
    }

    DLog(@"No last command mark found");
    return nil;
}

- (VT100GridCoordRange)commandRange {
    const long long offset = self.cumulativeScrollbackOverflow;
    if (self.commandStartCoord.x < 0) {
        return VT100GridCoordRangeMake(-1, -1, -1, -1);
    } else {
        return VT100GridCoordRangeMake(self.commandStartCoord.x,
                                       MAX(0, self.commandStartCoord.y - offset),
                                       self.currentGrid.cursorX,
                                       self.currentGrid.cursorY + self.numberOfScrollbackLines);
    }
}

- (BOOL)haveCommandInRange:(VT100GridCoordRange)range {
    if (range.start.x == -1) {
        return NO;
    }

    // If semantic history goes nuts and the end-of-command code isn't received (which seems to be a
    // common problem, probably because of buggy old versions of SH scripts) , the command can grow
    // without bound. We'll limit the length of a command to avoid performance problems.
    const int kMaxLines = 50;
    if (range.end.y - range.start.y > kMaxLines) {
        range.end.y = range.start.y + kMaxLines;
    }
    const int width = self.width;
    range.end.x = MIN(range.end.x, width - 1);
    range.start.x = MIN(range.start.x, width - 1);

    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    return [extractor haveNonWhitespaceInFirstLineOfRange:VT100GridWindowedRangeMake(range, 0, 0)];
}

#warning TODO: Figure out what to do with the mark cache. Also don't use totalScrollbackOverflow from mutable code path
- (VT100ScreenMark *)markOnLine:(int)line {
    return [VT100ScreenMark castFrom:self.markCache[@(self.cumulativeScrollbackOverflow + line)]];
}

- (NSString *)commandInRange:(VT100GridCoordRange)range {
    if (range.start.x == -1) {
        return nil;
    }
    // If semantic history goes nuts and the end-of-command code isn't received (which seems to be a
    // common problem, probably because of buggy old versions of SH scripts) , the command can grow
    // without bound. We'll limit the length of a command to avoid performance problems.
    const int kMaxLines = 50;
    if (range.end.y - range.start.y > kMaxLines) {
        range.end.y = range.start.y + kMaxLines;
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    NSString *command = [extractor contentInRange:VT100GridWindowedRangeMake(range, 0, 0)
                                attributeProvider:nil
                                       nullPolicy:kiTermTextExtractorNullPolicyFromStartToFirst
                                              pad:NO
                               includeLastNewline:NO
                           trimTrailingWhitespace:NO
                                     cappedAtSize:-1
                                     truncateTail:YES
                                continuationChars:nil
                                           coords:nil];
    NSRange newline = [command rangeOfString:@"\n"];
    if (newline.location != NSNotFound) {
        command = [command substringToIndex:newline.location];
    }

    return [command stringByTrimmingLeadingWhitespace];
}

- (id)lastMarkMustBePrompt:(BOOL)wantPrompt class:(Class)theClass {
    NSEnumerator *enumerator = [self.intervalTree reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id obj in objects) {
            if ([obj isKindOfClass:theClass]) {
                if (wantPrompt && [obj isPrompt]) {
                    return obj;
                } else if (!wantPrompt) {
                    return obj;
                }
            }
        }
        objects = [enumerator nextObject];
    }
    return nil;
}

- (NSString *)workingDirectoryOnLine:(int)line {
    VT100WorkingDirectory *workingDirectory =
        [self objectOnOrBeforeLine:line ofClass:[VT100WorkingDirectory class]];
    return workingDirectory.workingDirectory;
}

- (VT100RemoteHost *)lastRemoteHost {
    return [self lastMarkMustBePrompt:NO class:[VT100RemoteHost class]];
}

- (VT100ScreenMark *)lastPromptMark {
    return [self lastMarkMustBePrompt:YES class:[VT100ScreenMark class]];
}

#pragma mark - Colors

- (int)colorMapKeyForTerminalColorIndex:(VT100TerminalColorIndex)n {
    switch (n) {
        case VT100TerminalColorIndexText:
            return kColorMapForeground;
        case VT100TerminalColorIndexBackground:
            return kColorMapBackground;
        case VT100TerminalColorIndexCursor:
            return kColorMapCursor;
        case VT100TerminalColorIndexSelectionBackground:
            return kColorMapSelection;
        case VT100TerminalColorIndexSelectionForeground:
            return kColorMapSelectedText;
        case VT100TerminalColorIndexFirst8BitColorIndex:
        case VT100TerminalColorIndexLast8BitColorIndex:
            break;
    }
    if (n < 0 || n > 255) {
        return -1;
    } else {
        return kColorMap8bitBase + n;
    }
}

#pragma mark - Double Buffer

- (iTermTemporaryDoubleBufferedGridController *)temporaryDoubleBuffer {
    if (!self.config.reduceFlicker && !_temporaryDoubleBuffer.explicit) {
        return nil;
    }
    return _temporaryDoubleBuffer;
}

- (iTermTemporaryDoubleBufferedGridController *)unconditionalTemporaryDoubleBuffer {
    return _temporaryDoubleBuffer;
}

- (void)performBlockWithSavedGrid:(void (^)(id<PTYTextViewSynchronousUpdateStateReading> _Nullable state))block {
    if (!self.realCurrentGrid && self.temporaryDoubleBuffer.savedState) {
        // Swap in saved state.
        self.realCurrentGrid = self.currentGrid;
        self.currentGrid = self.temporaryDoubleBuffer.savedState.grid;

        block(self.temporaryDoubleBuffer.savedState);

        // Restore original state.
        self.currentGrid = self.realCurrentGrid;
        self.realCurrentGrid = nil;
        return;
    }

    // Regular behavior.
    block(nil);
}

#pragma mark - Advanced Prefs

- (BOOL)terminalIsTrusted {
    const BOOL result = ![iTermAdvancedSettingsModel disablePotentiallyInsecureEscapeSequences];
    DLog(@"terminalIsTrusted returning %@", @(result));
    return result;
}

#pragma mark - Development

- (NSString *)compactLineDumpWithHistoryAndContinuationMarksAndLineNumbers {
    NSMutableString *string =
        [NSMutableString stringWithString:[self.linebuffer compactLineDumpWithWidth:self.width andContinuationMarks:YES]];
    NSMutableArray *lines = [[string componentsSeparatedByString:@"\n"] mutableCopy];
    long long absoluteLineNumber = self.totalScrollbackOverflow;
    for (int i = 0; i < lines.count; i++) {
        lines[i] = [NSString stringWithFormat:@"%8lld:        %@", absoluteLineNumber++, lines[i]];
    }

    if ([string length]) {
        [lines addObject:@"- end of history -"];
    }
    NSString *gridDump = [self.currentGrid compactLineDumpWithContinuationMarks];
    NSArray *gridLines = [gridDump componentsSeparatedByString:@"\n"];
    for (int i = 0; i < gridLines.count; i++) {
        [lines addObject:[NSString stringWithFormat:@"%8lld (%04d): %@", absoluteLineNumber++, i, gridLines[i]]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

#pragma mark - iTermTextDataSource

- (ScreenCharArray *)screenCharArrayForLine:(int)line {
    const NSInteger numLinesInLineBuffer = [self.linebuffer numLinesWithWidth:self.currentGrid.size.width];
    if (line < numLinesInLineBuffer) {
        const BOOL eligibleForDWC = (line == numLinesInLineBuffer - 1 &&
                                     [self.currentGrid screenCharsAtLineNumber:0][1].code == DWC_RIGHT);
        return [[self.linebuffer wrappedLineAtIndex:line width:self.width continuation:NULL] paddedToLength:self.width
                                                                                             eligibleForDWC:eligibleForDWC];
    }
    return [self screenCharArrayAtScreenIndex:line - numLinesInLineBuffer];
}

- (ScreenCharArray *)screenCharArrayAtScreenIndex:(int)index {
    const screen_char_t *line = [self.currentGrid screenCharsAtLineNumber:index];
    const int width = self.width;
    ScreenCharArray *array = [[ScreenCharArray alloc] initWithLine:line
                                                            length:width
                                                      continuation:line[width]];
    return array;
}

- (id<iTermExternalAttributeIndexReading>)externalAttributeIndexForLine:(int)y {
    iTermImmutableMetadata metadata = [self metadataOnLine:y];
    return iTermImmutableMetadataGetExternalAttributesIndex(metadata);
}

- (id)fetchLine:(int)line block:(id (^ NS_NOESCAPE)(ScreenCharArray *))block {
    ScreenCharArray *sca = [self screenCharArrayForLine:line];
    return block(sca);
}

- (long long)totalScrollbackOverflow {
    return self.cumulativeScrollbackOverflow;
}

#pragma mark - VT100GridDelgate

// This is here to enable copying of the temporary double buffer.
- (screen_char_t)gridForegroundColorCode {
    return self.terminalForegroundColorCode;
}

- (screen_char_t)gridBackgroundColorCode {
    return self.terminalBackgroundColorCode;
}

- (iTermUnicodeNormalization)gridUnicodeNormalizationForm {
    return self.normalization;
}

- (void)gridCursorDidMove {
}

- (void)gridCursorDidChangeLine {
}

- (void)gridDidResize {
}

@end

