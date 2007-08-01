map <silent> <D-M-Right> :tabn<CR>
map <silent> <D-M-Left> :tabp<CR>

map <silent> <S-D-Left> :action selectPreviousWindow:<CR>
map <silent> <S-D-Right> :action selectNextWindow:<CR>

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
