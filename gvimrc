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

an <silent> 10.290 File.New\ Vim\ Window    :action newVimWindow:<CR>
an 10.300 File.-SEP0-                       <Nop>
an 10.326 File.New\ Tab                     :tabnew<CR>
an 10.331 File.Close\ Tab                   :tabclose<CR>


"
" Keyboard mappings
"

map <silent> <D-M-Right> :tabn<CR>
map <silent> <D-M-Left> :tabp<CR>

map <silent> <S-D-Left> :action selectPreviousWindow:<CR>
map <silent> <S-D-Right> :action selectNextWindow:<CR>



"
" Menu key equivalents (these should always have the 'D' modifier set)
"

menukeyequiv File.New\ Vim\ Window  <D-n>
menukeyequiv File.New\ Tab          <D-t>
menukeyequiv File.Close\ Tab        <D-w>

menukeyequiv File.Open\.\.\.        <D-o>
menukeyequiv File.Open\ Tab\.\.\.   <D-T>
"menukeyequiv File.New               <D-e>
"menukeyequiv File.Close             <D-w>
menukeyequiv File.Save              <D-s>
menukeyequiv File.Save\ As\.\.\.    <D-S>
menukeyequiv File.Exit              <D-W>

menukeyequiv Edit.Undo              <D-z>
menukeyequiv Edit.Redo              <D-Z>
menukeyequiv Edit.Cut               <D-x>
menukeyequiv Edit.Copy              <D-c>
menukeyequiv Edit.Paste             <D-v>
menukeyequiv Edit.Select\ All       <D-a>

menukeyequiv Tools.Make             <D-b>
menukeyequiv Tools.List\ Errors     <D-l>
menukeyequiv Tools.List\ Messages   <D-L>
menukeyequiv Tools.Next\ Error      <D-C-Right>
menukeyequiv Tools.Previous\ Error  <D-C-Left>
