" System gvimrc file for MacVim
" Author:	Björn Winckler
" Last Change:	Wed Aug  1 20:03:43 CEST 2007
"
" This is a work in progress.  If you feel so inclined, please help me improve
" this file.
"

"
" Extra menus
"

" File menu.

aunmenu File.New
aunmenu File.Close
aunmenu File.-SEP4-
aunmenu File.Exit
aunmenu File.Save-Exit

an <silent> 10.290 File.New\ Window         :action newVimWindow:<CR>
an 10.295 File.New\ Tab                     :tabnew<CR>
an 10.328 File.-SEP0-                       <Nop>
an <silent> 10.330 File.Close\ Window       :confirm qa<CR>
an 10.331 File.Close\ Tab                   :tabclose<CR>

an 20.460 Edit.-SEP4-                       <Nop>
an 20.470 Edit.Special\ Characters\.\.\.    :action orderFrontCharacterPalette:<CR>


" Try to make Window menu follow Apple HIG.
aunmenu Window

an <silent> 70.300 Window.Minimize          :action performMiniaturize:<CR>
an <silent> 70.310 Window.Zoom              :action performZoom:<CR>
an 70.320 Window.-SEP1-                     <Nop>
" TODO! Grey out if no tabs are visible.
an <silent> 70.330 Window.Previous\ Tab     :tabprevious<CR>
an <silent> 70.340 Window.Next\ Tab         :tabnext<CR>
an 70.350 Window.-SEP2-                     <Nop>
an <silent> 70.360 Window.Bring\ All\ To\ Front :action arrangeInFront:<CR>


"
" Keyboard mappings
"

" TODO: Do these mappings have to be this complicated?  Is it possible to have
" each tab 'remembering' which mode it was in?
"map <special><silent> <D-M-Right> :tabn<CR>
"imap <special><silent> <D-M-Right> <C-O>:tabn<CR>
"vmap <special><silent> <D-M-Right> <C-C>:tabn<CR><C-\><C-G>

"map <special><silent> <D-M-Left> :tabp<CR>
"imap <special><silent> <D-M-Left> <C-O>:tabp<CR>
"vmap <special><silent> <D-M-Left> <C-C>:tabp<CR><C-\><C-G>

map <special><silent> <S-D-Left> :action selectPreviousWindow:<CR>
imap <special><silent> <S-D-Left> <C-O>:action selectPreviousWindow:<CR>
vmap <special><silent> <S-D-Left> <C-C>:action selectPreviousWindow:<CR>

map <special><silent> <S-D-Right> :action selectNextWindow:<CR>
imap <special><silent> <S-D-Right> <C-O>:action selectNextWindow:<CR>
vmap <special><silent> <S-D-Right> <C-C>:action selectNextWindow:<CR>



"
" Menu key equivalents (these should always have the 'D' modifier set)
"

menukeyequiv File.New\ Window       <D-n>
menukeyequiv File.New\ Tab          <D-t>
menukeyequiv File.Close\ Tab        <D-w>

menukeyequiv File.Open\.\.\.        <D-o>
menukeyequiv File.Open\ Tab\.\.\.   <D-T>
"menukeyequiv File.New               <D-e>
menukeyequiv File.Close\ Window     <D-W>
menukeyequiv File.Save              <D-s>
menukeyequiv File.Save\ As\.\.\.    <D-S>
"menukeyequiv File.Exit              <D-W>
menukeyequiv File.Print             <D-p>

menukeyequiv Edit.Undo              <D-z>
menukeyequiv Edit.Redo              <D-Z>
menukeyequiv Edit.Cut               <D-x>
menukeyequiv Edit.Copy              <D-c>
menukeyequiv Edit.Paste             <D-v>
menukeyequiv Edit.Select\ All       <D-a>
menukeyequiv Edit.Special\ Characters\.\.\.    <D-M-t> 

menukeyequiv Tools.Make             <D-b>
menukeyequiv Tools.List\ Errors     <D-l>
menukeyequiv Tools.List\ Messages   <D-L>
menukeyequiv Tools.Next\ Error      <D-C-Right>
menukeyequiv Tools.Previous\ Error  <D-C-Left>

menukeyequiv Window.Minimize        <D-m>
"menukeyequiv Window.Zoom            <D-M>
menukeyequiv Window.Previous\ Tab   <D-M-Left>
menukeyequiv Window.Next\ Tab       <D-M-Right>
