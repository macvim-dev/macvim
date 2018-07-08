extern int use_gui_macvim_draw_string;

    void
macvim_early_init();
    void
gui_mch_prepare(int *argc, char **argv);
    void
gui_macvim_after_fork_init();
    int
gui_mch_init_check(void);
    int
gui_mch_init(void);
    void
gui_mch_exit(int rc);
    int
gui_mch_open(void);
    void
gui_mch_update(void);
    void
gui_mch_flush(void);
    void
gui_macvim_flush(void);
    void
gui_macvim_force_flush(void);
    int
gui_mch_wait_for_chars(int wtime);
    void
gui_mch_clear_all(void);
    void
gui_mch_clear_block(int row1, int col1, int row2, int col2);
    void
gui_mch_delete_lines(int row, int num_lines);
    int
gui_macvim_draw_string(int row, int col, char_u *s, int len, int flags);
    void
gui_mch_insert_lines(int row, int num_lines);
    void
gui_mch_set_curtab(int nr);
    int
gui_mch_showing_tabline(void);
    void
gui_mch_update_tabline(void);
    void
gui_mch_show_tabline(int showit);
    void
clip_mch_lose_selection(VimClipboard *cbd);
    int
clip_mch_own_selection(VimClipboard *cbd);
    void
clip_mch_request_selection(VimClipboard *cbd);
    void
clip_mch_set_selection(VimClipboard *cbd);
    void
gui_mch_add_menu(vimmenu_T *menu, int idx);
    void
gui_mch_add_menu_item(vimmenu_T *menu, int idx);
    void
gui_mch_destroy_menu(vimmenu_T *menu);
    void
gui_mch_menu_grey(vimmenu_T *menu, int grey);
    void
gui_mch_menu_hidden(vimmenu_T *menu, int hidden);
    void
gui_mch_show_popupmenu(vimmenu_T *menu);
    void
gui_mch_draw_menubar(void);
    void
gui_mch_enable_menu(int flag);
    void
gui_mch_show_toolbar(int showit);
    void
gui_mch_free_font(GuiFont font);
    GuiFont
gui_mch_get_font(char_u *name, int giveErrorIfMissing);
    char_u *
gui_mch_get_fontname(GuiFont font, char_u *name);
    int
gui_mch_init_font(char_u *font_name, int fontset);
    void
gui_mch_set_font(GuiFont font);
    int
gui_mch_adjust_charheight(void);
    int
gui_mch_adjust_charwidth(void);
    void
gui_mch_beep(void);
    char_u *
gui_mch_browse(
    int saving,
    char_u *title,
    char_u *dflt,
    char_u *ext,
    char_u *initdir,
    char_u *filter);
    char_u *
gui_mch_browsedir(char_u *title, char_u *initdir);
    void
gui_mch_create_scrollbar(
	scrollbar_T *sb,
	int orient);
    void
gui_mch_destroy_scrollbar(scrollbar_T *sb);
    int
gui_mch_dialog(
    int		type,
    char_u	*title,
    char_u	*message,
    char_u	*buttons,
    int		dfltbutton,
    char_u	*textfield,
    int         ex_cmd);
    void
gui_mch_draw_hollow_cursor(guicolor_T color);
    void
gui_mch_draw_part_cursor(int w, int h, guicolor_T color);
    void
gui_mch_enable_scrollbar(
	scrollbar_T	*sb,
	int		flag);
    void
gui_mch_flash(int msec);
    guicolor_T
gui_mch_get_color(char_u *name);
    guicolor_T
gui_mch_get_rgb(guicolor_T pixel);
    guicolor_T
gui_mch_get_rgb_color(int r, int g, int b);
    void
gui_mch_get_screen_dimensions(int *screen_w, int *screen_h);
    int
gui_mch_get_winpos(int *x, int *y);
    void
gui_mch_getmouse(int *x, int *y);
    int
gui_mch_haskey(char_u *name);
    void
gui_mch_iconify(void);
    void
gui_mch_invert_rectangle(int r, int c, int nr, int nc, int invert);
    void
gui_mch_new_colors(void);
    void
gui_mch_set_bg_color(guicolor_T color);
    int
gui_mch_is_blinking(void);
    int
gui_mch_is_blink_off(void);
    void
gui_mch_set_blinking(long wait, long on, long off);
    void
gui_mch_set_fg_color(guicolor_T color);
    void
gui_mch_set_foreground(void);
    void
gui_mch_set_scrollbar_pos(
	scrollbar_T *sb,
	int x,
	int y,
	int w,
	int h);
    void
gui_mch_set_scrollbar_thumb(
	scrollbar_T *sb,
	long val,
	long size,
	long max);
    void
gui_mch_set_shellsize(
    int		width,
    int		height,
    int		min_width,
    int		min_height,
    int		base_width,
    int		base_height,
    int		direction);
    void
gui_mch_resize_view();
    void
gui_mch_set_sp_color(guicolor_T color);
    void
gui_mch_set_text_area_pos(int x, int y, int w, int h);
    void
gui_mch_set_winpos(int x, int y);
    void
gui_mch_setmouse(int x, int y);
    void
gui_mch_settitle(char_u *title, char_u *icon);
    void
gui_mch_start_blink(void);
    void
gui_mch_stop_blink(int may_call_gui_update_cursor);
    void
gui_mch_toggle_tearoffs(int enable);
    void
mch_set_mouse_shape(int shape);
    void
gui_mch_def_colors();
    void
ex_macaction(exarg_T *eap);
    void
gui_make_popup(char_u *path_name, int mouse_pos);

void serverRegisterName(char_u *name);
int serverSendToVim(char_u *name, char_u *cmd, char_u **result, int *server, int asExpr, int timeout, int silent);
char_u *serverGetVimNames(void);
int serverStrToPort(char_u *str);
int serverPeekReply(int port, char_u **str);
int serverReadReply(int port, char_u **str);
int serverSendReply(char_u *serverid, char_u *str);

void gui_mch_enter_fullscreen(int fuoptions_flags, guicolor_T bg);
void gui_mch_leave_fullscreen(void);
void gui_mch_fuopt_update(void);

void gui_macvim_update_modified_flag();
void gui_macvim_add_to_find_pboard(char_u *pat);
void gui_macvim_set_antialias(int antialias);
void gui_macvim_set_ligatures(int ligatures);
void gui_macvim_set_thinstrokes(int thinStrokes);
void gui_macvim_set_blur(int blur);

int16_t odb_buffer_close(buf_T *buf);
int16_t odb_post_buffer_write(buf_T *buf);
void odb_end(void);

char_u *get_macaction_name(expand_T *xp, int idx);
int is_valid_macaction(char_u *action);

void gui_macvim_wait_for_startup();
void gui_macvim_get_window_layout(int *count, int *layout);

    void
gui_mch_find_dialog(exarg_T *eap);
    void
gui_mch_replace_dialog(exarg_T *eap);
    void
im_set_control(int enable);

    void *
gui_macvim_add_channel(channel_T *channel, ch_part_T part);
    void
gui_macvim_remove_channel(void *cookie);
    void
gui_macvim_cleanup_job_all(void);

    void
gui_mch_drawsign(int row, int col, int typenr);

    void *
gui_mch_register_sign(char_u *signfile);

    void
gui_mch_destroy_sign(void *sign);

void *gui_macvim_new_autoreleasepool();
void gui_macvim_release_autoreleasepool(void *pool);
