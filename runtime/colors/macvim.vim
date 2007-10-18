" MacVim colorscheme
"
" Maintainer:   Bjorn Winckler <bjorn.winckler@gmail.com>
" Last Change:  2007 Oct 11
"


" Tell vim that this is a light color scheme:
set background=light
highlight clear

" Reset String -> Constant links etc if they were reset
if exists("syntax_on")
  syntax reset
endif

let colors_name = "macvim"

" `:he highlight-groups`
hi ErrorMsg     guibg=Firebrick2 guifg=White
hi IncSearch    gui=reverse
hi ModeMsg      gui=bold
hi NonText      gui=bold guifg=Blue
hi StatusLine   gui=NONE guifg=White guibg=DarkSlateGray
hi StatusLineNC gui=NONE guifg=SlateGray guibg=Gray90
hi VertSplit    gui=NONE guifg=DarkSlateGray guibg=Gray90
hi DiffText     gui=NONE guibg=VioletRed
hi PmenuThumb   gui=reverse
hi PmenuSbar    guibg=Grey
hi TabLineSel   gui=bold
hi TabLineFill  gui=reverse
hi Cursor       guibg=fg guifg=bg
hi CursorIM     guibg=fg guifg=bg
hi lCursor      guibg=fg guifg=bg


hi Directory    guifg=#1600FF
hi LineNr       guifg=#888888 guibg=#E6E6E6
hi MoreMsg      gui=bold guifg=SeaGreen4
hi Question     gui=bold guifg=Chartreuse4
hi Search       guibg=CadetBlue1 guifg=NONE
hi SpellBad     guisp=Firebrick2 gui=undercurl
hi SpellCap     guisp=Blue gui=undercurl
hi SpellRare    guisp=Magenta gui=undercurl
hi SpellLocal   guisp=DarkCyan gui=undercurl
hi Pmenu        guibg=LightSteelBlue1
hi PmenuSel     guifg=White guibg=SkyBlue4
hi SpecialKey   guifg=Blue
hi Title        gui=bold guifg=DeepSkyBlue3
hi WarningMsg   guifg=Firebrick2
hi WildMenu     guibg=SkyBlue guifg=Black
hi Folded       guibg=#E6E6E6 guifg=DarkBlue
hi FoldColumn   guibg=Grey guifg=DarkBlue
hi SignColumn   guibg=Grey guifg=DarkBlue
hi Visual       guibg=MacSelectedTextBackgroundColor
hi DiffAdd      guibg=MediumSeaGreen
hi DiffChange   guibg=DeepSkyBlue
hi DiffDelete   gui=bold guifg=Black guibg=SlateBlue
hi TabLine      gui=underline guibg=LightGrey
hi CursorColumn guibg=#F1F5FA
hi CursorLine   guibg=#F1F5FA   "Data browser list view secondary color
hi MatchParen   guifg=White guibg=MediumPurple1
hi Normal       gui=NONE guifg=MacTextColor guibg=MacTextBackgroundColor


" Syntax items (`:he group-name` -- more groups are available, these are just
" the top level syntax items for now).

hi Comment gui=italic guifg=Blue2 guibg=NONE
hi Constant gui=NONE guifg=Magenta1 guibg=NONE
hi String gui=NONE guifg=SkyBlue4 guibg=NONE
hi Boolean gui=NONE guifg=Red3 guibg=NONE
hi Identifier gui=NONE guifg=Aquamarine4 guibg=NONE
hi Statement gui=bold guifg=Maroon guibg=NONE
hi PreProc gui=NONE guifg=DodgerBlue3 guibg=NONE
hi Type gui=bold guifg=Green4 guibg=NONE
hi Special  gui=NONE guifg=BlueViolet guibg=NONE
hi Underlined gui=underline guifg=SteelBlue1
hi Ignore gui=NONE guifg=bg guibg=NONE
hi Error gui=NONE guifg=White guibg=Firebrick3
hi Todo gui=NONE guifg=DarkGreen guibg=PaleGreen1


" Change the selection color on focus change (but only if the "macvim"
" colorscheme is active).
if !exists("s:augroups_defined")
  au FocusLost * if colors_name == "macvim" | hi Visual guibg=MacSecondarySelectedControlColor | endif
  au FocusGained * if colors_name == "macvim" | hi Visual guibg=MacSelectedTextBackgroundColor | endif

  let s:augroups_defined = 1
endif

" vim: sw=2
