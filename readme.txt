XVI 2.0 (pre-ALPHA) - Quick Help + Test Sheet (Commander X16)
 
This file is meant to be READ inside of XVI and als used as a TEST script.
Try the actions exactly as written and verify the result feels Vim-like.
 
------------------------------------------------------------------------
STARTUP
------------------------------------------------------------------------
 
Splash screen:
 
  :e         filename<Enter> Load a file
  <esc>R     New buffer in REPLACE mode
  <esc>i     New buffer in INSERT mode
 
Notes:
 
  - This editor is modal (like Vim)
  - Cursor is constrained to a fixed text box (no long lines yet).
 
------------------------------------------------------------------------
MODES
------------------------------------------------------------------------
 
NAV mode:
 
  - i insert before cursor (Vim-like)
  - a append after cursor (Vim-like)
  - Text shifts right as you type.
  - Backspace deletes to the left within the line.
 
REPLACE mode:
 
  - R replace characters under the cursor.
  - Typed characters overwrite existing text.
  - Backspace moves lef without inserting junk.
 
Status indicator:
 
"-- INSERT --" or "-- REPLACE --" appears on screen.
 
------------------------------------------------------------------------
NAVIGATION
------------------------------------------------------------------------

Movement:
 
 h left
 j down
 k up
 l right
 
Line movement:
 
 ^ jump to start of line
 $ jump to end of visible text
 g jump to top of document
 G jump to bottom of document
 
Paging:
 
 Ctrl+F page forward
 Ctrl+B page backward
 
Redraw:
 
 L redraw the screen
 
------------------------------------------------------------------------
EDITING (NAV mode)
------------------------------------------------------------------------
 
Single character:
 
  rX replace character under cursor with X
  x  delete character under cursor
 
Line:
 
  yy yank (copy) current line
  dd delete current line
  p  paste below (lower case)
  P  paste above (upper case)
 
Insert lines:
 
  o insert line below and entery edit
  O insert line above and enter edit
 
------------------------------------------------------------------------
COMMAND MODE
------------------------------------------------------------------------
 
Enter command mode:
 
  : (colon)
 
Quit:
 
  :q<Enter>  quit (refuses if UNSAVED)
  :q!<Enter> force quit
 
 
Write/save:
 
  :w<Enter>           save to current filename
  :w filename<Enter>  save as filename
  :w! filename<Enter> overwrite filename
 
Edit/open
 
  :e filename<Enter> load file
  :e<Enter>          new file buffer
 
 
IMPORTANT:
 
  New buffers have no filename
  Use :w filename to save them
 
 
------------------------------------------------------------------------
CHARACTER NOTES
------------------------------------------------------------------------
 
This editor currently accepts printable ISO ASCIIOnly:
 
  Character codes 32..126
 
Double-quote handling:
 
  This editor disables ROMquote-mode before outputting ".
 
If quotes or symboles behave strangely,report: ...
 
 - Mode (INSERT / REPLACE)
 - Keys typed
 - Emulator vs real hardware
 
