/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMApplication.h"

// Ctrl-Tab is broken on pre 10.5, so we add a hack to make it work.
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
# import "MMTextView.h"
# define MM_CTRL_TAB_HACK 1
#endif




@implementation MMApplication

- (void)sendEvent:(NSEvent *)event
{
    NSEventType type = [event type];
    unsigned flags = [event modifierFlags];

#ifdef MM_CTRL_TAB_HACK
    NSResponder *firstResponder = [[self keyWindow] firstResponder];

    if (NSKeyDown == type && NSControlKeyMask & flags && 48 == [event keyCode]
            && [firstResponder isKindOfClass:[MMTextView class]]) {
        // HACK! This is a Ctrl-Tab key down event and the first responder is
        // an MMTextView; send the event directly to the text view, else it
        // will never receive it on pre 10.5 systems.
        [firstResponder keyDown:event];
        return;
    }
#endif

    // HACK! Intercept 'help' key presses and clear the 'help key flag', else
    // Cocoa turns the mouse cursor into a question mark and goes into 'context
    // help mode' (the keyDown: event itself never reaches the text view).  By
    // clearing the 'help key flag' this event will be treated like a normal
    // key event.
    if ((NSKeyDown == type || NSKeyUp == type) && (flags & NSHelpKeyMask)) {
        flags &= ~NSHelpKeyMask;
        event = [NSEvent keyEventWithType:[event type]
                                 location:[event locationInWindow]
                            modifierFlags:flags
                                timestamp:[event timestamp]
                             windowNumber:[event windowNumber]
                                  context:[event context]
                               characters:[event characters]
              charactersIgnoringModifiers:[event charactersIgnoringModifiers]
                                isARepeat:[event isARepeat]
                                  keyCode:[event keyCode]];
    }

    [super sendEvent:event];
}

@end
