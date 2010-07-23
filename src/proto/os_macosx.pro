/* os_macosx.pro */
/* functions in os_macosx.m */

#if defined(FEAT_CLIPBOARD) && !defined(FEAT_GUI)
void clip_mch_lose_selection(VimClipboard *cbd);
int clip_mch_own_selection(VimClipboard *cbd);
void clip_mch_request_selection(VimClipboard *cbd);
void clip_mch_set_selection(VimClipboard *cbd);
#endif

void macosx_fork __ARGS((void));

/* vim: set ft=c : */
