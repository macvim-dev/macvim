/* vi:set ts=8 sts=4 sw=4 noet:
 *
 * VIM - Vi IMproved	by Bram Moolenaar
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 */

/*
 * Keycode definitions for special keys.
 *
 * Any special key code sequences are replaced by these codes.
 */

/*
 * For MSDOS some keys produce codes larger than 0xff. They are split into two
 * chars, the first one is K_NUL (same value used in term.h).
 */
#define K_NUL			(0xce)	// for MSDOS: special key follows

/*
 * K_SPECIAL is the first byte of a special key code and is always followed by
 * two bytes.
 * The second byte can have any value. ASCII is used for normal termcap
 * entries, 0x80 and higher for special keys, see below.
 * The third byte is guaranteed to be between 0x02 and 0x7f.
 */

#define K_SPECIAL		(0x80)

/*
 * Positive characters are "normal" characters.
 * Negative characters are special key codes.  Only characters below -0x200
 * are used to so that the absolute value can't be mistaken for a single-byte
 * character.
 */
#define IS_SPECIAL(c)		((c) < 0)

/*
 * Characters 0x0100 - 0x01ff have a special meaning for abbreviations.
 * Multi-byte characters also have ABBR_OFF added, thus are above 0x0200.
 */
#define ABBR_OFF		0x100

/*
 * NUL cannot be in the input string, therefore it is replaced by
 *	K_SPECIAL   KS_ZERO	KE_FILLER
 */
#define KS_ZERO			255

/*
 * K_SPECIAL cannot be in the input string, therefore it is replaced by
 *	K_SPECIAL   KS_SPECIAL	KE_FILLER
 */
#define KS_SPECIAL		254

/*
 * KS_EXTRA is used for keys that have no termcap name
 *	K_SPECIAL   KS_EXTRA	KE_xxx
 */
#define KS_EXTRA		253

/*
 * KS_MODIFIER is used when a modifier is given for a (special) key
 *	K_SPECIAL   KS_MODIFIER	bitmask
 */
#define KS_MODIFIER		252

/*
 * These are used for the GUI
 *	K_SPECIAL   KS_xxx	KE_FILLER
 */
#define KS_MOUSE		251
#define KS_MENU			250
#define KS_VER_SCROLLBAR	249
#define KS_HOR_SCROLLBAR	248

/*
 * These are used for DEC mouse
 */
#define KS_NETTERM_MOUSE	247
#define KS_DEC_MOUSE		246

/*
 * Used for switching Select mode back on after a mapping or menu.
 */
#define KS_SELECT		245
#define K_SELECT_STRING		(char_u *)"\200\365X"

/*
 * Used for tearing off a menu.
 */
#define KS_TEAROFF		244

// Used for JSB term mouse.
#define KS_JSBTERM_MOUSE	243

// Used a termcap entry that produces a normal character.
#define KS_KEY			242

// Used for the qnx pterm mouse.
#define KS_PTERM_MOUSE		241

// Used for click in a tab pages label.
#define KS_TABLINE		240

// Used for menu in a tab pages line.
#define KS_TABMENU		239

// Used for the urxvt mouse.
#define KS_URXVT_MOUSE		238

// Used for the sgr mouse.
#define KS_SGR_MOUSE		237
#define KS_SGR_MOUSE_RELEASE	236

// Used for the GPM mouse.
#define KS_GPM_MOUSE		235

/*
 * Filler used after KS_SPECIAL and others
 */
#define KE_FILLER		('X')

/*
 * translation of three byte code "K_SPECIAL a b" into int "K_xxx" and back
 */
#define TERMCAP2KEY(a, b)	(-((a) + ((int)(b) << 8)))
#define KEY2TERMCAP0(x)		((-(x)) & 0xff)
#define KEY2TERMCAP1(x)		(((unsigned)(-(x)) >> 8) & 0xff)

/*
 * get second or third byte when translating special key code into three bytes
 */
#define K_SECOND(c)	((c) == K_SPECIAL ? KS_SPECIAL : (c) == NUL ? KS_ZERO : KEY2TERMCAP0(c))

#define K_THIRD(c)	(((c) == K_SPECIAL || (c) == NUL) ? KE_FILLER : KEY2TERMCAP1(c))

/*
 * get single int code from second byte after K_SPECIAL
 */
#define TO_SPECIAL(a, b)    ((a) == KS_SPECIAL ? K_SPECIAL : (a) == KS_ZERO ? K_ZERO : TERMCAP2KEY(a, b))

/*
 * Codes for keys that do not have a termcap name.
 * The numbers are fixed to make sure that recorded key sequences remain valid.
 * Add new entries at the end, not halfway.
 *
 * K_SPECIAL KS_EXTRA KE_xxx
 */
enum key_extra
{
      KE_S_UP = 4		// shift-up
    , KE_S_DOWN = 5		// shift-down

    , KE_S_F1 = 6		// shifted function keys
    , KE_S_F2 = 7
    , KE_S_F3 = 8
    , KE_S_F4 = 9
    , KE_S_F5 = 10
    , KE_S_F6 = 11
    , KE_S_F7 = 12
    , KE_S_F8 = 13
    , KE_S_F9 = 14
    , KE_S_F10 = 15

    , KE_S_F11 = 16
    , KE_S_F12 = 17
    , KE_S_F13 = 18
    , KE_S_F14 = 19
    , KE_S_F15 = 20
    , KE_S_F16 = 21
    , KE_S_F17 = 22
    , KE_S_F18 = 23
    , KE_S_F19 = 24
    , KE_S_F20 = 25

    , KE_S_F21 = 26
    , KE_S_F22 = 27
    , KE_S_F23 = 28
    , KE_S_F24 = 29
    , KE_S_F25 = 30
    , KE_S_F26 = 31
    , KE_S_F27 = 32
    , KE_S_F28 = 33
    , KE_S_F29 = 34
    , KE_S_F30 = 35

    , KE_S_F31 = 36
    , KE_S_F32 = 37
    , KE_S_F33 = 38
    , KE_S_F34 = 39
    , KE_S_F35 = 40
    , KE_S_F36 = 41
    , KE_S_F37 = 42

    , KE_MOUSE = 43		// mouse event start

/*
 * Symbols for pseudo keys which are translated from the real key symbols
 * above.
 */
    , KE_LEFTMOUSE = 44		// Left mouse button click
    , KE_LEFTDRAG = 45		// Drag with left mouse button down
    , KE_LEFTRELEASE = 46	// Left mouse button release
    , KE_MIDDLEMOUSE = 47	// Middle mouse button click
    , KE_MIDDLEDRAG = 48	// Drag with middle mouse button down
    , KE_MIDDLERELEASE = 49	// Middle mouse button release
    , KE_RIGHTMOUSE = 50	// Right mouse button click
    , KE_RIGHTDRAG = 51		// Drag with right mouse button down
    , KE_RIGHTRELEASE = 52	// Right mouse button release

    , KE_IGNORE = 53		// Ignored mouse drag/release

    , KE_TAB = 54		// unshifted TAB key
    , KE_S_TAB_OLD = 55		// shifted TAB key (no longer used)

    , KE_SNIFF_UNUSED = 56	// obsolete
    , KE_XF1 = 57		// extra vt100 function keys for xterm
    , KE_XF2 = 58
    , KE_XF3 = 59
    , KE_XF4 = 60
    , KE_XEND = 61		// extra (vt100) end key for xterm
    , KE_ZEND = 62		// extra (vt100) end key for xterm
    , KE_XHOME = 63		// extra (vt100) home key for xterm
    , KE_ZHOME = 64		// extra (vt100) home key for xterm
    , KE_XUP = 65		// extra vt100 cursor keys for xterm
    , KE_XDOWN = 66
    , KE_XLEFT = 67
    , KE_XRIGHT = 68

    , KE_LEFTMOUSE_NM = 69	// non-mappable Left mouse button click
    , KE_LEFTRELEASE_NM = 70	// non-mappable left mouse button release

    , KE_S_XF1 = 71		// vt100 shifted function keys for xterm
    , KE_S_XF2 = 72
    , KE_S_XF3 = 73
    , KE_S_XF4 = 74

    // NOTE: The scroll wheel events are inverted: i.e. UP is the same as
    // moving the actual scroll wheel down, LEFT is the same as moving the
    // scroll wheel right.
    , KE_MOUSEDOWN = 75		// scroll wheel pseudo-button Down
    , KE_MOUSEUP = 76		// scroll wheel pseudo-button Up
    , KE_MOUSELEFT = 77		// scroll wheel pseudo-button Left
    , KE_MOUSERIGHT = 78	// scroll wheel pseudo-button Right

    , KE_KINS = 79		// keypad Insert key
    , KE_KDEL = 80		// keypad Delete key

    , KE_CSI = 81		// CSI typed directly
    , KE_SNR = 82		// <SNR>
    , KE_PLUG = 83		// <Plug>
    , KE_CMDWIN = 84		// open command-line window from Command-line
				// Mode

    , KE_C_LEFT = 85		// control-left
    , KE_C_RIGHT = 86		// control-right
    , KE_C_HOME = 87		// control-home
    , KE_C_END = 88		// control-end

    , KE_X1MOUSE = 89		// X1/X2 mouse-buttons
    , KE_X1DRAG = 90
    , KE_X1RELEASE = 91
    , KE_X2MOUSE = 92
    , KE_X2DRAG = 93
    , KE_X2RELEASE = 94

    , KE_DROP = 95		// DnD data is available
    , KE_CURSORHOLD = 96	// CursorHold event
    , KE_NOP = 97		// doesn't do something
    , KE_FOCUSGAINED = 98	// focus gained
    , KE_FOCUSLOST = 99		// focus lost
    , KE_MOUSEMOVE = 100	// mouse moved with no button down
    , KE_MOUSEMOVE_XY = 101	// KE_MOUSEMOVE with coordinates
    , KE_CANCEL = 102		// return from vgetc()
    , KE_COMMAND = 103		// <Cmd> special key
    , KE_SCRIPT_COMMAND = 104	// <ScriptCmd> special key
    , KE_S_BS = 105		// shift + <BS>
    , KE_SID = 106		// <SID> special key, followed by {nr};
    , KE_ESC = 107		// used for K_ESC
    , KE_WILD = 108		// triggers wildmode completion
#ifdef FEAT_GUI_MACVIM
    , KE_SWIPELEFT = 109	// Swipe trackpad left
    , KE_SWIPERIGHT = 110	// Swipe trackpad right
    , KE_SWIPEUP = 111		// Swipe trackpad up
    , KE_SWIPEDOWN = 112	// Swipe trackpad down
    , KE_FORCECLICK = 113	// Force click on trackpad
#endif
};

/*
 * The three-byte codes are replaced with a negative number when using vgetc().
 */
#define K_ZERO		TERMCAP2KEY(KS_ZERO, KE_FILLER)

#define K_ESC		TERMCAP2KEY(KS_EXTRA, KE_ESC)

#define K_UP		TERMCAP2KEY('k', 'u')
#define K_DOWN		TERMCAP2KEY('k', 'd')
#define K_LEFT		TERMCAP2KEY('k', 'l')
#define K_RIGHT		TERMCAP2KEY('k', 'r')
#define K_S_UP		TERMCAP2KEY(KS_EXTRA, KE_S_UP)
#define K_S_DOWN	TERMCAP2KEY(KS_EXTRA, KE_S_DOWN)
#define K_S_LEFT	TERMCAP2KEY('#', '4')
#define K_C_LEFT	TERMCAP2KEY(KS_EXTRA, KE_C_LEFT)
#define K_S_RIGHT	TERMCAP2KEY('%', 'i')
#define K_C_RIGHT	TERMCAP2KEY(KS_EXTRA, KE_C_RIGHT)

#define K_S_HOME	TERMCAP2KEY('#', '2')
#define K_C_HOME	TERMCAP2KEY(KS_EXTRA, KE_C_HOME)
#define K_S_END		TERMCAP2KEY('*', '7')
#define K_C_END		TERMCAP2KEY(KS_EXTRA, KE_C_END)

#define K_TAB		TERMCAP2KEY(KS_EXTRA, KE_TAB)
#define K_S_TAB		TERMCAP2KEY('k', 'B')
#define K_S_BS		TERMCAP2KEY(KS_EXTRA, KE_S_BS)

// extra set of function keys F1-F4, for vt100 compatible xterm
#define K_XF1		TERMCAP2KEY(KS_EXTRA, KE_XF1)
#define K_XF2		TERMCAP2KEY(KS_EXTRA, KE_XF2)
#define K_XF3		TERMCAP2KEY(KS_EXTRA, KE_XF3)
#define K_XF4		TERMCAP2KEY(KS_EXTRA, KE_XF4)

// extra set of cursor keys for vt100 compatible xterm
#define K_XUP		TERMCAP2KEY(KS_EXTRA, KE_XUP)
#define K_XDOWN		TERMCAP2KEY(KS_EXTRA, KE_XDOWN)
#define K_XLEFT		TERMCAP2KEY(KS_EXTRA, KE_XLEFT)
#define K_XRIGHT	TERMCAP2KEY(KS_EXTRA, KE_XRIGHT)

#define K_F1		TERMCAP2KEY('k', '1')	// function keys
#define K_F2		TERMCAP2KEY('k', '2')
#define K_F3		TERMCAP2KEY('k', '3')
#define K_F4		TERMCAP2KEY('k', '4')
#define K_F5		TERMCAP2KEY('k', '5')
#define K_F6		TERMCAP2KEY('k', '6')
#define K_F7		TERMCAP2KEY('k', '7')
#define K_F8		TERMCAP2KEY('k', '8')
#define K_F9		TERMCAP2KEY('k', '9')
#define K_F10		TERMCAP2KEY('k', ';')

#define K_F11		TERMCAP2KEY('F', '1')
#define K_F12		TERMCAP2KEY('F', '2')
#define K_F13		TERMCAP2KEY('F', '3')
#define K_F14		TERMCAP2KEY('F', '4')
#define K_F15		TERMCAP2KEY('F', '5')
#define K_F16		TERMCAP2KEY('F', '6')
#define K_F17		TERMCAP2KEY('F', '7')
#define K_F18		TERMCAP2KEY('F', '8')
#define K_F19		TERMCAP2KEY('F', '9')
#define K_F20		TERMCAP2KEY('F', 'A')

#define K_F21		TERMCAP2KEY('F', 'B')
#define K_F22		TERMCAP2KEY('F', 'C')
#define K_F23		TERMCAP2KEY('F', 'D')
#define K_F24		TERMCAP2KEY('F', 'E')
#define K_F25		TERMCAP2KEY('F', 'F')
#define K_F26		TERMCAP2KEY('F', 'G')
#define K_F27		TERMCAP2KEY('F', 'H')
#define K_F28		TERMCAP2KEY('F', 'I')
#define K_F29		TERMCAP2KEY('F', 'J')
#define K_F30		TERMCAP2KEY('F', 'K')

#define K_F31		TERMCAP2KEY('F', 'L')
#define K_F32		TERMCAP2KEY('F', 'M')
#define K_F33		TERMCAP2KEY('F', 'N')
#define K_F34		TERMCAP2KEY('F', 'O')
#define K_F35		TERMCAP2KEY('F', 'P')
#define K_F36		TERMCAP2KEY('F', 'Q')
#define K_F37		TERMCAP2KEY('F', 'R')

// extra set of shifted function keys F1-F4, for vt100 compatible xterm
#define K_S_XF1		TERMCAP2KEY(KS_EXTRA, KE_S_XF1)
#define K_S_XF2		TERMCAP2KEY(KS_EXTRA, KE_S_XF2)
#define K_S_XF3		TERMCAP2KEY(KS_EXTRA, KE_S_XF3)
#define K_S_XF4		TERMCAP2KEY(KS_EXTRA, KE_S_XF4)

#define K_S_F1		TERMCAP2KEY(KS_EXTRA, KE_S_F1)	// shifted func. keys
#define K_S_F2		TERMCAP2KEY(KS_EXTRA, KE_S_F2)
#define K_S_F3		TERMCAP2KEY(KS_EXTRA, KE_S_F3)
#define K_S_F4		TERMCAP2KEY(KS_EXTRA, KE_S_F4)
#define K_S_F5		TERMCAP2KEY(KS_EXTRA, KE_S_F5)
#define K_S_F6		TERMCAP2KEY(KS_EXTRA, KE_S_F6)
#define K_S_F7		TERMCAP2KEY(KS_EXTRA, KE_S_F7)
#define K_S_F8		TERMCAP2KEY(KS_EXTRA, KE_S_F8)
#define K_S_F9		TERMCAP2KEY(KS_EXTRA, KE_S_F9)
#define K_S_F10		TERMCAP2KEY(KS_EXTRA, KE_S_F10)

#define K_S_F11		TERMCAP2KEY(KS_EXTRA, KE_S_F11)
#define K_S_F12		TERMCAP2KEY(KS_EXTRA, KE_S_F12)
// K_S_F13 to K_S_F37  are currently not used

#define K_HELP		TERMCAP2KEY('%', '1')
#define K_UNDO		TERMCAP2KEY('&', '8')

#define K_BS		TERMCAP2KEY('k', 'b')

#define K_INS		TERMCAP2KEY('k', 'I')
#define K_KINS		TERMCAP2KEY(KS_EXTRA, KE_KINS)
#define K_DEL		TERMCAP2KEY('k', 'D')
#define K_KDEL		TERMCAP2KEY(KS_EXTRA, KE_KDEL)
#define K_HOME		TERMCAP2KEY('k', 'h')
#define K_KHOME		TERMCAP2KEY('K', '1')	// keypad home (upper left)
#define K_XHOME		TERMCAP2KEY(KS_EXTRA, KE_XHOME)
#define K_ZHOME		TERMCAP2KEY(KS_EXTRA, KE_ZHOME)
#define K_END		TERMCAP2KEY('@', '7')
#define K_KEND		TERMCAP2KEY('K', '4')	// keypad end (lower left)
#define K_XEND		TERMCAP2KEY(KS_EXTRA, KE_XEND)
#define K_ZEND		TERMCAP2KEY(KS_EXTRA, KE_ZEND)
#define K_PAGEUP	TERMCAP2KEY('k', 'P')
#define K_PAGEDOWN	TERMCAP2KEY('k', 'N')
#define K_KPAGEUP	TERMCAP2KEY('K', '3')	// keypad pageup (upper R.)
#define K_KPAGEDOWN	TERMCAP2KEY('K', '5')	// keypad pagedown (lower R.)

#define K_KPLUS		TERMCAP2KEY('K', '6')	// keypad plus
#define K_KMINUS	TERMCAP2KEY('K', '7')	// keypad minus
#define K_KDIVIDE	TERMCAP2KEY('K', '8')	// keypad /
#define K_KMULTIPLY	TERMCAP2KEY('K', '9')	// keypad *
#define K_KENTER	TERMCAP2KEY('K', 'A')	// keypad Enter
#define K_KPOINT	TERMCAP2KEY('K', 'B')	// keypad . or ,
#define K_PS		TERMCAP2KEY('P', 'S')	// paste start
#define K_PE		TERMCAP2KEY('P', 'E')	// paste end

#define K_K0		TERMCAP2KEY('K', 'C')	// keypad 0
#define K_K1		TERMCAP2KEY('K', 'D')	// keypad 1
#define K_K2		TERMCAP2KEY('K', 'E')	// keypad 2
#define K_K3		TERMCAP2KEY('K', 'F')	// keypad 3
#define K_K4		TERMCAP2KEY('K', 'G')	// keypad 4
#define K_K5		TERMCAP2KEY('K', 'H')	// keypad 5
#define K_K6		TERMCAP2KEY('K', 'I')	// keypad 6
#define K_K7		TERMCAP2KEY('K', 'J')	// keypad 7
#define K_K8		TERMCAP2KEY('K', 'K')	// keypad 8
#define K_K9		TERMCAP2KEY('K', 'L')	// keypad 9

#define K_MOUSE		TERMCAP2KEY(KS_MOUSE, KE_FILLER)
#define K_MENU		TERMCAP2KEY(KS_MENU, KE_FILLER)
#define K_VER_SCROLLBAR	TERMCAP2KEY(KS_VER_SCROLLBAR, KE_FILLER)
#define K_HOR_SCROLLBAR   TERMCAP2KEY(KS_HOR_SCROLLBAR, KE_FILLER)

#define K_NETTERM_MOUSE	TERMCAP2KEY(KS_NETTERM_MOUSE, KE_FILLER)
#define K_DEC_MOUSE	TERMCAP2KEY(KS_DEC_MOUSE, KE_FILLER)
#define K_JSBTERM_MOUSE	TERMCAP2KEY(KS_JSBTERM_MOUSE, KE_FILLER)
#define K_PTERM_MOUSE	TERMCAP2KEY(KS_PTERM_MOUSE, KE_FILLER)
#define K_URXVT_MOUSE	TERMCAP2KEY(KS_URXVT_MOUSE, KE_FILLER)
#define K_SGR_MOUSE	TERMCAP2KEY(KS_SGR_MOUSE, KE_FILLER)
#define K_SGR_MOUSERELEASE TERMCAP2KEY(KS_SGR_MOUSE_RELEASE, KE_FILLER)

#define K_SELECT	TERMCAP2KEY(KS_SELECT, KE_FILLER)
#define K_TEAROFF	TERMCAP2KEY(KS_TEAROFF, KE_FILLER)

#define K_TABLINE	TERMCAP2KEY(KS_TABLINE, KE_FILLER)
#define K_TABMENU	TERMCAP2KEY(KS_TABMENU, KE_FILLER)

/*
 * Symbols for pseudo keys which are translated from the real key symbols
 * above.
 */
#define K_LEFTMOUSE	TERMCAP2KEY(KS_EXTRA, KE_LEFTMOUSE)
#define K_LEFTMOUSE_NM	TERMCAP2KEY(KS_EXTRA, KE_LEFTMOUSE_NM)
#define K_LEFTDRAG	TERMCAP2KEY(KS_EXTRA, KE_LEFTDRAG)
#define K_LEFTRELEASE	TERMCAP2KEY(KS_EXTRA, KE_LEFTRELEASE)
#define K_LEFTRELEASE_NM TERMCAP2KEY(KS_EXTRA, KE_LEFTRELEASE_NM)
#define K_MOUSEMOVE	TERMCAP2KEY(KS_EXTRA, KE_MOUSEMOVE)
#define K_MIDDLEMOUSE	TERMCAP2KEY(KS_EXTRA, KE_MIDDLEMOUSE)
#define K_MIDDLEDRAG	TERMCAP2KEY(KS_EXTRA, KE_MIDDLEDRAG)
#define K_MIDDLERELEASE	TERMCAP2KEY(KS_EXTRA, KE_MIDDLERELEASE)
#define K_RIGHTMOUSE	TERMCAP2KEY(KS_EXTRA, KE_RIGHTMOUSE)
#define K_RIGHTDRAG	TERMCAP2KEY(KS_EXTRA, KE_RIGHTDRAG)
#define K_RIGHTRELEASE	TERMCAP2KEY(KS_EXTRA, KE_RIGHTRELEASE)
#define K_X1MOUSE	TERMCAP2KEY(KS_EXTRA, KE_X1MOUSE)
#define K_X1MOUSE	TERMCAP2KEY(KS_EXTRA, KE_X1MOUSE)
#define K_X1DRAG	TERMCAP2KEY(KS_EXTRA, KE_X1DRAG)
#define K_X1RELEASE     TERMCAP2KEY(KS_EXTRA, KE_X1RELEASE)
#define K_X2MOUSE	TERMCAP2KEY(KS_EXTRA, KE_X2MOUSE)
#define K_X2DRAG	TERMCAP2KEY(KS_EXTRA, KE_X2DRAG)
#define K_X2RELEASE     TERMCAP2KEY(KS_EXTRA, KE_X2RELEASE)

#define K_IGNORE	TERMCAP2KEY(KS_EXTRA, KE_IGNORE)
#define K_NOP		TERMCAP2KEY(KS_EXTRA, KE_NOP)
#define K_CANCEL	TERMCAP2KEY(KS_EXTRA, KE_CANCEL)

#define K_MOUSEDOWN	TERMCAP2KEY(KS_EXTRA, KE_MOUSEDOWN)
#define K_MOUSEUP	TERMCAP2KEY(KS_EXTRA, KE_MOUSEUP)
#define K_MOUSELEFT	TERMCAP2KEY(KS_EXTRA, KE_MOUSELEFT)
#define K_MOUSERIGHT	TERMCAP2KEY(KS_EXTRA, KE_MOUSERIGHT)

#define K_CSI		TERMCAP2KEY(KS_EXTRA, KE_CSI)
#define K_SNR		TERMCAP2KEY(KS_EXTRA, KE_SNR)
#define K_PLUG		TERMCAP2KEY(KS_EXTRA, KE_PLUG)
#define K_CMDWIN	TERMCAP2KEY(KS_EXTRA, KE_CMDWIN)

#define K_DROP		TERMCAP2KEY(KS_EXTRA, KE_DROP)
#define K_FOCUSGAINED	TERMCAP2KEY(KS_EXTRA, KE_FOCUSGAINED)
#define K_FOCUSLOST	TERMCAP2KEY(KS_EXTRA, KE_FOCUSLOST)

#define K_CURSORHOLD	TERMCAP2KEY(KS_EXTRA, KE_CURSORHOLD)

#define K_COMMAND	TERMCAP2KEY(KS_EXTRA, KE_COMMAND)
#define K_SCRIPT_COMMAND TERMCAP2KEY(KS_EXTRA, KE_SCRIPT_COMMAND)
#define K_SID		TERMCAP2KEY(KS_EXTRA, KE_SID)

#define K_WILD		TERMCAP2KEY(KS_EXTRA, KE_WILD)

#ifdef FEAT_GUI_MACVIM
# define K_SWIPELEFT	TERMCAP2KEY(KS_EXTRA, KE_SWIPELEFT)
# define K_SWIPERIGHT	TERMCAP2KEY(KS_EXTRA, KE_SWIPERIGHT)
# define K_SWIPEUP	TERMCAP2KEY(KS_EXTRA, KE_SWIPEUP)
# define K_SWIPEDOWN	TERMCAP2KEY(KS_EXTRA, KE_SWIPEDOWN)
# define K_FORCECLICK	TERMCAP2KEY(KS_EXTRA, KE_FORCECLICK)
#endif

// Bits for modifier mask
// 0x01 cannot be used, because the modifier must be 0x02 or higher
#define MOD_MASK_SHIFT	    0x02
#define MOD_MASK_CTRL	    0x04
#define MOD_MASK_ALT	    0x08	// aka META
#define MOD_MASK_META	    0x10	// META when it's different from ALT
#define MOD_MASK_2CLICK	    0x20	// use MOD_MASK_MULTI_CLICK
#define MOD_MASK_3CLICK	    0x40	// use MOD_MASK_MULTI_CLICK
#define MOD_MASK_4CLICK	    0x60	// use MOD_MASK_MULTI_CLICK
#if defined(MACOS_X) || defined(FEAT_GUI_GTK)
# define MOD_MASK_CMD	    0x80        // aka SUPER
#endif

#define MOD_MASK_MULTI_CLICK	(MOD_MASK_2CLICK|MOD_MASK_3CLICK|MOD_MASK_4CLICK)

/*
 * The length of the longest special key name, including modifiers.
 * Current longest is <M-C-S-T-D-A-4-ScrollWheelRight> (length includes '<' and
 * '>').
 */
#define MAX_KEY_NAME_LEN    32

/*
 * Maximum length of a special key event as tokens.  This includes modifiers.
 * The longest event is something like <M-C-S-T-4-LeftDrag> which would be the
 * following string of tokens:
 *
 * <K_SPECIAL> <KS_MODIFIER> bitmask <K_SPECIAL> <KS_EXTRA> <KT_LEFTDRAG>.
 *
 * This is a total of 6 tokens, and is currently the longest one possible.
 */
#define MAX_KEY_CODE_LEN    6
