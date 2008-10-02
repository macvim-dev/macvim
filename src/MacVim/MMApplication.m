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
 * MMApplication
 *
 * Some default NSApplication key input behavior is overridden here.
 */

#import "MMApplication.h"
#import "Miscellaneous.h"

// Ctrl-Tab is broken on pre 10.5, so we add a hack to make it work.
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
# import "MMTextView.h"
# define MM_CTRL_TAB_HACK 1
#endif




@implementation MMApplication

- (void)awakeFromNib
{
    [self fakeEscModifierKeyChanged:nil];
}

- (void)sendEvent:(NSEvent *)event
{
    NSEventType type = [event type];
    unsigned flags = [event modifierFlags];

    // The following hack allows the user to set one modifier key of choice
    // (Ctrl, Alt, or Cmd) to generate an Esc key press event.  In order for
    // the key to still be used as a modifier we only send the "faked" Esc
    // event if the modifier was pressed and released without any other keys
    // being pressed in between.  The user may elect to have the chosen
    // modifier sending Esc on key down, since sending it on key up makes it
    // appear a bit sluggish.  However, this effectively disables the modifier
    // key (but only the left key and not the right one, in case there are two
    // on the keyboard).
    //
    // This hack is particularly useful in conjunction with Mac OS X's ability
    // to turn Caps-Lock into a modifier key of choice because it enables us to
    // turn Caps-Lock into a quasi-Esc key!  (This remapping be done inside
    // "System Preferences -> Keyboard & Mouse -> Modifier Keys...".)
    //
    if (fakeEscKeyCode != 0) {
        if (NSFlagsChanged == type && [event keyCode] == fakeEscKeyCode) {
            BOOL sendEsc = NO;
            CFAbsoluteTime timeNow = CFAbsoluteTimeGetCurrent();

            if ((flags & fakeEscModifierMask) == 0) {
                // The chosen modifier was released.  If the modifier was
                // recently pressed then convert this event to a "fake" Esc key
                // press event.
                if (!blockFakeEscEvent && !fakeEscOnKeyDown &&
                        timeNow - fakeEscTimeDown < fakeEscTimeout)
                    sendEsc = YES;

                blockFakeEscEvent = YES;
                blockKeyDown = NO;
            } else {
                // The chosen modifier was pressed.
                blockFakeEscEvent = NO;
                fakeEscTimeDown = timeNow;

                if (fakeEscOnKeyDown) {
                    sendEsc = YES;

                    // Block key down while the fake Esc modifier key is held,
                    // otherwise "marked text" may pop up if a key is pressed
                    // while the fake Esc modifier is held (which looks ugly,
                    // but is harmless).
                    blockKeyDown = YES;
                }
            }

            if (sendEsc) {
                NSEvent *e = [NSEvent keyEventWithType:NSKeyDown
                                         location:[event locationInWindow]
                                    modifierFlags:flags & 0x0000ffffU
                                        timestamp:[event timestamp]
                                     windowNumber:[event windowNumber]
                                          context:[event context]
                                       characters:@"\x1b"   // Esc
                      charactersIgnoringModifiers:@"\x1b"
                                        isARepeat:NO
                                          keyCode:53];

                [self postEvent:e atStart:YES];
                return;
            }
        } else if (type != NSKeyUp) {
            // Another event occurred, so don't send any fake Esc events now
            // (else the modifier would not function as a modifier key any
            // more).
            blockFakeEscEvent = YES;
        }

        if (blockKeyDown && type == NSKeyDown)
            return;
    }

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
        NSEvent *e = [NSEvent keyEventWithType:[event type]
                                 location:[event locationInWindow]
                            modifierFlags:flags
                                timestamp:[event timestamp]
                             windowNumber:[event windowNumber]
                                  context:[event context]
                               characters:[event characters]
              charactersIgnoringModifiers:[event charactersIgnoringModifiers]
                                isARepeat:[event isARepeat]
                                  keyCode:[event keyCode]];

        [self postEvent:e atStart:YES];
        return;
    }

    [super sendEvent:event];
}


- (void)orderFrontStandardAboutPanel:(id)sender
{
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:
            @"CFBundleVersion"];
    NSString *marketingVersion = [[NSBundle mainBundle]
            objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *title = [NSString stringWithFormat:
            @"Custom Version %@ (%@)", marketingVersion, version];

    [self orderFrontStandardAboutPanelWithOptions:
            [NSDictionary dictionaryWithObjectsAndKeys:
                @"",    @"Version",
                title,  @"ApplicationVersion",
                nil]];
}

- (IBAction)fakeEscModifierKeyChanged:(id)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    switch ([ud integerForKey:MMFakeEscModifierKey]) {
    case MMCtrlFakeEsc:
        fakeEscKeyCode = 59;
        fakeEscModifierMask = NSControlKeyMask;
        break;
    case MMAltFakeEsc:
        fakeEscKeyCode = 58;
        fakeEscModifierMask = NSAlternateKeyMask;
        break;
    case MMCmdFakeEsc:
        fakeEscKeyCode = 55;
        fakeEscModifierMask = NSCommandKeyMask;
        break;
    default:
        fakeEscKeyCode = fakeEscModifierMask = 0;
    }

    fakeEscTimeout = [ud floatForKey:MMFakeEscTimeoutKey];
    fakeEscOnKeyDown = [ud boolForKey:MMFakeEscOnKeyDownKey];
}

@end
