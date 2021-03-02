# jed

This is a text editor for CP/M v2.2

It is a "modern" text editor, in that it uses VT100 cursor keys, and Page Up, Page Down, Home, End, Backspace etc, rather than CP/M-style Ctrl-S, Ctrl-E keys!

It's only a prototype so far, but it supports this:

* You can start it with a filename, and it will load up that file: JED MYFILE.TXT
* You can start it with no filename, and it will make an empty doc: JED
* If you start with no filename it will ask for one when you exit.
* You can navigate around with the normal arrow keys.
* You can press <kdb>Home</kbd> to go to the first non-space character in a row, or the start of the line.
* You can press <kdb>End</kdb> to go to the end of the row.
* You can press <kdb>PAGE-UP</kdb> and <kdb>PAGE-DOWN</kdb> to go up and down by a page.
* You can press <kdb>Ctrl</kdb> + <kdb>X</kdb> to exit.

Note that the editor is fixed to 80 cols by 20 rows at present.

