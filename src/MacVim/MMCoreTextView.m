/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * MMCoreTextView
 *
 * Dispatches keyboard and mouse input to the backend.  Handles drag-n-drop of
 * files onto window.  The rendering is done using CoreText.
 *
 * The text view area consists of two parts:
 *   1. The text area - this is where text is rendered; the size is governed by
 *      the current number of rows and columns.
 *   2. The inset area - this is a border around the text area; the size is
 *      governed by the user defaults MMTextInset[Left|Right|Top|Bottom].
 *
 * The current size of the text view frame does not always match the desired
 * area, i.e. the area determined by the number of rows, columns plus text
 * inset.  This distinction is particularly important when the view is being
 * resized.
 */

#import "Miscellaneous.h"
#import "MMAppController.h"
#import "MMCoreTextView.h"
#import "MMTextViewHelper.h"
#import "MMVimController.h"
#import "MMWindowController.h"


// TODO: What does DRAW_TRANSP flag do?  If the background isn't drawn when
// this flag is set, then sometimes the character after the cursor becomes
// blank.  Everything seems to work fine by just ignoring this flag.
#define DRAW_TRANSP               0x01    /* draw with transparent bg */
#define DRAW_BOLD                 0x02    /* draw bold text */
#define DRAW_UNDERL               0x04    /* draw underline text */
#define DRAW_UNDERC               0x08    /* draw undercurl text */
#define DRAW_ITALIC               0x10    /* draw italic text */
#define DRAW_CURSOR               0x20
#define DRAW_WIDE                 0x80    /* draw wide text */
#define DRAW_COMP                 0x100   /* drawing composing char */

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_8
#define kCTFontOrientationDefault kCTFontDefaultOrientation
#endif // MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_8

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);
#define fontSmoothingStyleLight (2 << 3)

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7
    static void
CTFontDrawGlyphs(CTFontRef fontRef, const CGGlyph glyphs[],
                 const CGPoint positions[], UniCharCount count,
                 CGContextRef context)
{
    CGFontRef cgFontRef = CTFontCopyGraphicsFont(fontRef, NULL);
    CGContextSetFont(context, cgFontRef);
    CGContextShowGlyphsAtPositions(context, glyphs, positions, count);
    CGFontRelease(cgFontRef);
}
#endif // MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7

@interface MMCoreTextView (Private)
- (MMWindowController *)windowController;
- (MMVimController *)vimController;
@end


@interface MMCoreTextView (Drawing)
- (NSPoint)pointForRow:(int)row column:(int)column;
- (NSRect)rectFromRow:(int)row1 column:(int)col1
                toRow:(int)row2 column:(int)col2;
- (NSSize)textAreaSize;
- (NSData *)optimizeBatchDrawData:(NSData *)data;
- (void)batchDrawData:(NSData *)data;
- (void)drawString:(const UniChar *)chars length:(UniCharCount)length
             atRow:(int)row column:(int)col cells:(int)cells
         withFlags:(int)flags foregroundColor:(int)fg
   backgroundColor:(int)bg specialColor:(int)sp;
- (void)deleteLinesFromRow:(int)row lineCount:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
                     color:(int)color;
- (void)insertLinesAtRow:(int)row lineCount:(int)count
            scrollBottom:(int)bottom left:(int)left right:(int)right
                   color:(int)color;
- (void)clearBlockFromRow:(int)row1 column:(int)col1 toRow:(int)row2
                   column:(int)col2 color:(int)color;
- (void)clearAll;
- (void)drawInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                       fraction:(int)percent color:(int)color;
- (void)drawInvertedRectAtRow:(int)row column:(int)col numRows:(int)nrows
                   numColumns:(int)ncols;
@end



    static float
defaultLineHeightForFont(NSFont *font)
{
    // HACK: -[NSFont defaultLineHeightForFont] is deprecated but since the
    // CoreText renderer does not use NSLayoutManager we create one
    // temporarily.
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    float height = [lm defaultLineHeightForFont:font];
    [lm release];

    return height;
}

    static double
defaultAdvanceForFont(NSFont *font)
{
    // NOTE: Previously we used CTFontGetAdvancesForGlyphs() to get the advance
    // for 'm' but this sometimes returned advances that were too small making
    // the font spacing look too tight.
    // Instead use the same method to query the width of 'm' as MMTextStorage
    // uses to make things consistent across renderers.

    NSDictionary *a = [NSDictionary dictionaryWithObject:font
                                                  forKey:NSFontAttributeName];
    return [@"m" sizeWithAttributes:a].width;
}

@implementation MMCoreTextView

- (id)initWithFrame:(NSRect)frame
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    
    cgBufferDrawEnabled = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMBufferedDrawingKey];
    cgBufferDrawNeedsUpdateContext = NO;

    cgLayerEnabled = NO;
    if (!cgBufferDrawEnabled) {
        // Buffered draw supercedes the CGLayer renderer, which is deprecated
        // and doesn't actually work in 10.14+.
        cgLayerEnabled = [[NSUserDefaults standardUserDefaults]
                boolForKey:MMUseCGLayerAlwaysKey];
    }
    cgLayerLock = [NSLock new];

    // NOTE: If the default changes to 'NO' then the intialization of
    // p_antialias in option.c must change as well.
    antialias = YES;

    drawData = [[NSMutableArray alloc] init];
    fontCache = [[NSMutableArray alloc] init];
    [self setFont:[NSFont userFixedPitchFontOfSize:0]];

    helper = [[MMTextViewHelper alloc] init];
    [helper setTextView:self];

    [self registerForDraggedTypes:[NSArray arrayWithObjects:
            NSFilenamesPboardType, NSStringPboardType, nil]];

    ligatures = NO;
    return self;
}

- (void)dealloc
{
    [font release];  font = nil;
    [fontWide release];  fontWide = nil;
    [defaultBackgroundColor release];  defaultBackgroundColor = nil;
    [defaultForegroundColor release];  defaultForegroundColor = nil;
    [drawData release];  drawData = nil;
    [fontCache release];  fontCache = nil;

    CGContextRelease(cgContext);  cgContext = nil;

    [helper setTextView:nil];
    [helper release];  helper = nil;

    if (glyphs) { free(glyphs); glyphs = NULL; }
    if (positions) { free(positions); positions = NULL; }

    [super dealloc];
}

- (int)maxRows
{
    return maxRows;
}

- (int)maxColumns
{
    return maxColumns;
}

- (void)getMaxRows:(int*)rows columns:(int*)cols
{
    if (rows) *rows = maxRows;
    if (cols) *cols = maxColumns;
}

- (void)setMaxRows:(int)rows columns:(int)cols
{
    // NOTE: Just remember the new values, the actual resizing is done lazily.
    maxRows = rows;
    maxColumns = cols;
}

- (void)setDefaultColorsBackground:(NSColor *)bgColor
                        foreground:(NSColor *)fgColor
{
    if (defaultBackgroundColor != bgColor) {
        [defaultBackgroundColor release];
        defaultBackgroundColor = bgColor ? [bgColor retain] : nil;
    }

    // NOTE: The default foreground color isn't actually used for anything, but
    // other class instances might want to be able to access it so it is stored
    // here.
    if (defaultForegroundColor != fgColor) {
        [defaultForegroundColor release];
        defaultForegroundColor = fgColor ? [fgColor retain] : nil;
    }
    [self setNeedsDisplay:YES];
}

- (NSColor *)defaultBackgroundColor
{
    return defaultBackgroundColor;
}

- (NSColor *)defaultForegroundColor
{
    return defaultForegroundColor;
}

- (void)setTextContainerInset:(NSSize)size
{
    insetSize = size;
}

- (NSRect)rectForRowsInRange:(NSRange)range
{
    // Compute rect whose vertical dimensions cover the rows in the given
    // range.
    // NOTE: The rect should be in _flipped_ coordinates and the first row must
    // include the top inset as well.  (This method is only used to place the
    // scrollbars inside MMVimView.)

    NSRect rect = { {0, 0}, {0, 0} };
    unsigned start = range.location > maxRows ? maxRows : range.location;
    unsigned length = range.length;

    if (start + length > maxRows)
        length = maxRows - start;

    if (start > 0) {
        rect.origin.y = cellSize.height * start + insetSize.height;
        rect.size.height = cellSize.height * length;
    } else {
        // Include top inset
        rect.origin.y = 0;
        rect.size.height = cellSize.height * length + insetSize.height;
    }

    return rect;
}

- (NSRect)rectForColumnsInRange:(NSRange)range
{
    // Compute rect whose horizontal dimensions cover the columns in the given
    // range.
    // NOTE: The first column must include the left inset.  (This method is
    // only used to place the scrollbars inside MMVimView.)

    NSRect rect = { {0, 0}, {0, 0} };
    unsigned start = range.location > maxColumns ? maxColumns : range.location;
    unsigned length = range.length;

    if (start+length > maxColumns)
        length = maxColumns - start;

    if (start > 0) {
        rect.origin.x = cellSize.width * start + insetSize.width;
        rect.size.width = cellSize.width * length;
    } else {
        // Include left inset
        rect.origin.x = 0;
        rect.size.width = cellSize.width * length + insetSize.width;
    }

    return rect;
}


- (void)setFont:(NSFont *)newFont
{
    if (!newFont || [font isEqual:newFont])
        return;

    double em = round(defaultAdvanceForFont(newFont));
    double pt = round([newFont pointSize]);

    CTFontDescriptorRef desc = CTFontDescriptorCreateWithNameAndSize((CFStringRef)[newFont fontName], pt);
    CTFontRef fontRef = CTFontCreateWithFontDescriptor(desc, pt, NULL);
    CFRelease(desc);

    [font release];
    font = (NSFont*)fontRef;

    float cellWidthMultiplier = [[NSUserDefaults standardUserDefaults]
            floatForKey:MMCellWidthMultiplierKey];

    // NOTE! Even though NSFontFixedAdvanceAttribute is a float, it will
    // only render at integer sizes.  Hence, we restrict the cell width to
    // an integer here, otherwise the window width and the actual text
    // width will not match.
    cellSize.width = columnspace + ceil(em * cellWidthMultiplier);
    cellSize.height = linespace + defaultLineHeightForFont(font);

    fontDescent = ceil(CTFontGetDescent(fontRef));

    [fontCache removeAllObjects];
}

- (void)setWideFont:(NSFont *)newFont
{
    if (!newFont) {
        // Use the normal font as the wide font (note that the normal font may
        // very well include wide characters.)
        if (font) [self setWideFont:font];
    } else if (newFont != fontWide) {
        // NOTE: No need to set point size etc. since this is taken from the
        // regular font when drawing.
        [fontWide release];

        // Use 'Apple Color Emoji' font for rendering emoji
        CGFloat size = [newFont pointSize] > [font pointSize] ? [font pointSize] : [newFont pointSize];
        NSFontDescriptor *emojiDesc = [NSFontDescriptor
            fontDescriptorWithName:@"Apple Color Emoji" size:size];
        NSFontDescriptor *newFontDesc = [newFont fontDescriptor];
        NSDictionary *attrs = [NSDictionary
            dictionaryWithObject:[NSArray arrayWithObject:newFontDesc]
                          forKey:NSFontCascadeListAttribute];
        NSFontDescriptor *desc =
            [emojiDesc fontDescriptorByAddingAttributes:attrs];
        fontWide = [[NSFont fontWithDescriptor:desc size:size] retain];
    }
}

- (NSFont *)font
{
    return font;
}

- (NSFont *)fontWide
{
    return fontWide;
}

- (NSSize)cellSize
{
    return cellSize;
}

- (void)setLinespace:(float)newLinespace
{
    linespace = newLinespace;

    // NOTE: The linespace is added to the cell height in order for a multiline
    // selection not to have white (background color) gaps between lines.  Also
    // this simplifies the code a lot because there is no need to check the
    // linespace when calculating the size of the text view etc.  When the
    // linespace is non-zero the baseline will be adjusted as well; check
    // MMTypesetter.
    cellSize.height = linespace + defaultLineHeightForFont(font);
}

- (void)setColumnspace:(float)newColumnspace
{
    columnspace = newColumnspace;

    double em = round(defaultAdvanceForFont(font));
    float cellWidthMultiplier = [[NSUserDefaults standardUserDefaults]
            floatForKey:MMCellWidthMultiplierKey];

    cellSize.width = columnspace + ceil(em * cellWidthMultiplier);
}




- (void)deleteSign:(NSString *)signName
{
    [helper deleteImage:signName];
}

- (void)setShouldDrawInsertionPoint:(BOOL)on
{
}

- (void)setPreEditRow:(int)row column:(int)col
{
    [helper setPreEditRow:row column:col];
}

- (void)setMouseShape:(int)shape
{
    [helper setMouseShape:shape];
}

- (void)setAntialias:(BOOL)state
{
    antialias = state;
}

- (void)setLigatures:(BOOL)state
{
    ligatures = state;
}

- (void)setThinStrokes:(BOOL)state
{
    thinStrokes = state;
}

- (void)setImControl:(BOOL)enable
{
    [helper setImControl:enable];
}

- (void)activateIm:(BOOL)enable
{
    [helper activateIm:enable];
}

- (void)checkImState
{
    [helper checkImState];
}

- (BOOL)_wantsKeyDownForEvent:(id)event
{
    // HACK! This is an undocumented method which is called from within
    // -[NSWindow sendEvent] (and perhaps in other places as well) when the
    // user presses e.g. Ctrl-Tab or Ctrl-Esc .  Returning YES here effectively
    // disables the Cocoa "key view loop" (which is undesirable).  It may have
    // other side-effects, but we really _do_ want to process all key down
    // events so it seems safe to always return YES.
    return YES;
}

- (void)setFrameSize:(NSSize)newSize {
    if (!NSEqualSizes(newSize, self.bounds.size)) {
        if (!drawPending && !cgBufferDrawEnabled && drawData.count == 0) {
            // When resizing a window, it will invalidate the buffer and cause
            // MacVim to draw black until we get the draw commands from Vim and
            // we draw them out in drawRect. Use beginGrouping to stop the
            // window resize from happening until we get the draw calls.
            //
            // The updateLayer/cgBufferDrawEnabled path handles this differently
            // and don't need this.
            [NSAnimationContext beginGrouping];
            drawPending = YES;
        }
        if (cgBufferDrawEnabled) {
            cgBufferDrawNeedsUpdateContext = YES;
        }
    }
    
    [super setFrameSize:newSize];
}

- (void)viewDidChangeBackingProperties {
    if (cgBufferDrawEnabled) {
        cgBufferDrawNeedsUpdateContext = YES;
    }
    [super viewDidChangeBackingProperties];
}

- (void)keyDown:(NSEvent *)event
{
    [helper keyDown:event];
}

- (void)insertText:(id)string
{
    [helper insertText:string];
}

- (void)doCommandBySelector:(SEL)selector
{
    [helper doCommandBySelector:selector];
}

- (BOOL)hasMarkedText
{
    return [helper hasMarkedText];
}

- (NSRange)markedRange
{
    return [helper markedRange];
}

- (NSDictionary *)markedTextAttributes
{
    return [helper markedTextAttributes];
}

- (void)setMarkedTextAttributes:(NSDictionary *)attr
{
    [helper setMarkedTextAttributes:attr];
}

- (void)setMarkedText:(id)text selectedRange:(NSRange)range
{
    [helper setMarkedText:text selectedRange:range];
}

- (void)unmarkText
{
    [helper unmarkText];
}

- (void)scrollWheel:(NSEvent *)event
{
    [helper scrollWheel:event];
}

- (void)mouseDown:(NSEvent *)event
{
    [helper mouseDown:event];
}

- (void)rightMouseDown:(NSEvent *)event
{
    [helper mouseDown:event];
}

- (void)otherMouseDown:(NSEvent *)event
{
    [helper mouseDown:event];
}

- (void)mouseUp:(NSEvent *)event
{
    [helper mouseUp:event];
}

- (void)rightMouseUp:(NSEvent *)event
{
    [helper mouseUp:event];
}

- (void)otherMouseUp:(NSEvent *)event
{
    [helper mouseUp:event];
}

- (void)mouseDragged:(NSEvent *)event
{
    [helper mouseDragged:event];
}

- (void)rightMouseDragged:(NSEvent *)event
{
    [helper mouseDragged:event];
}

- (void)otherMouseDragged:(NSEvent *)event
{
    [helper mouseDragged:event];
}

- (void)mouseMoved:(NSEvent *)event
{
    [helper mouseMoved:event];
}

- (void)swipeWithEvent:(NSEvent *)event
{
    [helper swipeWithEvent:event];
}

- (void)pressureChangeWithEvent:(NSEvent *)event
{
    [helper pressureChangeWithEvent:event];
}

- (NSMenu*)menuForEvent:(NSEvent *)event
{
    // HACK! Return nil to disable default popup menus (Vim provides its own).
    // Called when user Ctrl-clicks in the view (this is already handled in
    // rightMouseDown:).
    return nil;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    return [helper performDragOperation:sender];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    return [helper draggingEntered:sender];
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
    return [helper draggingUpdated:sender];
}



- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (BOOL)isOpaque
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)isFlipped
{
    return NO;
}

- (void)updateCGContext {
    if (cgContext) {
        CGContextRelease(cgContext);
        cgContext = nil;
    }

    NSRect backingRect = [self convertRectToBacking:self.bounds];
    cgContext = CGBitmapContextCreate(NULL, NSWidth(backingRect), NSHeight(backingRect), 8, 0, self.window.colorSpace.CGColorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGContextScaleCTM(cgContext, self.window.backingScaleFactor, self.window.backingScaleFactor);
    
    cgBufferDrawNeedsUpdateContext = NO;
}

- (BOOL)wantsUpdateLayer {
    return cgBufferDrawEnabled;
}

- (void)updateLayer {
    if (!cgContext) {
        [self updateCGContext];
    } else if (cgBufferDrawNeedsUpdateContext) {
        if ([drawData count] != 0) {
            [self updateCGContext];
        } else {
            // In this case, we don't have a single draw command, meaning that
            // Vim hasn't caught up yet and hasn't issued draw commands. We
            // don't want to use [NSAnimationContext beginGrouping] as it's
            // fragile (we may miss the endGrouping call due to order of
            // operation), and also it makes the animation jerky.
            // Instead, copy the image to the new context and align it to the
            // top left and make sure it doesn't stretch. This makes the
            // resizing smooth while Vim tries to catch up in issuing draws.
            CGImageRef oldImage = CGBitmapContextCreateImage(cgContext);

            [self updateCGContext]; // This will make a new cgContext
            
            CGContextSaveGState(cgContext);
            CGContextSetBlendMode(cgContext, kCGBlendModeCopy);
            
            // Filling the background so the edge won't be black.
            NSRect newRect = [self bounds];
            float r = [defaultBackgroundColor redComponent];
            float g = [defaultBackgroundColor greenComponent];
            float b = [defaultBackgroundColor blueComponent];
            float a = [defaultBackgroundColor alphaComponent];
            CGContextSetRGBFillColor(cgContext, r, g, b, a);
            CGContextFillRect(cgContext, *(CGRect*)&newRect);
            CGContextSetBlendMode(cgContext, kCGBlendModeNormal);

            // Copy the old image over to the new image, and make sure to
            // respect scaling and remember that CGImage's Y origin is
            // bottom-left.
            CGFloat scale = self.window.backingScaleFactor;
            size_t oldWidth = CGImageGetWidth(oldImage) / scale;
            size_t oldHeight = CGImageGetHeight(oldImage) / scale;
            CGFloat newHeight = newRect.size.height;
            NSRect imageRect = NSMakeRect(0, newHeight - oldHeight, (CGFloat)oldWidth, (CGFloat)oldHeight);

            CGContextDrawImage(cgContext, imageRect, oldImage);
            CGImageRelease(oldImage);
            CGContextRestoreGState(cgContext);
        }
    }
    
    // Now issue the batched draw commands
    if ([drawData count] != 0) {
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:cgContext flipped:self.flipped];
        id data;
        NSEnumerator *e = [drawData objectEnumerator];
        while ((data = [e nextObject]))
            [self batchDrawData:data];
        [drawData removeAllObjects];
        [NSGraphicsContext restoreGraphicsState];
    }

    CGImageRef contentsImage = CGBitmapContextCreateImage(cgContext);
    self.layer.contents = (id)contentsImage;
    CGImageRelease(contentsImage);
}

- (void)drawRect:(NSRect)rect
{
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context setShouldAntialias:antialias];

    if (cgLayerEnabled && drawData.count == 0) {
        // during a live resize, we will have around a stale layer until the
        // refresh messages travel back from the vim process. We push the old
        // layer in at an offset to get rid of jitter due to lines changing
        // position.
        [cgLayerLock lock];
        CGLayerRef l = [self getCGLayer];
        CGSize cgLayerSize = CGLayerGetSize(l);
        CGSize frameSize = [self frame].size;
        NSRect drawRect = NSMakeRect(
                0,
                frameSize.height - cgLayerSize.height,
                cgLayerSize.width,
                cgLayerSize.height);

        CGContextRef cgContext = [context graphicsPort];

        const NSRect *rects;
        long count;
        [self getRectsBeingDrawn:&rects count:&count];

        int i;
        for (i = 0; i < count; i++) {
           CGContextSaveGState(cgContext);
           CGContextClipToRect(cgContext, rects[i]);
           CGContextSetBlendMode(cgContext, kCGBlendModeCopy);
           CGContextDrawLayerInRect(cgContext, drawRect, l);
           CGContextRestoreGState(cgContext);
        }
        [cgLayerLock unlock];
    } else {
       id data;
       NSEnumerator *e = [drawData objectEnumerator];
       while ((data = [e nextObject]))
          [self batchDrawData:data];

       [drawData removeAllObjects];
    }
}

- (void)performBatchDrawWithData:(NSData *)data
{
    if (cgBufferDrawEnabled) {
        // We batch up all the commands and actually perform the draw at
        // updateLayer. The reason is that right now MacVim has a lot of
        // different paths that could change the view size (zoom, user resizing
        // from either dragging border or another program, Cmd-+/- to change
        // font size, fullscreen, etc). Those different paths don't currently
        // have a consistent order of operation of (Vim or MacVim go first), so
        // sometimes Vim gets updated and issue a batch draw first, but
        // sometimes MacVim gets notified first (e.g. when window is resized).
        // If frame size has changed we need to call updateCGContext but we
        // can't do it here because of the order of operation issue. That's why
        // we wait till updateLayer to do it where everything has already been
        // done and settled.
        //
        // Note: Should probably refactor the different ways window size could
        // be changed and unify them instead of the status quo of spaghetti.
        [drawData addObject:data];
        [self setNeedsDisplay:YES];
    } else if (cgLayerEnabled && drawData.count == 0 && [self getCGContext]) {
        [cgLayerLock lock];
        [self batchDrawData:data];
        [cgLayerLock unlock];
    } else {
        [drawData addObject:data];
        [self setNeedsDisplay:YES];
    }
    if (drawPending) {
        [NSAnimationContext endGrouping];
        drawPending = NO;
    }
}

- (void)setCGLayerEnabled:(BOOL)enabled
{
    if (cgContext || cgBufferDrawEnabled)
        return;

    cgLayerEnabled = enabled;

    if (!cgLayerEnabled)
        [self releaseCGLayer];
}

- (BOOL)getCGLayerEnabled
{
    return cgLayerEnabled;
}

- (void)releaseCGLayer
{
    if (cgLayer)  {
        CGLayerRelease(cgLayer);
        cgLayer = nil;
        cgLayerContext = nil;
    }
}

- (CGLayerRef)getCGLayer
{
    NSParameterAssert(cgLayerEnabled);
    if (!cgLayer && [self lockFocusIfCanDraw]) {
        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        NSRect frame = [self frame];
        cgLayer = CGLayerCreateWithContext(
            [context graphicsPort], frame.size, NULL);
        [self unlockFocus];
    }
    return cgLayer;
}

- (CGContextRef)getCGContext
{
    if (cgLayerEnabled) {
        if (!cgLayerContext)
            cgLayerContext = CGLayerGetContext([self getCGLayer]);
        return cgLayerContext;
    } else {
        return [[NSGraphicsContext currentContext] graphicsPort];
    }
}

- (void)setNeedsDisplayCGLayerInRect:(CGRect)rect
{
    if (cgLayerEnabled)
       [self setNeedsDisplayInRect:rect];
}

- (void)setNeedsDisplayCGLayer:(BOOL)flag
{
    if (cgLayerEnabled)
       [self setNeedsDisplay:flag];
}


- (NSSize)constrainRows:(int *)rows columns:(int *)cols toSize:(NSSize)size
{
    // TODO:
    // - Rounding errors may cause size change when there should be none
    // - Desired rows/columns shold not be 'too small'

    // Constrain the desired size to the given size.  Values for the minimum
    // rows and columns are taken from Vim.
    NSSize desiredSize = [self desiredSize];
    int desiredRows = maxRows;
    int desiredCols = maxColumns;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    if (size.height != desiredSize.height) {
        float fh = cellSize.height;
        float ih = insetSize.height + bot;
        if (fh < 1.0f) fh = 1.0f;

        desiredRows = floor((size.height - ih)/fh);
        desiredSize.height = fh*desiredRows + ih;
    }

    if (size.width != desiredSize.width) {
        float fw = cellSize.width;
        float iw = insetSize.width + right;
        if (fw < 1.0f) fw = 1.0f;

        desiredCols = floor((size.width - iw)/fw);
        desiredSize.width = fw*desiredCols + iw;
    }

    if (rows) *rows = desiredRows;
    if (cols) *cols = desiredCols;

    return desiredSize;
}

- (NSSize)desiredSize
{
    // Compute the size the text view should be for the entire text area and
    // inset area to be visible with the present number of rows and columns.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    return NSMakeSize(maxColumns * cellSize.width + insetSize.width + right,
                      maxRows * cellSize.height + insetSize.height + bot);
}

- (NSSize)minSize
{
    // Compute the smallest size the text view is allowed to be.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    return NSMakeSize(MMMinColumns * cellSize.width + insetSize.width + right,
                      MMMinRows * cellSize.height + insetSize.height + bot);
}

- (void)changeFont:(id)sender
{
    NSFont *newFont = [sender convertFont:font];

    if (newFont) {
        NSString *name = [newFont fontName];
        unsigned len = [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (len > 0) {
            NSMutableData *data = [NSMutableData data];
            float pointSize = [newFont pointSize];

            [data appendBytes:&pointSize length:sizeof(float)];

            ++len;  // include NUL byte
            [data appendBytes:&len length:sizeof(unsigned)];
            [data appendBytes:[name UTF8String] length:len];

            [[self vimController] sendMessage:SetFontMsgID data:data];
        }
    }
}


//
// NOTE: The menu items cut/copy/paste/undo/redo/select all/... must be bound
// to the same actions as in IB otherwise they will not work with dialogs.  All
// we do here is forward these actions to the Vim process.
//
- (IBAction)cut:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (IBAction)copy:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (IBAction)paste:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (IBAction)undo:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (IBAction)redo:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (IBAction)selectAll:(id)sender
{
    [[self windowController] vimMenuItemAction:sender];
}

- (BOOL)convertPoint:(NSPoint)point toRow:(int *)row column:(int *)column
{
    point.y = [self bounds].size.height - point.y;

    NSPoint origin = { insetSize.width, insetSize.height };

    if (!(cellSize.width > 0 && cellSize.height > 0))
        return NO;

    if (row) *row = floor((point.y-origin.y-1) / cellSize.height);
    if (column) *column = floor((point.x-origin.x-1) / cellSize.width);

    //ASLogDebug(@"point=%@ row=%d col=%d",
    //      NSStringFromPoint(point), *row, *column);

    return YES;
}

- (NSRect)rectForRow:(int)row column:(int)col numRows:(int)nr
          numColumns:(int)nc
{
    // Return the rect for the block which covers the specified rows and
    // columns.  The lower-left corner is the origin of this rect.
    // NOTE: The coordinate system is _NOT_ flipped!
    NSRect rect;
    NSRect frame = [self bounds];

    rect.origin.x = col*cellSize.width + insetSize.width;
    rect.origin.y = frame.size.height - (row+nr)*cellSize.height -
                    insetSize.height;
    rect.size.width = nc*cellSize.width;
    rect.size.height = nr*cellSize.height;

    return rect;
}

- (NSArray *)validAttributesForMarkedText
{
    return nil;
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range
{
    return nil;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point
{
    return NSNotFound;
}

- (NSInteger)conversationIdentifier
{
    return (NSInteger)self;
}

- (NSRange)selectedRange
{
    return [helper imRange];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range
{
    return [helper firstRectForCharacterRange:range];
}

@end // MMCoreTextView




@implementation MMCoreTextView (Private)

- (MMWindowController *)windowController
{
    id windowController = [[self window] windowController];
    if ([windowController isKindOfClass:[MMWindowController class]])
        return (MMWindowController*)windowController;
    return nil;
}

- (MMVimController *)vimController
{
    return [[self windowController] vimController];
}

@end // MMCoreTextView (Private)




@implementation MMCoreTextView (Drawing)

- (NSPoint)pointForRow:(int)row column:(int)col
{
    NSRect frame = [self bounds];
    return NSMakePoint(
            col*cellSize.width + insetSize.width,
            frame.size.height - (row+1)*cellSize.height - insetSize.height);
}

- (NSRect)rectFromRow:(int)row1 column:(int)col1
                toRow:(int)row2 column:(int)col2
{
    NSRect frame = [self bounds];
    return NSMakeRect(
            insetSize.width + col1*cellSize.width,
            frame.size.height - insetSize.height - (row2+1)*cellSize.height,
            (col2 + 1 - col1) * cellSize.width,
            (row2 + 1 - row1) * cellSize.height);
}

- (NSSize)textAreaSize
{
    // Calculate the (desired) size of the text area, i.e. the text view area
    // minus the inset area.
    return NSMakeSize(maxColumns * cellSize.width, maxRows * cellSize.height);
}

#define MM_DEBUG_DRAWING 0

// TODO: move this to a utility class to be shared
// Reader / writer utilities to interact with the batch draw data stream.
struct DrawCmdClearAll
{
};

struct DrawCmdClearBlock
{
    unsigned color;
    int row1;
    int col1;
    int row2;
    int col2;
};

struct DrawCmdDeleteLines
{
    unsigned color;
    int row;
    int count;
    int bot;
    int left;
    int right;
};

struct DrawCmdDrawSign
{
    int strSize;
    const char *imgName;
    int col;
    int row;
    int width;
    int height;
};

struct DrawCmdDrawString
{
    int bg;
    int fg;
    int sp;
    int row;
    int col;
    int cells;
    int flags;
    int len;
    UInt8 *str;
};

struct DrawCmdInsertLines
{
    unsigned color;
    int row;
    int count;
    int bot;
    int left;
    int right;
};

struct DrawCmdDrawCursor
{
    unsigned color;
    int row;
    int col;
    int shape;
    int percent;
};

struct DrawCmdDrawInvertedRect
{
    int row;
    int col;
    int nr;
    int nc;
    int invert;
};

struct DrawCmdSetCursorPos
{
    int row;
    int col;
};

struct DrawCmd
{
    union
    {
        struct DrawCmdClearAll drawCmdClearAll;
        struct DrawCmdClearBlock drawCmdClearBlock;
        struct DrawCmdDeleteLines drawCmdDeleteLines;
        struct DrawCmdDrawSign drawCmdDrawSign;
        struct DrawCmdDrawString drawCmdDrawString;
        struct DrawCmdInsertLines drawCmdInsertLines;
        struct DrawCmdDrawCursor drawCmdDrawCursor;
        struct DrawCmdDrawInvertedRect drawCmdDrawInvertedRect;
        struct DrawCmdSetCursorPos drawCmdSetCursorPos;
    };

    int type;
};

// Read a single draw command from the batch draw data stream, and returns the
// draw type (the type is also stored in drawCmd->type).
static int ReadDrawCmd(const void **bytesRef, struct DrawCmd *drawCmd)
{
    const void *bytes = *bytesRef;
    
    int type = *((int*)bytes);  bytes += sizeof(int);
    
    switch (type) {
        case ClearAllDrawType:
            break;
        case ClearBlockDrawType:
        {
            struct DrawCmdClearBlock *cmd = &drawCmd->drawCmdClearBlock;
            cmd->color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            cmd->row1 = *((int*)bytes);  bytes += sizeof(int);
            cmd->col1 = *((int*)bytes);  bytes += sizeof(int);
            cmd->row2 = *((int*)bytes);  bytes += sizeof(int);
            cmd->col2 = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case DeleteLinesDrawType:
        {
            struct DrawCmdDeleteLines *cmd = &drawCmd->drawCmdDeleteLines;
            cmd->color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->count = *((int*)bytes);  bytes += sizeof(int);
            cmd->bot = *((int*)bytes);  bytes += sizeof(int);
            cmd->left = *((int*)bytes);  bytes += sizeof(int);
            cmd->right = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case DrawSignDrawType:
        {
            struct DrawCmdDrawSign *cmd = &drawCmd->drawCmdDrawSign;
            cmd->strSize = *((int*)bytes);  bytes += sizeof(int);
            cmd->imgName = (const char*)bytes; bytes += cmd->strSize;
            cmd->col = *((int*)bytes);  bytes += sizeof(int);
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->width = *((int*)bytes);  bytes += sizeof(int);
            cmd->height = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case DrawStringDrawType:
        {
            struct DrawCmdDrawString *cmd = &drawCmd->drawCmdDrawString;
            cmd->bg = *((int*)bytes);  bytes += sizeof(int);
            cmd->fg = *((int*)bytes);  bytes += sizeof(int);
            cmd->sp = *((int*)bytes);  bytes += sizeof(int);
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->col = *((int*)bytes);  bytes += sizeof(int);
            cmd->cells = *((int*)bytes);  bytes += sizeof(int);
            cmd->flags = *((int*)bytes);  bytes += sizeof(int);
            cmd->len = *((int*)bytes);  bytes += sizeof(int);
            cmd->str = (UInt8 *)bytes;  bytes += cmd->len;
        }
            break;
        case InsertLinesDrawType:
        {
            struct DrawCmdInsertLines *cmd = &drawCmd->drawCmdInsertLines;
            cmd->color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->count = *((int*)bytes);  bytes += sizeof(int);
            cmd->bot = *((int*)bytes);  bytes += sizeof(int);
            cmd->left = *((int*)bytes);  bytes += sizeof(int);
            cmd->right = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case DrawCursorDrawType:
        {
            struct DrawCmdDrawCursor *cmd = &drawCmd->drawCmdDrawCursor;
            cmd->color = *((unsigned*)bytes);  bytes += sizeof(unsigned);
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->col = *((int*)bytes);  bytes += sizeof(int);
            cmd->shape = *((int*)bytes);  bytes += sizeof(int);
            cmd->percent = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case DrawInvertedRectDrawType:
        {
            struct DrawCmdDrawInvertedRect *cmd = &drawCmd->drawCmdDrawInvertedRect;
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->col = *((int*)bytes);  bytes += sizeof(int);
            cmd->nr = *((int*)bytes);  bytes += sizeof(int);
            cmd->nc = *((int*)bytes);  bytes += sizeof(int);
            cmd->invert = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        case SetCursorPosDrawType:
        {
            struct DrawCmdSetCursorPos *cmd = &drawCmd->drawCmdSetCursorPos;
            cmd->row = *((int*)bytes);  bytes += sizeof(int);
            cmd->col = *((int*)bytes);  bytes += sizeof(int);
        }
            break;
        default:
        {
            ASLogWarn(@"Unknown draw type (type=%d)", type);
            type = InvalidDrawType;
        }
            break;
    }
    
    *bytesRef = bytes;
    drawCmd->type = type;
    return type;
}

// Write a single draw command to the batch draw data stream.
static void WriteDrawCmd(NSMutableData *drawData, const struct DrawCmd *drawCmd)
{
    int type = drawCmd->type;
    
    [drawData appendBytes:&type length:sizeof(int)];
    
    switch (type) {
        case ClearAllDrawType:
            break;
        case ClearBlockDrawType:
        {
            const struct DrawCmdClearBlock *cmd = &drawCmd->drawCmdClearBlock;
            [drawData appendBytes:cmd length:sizeof(struct DrawCmdClearBlock)];
            static_assert(sizeof(struct DrawCmdClearBlock) == sizeof(unsigned) + sizeof(int)*4, "Wrong size");
        }
            break;
        case DeleteLinesDrawType:
        {
            const struct DrawCmdDeleteLines *cmd = &drawCmd->drawCmdDeleteLines;
            [drawData appendBytes:cmd length:sizeof(struct DrawCmdDeleteLines)];
            static_assert(sizeof(struct DrawCmdDeleteLines) == sizeof(unsigned) + sizeof(int)*5, "Wrong size");
        }
            break;
        case DrawSignDrawType:
        {
            // Can't do simple memcpy of whole struct because of cmd->imgName.
            const struct DrawCmdDrawSign *cmd = &drawCmd->drawCmdDrawSign;
            [drawData appendBytes:&cmd->strSize length:sizeof(int)];
            [drawData appendBytes:cmd->imgName length:cmd->strSize];
            [drawData appendBytes:&cmd->col length:sizeof(int)];
            [drawData appendBytes:&cmd->row length:sizeof(int)];
            [drawData appendBytes:&cmd->width length:sizeof(int)];
            [drawData appendBytes:&cmd->height length:sizeof(int)];
        }
            break;
        case DrawStringDrawType:
        {
            // Can't do simple memcpy of whole struct because of cmd->str.
            const struct DrawCmdDrawString *cmd = &drawCmd->drawCmdDrawString;
            [drawData appendBytes:&cmd->bg length:sizeof(int)];
            [drawData appendBytes:&cmd->fg length:sizeof(int)];
            [drawData appendBytes:&cmd->sp length:sizeof(int)];
            [drawData appendBytes:&cmd->row length:sizeof(int)];
            [drawData appendBytes:&cmd->col length:sizeof(int)];
            [drawData appendBytes:&cmd->cells length:sizeof(int)];
            [drawData appendBytes:&cmd->flags length:sizeof(int)];
            [drawData appendBytes:&cmd->len length:sizeof(int)];
            [drawData appendBytes:cmd->str length:cmd->len];
        }
            break;
        case InsertLinesDrawType:
        {
            const struct DrawCmdInsertLines *cmd = &drawCmd->drawCmdInsertLines;
            [drawData appendBytes:cmd length:sizeof(struct DrawCmdInsertLines)];
            static_assert(sizeof(struct DrawCmdInsertLines) == sizeof(unsigned) + sizeof(int)*5, "Wrong size");
        }
            break;
        case DrawCursorDrawType:
        {
            const struct DrawCmdDrawCursor *cmd = &drawCmd->drawCmdDrawCursor;
            [drawData appendBytes:cmd length:sizeof(struct DrawCmdDrawCursor)];
            static_assert(sizeof(struct DrawCmdDrawCursor) == sizeof(unsigned) + sizeof(int)*4, "Wrong size");
        }
            break;
        case DrawInvertedRectDrawType:
        {
            const struct DrawCmdDrawInvertedRect *cmd = &drawCmd->drawCmdDrawInvertedRect;
            [drawData appendBytes:cmd length:sizeof(struct DrawCmdDrawInvertedRect)];
            static_assert(sizeof(struct DrawCmdDrawInvertedRect) == sizeof(int)*5, "Wrong size");
        }
            break;
        case SetCursorPosDrawType:
        {
            const struct DrawCmdSetCursorPos *cmd = &drawCmd->drawCmdSetCursorPos;
            [drawData appendBytes:cmd length:sizeof(struct DrawCmdSetCursorPos)];
            static_assert(sizeof(struct DrawCmdSetCursorPos) == sizeof(int)*2, "Wrong size");
        }
            break;
        default:
        {
            ASLogWarn(@"Unknown draw type (type=%d)", type);
        }
            break;
    }
}

// Utility to optimize batch draw commands.
//
// Right now, there's only a single reason for this to exist, which is to
// reduce multiple deleteLines commands from being issued. This can happen when
// ":version" is called, or ":!" or misc cmds like ":ls". What usually happens
// is that Vim will issue a "delete lines" command that deletes 1 line, draw
// some text, then delete another line and so on. This is bad because
// deleteLinesFromRow: calls scrollRect: which is currently not fast in CGLayer
// (deprecated) or BufferDraw (default under Mojave) mode as they are not
// GPU-accelerated. Multiple scrolls means multiple image blits which will
// severely degrade rendering performance.
//
// This function will combine all these little delete lines calls into a single
// one, and then re-shuffle all the draw string commands later to be draw to
// the right place. This makes rendering performance much better in the above
// mentioned situations.
//
// This may get revisited later. Also, if we move to a GPU-based Metal renderer
// or a glyph-based one (rather than draw command-based) we may have no need
// for this as scrolling/deleting lines would just involve shuffling memory
// around before we do any draws on the glyphs.
- (NSData *)optimizeBatchDrawData:(NSData *)data
{
    const void *bytes = [data bytes];
    const void *end = bytes + [data length];
    
    //
    // 1) Do a single pass to detect whether we need to optimize the batch draw
    //    data stream. If not, we just return the original data back.
    //
    bool shouldOptimize = false;

    int deleteLinesCount = 0;

    unsigned deleteLinesColor = 0;
    int deleteLinesRow = 0;
    int deleteLinesBot = 0;
    int deleteLinesLeft = 0;
    int deleteLinesRight = 0;

    struct DrawCmd cmd;
    
    while (bytes < end) {
        int type = ReadDrawCmd(&bytes, &cmd);
        if (deleteLinesCount != 0) {
            // Right onw in the only known cases where multiple delete lines
            // get issued only draw string commands would get issued so just
            // don't optimize the other cases for now for simplicity.
            if (type != DeleteLinesDrawType
                && type != DrawStringDrawType
                && type != SetCursorPosDrawType) {
                return data;
            }
        }

        if (DeleteLinesDrawType == type) {
            struct DrawCmdDeleteLines *cmdDel = &cmd.drawCmdDeleteLines;
            if (deleteLinesCount == 0) {
                // First time seeing a delete line operation, cache its
                // properties.
                deleteLinesColor = cmdDel->color;
                deleteLinesRow = cmdDel->row;
                deleteLinesBot = cmdDel->bot;
                deleteLinesLeft = cmdDel->left;
                deleteLinesRight = cmdDel->right;
            } else {
                // We only optimize if we see 2+ delete line operations,
                // otherwise this is no point.
                shouldOptimize = true;

                bool similarCmd =
                    deleteLinesColor == cmdDel->color &&
                    deleteLinesRow == cmdDel->row &&
                    deleteLinesBot == cmdDel->bot &&
                    deleteLinesLeft == cmdDel->left &&
                    deleteLinesRight == cmdDel->right;
                if (!similarCmd) {
                    // This shouldn't really happen, but in case we have
                    // situations where the multiple delete line operations are
                    // different it's kind of hard to combine them together, so
                    // just ignore.
                    return data;
                }
            }

            deleteLinesCount += cmdDel->count;
        } else if (DrawStringDrawType == type) {
            // There may be cases where this optimization doesn't work and we
            // need to bail here. E.g. if the string is drawn across the
            // scrolling boundary of the delete line operation moving the
            // command around would not result in the correct rendering, or if
            // the string is in the deleted region later this would cause
            // problems too.
            // For simplicity we don't check for those cases now, as they
            // aren't known to happen.
        }
    }

    if (!shouldOptimize) {
        return data;
    }

    //
    // 2) If we reach here, we want to optimize the data stream. Make a new
    //    data stream with the delete lines commands all shoved into one single
    //    one.
    //
    NSMutableData *newData =  [[[NSMutableData alloc] initWithCapacity:[data length]] autorelease];
    
    struct DrawCmd drawCmdDelLines;
    drawCmdDelLines.type = DeleteLinesDrawType;
    {
        struct DrawCmdDeleteLines *cmdDel = &drawCmdDelLines.drawCmdDeleteLines;
        cmdDel->color = deleteLinesColor;
        cmdDel->row = deleteLinesRow;
        cmdDel->count = deleteLinesCount;
        cmdDel->bot = deleteLinesBot;
        cmdDel->left = deleteLinesLeft;
        cmdDel->right = deleteLinesRight;
    }
    
    bytes = [data bytes];
    end = bytes + [data length];

    bool insertedDelLinesCmd = false;
    int remainingDeleteLinesLeft = deleteLinesCount;
    while (bytes < end) {
        int type = ReadDrawCmd(&bytes, &cmd);

        if (type == DeleteLinesDrawType) {
            if (!insertedDelLinesCmd) {
                // We replace the 1st delete line command by the combined
                // delete line command. This way earlier commands can remain
                // untouched and only later commands need to be touched up.
                WriteDrawCmd(newData, &drawCmdDelLines);
                insertedDelLinesCmd = true;
            }
            remainingDeleteLinesLeft -= cmd.drawCmdDeleteLines.count;
            continue;
        }
        
        if (!insertedDelLinesCmd) {
            WriteDrawCmd(newData, &cmd);
            continue;
        }

        // Shift the draw command up.
        // Before the optimization, we have:
        //  A1. delete N lines
        //  A2. draw string
        //  A3. delete M lines
        // After the optimization:
        //  B1. delete N + M lines
        //  B2. draw string
        //
        // A3 would have shifted the draw string M lines up but it won't now.
        // Therefore, when we draw B2 (which is here), we need to make sure to
        // draw it M lines higher to present the same result.
        if (type == DrawStringDrawType) {
            struct DrawCmdDrawString *drawCmd = &cmd.drawCmdDrawString;
            if (drawCmd->row > deleteLinesRow) {
                drawCmd->row -= remainingDeleteLinesLeft;
            }
        } else if (type == SetCursorPosDrawType) {
            struct DrawCmdSetCursorPos *drawCmd = &cmd.drawCmdSetCursorPos;
            if (drawCmd->row > deleteLinesRow) {
                drawCmd->row -= remainingDeleteLinesLeft;
            }
        }
        WriteDrawCmd(newData, &cmd);
    }
    
    return newData;
}

- (void)batchDrawData:(NSData *)data
{
    // Optimize the batch draw commands before issuing them. This makes the
    // draw commands more efficient but should result in identical final
    // results.
    data = [self optimizeBatchDrawData:data];

    const void *bytes = [data bytes];
    const void *end = bytes + [data length];

#if MM_DEBUG_DRAWING
    ASLogNotice(@"====> BEGIN");
#endif
    // TODO: Sanity check input

    while (bytes < end) {
        struct DrawCmd drawCmd;
        int type = ReadDrawCmd(&bytes, &drawCmd);

        if (ClearAllDrawType == type) {
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Clear all");
#endif
            [self clearAll];
        } else if (ClearBlockDrawType == type) {
            struct DrawCmdClearBlock *cmd = &drawCmd.drawCmdClearBlock;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Clear block (%d,%d) -> (%d,%d)", cmd->row1, cmd->col1,
                    cmd->row2, cmd->col2);
#endif
            [self clearBlockFromRow:cmd->row1 column:cmd->col1
                    toRow:cmd->row2 column:cmd->col2
                    color:cmd->color];
        } else if (DeleteLinesDrawType == type) {
            struct DrawCmdDeleteLines *cmd = &drawCmd.drawCmdDeleteLines;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Delete %d line(s) from %d", cmd->count, cmd->row);
#endif
            [self deleteLinesFromRow:cmd->row lineCount:cmd->count
                    scrollBottom:cmd->bot left:cmd->left right:cmd->right
                           color:cmd->color];
        } else if (DrawSignDrawType == type) {
            struct DrawCmdDrawSign *cmd = &drawCmd.drawCmdDrawSign;
            NSString *imgName =
                [NSString stringWithUTF8String:cmd->imgName];

            NSImage *signImg = [helper signImageForName:imgName];
            NSRect r = [self rectForRow:cmd->row
                                 column:cmd->col
                                numRows:cmd->height
                             numColumns:cmd->width];
            if (cgLayerEnabled) {
                CGContextRef context = [self getCGContext];
                CGImageRef cgImage = [signImg CGImageForProposedRect:&r
                                                             context:nil
                                                               hints:nil];
                CGContextDrawImage(context, r, cgImage);
            } else {
                [signImg drawInRect:r
                           fromRect:NSZeroRect
                          operation:NSCompositingOperationSourceOver
                           fraction:1.0];
            }
            [self setNeedsDisplayCGLayerInRect:r];
        } else if (DrawStringDrawType == type) {
            struct DrawCmdDrawString *cmd = &drawCmd.drawCmdDrawString;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Draw string len=%d row=%d col=%d flags=%#x",
                    cmd->len, cmd->row, cmd->col, cmd->flags);
#endif

            // Convert UTF-8 chars to UTF-16
            CFStringRef sref = CFStringCreateWithBytesNoCopy(NULL, cmd->str, cmd->len,
                                kCFStringEncodingUTF8, false, kCFAllocatorNull);
            if (sref == NULL) {
                ASLogWarn(@"Conversion error: some text may not be rendered");
                continue;
            }
            CFIndex unilength = CFStringGetLength(sref);
            const UniChar *unichars = CFStringGetCharactersPtr(sref);
            UniChar *buffer = NULL;
            if (unichars == NULL) {
                buffer = malloc(unilength * sizeof(UniChar));
                CFStringGetCharacters(sref, CFRangeMake(0, unilength), buffer);
                unichars = buffer;
            }

            [self drawString:unichars length:unilength
                       atRow:cmd->row column:cmd->col cells:cmd->cells
                              withFlags:cmd->flags
                        foregroundColor:cmd->fg
                        backgroundColor:cmd->bg
                           specialColor:cmd->sp];

            if (buffer) {
                free(buffer);
                buffer = NULL;
            }
            CFRelease(sref);
        } else if (InsertLinesDrawType == type) {
            struct DrawCmdInsertLines *cmd = &drawCmd.drawCmdInsertLines;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Insert %d line(s) at row %d", cmd->count, cmd->row);
#endif
            [self insertLinesAtRow:cmd->row lineCount:cmd->count
                             scrollBottom:cmd->bot left:cmd->left right:cmd->right
                                    color:cmd->color];
        } else if (DrawCursorDrawType == type) {
            struct DrawCmdDrawCursor *cmd = &drawCmd.drawCmdDrawCursor;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Draw cursor at (%d,%d)", cmd->row, cmd->col);
#endif
            [self drawInsertionPointAtRow:cmd->row column:cmd->col shape:cmd->shape
                                     fraction:cmd->percent
                                        color:cmd->color];
        } else if (DrawInvertedRectDrawType == type) {
            struct DrawCmdDrawInvertedRect *cmd = &drawCmd.drawCmdDrawInvertedRect;
#if MM_DEBUG_DRAWING
            ASLogNotice(@"   Draw inverted rect: row=%d col=%d nrows=%d "
                   "ncols=%d", cmd->row, cmd->col, cmd->nr, cmd->nc);
#endif
            [self drawInvertedRectAtRow:cmd->row column:cmd->col numRows:cmd->nr
                             numColumns:cmd->nc];
        } else if (SetCursorPosDrawType == type) {
            // TODO: This is used for Voice Over support in MMTextView,
            // MMCoreTextView currently does not support Voice Over.
#if MM_DEBUG_DRAWING
            struct DrawCmdSetCursorPos *cmd = &drawCmd.drawCmdSetCursorPos;
            ASLogNotice(@"   Set cursor row=%d col=%d", cmd->row, cmd->col);
#endif
        } else {
            ASLogWarn(@"Unknown draw type (type=%d)", type);
        }
    }

#if MM_DEBUG_DRAWING
    ASLogNotice(@"<==== END");
#endif
}

    static CTFontRef
lookupFont(NSMutableArray *fontCache, const unichar *chars, UniCharCount count,
           CTFontRef currFontRef)
{
    CGGlyph glyphs[count];

    // See if font in cache can draw at least one character
    NSUInteger i;
    for (i = 0; i < [fontCache count]; ++i) {
        NSFont *font = [fontCache objectAtIndex:i];

        if (CTFontGetGlyphsForCharacters((CTFontRef)font, chars, glyphs, count))
            return (CTFontRef)[font retain];
    }

    // Ask Core Text for a font (can be *very* slow, which is why we cache
    // fonts in the first place)
    CFRange r = { 0, count };
    CFStringRef strRef = CFStringCreateWithCharacters(NULL, chars, count);
    CTFontRef newFontRef = CTFontCreateForString(currFontRef, strRef, r);
    CFRelease(strRef);

    // Verify the font can actually convert all the glyphs.
    if (!CTFontGetGlyphsForCharacters(newFontRef, chars, glyphs, count))
        return nil;

    if (newFontRef)
        [fontCache addObject:(NSFont *)newFontRef];

    return newFontRef;
}

    static CFAttributedStringRef
attributedStringForString(NSString *string, const CTFontRef font,
                          BOOL useLigatures)
{
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                            (id)font, kCTFontAttributeName,
                            // 2 - full ligatures including rare
                            // 1 - basic ligatures
                            // 0 - no ligatures
                            [NSNumber numberWithBool:useLigatures],
                            kCTLigatureAttributeName,
                            nil
    ];

    return CFAttributedStringCreate(NULL, (CFStringRef)string,
                                    (CFDictionaryRef)attrs);
}

    static UniCharCount
fetchGlyphsAndAdvances(const CTLineRef line, CGGlyph *glyphs, CGSize *advances,
                       CGPoint *positions, UniCharCount length)
{
    NSArray *glyphRuns = (NSArray*)CTLineGetGlyphRuns(line);

    // get a hold on the actual character widths and glyphs in line
    UniCharCount offset = 0;
    for (id item in glyphRuns) {
        CTRunRef run  = (CTRunRef)item;
        CFIndex count = CTRunGetGlyphCount(run);

        if (count > 0) {
            if (count > length - offset)
                count = length - offset;

            CFRange range = CFRangeMake(0, count);

            if (glyphs != NULL)
                CTRunGetGlyphs(run, range, &glyphs[offset]);
            if (advances != NULL)
                CTRunGetAdvances(run, range, &advances[offset]);
            if (positions != NULL)
                CTRunGetPositions(run, range, &positions[offset]);

            offset += count;
            if (offset >= length)
                break;
        }
    }

    return offset;
}

    static UniCharCount
gatherGlyphs(CGGlyph glyphs[], UniCharCount count)
{
    // Gather scattered glyphs that was happended by Surrogate pair chars
    UniCharCount glyphCount = 0;
    NSUInteger pos = 0;
    NSUInteger i;
    for (i = 0; i < count; ++i) {
        if (glyphs[i] != 0) {
            ++glyphCount;
            glyphs[pos++] = glyphs[i];
        }
    }
    return glyphCount;
}

    static UniCharCount
composeGlyphsForChars(const unichar *chars, CGGlyph *glyphs,
                      CGPoint *positions, UniCharCount length, CTFontRef font,
                      BOOL isComposing, BOOL useLigatures)
{
    memset(glyphs, 0, sizeof(CGGlyph) * length);

    NSString *plainText = [NSString stringWithCharacters:chars length:length];
    CFAttributedStringRef composedText = attributedStringForString(plainText,
                                                                   font,
                                                                   useLigatures);

    CTLineRef line = CTLineCreateWithAttributedString(composedText);

    // get the (composing)glyphs and advances for the new text
    UniCharCount offset = fetchGlyphsAndAdvances(line, glyphs, NULL,
                                                 isComposing ? positions : NULL,
                                                 length);

    CFRelease(composedText);
    CFRelease(line);

    // as ligatures composing characters it is required to adjust the
    // original length value
    return offset;
}

    static void
recurseDraw(const unichar *chars, CGGlyph *glyphs, CGPoint *positions,
            UniCharCount length, CGContextRef context, CTFontRef fontRef,
            NSMutableArray *fontCache, BOOL isComposing, BOOL useLigatures)
{
    if (CTFontGetGlyphsForCharacters(fontRef, chars, glyphs, length)) {
        // All chars were mapped to glyphs, so draw all at once and return.
        length = isComposing || useLigatures
                ? composeGlyphsForChars(chars, glyphs, positions, length,
                                        fontRef, isComposing, useLigatures)
                : gatherGlyphs(glyphs, length);
        CTFontDrawGlyphs(fontRef, glyphs, positions, length, context);
        return;
    }

    CGGlyph *glyphsEnd = glyphs+length, *g = glyphs;
    CGPoint *p = positions;
    const unichar *c = chars;
    while (glyphs < glyphsEnd) {
        if (*g) {
            // Draw as many consecutive glyphs as possible in the current font
            // (if a glyph is 0 that means it does not exist in the current
            // font).
            BOOL surrogatePair = NO;
            while (*g && g < glyphsEnd) {
                if (CFStringIsSurrogateHighCharacter(*c)) {
                    surrogatePair = YES;
                    g += 2;
                    c += 2;
                } else {
                    ++g;
                    ++c;
                }
                ++p;
            }

            int count = g-glyphs;
            if (surrogatePair)
                count = gatherGlyphs(glyphs, count);
            CTFontDrawGlyphs(fontRef, glyphs, positions, count, context);
        } else {
            // Skip past as many consecutive chars as possible which cannot be
            // drawn in the current font.
            while (0 == *g && g < glyphsEnd) {
                if (CFStringIsSurrogateHighCharacter(*c)) {
                    g += 2;
                    c += 2;
                } else {
                    ++g;
                    ++c;
                }
                ++p;
            }

            // Try to find a fallback font that can render the entire
            // invalid range. If that fails, repeatedly halve the attempted
            // range until a font is found.
            UniCharCount count = c - chars;
            UniCharCount attemptedCount = count;
            CTFontRef fallback = nil;
            while (fallback == nil && attemptedCount > 0) {
                fallback = lookupFont(fontCache, chars, attemptedCount,
                                      fontRef);
                if (!fallback)
                    attemptedCount /= 2;
            }

            if (!fallback)
                return;

            recurseDraw(chars, glyphs, positions, attemptedCount, context,
                        fallback, fontCache, isComposing, useLigatures);

            // If only a portion of the invalid range was rendered above,
            // the remaining range needs to be attempted by subsequent
            // iterations of the draw loop.
            c -= count - attemptedCount;
            g -= count - attemptedCount;
            p -= count - attemptedCount;

            CFRelease(fallback);
        }

        if (glyphs == g) {
           // No valid chars in the glyphs. Exit from the possible infinite
           // recursive call.
           break;
        }

        chars = c;
        glyphs = g;
        positions = p;
    }
}

- (void)drawString:(const UniChar *)chars length:(UniCharCount)length
             atRow:(int)row column:(int)col cells:(int)cells
         withFlags:(int)flags foregroundColor:(int)fg
   backgroundColor:(int)bg specialColor:(int)sp
{
    CGContextRef context = [self getCGContext];
    NSRect frame = [self bounds];
    float x = col*cellSize.width + insetSize.width;
    float y = frame.size.height - insetSize.height - (1+row)*cellSize.height;
    float w = cellSize.width;
    BOOL wide = flags & DRAW_WIDE ? YES : NO;
    BOOL composing = flags & DRAW_COMP ? YES : NO;

    if (wide) {
        // NOTE: It is assumed that either all characters in 'chars' are wide
        // or all are normal width.
        w *= 2;
    }

    CGContextSaveGState(context);

    int originalFontSmoothingStyle = 0;
    if (thinStrokes) {
        CGContextSetShouldSmoothFonts(context, YES);
        originalFontSmoothingStyle = CGContextGetFontSmoothingStyle(context);
        CGContextSetFontSmoothingStyle(context, fontSmoothingStyleLight);
    }

    // NOTE!  'cells' is zero if we're drawing a composing character
    CGFloat clipWidth = cells > 0 ? cells*cellSize.width : w;
    CGRect clipRect = { {x, y}, {clipWidth, cellSize.height} };
    CGContextClipToRect(context, clipRect);

    if (!(flags & DRAW_TRANSP)) {
        // Draw the background of the text.  Note that if we ignore the
        // DRAW_TRANSP flag and always draw the background, then the insert
        // mode cursor is drawn over.
        CGRect rect = { {x, y}, {cells*cellSize.width, cellSize.height} };
        CGContextSetRGBFillColor(context, RED(bg), GREEN(bg), BLUE(bg),
                                 ALPHA(bg));

        // Antialiasing may cause bleeding effects which are highly undesirable
        // when clearing the background (this code is also called to draw the
        // cursor sometimes) so disable it temporarily.
        CGContextSetShouldAntialias(context, NO);
        CGContextSetBlendMode(context, kCGBlendModeCopy);
        CGContextFillRect(context, rect);
        CGContextSetShouldAntialias(context, antialias);
        CGContextSetBlendMode(context, kCGBlendModeNormal);
    }

    if (flags & DRAW_UNDERL) {
        // Draw underline
        CGRect rect = { {x, y+0.4*fontDescent}, {cells*cellSize.width, 1} };
        CGContextSetRGBFillColor(context, RED(sp), GREEN(sp), BLUE(sp),
                                 ALPHA(sp));
        CGContextFillRect(context, rect);
    } else if (flags & DRAW_UNDERC) {
        // Draw curly underline
        int k;
        float x0 = x, y0 = y+1, w = cellSize.width, h = 0.5*fontDescent;

        CGContextMoveToPoint(context, x0, y0);
        for (k = 0; k < cells; ++k) {
            CGContextAddCurveToPoint(context, x0+0.25*w, y0, x0+0.25*w, y0+h,
                                     x0+0.5*w, y0+h);
            CGContextAddCurveToPoint(context, x0+0.75*w, y0+h, x0+0.75*w, y0,
                                     x0+w, y0);
            x0 += w;
        }

        CGContextSetRGBStrokeColor(context, RED(sp), GREEN(sp), BLUE(sp),
                                   ALPHA(sp));
        CGContextStrokePath(context);
    }

    if (length > maxlen) {
        if (glyphs) free(glyphs);
        if (positions) free(positions);
        glyphs = (CGGlyph*)calloc(length, sizeof(CGGlyph));
        positions = (CGPoint*)calloc(length, sizeof(CGPoint));
        maxlen = length;
    }

    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextDrawingMode(context, kCGTextFill);
    CGContextSetRGBFillColor(context, RED(fg), GREEN(fg), BLUE(fg), ALPHA(fg));
    CGContextSetFontSize(context, [font pointSize]);

    // Calculate position of each glyph relative to (x,y).
    float xrel = composing ? .0 : w;
    for (unsigned i = 0; i < length; ++i) {
        positions[i].x = i * xrel;
        positions[i].y = .0;
    }

    CTFontRef fontRef = (CTFontRef)(wide ? [fontWide retain]
                                         : [font retain]);
    unsigned traits = 0;
    if (flags & DRAW_ITALIC)
        traits |= kCTFontItalicTrait;
    if (flags & DRAW_BOLD)
        traits |= kCTFontBoldTrait;

    if (traits) {
        CTFontRef fr = CTFontCreateCopyWithSymbolicTraits(fontRef, 0.0, NULL,
                                                          traits, traits);
        if (fr) {
            CFRelease(fontRef);
            fontRef = fr;
        }
    }

    CGContextSetTextPosition(context, x, y+fontDescent);
    recurseDraw(chars, glyphs, positions, length, context, fontRef, fontCache,
                composing, ligatures);

    CFRelease(fontRef);
    if (thinStrokes)
        CGContextSetFontSmoothingStyle(context, originalFontSmoothingStyle);
    CGContextRestoreGState(context);

    [self setNeedsDisplayCGLayerInRect:clipRect];
}

- (void)scrollRect:(NSRect)rect lineCount:(int)count
{
    if (cgContext) {
        NSRect fromRect = NSOffsetRect(self.bounds, 0, -count * cellSize.height);
        NSRect toRect = NSOffsetRect(rect, 0, -count * cellSize.height);
        CGContextSaveGState(cgContext);
        CGContextClipToRect(cgContext, toRect);
        CGContextSetBlendMode(cgContext, kCGBlendModeCopy);
        CGImageRef contentsImage = CGBitmapContextCreateImage(cgContext);
        CGContextDrawImage(cgContext, fromRect, contentsImage);
        CGImageRelease(contentsImage);
        CGContextRestoreGState(cgContext);
        [self setNeedsDisplayCGLayerInRect:toRect];
    } else if (cgLayerEnabled) {
        CGContextRef context = [self getCGContext];
        int yOffset = count * cellSize.height;
        NSRect clipRect = rect;
        clipRect.origin.y -= yOffset;

        // draw self on top of self, offset so as to "scroll" lines vertically
        CGContextSaveGState(context);
        CGContextClipToRect(context, clipRect);
        CGContextSetBlendMode(context, kCGBlendModeCopy);
        CGContextDrawLayerAtPoint(
                context, CGPointMake(0, -yOffset), [self getCGLayer]);
        CGContextRestoreGState(context);
        [self setNeedsDisplayCGLayerInRect:clipRect];
    } else {
        NSSize delta={0, -count * cellSize.height};
        [self scrollRect:rect by:delta];
    }
}

- (void)deleteLinesFromRow:(int)row lineCount:(int)count
              scrollBottom:(int)bottom left:(int)left right:(int)right
                     color:(int)color
{
    NSRect rect = [self rectFromRow:row + count
                             column:left
                              toRow:bottom
                             column:right];

    // move rect up for count lines
    [self scrollRect:rect lineCount:-count];
    [self clearBlockFromRow:bottom - count + 1
                     column:left
                      toRow:bottom
                     column:right
                      color:color];
}

- (void)insertLinesAtRow:(int)row lineCount:(int)count
            scrollBottom:(int)bottom left:(int)left right:(int)right
                   color:(int)color
{
    NSRect rect = [self rectFromRow:row
                             column:left
                              toRow:bottom - count
                             column:right];

    // move rect down for count lines
    [self scrollRect:rect lineCount:count];
    [self clearBlockFromRow:row
                     column:left
                      toRow:row + count - 1
                     column:right
                      color:color];
}

- (void)clearBlockFromRow:(int)row1 column:(int)col1 toRow:(int)row2
                   column:(int)col2 color:(int)color
{
    CGContextRef context = [self getCGContext];
    NSRect rect = [self rectFromRow:row1 column:col1 toRow:row2 column:col2];

    CGContextSetRGBFillColor(context, RED(color), GREEN(color), BLUE(color),
                             ALPHA(color));

    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextFillRect(context, *(CGRect*)&rect);
    CGContextSetBlendMode(context, kCGBlendModeNormal);
    [self setNeedsDisplayCGLayerInRect:rect];
}

- (void)clearAll
{
    [self releaseCGLayer];
    CGContextRef context = [self getCGContext];
    NSRect rect = [self bounds];
    float r = [defaultBackgroundColor redComponent];
    float g = [defaultBackgroundColor greenComponent];
    float b = [defaultBackgroundColor blueComponent];
    float a = [defaultBackgroundColor alphaComponent];

    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextSetRGBFillColor(context, r, g, b, a);
    CGContextFillRect(context, *(CGRect*)&rect);
    CGContextSetBlendMode(context, kCGBlendModeNormal);

    [self setNeedsDisplayCGLayer:YES];
}

- (void)drawInsertionPointAtRow:(int)row column:(int)col shape:(int)shape
                       fraction:(int)percent color:(int)color
{
    CGContextRef context = [self getCGContext];
    NSRect rect = [self rectForRow:row column:col numRows:1 numColumns:1];

    CGContextSaveGState(context);

    if (MMInsertionPointHorizontal == shape) {
        int frac = (cellSize.height * percent + 99)/100;
        rect.size.height = frac;
    } else if (MMInsertionPointVertical == shape) {
        int frac = (cellSize.width * percent + 99)/100;
        rect.size.width = frac;
    } else if (MMInsertionPointVerticalRight == shape) {
        int frac = (cellSize.width * percent + 99)/100;
        rect.origin.x += rect.size.width - frac;
        rect.size.width = frac;
    }

    // Temporarily disable antialiasing since we are only drawing square
    // cursors.  Failing to disable antialiasing can cause the cursor to bleed
    // over into adjacent display cells and it may look ugly.
    CGContextSetShouldAntialias(context, NO);

    if (MMInsertionPointHollow == shape) {
        // When stroking a rect its size is effectively 1 pixel wider/higher
        // than we want so make it smaller to avoid having it bleed over into
        // the adjacent display cell.
        // We also have to shift the rect by half a point otherwise it will be
        // partially drawn outside its bounds on a Retina display.
        rect.size.width -= 1;
        rect.size.height -= 1;
        rect.origin.x += 0.5;
        rect.origin.y += 0.5;

        CGContextSetRGBStrokeColor(context, RED(color), GREEN(color),
                                   BLUE(color), ALPHA(color));
        CGContextStrokeRect(context, *(CGRect*)&rect);
    } else {
        CGContextSetRGBFillColor(context, RED(color), GREEN(color), BLUE(color),
                                 ALPHA(color));
        CGContextFillRect(context, *(CGRect*)&rect);
    }

    [self setNeedsDisplayCGLayerInRect:rect];
    CGContextRestoreGState(context);
}

- (void)drawInvertedRectAtRow:(int)row column:(int)col numRows:(int)nrows
                   numColumns:(int)ncols
{
    // TODO: THIS CODE HAS NOT BEEN TESTED!
    CGContextRef cgctx = [self getCGContext];
    CGContextSaveGState(cgctx);
    CGContextSetBlendMode(cgctx, kCGBlendModeDifference);
    CGContextSetRGBFillColor(cgctx, 1.0, 1.0, 1.0, 1.0);

    NSRect rect = [self rectForRow:row column:col numRows:nrows
                        numColumns:ncols];
    CGContextFillRect(cgctx, *(CGRect*)&rect);

    [self setNeedsDisplayCGLayerInRect:rect];
    CGContextRestoreGState(cgctx);
}

@end // MMCoreTextView (Drawing)
