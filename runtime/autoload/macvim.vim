vim9script
# Support scripts for MacVim-specific functionality
# Maintainer:   Yee Cheng Chin (macvim-dev@macvim.org)
# Last Change:  2023-03-15

# Ask macOS to show the definition of the last selected text. Note that this
# uses '<, and therefore has to be used in normal mode where the mark has
# already been updated.
export def ShowDefinitionSelected()
  const sel_text = join(getregion(getpos("'<"), getpos("'>"), { type: visualmode(), exclusive: (&selection ==# "exclusive") }), "\n")
  if len(sel_text) > 0
    const sel_start = getpos("'<")
    const sel_screenpos = win_getid()->screenpos(sel_start[1], sel_start[2])
    showdefinition(sel_text, sel_screenpos)
  endif
enddef

# Ask macOS to show the definition of the word under the cursor.
export def ShowDefinitionUnderCursor()
  call search('\<', 'bc') # Go to the beginning of a word, so that showdefinition() will show the popup at the correct location.

  const text = expand('<cword>')
  if len(text) > 0
    showdefinition(text)
  endif
enddef

# Print functionality. We simply show the file in Preview and let the user
# decide what to do. This allows for more control instead of immediately
# piping the file to lpr which will actually print the file.
#
# PreviewConvertPostScript: 
#   Convert the provided PostScript file to PDF, then show in Preview. This is
#   necessary in macOS 13+ as Preview doesn't support .ps files anymore.
# PreviewPostScript:
#   Directly open PostScript file in Preview. Can use this if
#   PreviewConvertPostScript doesn't work.
export def PreviewConvertPostScript(deltimer = 10000): number
  # Convert PS to PDF because Preview can't use PS files in macOS 13+
  if executable('/usr/bin/pstopdf')
    system($"/usr/bin/pstopdf {v:fname_in} -o {v:fname_in}.pdf")
  else
    # Starting in macOS 14, pstopdf is no longer bundled. We just require the
    # user to install ps2pdf as it's the simplest solution for a relatively
    # niche feature today (printing).
    if executable('ps2pdf')
      system($"ps2pdf {v:fname_in} {v:fname_in}.pdf")
    else
      echoerr 'Cannot find ps2pdf. You can install it by installing Ghostscript. This is necessary in macOS 14+ for printing to work.'
      return 1
    endif
  endif
  if v:shell_error != 0
    return v:shell_error
  endif
  system($"open -a Preview {v:fname_in}.pdf")
  delete(v:fname_in)

  # Delete the file after it's opened in Preview for privacy. We don't have an
  # easy way to detect that Preview has opened the file already, so we just
  # use a generous 10 secs timer.
  # Note that we can't use `open -W` instead because 1) it will block
  # synchronously, and 2) it will only return if Preview.app has closed, which
  # may not happen for a while if it has other unrelated documents opened.
  var to_delete_file = $"{v:fname_in}.pdf"
  timer_start(deltimer, (timer) => delete(to_delete_file))

  return v:shell_error
enddef

export def PreviewPostScript(deltimer = 10000): number
  system($"open -a Preview {v:fname_in}")

  var to_delete_file = v:fname_in
  timer_start(deltimer, (timer) => delete(to_delete_file))

  return v:shell_error
enddef

# vim: set sw=2 ts=2 et :
