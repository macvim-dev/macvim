/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import <Foundation/Foundation.h>
#import "MMBackend.h"
#import "MacVim.h"
#import "vim.h"



// -- Initialization --------------------------------------------------------

/*
 * Parse the GUI related command-line arguments.  Any arguments used are
 * deleted from argv, and *argc is decremented accordingly.  This is called
 * when vim is started, whether or not the GUI has been started.
 */
    void
gui_mch_prepare(int *argc, char **argv)
{
    //NSLog(@"gui_mch_prepare(argc=%d)", *argc);

    // Set environment variables $VIM and $VIMRUNTIME
    // NOTE!  If vim_getenv is called with one of these as parameters before
    // they have been set here, they will most likely end up with the wrong
    // values!
    //
    // TODO:
    // - ensure this is called first to avoid above problem
    // - encoding

    NSString *path = [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:@"vim"];
    vim_setenv((char_u*)"VIM", (char_u*)[path UTF8String]);

    path = [path stringByAppendingPathComponent:@"runtime"];
    vim_setenv((char_u*)"VIMRUNTIME", (char_u*)[path UTF8String]);
}


/*
 * Check if the GUI can be started.  Called before gvimrc is sourced.
 * Return OK or FAIL.
 */
    int
gui_mch_init_check(void)
{
    //NSLog(@"gui_mch_init_check()");
    return OK;
}


/*
 * Initialise the GUI.  Create all the windows, set up all the call-backs etc.
 * Returns OK for success, FAIL when the GUI can't be started.
 */
    int
gui_mch_init(void)
{
    //NSLog(@"gui_mch_init()");

    if (![[MMBackend sharedInstance] checkin])
        return FAIL;

    // HACK!  Force the 'termencoding to utf-8.  For the moment also force
    // 'encoding', although this will change in the future.  The user can still
    // change 'encoding'; doing so WILL crash the program.
    set_option_value((char_u *)"termencoding", 0L, (char_u *)"utf-8", 0);
    set_option_value((char_u *)"encoding", 0L, (char_u *)"utf-8", 0);

    // Set values so that pixels and characters are in one-to-one
    // correspondence (assuming all characters have the same dimensions).
    gui.scrollbar_width = gui.scrollbar_height = 0;

    gui.char_height = 1;
    gui.char_width = 1;
    gui.char_ascent = 0;

    // Default foreground and background colors are black and white.
    gui.def_norm_pixel = gui.norm_pixel = 0;
    gui.def_back_pixel = gui.back_pixel = 0xffffff;

    [[MMBackend sharedInstance]
        setDefaultColorsBackground:gui.back_pixel foreground:gui.norm_pixel];
    [[MMBackend sharedInstance] setBackgroundColor:gui.back_pixel];
    [[MMBackend sharedInstance] setForegroundColor:gui.norm_pixel];

    // NOTE: If this call is left out the cursor is opaque.
    highlight_gui_started();

    return OK;
}



    void
gui_mch_exit(int rc)
{
    //NSLog(@"gui_mch_exit(rc=%d)", rc);

    [[MMBackend sharedInstance] exit];
}


/*
 * Open the GUI window which was created by a call to gui_mch_init().
 */
    int
gui_mch_open(void)
{
    //NSLog(@"gui_mch_open()");

    return [[MMBackend sharedInstance]
            openVimWindowWithRows:gui.num_rows columns:gui.num_cols];
}


// -- Updating --------------------------------------------------------------


/*
 * Catch up with any queued X events.  This may put keyboard input into the
 * input buffer, call resize call-backs, trigger timers etc.  If there is
 * nothing in the X event queue (& no timers pending), then we return
 * immediately.
 */
    void
gui_mch_update(void)
{
    // HACK!  Nothing to do here since we tend to the run loop (which holds
    // incoming events) in gui_mch_wait_for_chars().
}


/* Flush any output to the screen */
    void
gui_mch_flush(void)
{
    // HACK!  This function is called so often that draw performance suffers.
    // Instead of actually flushing the output it is placed on a queue and
    // flushed in gui_mch_wait_for_chars(), which makes the program feel much
    // more responsive.  This might have unintended side effects though;  if
    // so, another solution might have to be found.

    //[[MMBackend sharedInstance] flush];
}


/*
 * GUI input routine called by gui_wait_for_chars().  Waits for a character
 * from the keyboard.
 *  wtime == -1	    Wait forever.
 *  wtime == 0	    This should never happen.
 *  wtime > 0	    Wait wtime milliseconds for a character.
 * Returns OK if a character was found to be available within the given time,
 * or FAIL otherwise.
 */
    int
gui_mch_wait_for_chars(int wtime)
{
    // HACK!  See comment in gui_mch_flush().
    [[MMBackend sharedInstance] flushQueue];

    return [[MMBackend sharedInstance] waitForInput:wtime];
}


// -- Drawing ---------------------------------------------------------------


/*
 * Clear the whole text window.
 */
    void
gui_mch_clear_all(void)
{
    [[MMBackend sharedInstance] clearAll];
}


/*
 * Clear a rectangular region of the screen from text pos (row1, col1) to
 * (row2, col2) inclusive.
 */
    void
gui_mch_clear_block(int row1, int col1, int row2, int col2)
{
    [[MMBackend sharedInstance] clearBlockFromRow:row1 column:col1
                                                    toRow:row2 column:col2];
}


/*
 * Delete the given number of lines from the given row, scrolling up any
 * text further down within the scroll region.
 */
    void
gui_mch_delete_lines(int row, int num_lines)
{
    [[MMBackend sharedInstance] deleteLinesFromRow:row count:num_lines
            scrollBottom:gui.scroll_region_bot
                    left:gui.scroll_region_left
                   right:gui.scroll_region_right];
}


    void
gui_mch_draw_string(int row, int col, char_u *s, int len, int flags)
{
    [[MMBackend sharedInstance] replaceString:(char*)s length:len
            row:row column:col flags:flags];
}


    int
gui_macvim_draw_string(int row, int col, char_u *s, int len, int flags)
{
#if 0
    NSString *string = [[NSString alloc]
            initWithBytesNoCopy:(void*)s
                         length:len
                       encoding:NSUTF8StringEncoding
                   freeWhenDone:NO];
    int cells = [string length];
    [string release];

    NSLog(@"gui_macvim_draw_string(row=%d, col=%d, len=%d, cells=%d, flags=%d)",
            row, col, len, cells, flags);

    [[MMBackend sharedInstance] replaceString:(char*)s length:len
            row:row column:col flags:flags];

    return cells;
#elif 0
    int c;
    int cn;
    int cl;
    int i;
    BOOL wide = NO;
    int start = 0;
    int endcol = col;
    int startcol = col;
    MMBackend *backend = [MMBackend sharedInstance];

    for (i = 0; i < len; i += cl) {
        c = utf_ptr2char(s + i);
        cl = utf_ptr2len(s + i);
        cn = utf_char2cells(c);
        comping = utf_iscomposing(c);

        if (!comping)
            endcol += cn;

        if (cn > 1 && !wide) {
            // Start of wide characters.
            wide = YES;

            // Output non-wide characters.
            if (start > i) {
                NSLog(@"Outputting %d non-wide chars (%d bytes)",
                        endcol-startcol, start-i);
                [backend replaceString:(char*)(s+start) length:start-i
                        row:row column:startcol flags:flags];
                startcol = endcol;
                start = i;
            }
        } else if (cn <= 1 && !comping && wide) {
            // End of wide characters.
            wide = NO;

            // Output wide characters.
            if (start > i) {
                NSLog(@"Outputting %d wide chars (%d bytes)",
                        endcol-startcol, start-i);
                [backend replaceString:(char*)(s+start) length:start-i
                        row:row column:startcol flags:(flags|0x80)];
                startcol = endcol;
                start = i;
            }
        }
    }

    // Output remaining characters.
    flags = wide ? flags|0x80 : flags;
    NSLog(@"Outputting %d %s chars (%d bytes)", endcol-startcol, wide ? "wide"
            : "non-wide", len-start);
    [backend replaceString:(char*)(s+start) length:len-start
            row:row column:startcol flags:flags];

    return endcol - col;
#elif 1
    //
    // Output chars until a wide char found.  If a wide char is found, output a
    // zero-width space after it so that a wide char looks like two chars to
    // MMTextStorage.  This way 1 char corresponds to 1 column.
    //

    int c;
    int cn;
    int cl;
    int i;
    int start = 0;
    int endcol = col;
    int startcol = col;
    BOOL outPad = NO;
    MMBackend *backend = [MMBackend sharedInstance];
    static char ZeroWidthSpace[] = { 0xe2, 0x80, 0x8b };

    for (i = 0; i < len; i += cl) {
        c = utf_ptr2char(s + i);
        cl = utf_ptr2len(s + i);
        cn = utf_char2cells(c);

        if (!utf_iscomposing(c)) {
            if (outPad) {
                outPad = NO;
#if 0
                NSString *string = [[NSString alloc]
                        initWithBytesNoCopy:(void*)(s+start)
                                     length:i-start
                                   encoding:NSUTF8StringEncoding
                               freeWhenDone:NO];
                NSLog(@"Flushing string=%@ len=%d row=%d col=%d end=%d",
                        string, i-start, row, startcol, endcol);
                [string release];
#endif
                [backend replaceString:(char*)(s+start) length:i-start
                        row:row column:startcol flags:flags];
                start = i;
                startcol = endcol;
#if 0
                NSLog(@"Padding len=%d row=%d col=%d", sizeof(ZeroWidthSpace),
                        row, endcol-1);
#endif
                [backend replaceString:ZeroWidthSpace
                             length:sizeof(ZeroWidthSpace)
                        row:row column:endcol-1 flags:flags];
            }

            endcol += cn;
        }

        if (cn > 1) {
#if 0
            NSLog(@"Wide char detected! (char=%C hex=%x cells=%d)", c, c, cn);
#endif
            outPad = YES;
        }
    }

#if 0
    if (row < 1) {
        NSString *string = [[NSString alloc]
                initWithBytesNoCopy:(void*)(s+start)
                             length:len-start
                           encoding:NSUTF8StringEncoding
                       freeWhenDone:NO];
        NSLog(@"Output string=%@ len=%d row=%d col=%d", string, len-start, row,
                startcol);
        [string release];
    }
#endif

    // Output remaining characters.
    [backend replaceString:(char*)(s+start) length:len-start
            row:row column:startcol flags:flags];

    if (outPad) {
#if 0
        NSLog(@"Padding len=%d row=%d col=%d", sizeof(ZeroWidthSpace), row,
                endcol-1);
#endif
        [backend replaceString:ZeroWidthSpace
                     length:sizeof(ZeroWidthSpace)
                row:row column:endcol-1 flags:flags];
    }

    return endcol - col;
#else
    // This will fail abysmally when wide or composing characters are used.
    [[MMBackend sharedInstance]
            replaceString:(char*)s length:len row:row column:col flags:flags];

    int i, c, cl, cn, cells = 0;
    for (i = 0; i < len; i += cl) {
        c = utf_ptr2char(s + i);
        cl = utf_ptr2len(s + i);
        cn = utf_char2cells(c);

        if (!utf_iscomposing(c))
            cells += cn;
    }

    return cells;
#endif
}


/*
 * Insert the given number of lines before the given row, scrolling down any
 * following text within the scroll region.
 */
    void
gui_mch_insert_lines(int row, int num_lines)
{
    [[MMBackend sharedInstance] insertLinesFromRow:row count:num_lines
            scrollBottom:gui.scroll_region_bot
                    left:gui.scroll_region_left
                   right:gui.scroll_region_right];
}


// -- Tab line --------------------------------------------------------------


/*
 * Set the current tab to "nr".  First tab is 1.
 */
    void
gui_mch_set_curtab(int nr)
{
    //NSLog(@"gui_mch_set_curtab(nr=%d)", nr);
    [[MMBackend sharedInstance] selectTab:nr];
}


/*
 * Return TRUE when tabline is displayed.
 */
    int
gui_mch_showing_tabline(void)
{
    //NSLog(@"gui_mch_showing_tabline()");
    return [[MMBackend sharedInstance] tabBarVisible];
}

/*
 * Update the labels of the tabline.
 */
    void
gui_mch_update_tabline(void)
{
    //NSLog(@"gui_mch_update_tabline()");
    [[MMBackend sharedInstance] updateTabBar];
}

/*
 * Show or hide the tabline.
 */
    void
gui_mch_show_tabline(int showit)
{
    //NSLog(@"gui_mch_show_tabline(showit=%d)", showit);
    [[MMBackend sharedInstance] showTabBar:showit];
}


// -- Clipboard -------------------------------------------------------------


    void
clip_mch_lose_selection(VimClipboard *cbd)
{
}


    int
clip_mch_own_selection(VimClipboard *cbd)
{
    return 0;
}


    void
clip_mch_request_selection(VimClipboard *cbd)
{
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *type = [pb availableTypeFromArray:
            [NSArray arrayWithObject:NSStringPboardType]];
    if (type) {
        NSMutableString *string =
        [[pb stringForType:NSStringPboardType] mutableCopy];

        // Replace unrecognized end-of-line sequences with \x0a (line feed).
        NSRange range = { 0, [string length] };
        unsigned n = [string replaceOccurrencesOfString:@"\x0d\x0a"
                                             withString:@"\x0a" options:0
                                                  range:range];
        if (0 == n) {
            n = [string replaceOccurrencesOfString:@"\x0d" withString:@"\x0a"
                                           options:0 range:range];
        }
        
        // Scan for newline character to decide whether the string should be
        // pasted linewise or characterwise.
        int type = MCHAR;
        if (0 < n || NSNotFound != [string rangeOfString:@"\n"].location)
            type = MLINE;
        
        const char *utf8chars = [string UTF8String];
        clip_yank_selection(type, (char_u*)utf8chars, strlen(utf8chars), cbd);
    }
}


/*
 * Send the current selection to the clipboard.
 */
    void
clip_mch_set_selection(VimClipboard *cbd)
{
    // If the '*' register isn't already filled in, fill it in now.
    cbd->owned = TRUE;
    clip_get_selection(cbd);
    cbd->owned = FALSE;
    
    // Get the text to put on the pasteboard.
    long_u len = 0; char_u *str = 0;
    int type = clip_convert_selection(&str, &len, cbd);
    if (type < 0)
        return;
    
    NSString *string = [[NSString alloc] initWithBytes:str length:len
                                              encoding:NSUTF8StringEncoding];
    
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pb setString:string forType:NSStringPboardType];
    
    [string release];
    vim_free(str);
}


// -- Menu ------------------------------------------------------------------


/*
 * Add a sub menu to the menu bar.
 */
    void
gui_mch_add_menu(vimmenu_T *menu, int idx)
{
    //NSLog(@"gui_mch_add_menu(name=%s, idx=%d)", menu->name, idx);

    // HACK!  If menu has no parent, then we set the parent tag to the type of
    // menu it is.  This will not mix up tag and type because pointers can not
    // take values close to zero (and the tag is simply the value of the
    // pointer).
    int parent = (int)menu->parent;
    if (!parent) {
        parent = menu_is_popup(menu->name) ? MenuPopupType :
                 menu_is_toolbar(menu->name) ? MenuToolbarType :
                 MenuMenubarType;
    }

    [[MMBackend sharedInstance]
            addMenuWithTag:(int)menu parent:parent name:(char*)menu->dname
                   atIndex:idx];
}


/*
 * Add a menu item to a menu
 */
    void
gui_mch_add_menu_item(vimmenu_T *menu, int idx)
{
    //NSLog(@"gui_mch_add_menu_item(name=%s, accel=%s idx=%d)", menu->dname,
    //        menu->actext, idx);

    // NOTE!  If 'iconfile' is not set but 'iconidx' is, use the name of the
    // menu item.  (Should correspond to a stock item.)
    char *icon = menu->iconfile ? (char*)menu->iconfile :
                 menu->iconidx >= 0 ? (char*)menu->dname :
                 NULL;
    char *name = menu_is_separator(menu->name) ? NULL : (char*)menu->dname;
    char *tip = menu->strings[MENU_INDEX_TIP]
            ? (char*)menu->strings[MENU_INDEX_TIP] : (char*)menu->actext;

    [[MMBackend sharedInstance]
            addMenuItemWithTag:(int)menu parent:(int)menu->parent name:name
                           tip:tip icon:(char*)icon atIndex:idx];
}


/*
 * Destroy the machine specific menu widget.
 */
    void
gui_mch_destroy_menu(vimmenu_T *menu)
{
    //NSLog(@"gui_mch_destroy_menu(name=%s)", menu->name);

    [[MMBackend sharedInstance] removeMenuItemWithTag:(int)menu];
}


/*
 * Make a menu either grey or not grey.
 */
    void
gui_mch_menu_grey(vimmenu_T *menu, int grey)
{
    //NSLog(@"gui_mch_menu_grey(name=%s, grey=%d)", menu->name, grey);
    [[MMBackend sharedInstance]
            enableMenuItemWithTag:(int)menu state:!grey];
}


/*
 * Make menu item hidden or not hidden
 */
    void
gui_mch_menu_hidden(vimmenu_T *menu, int hidden)
{
    //NSLog(@"gui_mch_menu_hidden(name=%s, hidden=%d)", menu->name, hidden);

    // HACK! There is no (obvious) way to hide a menu item, so simply
    // enable/disable it instead.
    [[MMBackend sharedInstance]
            enableMenuItemWithTag:(int)menu state:!hidden];
}


    void
gui_mch_show_popupmenu(vimmenu_T *menu)
{
    //NSLog(@"gui_mch_show_popupmenu(name=%s)", menu->name);
}


/*
 * This is called after setting all the menus to grey/hidden or not.
 */
    void
gui_mch_draw_menubar(void)
{
    // The (main) menu draws itself in Mac OS X.
}


    void
gui_mch_enable_menu(int flag)
{
    // The (main) menu is always enabled in Mac OS X.
}


#if 0
    void
gui_mch_set_menu_pos(int x, int y, int w, int h)
{
    // The (main) menu cannot be moved in Mac OS X.
}
#endif


    void
gui_mch_show_toolbar(int showit)
{
    int flags = 0;
    if (toolbar_flags & TOOLBAR_TEXT) flags |= ToolbarLabelFlag;
    if (toolbar_flags & TOOLBAR_ICONS) flags |= ToolbarIconFlag;
    if (tbis_flags & (TBIS_MEDIUM|TBIS_LARGE)) flags |= ToolbarSizeRegularFlag;

    //NSLog(@"gui_mch_show_toolbar(showit=%d, flags=%d)", showit, flags);

    [[MMBackend sharedInstance] showToolbar:showit flags:flags];
}




// -- Fonts -----------------------------------------------------------------


/*
 * If a font is not going to be used, free its structure.
 */
    void
gui_mch_free_font(font)
    GuiFont	font;
{
#if 0
    static GuiFont last_font = -1;
    if (last_font != font) {
        NSLog(@"gui_mch_free_font(font=%d)", font);
        last_font = font;
    }
#endif
}


/*
 * Get a font structure for highlighting.
 */
    GuiFont
gui_mch_get_font(char_u *name, int giveErrorIfMissing)
{
    //NSLog(@"gui_mch_get_font(name=%s, giveErrorIfMissing=%d)", name,
    //        giveErrorIfMissing);
    return 0;
}


#if defined(FEAT_EVAL) || defined(PROTO)
/*
 * Return the name of font "font" in allocated memory.
 * Don't know how to get the actual name, thus use the provided name.
 */
    char_u *
gui_mch_get_fontname(GuiFont font, char_u *name)
{
    //NSLog(@"gui_mch_get_fontname(font=%d, name=%s)", font, name);
    return 0;
}
#endif


/*
 * Initialise vim to use the font with the given name.	Return FAIL if the font
 * could not be loaded, OK otherwise.
 */
    int
gui_mch_init_font(char_u *font_name, int fontset)
{
    //NSLog(@"gui_mch_init_font(font_name=%s, fontset=%d)", font_name, fontset);

    // HACK!  This gets called whenever the user types :set gfn=fontname, so
    // for now we set the font here.
    // TODO!  Proper font handling, the way Vim expects it.
    return [[MMBackend sharedInstance]
            setFontWithName:(char*)font_name];
}


/*
 * Set the current text font.
 */
    void
gui_mch_set_font(GuiFont font)
{
#if 0
    static GuiFont last_font = -1;
    if (last_font != font) {
        NSLog(@"gui_mch_set_font(font=%d)", font);
        last_font = font;
    }
#endif
}




// -- Scrollbars ------------------------------------------------------------


    void
gui_mch_create_scrollbar(
	scrollbar_T *sb,
	int orient)	/* SBAR_VERT or SBAR_HORIZ */
{
    //NSLog(@"gui_mch_create_scrollbar(id=%d, orient=%d, type=%d)",
    //        sb->ident, orient, sb->type);

    [[MMBackend sharedInstance] 
            createScrollbarWithIdentifier:sb->ident type:sb->type];
}


    void
gui_mch_destroy_scrollbar(scrollbar_T *sb)
{
    //NSLog(@"gui_mch_destroy_scrollbar(id=%d)", sb->ident);

    [[MMBackend sharedInstance] 
            destroyScrollbarWithIdentifier:sb->ident];
}


    void
gui_mch_enable_scrollbar(
	scrollbar_T	*sb,
	int		flag)
{
    //NSLog(@"gui_mch_enable_scrollbar(id=%d, flag=%d)", sb->ident, flag);

    [[MMBackend sharedInstance] 
            showScrollbarWithIdentifier:sb->ident state:flag];
}


    void
gui_mch_set_scrollbar_pos(
	scrollbar_T *sb,
	int x,
	int y,
	int w,
	int h)
{
    //NSLog(@"gui_mch_set_scrollbar_pos(id=%d, x=%d, y=%d, w=%d, h=%d)",
    //        sb->ident, x, y, w, h);

    int pos = y;
    int len = h;
    if (SBAR_BOTTOM == sb->type) {
        pos = x;
        len = w; 
    }

    [[MMBackend sharedInstance] 
            setScrollbarPosition:pos length:len identifier:sb->ident];
}


    void
gui_mch_set_scrollbar_thumb(
	scrollbar_T *sb,
	long val,
	long size,
	long max)
{
    //NSLog(@"gui_mch_set_scrollbar_thumb(id=%d, val=%d, size=%d, max=%d)",
    //        sb->ident, val, size, max);

#if 0
    float value = max-size+1 > 0 ? (float)val/(max-size+1) : 0;
    float prop = (float)size/(max+1);
    if (value < 0) value = 0;
    else if (value > 1.0f) value = 1.0f;
    if (prop < 0) prop = 0;
    else if (prop > 1.0f) prop = 1.0f;

    [[MMBackend sharedInstance] 
            setScrollbarThumbValue:value proportion:prop identifier:sb->ident];
#else
    [[MMBackend sharedInstance] 
            setScrollbarThumbValue:val size:size max:max identifier:sb->ident];
#endif
}





// -- Unsorted --------------------------------------------------------------


/*
 * Adjust gui.char_height (after 'linespace' was changed).
 */
    int
gui_mch_adjust_charheight(void)
{
    return 0;
}


    void
gui_mch_beep(void)
{
}



#ifdef FEAT_BROWSE
/*
 * Pop open a file browser and return the file selected, in allocated memory,
 * or NULL if Cancel is hit.
 *  saving  - TRUE if the file will be saved to, FALSE if it will be opened.
 *  title   - Title message for the file browser dialog.
 *  dflt    - Default name of file.
 *  ext     - Default extension to be added to files without extensions.
 *  initdir - directory in which to open the browser (NULL = current dir)
 *  filter  - Filter for matched files to choose from.
 *  Has a format like this:
 *  "C Files (*.c)\0*.c\0"
 *  "All Files\0*.*\0\0"
 *  If these two strings were concatenated, then a choice of two file
 *  filters will be selectable to the user.  Then only matching files will
 *  be shown in the browser.  If NULL, the default allows all files.
 *
 *  *NOTE* - the filter string must be terminated with TWO nulls.
 */
    char_u *
gui_mch_browse(
    int saving,
    char_u *title,
    char_u *dflt,
    char_u *ext,
    char_u *initdir,
    char_u *filter)
{
    //NSLog(@"gui_mch_browse(saving=%d, title=%s, dflt=%s, ext=%s, initdir=%s,"
    //        " filter=%s", saving, title, dflt, ext, initdir, filter);

    char_u *s = (char_u*)[[MMBackend sharedInstance]
            browseForFileInDirectory:(char*)initdir title:(char*)title
                              saving:saving];

    return s;
}
#endif /* FEAT_BROWSE */



    int
gui_mch_dialog(
    int		type,
    char_u	*title,
    char_u	*message,
    char_u	*buttons,
    int		dfltbutton,
    char_u	*textfield)
{
    return 0;
}


/*
 * Draw a cursor without focus.
 */
    void
gui_mch_draw_hollow_cursor(guicolor_T color)
{
}


/*
 * Draw part of a cursor, only w pixels wide, and h pixels high.
 */
    void
gui_mch_draw_part_cursor(int w, int h, guicolor_T color)
{
}


    void
gui_mch_flash(int msec)
{
}


/*
 * Return the Pixel value (color) for the given color name.  This routine was
 * pretty much taken from example code in the Silicon Graphics OSF/Motif
 * Programmer's Guide.
 * Return INVALCOLOR when failed.
 */
    guicolor_T
gui_mch_get_color(char_u *name)
{
    NSString *key = [NSString stringWithUTF8String:(char*)name];
    return [[MMBackend sharedInstance] lookupColorWithKey:key];
}


/*
 * Return the RGB value of a pixel as long.
 */
    long_u
gui_mch_get_rgb(guicolor_T pixel)
{
    // This is only implemented so that vim can guess the correct value for
    // 'background' (which otherwise defaults to 'dark'); it is not used for
    // anything else (as far as I know).
    // The implementation is simple since colors are stored in an int as
    // "rrggbb".
    return pixel;
}


/*
 * Get the screen dimensions.
 * Allow 10 pixels for horizontal borders, 40 for vertical borders.
 * Is there no way to find out how wide the borders really are?
 * TODO: Add live udate of those value on suspend/resume.
 */
    void
gui_mch_get_screen_dimensions(int *screen_w, int *screen_h)
{
    //NSLog(@"gui_mch_get_screen_dimensions()");
    *screen_w = Columns;
    *screen_h = Rows;
}


/*
 * Get the position of the top left corner of the window.
 */
    int
gui_mch_get_winpos(int *x, int *y)
{
    *x = *y = 0;
    return OK;
}


/*
 * Get current mouse coordinates in text window.
 */
    void
gui_mch_getmouse(int *x, int *y)
{
}


/*
 * Return OK if the key with the termcap name "name" is supported.
 */
    int
gui_mch_haskey(char_u *name)
{
    NSLog(@"gui_mch_haskey(name=%s)", name);
    return 0;
}


/*
 * Iconify the GUI window.
 */
    void
gui_mch_iconify(void)
{
}


/*
 * Invert a rectangle from row r, column c, for nr rows and nc columns.
 */
    void
gui_mch_invert_rectangle(int r, int c, int nr, int nc)
{
}


/*
 * Called when the foreground or background color has been changed.
 */
    void
gui_mch_new_colors(void)
{
    gui.def_back_pixel = gui.back_pixel;
    gui.def_norm_pixel = gui.norm_pixel;

    //NSLog(@"gui_mch_new_colors(back=%x, norm=%x)", gui.def_back_pixel,
    //        gui.def_norm_pixel);

    [[MMBackend sharedInstance]
        setDefaultColorsBackground:gui.def_back_pixel
                        foreground:gui.def_norm_pixel];
}


/*
 * Set the current text background color.
 */
    void
gui_mch_set_bg_color(guicolor_T color)
{
    [[MMBackend sharedInstance] setBackgroundColor:color];
}


/*
 * Cursor blink functions.
 *
 * This is a simple state machine:
 * BLINK_NONE	not blinking at all
 * BLINK_OFF	blinking, cursor is not shown
 * BLINK_ON blinking, cursor is shown
 */
    void
gui_mch_set_blinking(long wait, long on, long off)
{
}


/*
 * Set the current text foreground color.
 */
    void
gui_mch_set_fg_color(guicolor_T color)
{
    [[MMBackend sharedInstance] setForegroundColor:color];
}


#if defined(FEAT_EVAL) || defined(PROTO)
/*
 * Bring the Vim window to the foreground.
 */
    void
gui_mch_set_foreground(void)
{
}
#endif



    void
gui_mch_set_shellsize(
    int		width,
    int		height,
    int		min_width,
    int		min_height,
    int		base_width,
    int		base_height,
    int		direction)
{
    //NSLog(@"gui_mch_set_shellsize(width=%d, height=%d, min_width=%d,"
    //        " min_height=%d, base_width=%d, base_height=%d, direction=%d)",
    //        width, height, min_width, min_height, base_width, base_height,
    //        direction);
    [[MMBackend sharedInstance] setRows:height columns:width];
}


/*
 * Set the current text special color.
 */
    void
gui_mch_set_sp_color(guicolor_T color)
{
}


    void
gui_mch_set_text_area_pos(int x, int y, int w, int h)
{
}

/*
 * Set the position of the top left corner of the window to the given
 * coordinates.
 */
    void
gui_mch_set_winpos(int x, int y)
{
}


    void
gui_mch_setmouse(int x, int y)
{
}


#ifdef FEAT_TITLE
/*
 * Set the window title and icon.
 * (The icon is not taken care of).
 */
    void
gui_mch_settitle(char_u *title, char_u *icon)
{
    //NSLog(@"gui_mch_settitle(title=%s, icon=%s)", title, icon);

    [[MMBackend sharedInstance] setVimWindowTitle:(char*)title];
}
#endif


/*
 * Start the cursor blinking.  If it was already blinking, this restarts the
 * waiting time and shows the cursor.
 */
    void
gui_mch_start_blink(void)
{
}


/*
 * Stop the cursor blinking.  Show the cursor if it wasn't shown.
 */
    void
gui_mch_stop_blink(void)
{
}


    void
gui_mch_toggle_tearoffs(int enable)
{
}


    void
mch_set_mouse_shape(int shape)
{
}
