; This file contains the configuration of the screen size and the key definitions.

VIEW_HEIGHT:
    db 24
VIEW_WIDTH:
    db 80

; This is the key-definition table, that ties keystrokes to user actions.
; Each row shows the values that come from the keyboard, which can 
; be up to 8 hex values, followed by $00s, followed by the action itself.
; For example, on my keyboard, pressing Cursor-Up gives 1B 5B 41.
; You can change the key defs by editing here and re-assembling.
; Or you can use the JEDCONF.COM program to redefine the keys.
; JEDCONF makes a JED.KEY file, which JED uses to define the keys.
keytable: 
    db $0D, $00, $00, $00, $00, $00, $00, $00, $00, ENTER
    db $09, $00, $00, $00, $00, $00, $00, $00, $00, TAB
    db $7F, $00, $00, $00, $00, $00, $00, $00, $00, BACKSPACE
    db $1B, $5B, $33, $7E, $00, $00, $00, $00, $00, USER_DELETE
    db $1B, $5B, $41, $00, $00, $00, $00, $00, $00, USER_CURSOR_UP
    db $1B, $5B, $42, $00, $00, $00, $00, $00, $00, USER_CURSOR_DOWN
    db $1B, $5B, $44, $00, $00, $00, $00, $00, $00, USER_CURSOR_LEFT
    db $1B, $5B, $43, $00, $00, $00, $00, $00, $00, USER_CURSOR_RIGHT
    db $1B, $5B, $48, $00, $00, $00, $00, $00, $00, USER_CURSOR_HOME
    db $1B, $5B, $46, $00, $00, $00, $00, $00, $00, USER_CURSOR_END
    db $1B, $5B, $35, $7E, $00, $00, $00, $00, $00, USER_CURSOR_PGUP
    db $1B, $5B, $36, $7E, $00, $00, $00, $00, $00, USER_CURSOR_PGDN
    db $18, $00, $00, $00, $00, $00, $00, $00, $00, USER_QUIT
    db $19, $00, $00, $00, $00, $00, $00, $00, $00, USER_QUIT_NO_SAVE
    db $00