#
# Common Makefile, defines the list of tests to run.
#

# Options for protecting the tests against undesirable interaction with the
# environment
NO_PLUGINS = --noplugin --not-a-term
NO_INITS = -U NONE $(NO_PLUGINS)

# File to delete when testing starts
CLEANUP_FILES = test.log messages starttime

# Tests for tiny build.
SCRIPTS_TINY = \
	test10 \
	test20 \
	test21 \
	test22 \
	test23 \
	test24 \
	test25 \
	test26 \
	test27 \
	test28

SCRIPTS_TINY_OUT = \
	test10.out \
	test20.out \
	test21.out \
	test22.out \
	test23.out \
	test24.out \
	test25.out \
	test26.out \
	test27.out \
	test28.out

# Tests for Vim9 script.
TEST_VIM9 = \
	test_vim9_assign \
	test_vim9_builtin \
	test_vim9_class \
	test_vim9_cmd \
	test_vim9_disassemble \
	test_vim9_enum \
	test_vim9_expr \
	test_vim9_fails \
	test_vim9_func \
	test_vim9_import \
	test_vim9_script \
	test_vim9_typealias

TEST_VIM9_RES = \
	test_vim9_assign.res \
	test_vim9_builtin.res \
	test_vim9_class.res \
	test_vim9_cmd.res \
	test_vim9_disassemble.res \
	test_vim9_enum.res \
	test_vim9_expr.res \
	test_vim9_fails.res \
	test_vim9_func.res \
	test_vim9_import.res \
	test_vim9_script.res \
	test_vim9_typealias.res

# Benchmark scripts.
SCRIPTS_BENCH = test_bench_regexp.res

# Individual tests, including the ones part of test_alot.
# Please keep sorted up to test_alot.
NEW_TESTS = \
	test_arabic \
	test_arglist \
	test_assert \
	test_autochdir \
	test_autocmd \
	test_autoload \
	test_backspace_opt \
	test_backup \
	test_balloon \
	test_balloon_gui \
	test_behave \
	test_blob \
	test_blockedit \
	test_breakindent \
	test_buffer \
	test_bufline \
	test_bufwintabinfo \
	test_cd \
	test_cdo \
	test_changedtick \
	test_changelist \
	test_channel \
	test_charsearch \
	test_charsearch_utf8 \
	test_checkpath \
	test_cindent \
	test_cjk_linebreak \
	test_clientserver \
	test_close_count \
	test_cmd_lists \
	test_cmdline \
	test_cmdmods \
	test_cmdwin \
	test_codestyle \
	test_command_count \
	test_comments \
	test_comparators \
	test_compiler \
	test_conceal \
	test_const \
	test_cpoptions \
	test_crash \
	test_crypt \
	test_cscope \
	test_cursor_func \
	test_cursorline \
	test_curswant \
	test_debugger \
	test_delete \
	test_diffmode \
	test_digraph \
	test_display \
	test_edit \
	test_environ \
	test_erasebackword \
	test_escaped_glob \
	test_eval_stuff \
	test_ex_equal \
	test_ex_mode \
	test_ex_undo \
	test_ex_z \
	test_excmd \
	test_exec_while_if \
	test_execute_func \
	test_exists \
	test_exists_autocmd \
	test_exit \
	test_expand \
	test_expand_dllpath \
	test_expand_func \
	test_expr \
	test_expr_utf8 \
	test_file_perm \
	test_file_size \
	test_filechanged \
	test_filecopy \
	test_fileformat \
	test_filetype \
	test_filter_cmd \
	test_filter_map \
	test_find_complete \
	test_findfile \
	test_fixeol \
	test_flatten \
	test_float_func \
	test_fnameescape \
	test_fnamemodify \
	test_fold \
	test_format \
	test_functions \
	test_function_lists \
	test_ga \
	test_getcwd \
	test_gettext \
	test_gettext_cp1251 \
	test_gettext_utf8 \
	test_gettext_make \
	test_getvar \
	test_gf \
	test_glob2regpat \
	test_global \
	test_gn \
	test_goto \
	test_gui \
	test_gui_init \
	test_hardcopy \
	test_help \
	test_help_tagjump \
	test_hide \
	test_highlight \
	test_history \
	test_hlsearch \
	test_iminsert \
	test_increment \
	test_increment_dbcs \
	test_indent \
	test_input \
	test_ins_complete \
	test_ins_complete_no_halt \
	test_interrupt \
	test_job_fails \
	test_join \
	test_json \
	test_jumplist \
	test_lambda \
	test_langmap \
	test_largefile \
	test_let \
	test_lineending \
	test_lispindent \
	test_listchars \
	test_listdict \
	test_listener \
	test_listlbr \
	test_listlbr_utf8 \
	test_lua \
	test_macvim \
	test_makeencoding \
	test_man \
	test_map_functions \
	test_mapping \
	test_marks \
	test_match \
	test_matchadd_conceal \
	test_matchadd_conceal_utf8 \
	test_matchfuzzy \
	test_matchparen \
	test_memory_usage \
	test_menu \
	test_messages \
	test_method \
	test_mksession \
	test_mksession_utf8 \
	test_modeless \
	test_modeline \
	test_move \
	test_mswin_event \
	test_mzscheme \
	test_nested_function \
	test_netbeans \
	test_normal \
	test_number \
	test_options \
	test_options_all \
	test_packadd \
	test_partial \
	test_paste \
	test_perl \
	test_plus_arg_edit \
	test_popup \
	test_popupwin \
	test_popupwin_textprop \
	test_preview \
	test_profile \
	test_prompt_buffer \
	test_put \
	test_python2 \
	test_python3 \
	test_pyx2 \
	test_pyx3 \
	test_quickfix \
	test_quotestar \
	test_random \
	test_recover \
	test_regex_char_classes \
	test_regexp_latin \
	test_regexp_utf8 \
	test_registers \
	test_reltime \
	test_remote \
	test_rename \
	test_restricted \
	test_retab \
	test_ruby \
	test_scriptnames \
	test_scroll_opt \
	test_scrollbind \
	test_search \
	test_search_stat \
	test_searchpos \
	test_selectmode \
	test_set \
	test_sha256 \
	test_shell \
	test_shift \
	test_shortpathname \
	test_signals \
	test_signs \
	test_sleep \
	test_smartindent \
	test_sort \
	test_sound \
	test_source \
	test_source_utf8 \
	test_spell \
	test_spell_utf8 \
	test_spellfile \
	test_spellrare \
	test_startup \
	test_startup_utf8 \
	test_stat \
	test_statusline \
	test_substitute \
	test_suspend \
	test_swap \
	test_syn_attr \
	test_syntax \
	test_system \
	test_tab \
	test_tabline \
	test_tabpage \
	test_tagcase \
	test_tagfunc \
	test_tagjump \
	test_taglist \
	test_tcl \
	test_termcodes \
	test_termdebug \
	test_termencoding \
	test_terminal \
	test_terminal2 \
	test_terminal3 \
	test_terminal_fail \
	test_textformat \
	test_textobjects \
	test_textprop \
	test_timers \
	test_tohtml \
	test_true_false \
	test_trycatch \
	test_undo \
	test_unlet \
	test_user_func \
	test_usercommands \
	test_utf8 \
	test_utf8_comparisons \
	test_vartabs \
	test_version \
	$(TEST_VIM9) \
	test_viminfo \
	test_vimscript \
	test_virtualedit \
	test_visual \
	test_winbar \
	test_winbuf_close \
	test_window_cmd \
	test_window_id \
	test_windows_home \
	test_winfixbuf \
	test_wnext \
	test_wordcount \
	test_writefile \
	test_xdg \
	test_xxd \
	test_zip_plugin \
	test_alot_latin \
	test_alot_utf8 \
	test_alot

# Test targets that use runtest.vim.
# Keep test_alot*.res as the last one, sort the others.
# test_largefile.res is omitted, it uses too much resources to run on CI.
NEW_TESTS_RES = \
	test_arabic.res \
	test_arglist.res \
	test_assert.res \
	test_autochdir.res \
	test_autocmd.res \
	test_autoload.res \
	test_backspace_opt.res \
	test_balloon.res \
	test_balloon_gui.res \
	test_blob.res \
	test_blockedit.res \
	test_breakindent.res \
	test_buffer.res \
	test_bufline.res \
	test_bufwintabinfo.res \
	test_cd.res \
	test_cdo.res \
	test_changedtick.res \
	test_changelist.res \
	test_channel.res \
	test_charsearch.res \
	test_checkpath.res \
	test_cindent.res \
	test_cjk_linebreak.res \
	test_clientserver.res \
	test_close_count.res \
	test_cmd_lists.res \
	test_cmdline.res \
	test_cmdmods.res \
	test_cmdwin.res \
	test_codestyle.res \
	test_command_count.res \
	test_comments.res \
	test_comparators.res \
	test_conceal.res \
	test_const.res \
	test_cpoptions.res \
	test_crash.res \
	test_crypt.res \
	test_cscope.res \
	test_cursor_func.res \
	test_cursorline.res \
	test_curswant.res \
	test_debugger.res \
	test_delete.res \
	test_diffmode.res \
	test_digraph.res \
	test_display.res \
	test_edit.res \
	test_environ.res \
	test_erasebackword.res \
	test_escaped_glob.res \
	test_eval_stuff.res \
	test_excmd.res \
	test_exec_while_if.res \
	test_execute_func.res \
	test_exists.res \
	test_exists_autocmd.res \
	test_exit.res \
	test_expr.res \
	test_file_size.res \
	test_filechanged.res \
	test_filecopy.res \
	test_fileformat.res \
	test_filetype.res \
	test_filter_cmd.res \
	test_filter_map.res \
	test_find_complete.res \
	test_findfile.res \
	test_fixeol.res \
	test_flatten.res \
	test_float_func.res \
	test_fnameescape.res \
	test_fold.res \
	test_functions.res \
	test_function_lists.res \
	test_getcwd.res \
	test_gettext.res \
	test_gettext_cp1251.res \
	test_gettext_utf8.res \
	test_gettext_make.res \
	test_getvar.res \
	test_gf.res \
	test_gn.res \
	test_goto.res \
	test_gui.res \
	test_gui_init.res \
	test_hardcopy.res \
	test_help.res \
	test_help_tagjump.res \
	test_hide.res \
	test_highlight.res \
	test_history.res \
	test_hlsearch.res \
	test_iminsert.res \
	test_increment.res \
	test_increment_dbcs.res \
	test_indent.res \
	test_input.res \
	test_ins_complete.res \
	test_ins_complete_no_halt.res \
	test_interrupt.res \
	test_job_fails.res \
	test_join.res \
	test_json.res \
	test_jumplist.res \
	test_lambda.res \
	test_langmap.res \
	test_let.res \
	test_lineending.res \
	test_lispindent.res \
	test_listchars.res \
	test_listdict.res \
	test_listener.res \
	test_listlbr.res \
	test_listlbr_utf8.res \
	test_lua.res \
	test_macvim.res \
	test_makeencoding.res \
	test_man.res \
	test_map_functions.res \
	test_mapping.res \
	test_marks.res \
	test_match.res \
	test_matchadd_conceal.res \
	test_matchadd_conceal_utf8.res \
	test_matchfuzzy.res \
	test_matchparen.res \
	test_memory_usage.res \
	test_menu.res \
	test_messages.res \
	test_method.res \
	test_mksession.res \
	test_modeless.res \
	test_modeline.res \
	test_mswin_event.res \
	test_mzscheme.res \
	test_nested_function.res \
	test_netbeans.res \
	test_normal.res \
	test_number.res \
	test_options.res \
	test_options_all.res \
	test_packadd.res \
	test_partial.res \
	test_paste.res \
	test_perl.res \
	test_plus_arg_edit.res \
	test_popup.res \
	test_popupwin.res \
	test_popupwin_textprop.res \
	test_preview.res \
	test_profile.res \
	test_prompt_buffer.res \
	test_python2.res \
	test_python3.res \
	test_pyx2.res \
	test_pyx3.res \
	test_quickfix.res \
	test_quotestar.res \
	test_random.res \
	test_recover.res \
	test_regex_char_classes.res \
	test_registers.res \
	test_remote.res \
	test_rename.res \
	test_restricted.res \
	test_retab.res \
	test_ruby.res \
	test_scriptnames.res \
	test_scroll_opt.res \
	test_scrollbind.res \
	test_search.res \
	test_search_stat.res \
	test_selectmode.res \
	test_shell.res \
	test_shortpathname.res \
	test_signals.res \
	test_signs.res \
	test_sleep.res \
	test_smartindent.res \
	test_sort.res \
	test_sound.res \
	test_source.res \
	test_spell.res \
	test_spell_utf8.res \
	test_spellfile.res \
	test_spellrare.res \
	test_startup.res \
	test_stat.res \
	test_statusline.res \
	test_substitute.res \
	test_suspend.res \
	test_swap.res \
	test_syn_attr.res \
	test_syntax.res \
	test_system.res \
	test_tab.res \
	test_tabpage.res \
	test_tagjump.res \
	test_taglist.res \
	test_tcl.res \
	test_termcodes.res \
	test_termdebug.res \
	test_termencoding.res \
	test_terminal.res \
	test_terminal2.res \
	test_terminal3.res \
	test_terminal_fail.res \
	test_textformat.res \
	test_textobjects.res \
	test_textprop.res \
	test_timers.res \
	test_tohtml.res \
	test_true_false.res \
	test_trycatch.res \
	test_undo.res \
	test_user_func.res \
	test_usercommands.res \
	test_vartabs.res \
	$(TEST_VIM9_RES) \
	test_viminfo.res \
	test_vimscript.res \
	test_virtualedit.res \
	test_visual.res \
	test_winbar.res \
	test_winbuf_close.res \
	test_window_cmd.res \
	test_window_id.res \
	test_windows_home.res \
	test_winfixbuf.res \
	test_wordcount.res \
	test_writefile.res \
	test_xdg.res \
	test_xxd.res \
	test_zip_plugin.res \
	test_alot_latin.res \
	test_alot_utf8.res \
	test_alot.res
