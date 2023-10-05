/* gui_xim.c */
char *did_set_imactivatefunc(optset_T *args);
char *did_set_imstatusfunc(optset_T *args);
void free_xim_stuff(void);
int set_ref_in_im_funcs(int copyID);
void im_set_active(int active);
void xim_set_focus(int focus);
void im_set_position(int row, int col);
void xim_set_preedit(void);
int im_get_feedback_attr(int col);
void xim_init(void);
void im_shutdown(void);
int im_xim_isvalid_imactivate(void);
void xim_reset(void);
int xim_queue_key_press_event(GdkEventKey *event, int down);
int im_get_status(void);
int preedit_get_status(void);
int im_is_preediting(void);
void xim_set_status_area(void);
int xim_get_status_area_height(void);

// MacVim
void call_imactivatefunc(int active);
int call_imstatusfunc(void);
void im_preedit_start_macvim(void);
void im_preedit_end_macvim(void);
void im_preedit_abandon_macvim(void);
void im_preedit_changed_macvim(char *preedit_string, int cursor_index);
/* vim: set ft=c : */
