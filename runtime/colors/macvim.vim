" MacVim colorscheme
"
" Maintainer:   Björn Winckler <bjorn.winckler@gmail.com>
" Last Change:  2007 Sep 22
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
hi StatusLine   gui=NONE guifg=white guibg=Black
hi StatusLineNC gui=NONE guifg=Gray95 guibg=SlateGray
hi VertSplit    gui=NONE guifg=SlateGray guibg=Gray
hi DiffText     gui=bold guibg=firebrick2
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
hi Question     gui=bold guifg=chartreuse4
hi Search       guibg=cadetblue1 guifg=NONE
hi SpellBad     guisp=firebrick2 gui=undercurl
hi SpellCap     guisp=blue gui=undercurl
hi SpellRare    guisp=Magenta gui=undercurl
hi SpellLocal   guisp=DarkCyan gui=undercurl
hi Pmenu        guibg=Cornsilk
hi PmenuSel     guifg=White guibg=goldenrod2
hi SpecialKey   guifg=Blue
hi Title        gui=bold guifg=DeepSkyBlue3
hi WarningMsg   guifg=firebrick2
hi WildMenu     guibg=SkyBlue guifg=Black
hi Folded       guibg=#E6E6E6 guifg=DarkBlue
hi FoldColumn   guibg=Grey guifg=DarkBlue
hi SignColumn   guibg=Grey guifg=DarkBlue
hi Visual       guibg=MacSelectedTextBackgroundColor
hi DiffAdd      guibg=LightBlue
hi DiffChange   guibg=DarkSlateBlue
hi DiffDelete   gui=bold guifg=black guibg=SpringGreen4
hi TabLine      gui=underline guibg=LightGrey
hi CursorColumn guibg=#F1F5FA
hi CursorLine   guibg=#F1F5FA   "Data browser list view secondary color
hi MatchParen   guifg=white guibg=DeepPink4
hi Normal       gui=NONE


" Syntax items (`:he group-name` -- more groups are available, these are just
" the top level syntax items for now).

hi Comment gui=italic guifg=blue2 guibg=NONE
hi Constant gui=NONE guifg=magenta1 guibg=NONE
hi String gui=NONE guifg=SkyBlue4 guibg=NONE
hi Boolean gui=NONE guifg=red3 guibg=NONE
hi Identifier gui=NONE guifg=aquamarine4 guibg=NONE
hi Statement gui=bold guifg=maroon guibg=NONE
hi PreProc gui=NONE guifg=DodgerBlue3 guibg=NONE
hi Type gui=bold guifg=green4 guibg=NONE
hi Special  gui=NONE guifg=BlueViolet guibg=NONE
hi Underlined gui=underline guifg=SteelBlue1
hi Ignore gui=NONE guifg=bg guibg=NONE
hi Error gui=NONE guifg=White guibg=firebrick3
hi Todo gui=NONE guifg=White guibg=magenta3

" vim: sw=2
