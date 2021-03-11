# jed

This is a text editor for CP/M v2.2

It is a "modern" text editor, in that it uses VT100 cursor keys, and Page Up, Page Down, Home, End, Backspace etc, rather than CP/M-style Ctrl-S, Ctrl-E keys!

It's only a prototype so far, but it supports this:

* You can start it with a filename, and it will load up that file: JED MYFILE.TXT
* You can start it with no filename, and it will make an empty doc: JED
* If you start with no filename it will ask for one when you exit.
* You can navigate around with the normal arrow keys.
* You can press <kbd>Home</kbd> to go to the first non-space character in a row, or the start of the line.
* You can press <kbd>End</kbd> to go to the end of the row.
* You can press <kbd>PAGE-UP</kbd> and <kbd>PAGE-DOWN</kbd> to go up and down by a page.
* You can press <kbd>Ctrl</kbd> + <kbd>X</kbd> to exit.

There is also a configuration program, JEDCONF.COM, which configures the screen dimensions, and the key definitions. Run JEDCONF first to define all your keys and set your screen height and width. This will create a file JED.CFG with the configuration in it, which JED will then use. Each key, such as Page-Up can be associated with a string of up to 8 hex values, so just about any keyboard should work with it.

