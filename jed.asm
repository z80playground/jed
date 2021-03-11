; This is JED.COM the text editor.
; The max file length is 65535 lines.
; The max line length is 255 chars.
; The whole file needs to fit in memory, so you can't edit a file bigger than that.
; When you load a file it is arranged like this... (The [] are control chars)
;
; [START_OF_TEXT]
; line one[EOL]
; line two goes here[EOL]
; [EOL]
; previous line was blank[END_OF_TEXT]
;
; We keep track of the number of lines in the doc in the variable doc_lines.
; No lines wrap, so doc_lines = total lines in the editor.
;
; There is a cursor that can move around inside the document.
; Top-most location is 0,0.
; There is also a doc_pointer that points to the current char that the cursor is on.
;
; The current view of the document is displayed on the screen in
; an area VIEW_WIDTH x VIEW_HEIGHT.
;
; The keys that can be used in this editor are:
; Any letter/number/symbol in the range ASCII 33 to 128
; ENTER
; TAB
; <BACKSPACE, i.e. Rubout backwards.
; DEL, i.e. Forward delete.
; Cursor keys: Arrow Up, Arrow Down, Arrow Left, Arrow Right.
; Home, moves to first non-blank character in the line, then to the start of the line.
; End, moves to the end of the current line.
; Page Up, moves up a page.
; Page Down, moves down a page.
; Ctrl-X, saves and exits.
;
; The keys are configurable by the program JEDCONF.COM,
; which writes a file called JED.KEY.
; When JED.COM starts it reads in JED.KEY to define the keys.
; These keys over-write the keytable below.
; If no JED.KEY file is present, the default keys are used.

    org $0100

    jp main_program

include "keytable.asm"
include "version.asm"

main_program:
    ; Load a file into ram
    ; We need to know the start and end of the ram space
    ; Start is the end of this code+1
    ; End is BDOS-1

    ; Set the stack to point to our local stack
    ld sp, stacktop

    ; Read in JED.KEY if it exists
    call read_jed_keys

    ; reset screen position and cursor pos
    ld hl, 0
    ld (screen_top), hl
    xor a
    ld (screen_left), a

    ld (cursor_y), hl
    ld (cursor_x), a

    ; Find address of BDOS, minus 1, which is the end of ram, and store it
    ld hl, (6)
    dec hl
    ld (ram_end), hl

    ; Find address of the start of useable ram and store it
    ld hl, end_of_code
    inc hl
    ld (hl), START_OF_TEXT            ; Put the START OF TEXT terminator before the file
    inc hl
    ld (hl), END_OF_TEXT              ; Put the END OF TEXT terminator after the (blank) file
    ld (doc_start), hl
    ld (doc_pointer), hl

    call find_address_of_bios

    ; Clear the doc area
    call clear_selection
    call clear_doc_lines
    ld hl, (doc_start)
    ld (doc_pointer), hl
    ld (doc_end), hl

    call clear_keybuff

    call was_filename_provided
    call z, load_file

    call show_screen
main_loop:
    call show_screen_if_scrolled
    ;call show_cursor_coords
main_loop_no_scroll_change:
    ;call show_current_char
    call set_cursor_position
main_loop_get_key:
    call get_user_action
    or a
    jr z, main_loop_get_key
    cp BACKSPACE
    jp z, backspace_pressed
    cp USER_DELETE
    jr z, delete_pressed
    cp ENTER
    jp z, insert_char
    cp 127
    jp c, insert_char
    cp USER_QUIT
    jp z, save_and_exit
    cp USER_CURSOR_RIGHT
    jp z, cursor_right
    cp USER_CURSOR_LEFT
    jp z, cursor_left
    cp USER_CURSOR_UP
    jp z, cursor_up
    cp USER_CURSOR_DOWN
    jp z, cursor_down
    cp USER_CURSOR_HOME
    jp z, cursor_home
    cp USER_CURSOR_END
    jp z, cursor_end
    cp USER_CURSOR_PGUP
    jp z, cursor_page_up
    cp USER_CURSOR_PGDN
    jp z, cursor_page_down
    jp main_loop

was_filename_provided:
    ; Returns Z if a filename was provided by CP/M in the FCB
    ld hl, FCB+1
    ld a, (hl)
    cp ' '
    jp nz, return_Z
    jp return_NZ

delete_pressed:
    ; User has pressed forward "delete".
    ; Not allowed if right at end of doc...
    xor a
    ld (need_to_redraw_screen), a
    ld hl, (doc_pointer)
    ld a, (hl)
    cp END_OF_TEXT
    jr z, main_loop

    ; Did we just delete into the next line?
    cp EOL
    jr nz, normal_delete

join_with_next_line:
    ; Deleting into the next line.
    ; If this would result in a line > 255 long, don't allow it.
    ld hl, (doc_pointer)
    call skip_to_start_of_line
    call get_line_length
    ld d, a
    call skip_to_start_of_next_line
    call get_line_length
    add a, d
    jp c, main_loop
    ; document shrinks by one line
    ld hl, (doc_lines)
    dec hl
    ld (doc_lines), hl

    ; Force screen redraw later....
    ld a, 1
    ld (need_to_redraw_screen), a

normal_delete:
    ; Move everything in memory from current pos down by one.
    ld hl, (doc_end)
    ld de, (doc_pointer)
    or a                                ; clear carry
    sbc hl, de                          
    ld b, h
    ld c, l                             ; BC = size of doc beyond this point

    ; Shorten the doc by one byte
    ld hl, (doc_end)
    dec hl
    ld (doc_end), hl

    ; Copy down the remaining doc by 1 byte
    ld hl, (doc_pointer)
    ld e, l
    ld d, h
    inc hl
    ;inc bc do we need this???
    ldir                                

    ld a, (need_to_redraw_screen)
    or a
    jp nz, need_to_redraw

    ; Redraw the current row
    call show_current_line
    jp main_loop

backspace_pressed:
    ; User has pressed "< BACKSPACE"
    ; Not allowed if right at start of doc...
    xor a
    ld (need_to_redraw_screen), a
    ld hl, (doc_pointer)
    dec hl
    ld a, (hl)
    cp START_OF_TEXT
    jp z, main_loop

    ; Did we just backspace into the previous line?
    cp EOL
    jr nz, normal_backspace

join_with_previous_line:
    ; Deleting into the previous line.
    ; If this would result in a line > 255 long, don't allow it.
    ld hl, (doc_pointer)
    call get_line_length
    ld d, a
    dec hl
    call skip_to_start_of_line
    call get_line_length
    add a, d
    jp c, main_loop
join_with_previous_line1:
    ; document shrinks by one line
    ld hl, (doc_lines)
    dec hl
    ld (doc_lines), hl

    ; Work out where the cursor will be
    ld hl, (doc_pointer)
    dec hl
    call skip_to_start_of_line
    ld a, 255
    call skip_cols                  ; go to end of previous line
    ld a, c
    ld (cursor_x), a

    ; move cursor up
    ld hl, (cursor_y)
    dec hl
    ld (cursor_y), hl
    
    ;Force screen redraw later....
    ld a, 1
    ld (need_to_redraw_screen), a
    jr backspace_pressed1

normal_backspace:
    ; Work out where the cursor will be after this deletion
    call skip_to_start_of_line
    ld a, (cursor_x)
    dec a
    call skip_cols
    ld a, c
    ld (cursor_x), a

backspace_pressed1:
    ; Move everything in memory from current pos down by one.
    ld hl, (doc_end)
    ld de, (doc_pointer)
    or a                                ; clear carry
    sbc hl, de                          
    ld b, h
    ld c, l                             ; BC = size of doc beyond this point

    ; Shorten the doc by one byte
    ld hl, (doc_end)
    dec hl
    ld (doc_end), hl

    ; Copy down the remaining doc by 1 byte
    ld hl, (doc_pointer)
    dec hl
    ld (doc_pointer), hl
    inc hl
    ld e, l
    ld d, h
    dec de
    inc bc
    ldir                                

    ld a, (need_to_redraw_screen)
    or a
    jr nz, need_to_redraw

    ; Redraw the current row
    call show_current_line
    jp main_loop

need_to_redraw:
    call show_screen
    jp main_loop    

insert_char:
    ; Char to insert is in A
    ; Work out if there is enough memory free to insert a char.
    ld hl, (ram_end)
    ld de, (doc_end)
    or a                                ; clear carry
    sbc hl, de
    jp c, out_of_memory

    ; Check length of current line. If it is 255 we cannot allow any more, unless we are pressing ENTER!
    cp ENTER
    jr z, insert_char1
    ld d, a
    ld hl, (doc_pointer)
    call skip_to_start_of_line
    call get_line_length
    cp 255
    jp z, main_loop
    ld a, d

insert_char1:
    ; Move everything from current pos up by one.
    ld hl, (doc_end)
    ld de, (doc_pointer)
    or a                                ; clear carry
    sbc hl, de                          
    ld b, h
    ld c, l                             ; BC = size of doc beyond this point

    ld hl, (doc_end)
    ld e, l
    ld d, h
    inc de
    inc bc
    lddr                                ; Copy up the remaining doc by 1 byte

    ; Add the current char.
    ld hl, (doc_end)
    inc hl
    ld (doc_end), hl

    ld hl, (doc_pointer)
    ld (hl), a
    inc hl
    ld (doc_pointer), hl

    ; Was the key the ENTER / return key??
    cp ENTER
    jr z, enter_pressed

    cp TAB
    jr z, tab_pressed

    ld a, (cursor_x)
    inc a
    ld (cursor_x), a

    ; Redraw the current row
    call show_current_line

    jp main_loop

tab_pressed:
    ; User has pressed the TAB key.
    ; The cursor may move right 4, 3, 2 or 1 char.
    ld a, (cursor_x)
    ld b, a
tab_pressed1:
    inc a
    inc b
    and TAB_MASK
    or a
    jr nz, tab_pressed1
    ld a, b
    ld (cursor_x), a
    call show_current_line
    jp main_loop

enter_pressed:
    ; User has pressed ENTER / return
    ; It is like they are inserting a character.
    ; But the character splits the lines up.
    ld hl, (doc_lines)
    inc hl
    ld (doc_lines), hl

    ld hl, (cursor_y)
    inc hl
    ld (cursor_y), hl

    ld a, 0
    ld (cursor_x), a
    
    call show_screen

    jp main_loop

show_current_line:
    ; Show the current line again because it has changed
    ; Move screen draw position to start of current line
    call hide_cursor
    ld hl, (cursor_y)
    ld de, (screen_top)
    or a
    sbc hl, de          ; y coord is in l
    ld b, l             ; y coord is now in b
    inc b               ; adjust because VT100 screen coords start at 1, but we start at 0
    ld c, 1             ; x coord is in c
    call move_to_xy

    ; Now redraw the row
    ld hl, (doc_pointer)
    call skip_to_start_of_line
    ld a, (screen_left)
    ld (current_col), a                 ; Keep track of the current column we are displaying
    call skip_cols
    ld a, (VIEW_WIDTH)                     ; b = cols left to Show
    ld b, a
show_current_line1:
    ld a, (hl)
    cp END_OF_TEXT
    jp z, show_current_line2
    cp EOL 
    jp z, show_current_line2
    cp TAB
    jp z, show_current_line_tab
    call print_a
    ld a, (current_col)
    inc a
    ld (current_col), a
    inc hl
    djnz show_current_line1
    jr show_current_line_done
show_current_line2:
    ; Fill remainer of row with spaces
    ld a, ' '
    call print_a
    djnz show_current_line2
    jr show_current_line_done
show_current_line_tab:
    ld c, b
    ld a, (current_col)
    and TAB_MASK
    ld b, a
    ld a, TAB_WIDTH
    sub b
    ld b, a                 ; b stores how long a tab is
show_current_line_tab1:
    ld a, ' '               ; show a tab
    call print_a
    dec c
    ld a, (current_col)
    inc a
    ld (current_col), a
    djnz show_current_line_tab1
    inc hl
    ld b, c
    djnz show_current_line1
show_current_line_done:
    call show_cursor
    ret

out_of_memory:
    ld de, out_of_memory_message
    call show_string_de
    jp exit
out_of_memory_message:
    db 'Out of memory!',13,10,'$'

show_screen_if_scrolled:
    ; If the cursor is still on the screen then do nothing.
    ; If it has moved off the edge, re-position the screen to bring it back on.

    ld b, 0 ; b <> 0 if we need to redraw the screen

    ; Has cursor gone off the left side?
    ; If cursor_x < screen_left then screen_left = cursor_x, redraw
    ld a, (screen_left)
    ld e, a
    ld a, (cursor_x)
    cp e
    jr nc, show_screen_if_scrolled1
    ld (screen_left), a
    ld b, 'L'
    jr show_screen_if_scrolled2
show_screen_if_scrolled1:
    ; Has cursor gone off right side?
    ; If cursor_x >= screen_left + PAGE_WIDTH then screen_left = (cursor_x - PAGE_WIDTH) + 1, redraw
    ld a, (screen_left)
    ld e, a
    ld a, (VIEW_WIDTH)
    add a, e
    ld e, a
    ld a, (cursor_x)
    cp e
    jr c, show_screen_if_scrolled2
    ld e, a
    ld a, (VIEW_WIDTH)
    ld d, a
    ld a, e
    sub d
    inc a
    ld (screen_left), a
    ld b, 'R'
show_screen_if_scrolled2:    
    ; Has cursor gone off top?
    ; If cursor_y < screen_top then screen_top = cursor_y, redraw
    ld hl, (cursor_y)
    ld de, (screen_top)
    or a                                ; clear carry
    sbc hl, de
    jr nc, show_screen_if_scrolled3
    ld hl, (cursor_y)
    ld (screen_top), hl
    ld b, 'T'
    jr show_screen_if_scrolled4
show_screen_if_scrolled3:    
    ; Has cursor gone off bottom?
    ; If cursor_y >= screen_top + PAGE_HEIGHT then screen_top = (cursor_y - PAGE_HEIGHT) + 1, redraw
    ld hl, (screen_top)
    ld a, (VIEW_HEIGHT)
    ld e, a
    dec e
    ld d, 0
    add hl, de
    ld de, (cursor_y)
    or a                                ; clear carry
    sbc hl, de
    jr nc, show_screen_if_scrolled4
    ld hl, (cursor_y)
    ld d, 0
    ld a, (VIEW_HEIGHT)
    ld e, a
    or a                                ; clear carry
    sbc hl, de
    inc hl
    ld (screen_top), hl
    ld b, 'B'
show_screen_if_scrolled4:
    ld a, b
    or a
    ret z
    call show_screen
    ret

cursor_down:
    ld hl, (cursor_y)
    ld de, (doc_lines)
    or a                                ; clear carry
    sbc hl, de
    jp nc, main_loop                    ; We're at the bottom, so can't go any further down.
    ; Yes we can move down
    ld hl, (cursor_y)
    inc hl
    ld (cursor_y), hl
    ; Update the doc_pointer and cursor_x
    ld hl, (doc_pointer)
    call skip_to_start_of_next_line
    ld a, (cursor_x)
    call skip_cols
    ld (doc_pointer), hl
    ld a, c
    ld (cursor_x), a
    jp main_loop

cursor_up:
    ld hl, (cursor_y)
    ld a, l
    or h
    jp z, main_loop
    dec hl
    ld (cursor_y), hl
    ; Update the doc_pointer and cursor_x
    ld hl, (doc_pointer)
    call skip_to_start_of_previous_line
    ld a, (cursor_x)
    call skip_cols
    ld (doc_pointer), hl
    ld a, c
    ld (cursor_x), a
    jp main_loop

cursor_left:
    ; Move the cursor left...
    ; Is cursor already at the start of the doc?
    ld hl, (doc_pointer)
    dec hl
    ld a, (hl)
    cp START_OF_TEXT
    jp z, main_loop                 ; abort if at start of doc

    ld a, (cursor_x)
    dec a
    ld (cursor_x), a

    ld a, (hl)
    cp EOL                          ; Are we wrapping back onto previous row?
    jr z, cursor_left_wrap 
    cp TAB                          ; Have we moved onto a tab?
    jr z, cursor_left_tab
    ; Normal cursor left....
    ld (doc_pointer), hl
    jp main_loop
cursor_left_wrap:
    ; Cursor has gone off the left of line x onto end of line x-1
    call skip_to_start_of_line
    ld a, 255
    call skip_cols
    ld (doc_pointer), hl
    ld a, c
    ld (cursor_x), a                ; Set cursor to end of line
    ld a, (cursor_y)
    dec a
    ld (cursor_y), a
    jp main_loop
cursor_left_tab:
    ; If we hit a tab recalulate the cursor_x position by going to the start of the line
    ; and counting along again.
    call skip_to_start_of_line
    ld a, (cursor_x)
    call skip_cols
    ld (doc_pointer), hl
    ld a, c
    ld (cursor_x), a
    jp main_loop

cursor_right:
    ; Move to the right...
    ; If we are at the end of the file, we can't go right
    ld hl, (doc_pointer)
    ld a, (hl)
    cp END_OF_TEXT
    jp z, main_loop

    ld a, (cursor_x)                ; Move one space right
    inc a
    ld (cursor_x), a
    ld hl, (doc_pointer)
    ld a, (hl)
    inc hl
    ld (doc_pointer), hl
    cp EOL                          ; but if we were on a CR, wrap to next line
    jr z, cursor_right_wrap
    cp TAB
    jr z, cursor_right_tab          ; And if we were on a tab, move extra spaces if needed
    jp main_loop
cursor_right_wrap:
    ; Cursor has gone off the end of line x onto start of line x+1
    xor a
    ld (cursor_x), a                ; Set cursor to start of line
    ld a, (cursor_y)
    inc a
    ld (cursor_y), a                ; On next line
    jp main_loop
cursor_right_tab:
    ld a, (cursor_x)                ; For TAB, we need to end up on a mod-4 boundary
    and TAB_MASK
    jp z, main_loop
    ld a, (cursor_x)
    inc a
    ld (cursor_x), a
    jr cursor_right_tab

cursor_home:
    ; Move cursor to start of the line.
    ; If cursor_x is 0 then do nothing.
    ; Move cursor_x left to either the first non-space char, or 0.
    ld a, (cursor_x)
    or a
    jp z, main_loop
    ; Check location of first non-space char on this line
    ld hl, (doc_pointer)
    call skip_to_start_of_line
    call skip_spaces                            ; col into into c, pointer into hl
    ld a, (cursor_x)
    cp c                                        ; is the first non-space where we already are?
    jr c, cursor_home_start_of_line             ; If so, go to the start of the line
    jr z, cursor_home_start_of_line
    ; Move to first non-space
    ld a, c
    ld (doc_pointer), hl
    ld (cursor_x), a
    jp main_loop
cursor_home_start_of_line:
    call skip_to_start_of_line
    ld (doc_pointer), hl
    xor a
    ld (cursor_x), a
    jp main_loop

cursor_end:
    ; Move cursor to the end of the current line.
    ld hl, (doc_pointer)
    call skip_to_start_of_line
    ld a, 255
    call skip_cols
    ld (doc_pointer), hl
    ld a, c
    ld (cursor_x), a
    jp main_loop

cursor_page_down:
    ; Move the cursor down VIEW_HEIGHT-1 rows
    ld hl, (cursor_y)
    ld de, (doc_lines)
    or a                                ; clear carry
    sbc hl, de
    jp nc, main_loop                    ; We're at the bottom, so can't go any further down.

    ld a, (VIEW_HEIGHT)
    ld b, a
    dec b
cursor_page_down_loop:
    ld hl, (cursor_y)
    ld de, (doc_lines)
    or a                                ; clear carry
    sbc hl, de
    jp nc, cursor_page_down_stop
    ; Yes we can move down
    ld hl, (cursor_y)
    inc hl
    ld (cursor_y), hl
    ; Update the doc_pointer
    ld hl, (doc_pointer)
    push bc
    call skip_to_start_of_next_line
    pop bc
    ld (doc_pointer), hl
    djnz cursor_page_down_loop
 cursor_page_down_stop:
    ld hl, (doc_pointer)
    call skip_to_start_of_line
    call get_line_length                ; length is in a, hl still pointing at start of line
    ld b, a
    dec b
    ld a, (cursor_x)
    cp b
    jr c, cursor_page_down_ok
    jr z, cursor_page_down_ok
    ld a, b
    ld (cursor_x), a
cursor_page_down_ok:
    call skip_cols
    ld (doc_pointer), hl
    jp main_loop

cursor_page_up:
    ; Move the cursor up VIEW_HEIGHT+1 rows
    ld hl, (cursor_y)
    ld a, l
    or h
    jp z, main_loop

    ld a, (VIEW_HEIGHT)
    ld b, a
    dec b
cursor_page_up_loop:
    ld hl, (cursor_y)
    ld a, l
    or h
    jp z, cursor_page_up_stop

    ; increase cursor
    dec hl
    ld (cursor_y), hl
    ; Update the doc_pointer
    ld hl, (doc_pointer)
    push bc
    call skip_to_start_of_previous_line
    pop bc
    ld (doc_pointer), hl
    djnz cursor_page_up_loop
cursor_page_up_stop:
    ld hl, (doc_pointer)
    call get_line_length                ; length is in a, hl still pointing at start of line
    ld b, a
    dec b
    ld a, (cursor_x)
    cp b
    jr c, cursor_page_up_ok
    jr z, cursor_page_up_ok
    ld a, b
    ld (cursor_x), a
cursor_page_up_ok:
    call skip_cols
    ld (doc_pointer), hl
    jp main_loop

save_and_exit:
    ; If no filename to save to, ask for one
    call was_filename_provided
    jr z, save_and_exit1

    call nz, ask_for_filename

    ; Only save if a filename was provided
    call was_filename_provided
    jr nz, exit
save_and_exit1:
    call save_file
exit:
    call cls
    jp 0

save_as_message:
    db 'If you want to save, enter a filename.',13,10
    db 'If you don''t want to save, just press ENTER.',13,10,'$'
ask_for_filename:
    ; Clear screen, ask for filename, enter one.
    ; Check it is nnnnnnnn.eee
    ; If not, ask again.
    ; If they don't want to save they can press ENTER on a blank one.
    ; Return it in the FCB.

    ; Clear the FCB
    ld hl, FCB
    ld (hl), 0
    inc hl
    ld de, FCB+2
    ld (hl), ' '
    ld bc, 10
    ldir

    call clear_remainder_of_fcb

    call cls
    
    ld de, save_as_message
    call show_string_de

    ; Set up a buffer of max 13 chars, and fill with zeros
    ld hl, filename_buffer
    ld de, filename_buffer+1
    ld (hl), 0
    ld bc, 13
    ldir

    ld hl, filename_buffer
    ld (hl), 12
    ex de, hl
    ld c, BDOS_Read_Console_Buffer
    call BDOS

    ; Check filename buffer is valid
    ld hl, filename_buffer+1
    ld a, (hl)                          ; Length of filename
    cp 0
    ret z                               ; Exit if they just hit ENTER
    inc hl

    ld b, 8
    ld de, FCB+1
    call copy_filename_chars
    ld a, (hl)
    cp '.'
    ret nz                              ; Give up if no "."
    inc hl
    ld b, 3
    ld de, FCB+9
    call copy_filename_chars
    ret

copy_filename_chars:
    ; Pass in destination DE.
    ; Source in HL.
    ; Max number of chars to copy in B.
    ; Copies from HL to DE exactly B chars.
    ; If we hit an invalid one, such as NULL or "." or " " then we stop copying.
    ; Return updated HL so the next call to this function can carry on where this one left off.
    ld a, (hl)
    call is_char_valid
    ret nz
    call make_uppercase
    inc hl
    ld (de), a
    inc de
    djnz copy_filename_chars
    ret

make_uppercase:
    ; Makes a letter in A into uppercase
    cp 'a'
    ret c
    cp 'z'+1
    ret nc 
    and %11011111
    ret

is_char_valid:
    ; Checks if A is a valid filename character.
    cp 33
    jr c, return_NZ
    cp '*'
    jr z, return_NZ
    cp '?'
    jr z, return_NZ
    cp '.'
    jr z, return_NZ
    cp 127
    jr nc, return_NZ
    jr return_Z

return_NZ:
    or 1                                ; clear zero flag
    ret    

return_Z:
    cp a                                ; Set Z
    ret

set_cursor_position:
    ; Put the cursor on the screen at the correct position.
    ; This is calculated by cursor_x - screen_left, cursor_y - screen_top.
    ld hl, (cursor_y)
    ld de, (screen_top)
    or a
    sbc hl, de          ; y coord is in l
    inc l               ; adjust because VT100 screen coords start at 1, but we start at 0
    ld a, (screen_left)
    ld b, a
    ld a, (cursor_x)
    sub b               
    ld c, a             ; x coord is in b
    inc c               ; adjust because VT100 screen coords start at 1, but we start at 0
    ld b, l             ; y coord now in b
    call move_to_xy
    ret

show_screen:
    ; Redraw the entire screen.
    ; We draw starting at a given set of coords. These are stored in screen_left,screen_top:
    ; 0,0 to start at the top of the doc. 
    ; 10,0 to start at the top of the doc, but scrolled across 10 chars.
    ; 0,20 to start on line 21, scrolled to the left.
    ; We may be showing a selected area, if the selected start loc isn't FFFF.
    ; The selected area marks a location in the doc to start the selection,
    ; and a location to stop the selection.
    ld hl, (doc_start)
    ld bc, (screen_top)
    call skip_lines
    call cls 
    call hide_cursor
    xor a
    ld (shown_lines), a
show_screen_row:
    ld a, (screen_left)
    ld (current_col), a                 ; Keep track of the current column we are displaying
    call skip_cols
    jr z, shown_enough
    ld a, (VIEW_WIDTH)                     
    ld b, a                             ; b = cols left to Show
show_screen1:
    ld a, (hl)
    cp END_OF_TEXT
    jp z, show_screen_done
    cp EOL 
    jp z, show_screen_eol
    cp TAB 
    jp z, show_screen_tab
    call print_a
    ld a, (current_col)
    inc a
    ld (current_col), a
    dec b
    jr z, shown_enough
    inc hl
    jr show_screen1
shown_enough:
    call skip_to_start_of_next_line
    dec hl
show_screen_eol:
    ld a, (screen_left)
    ld (current_col), a                 ; start a new row
    ld a, (shown_lines)
    inc a
    ld (shown_lines), a
    ld e, a
    ld a, (VIEW_HEIGHT)
    ld d, a
    ld a, e
    cp d
    jr nc, show_screen_done
    ld a, 13
    call print_a
    ld a, 10
    call print_a
    inc hl
    jr show_screen_row
show_screen_done:
    call show_cursor
    ret
show_screen_tab:
    push bc
    ld a, (current_col)
    and TAB_MASK
    ld b, a
    ld a, TAB_WIDTH
    sub b
    ld b, a                 ; b stores how long a tab is
show_screen_tab1:
    ld a, ' '               ; show a tab
    call print_a
    ld a, (current_col)
    inc a
    ld (current_col), a
    djnz show_screen_tab1
    inc hl
    pop bc
    jr show_screen1

skip_cols:
    ; We are pointing to the doc in hl.
    ; This skips across "a" cols.
    ; If a TAB is found we need to take that into account.
    ; Returns Z if could not skip that number of cols, or NZ if all good.
    ; Returns the new doc pointer in hl.
    ; Returns the new cursor_x in c.
    ld c, 0                         ; c = current col = 0
    or a
    jr z, skip_cols_done            ; return with NZ if no cols to skip
    ld b, a                         ; b = number of cols to skip
skip_col:
    ld a, (hl)
    cp END_OF_TEXT
    ret z                           ; exit with Z if found end of doc
    cp EOL 
    ret z                           ; exit with Z if found end of row
    cp TAB
    jr nz, skip_cols_not_tab
    ; If we are on a tab we need to swallow 1-7 increments
    ld a, c
    and TAB_MASK
    ld d, a
    ld a, TAB_WIDTH 
    dec a
    sub d                   ; for first char of tab, a = 7, 2nd a = 6, 3rd a = 5, last a = 0
    ; if b < a we aren't going to reach the end of the tab, so stay here
    cp b
    jr nc, skip_cols_done
    ; take a off of b
    ld d, a
    ld a, b
    sub d
    ld b, a

    ; add a onto c, so we skip that many tabs
    ld a, c
    add a, d
    ld c, a
skip_cols_not_tab
    inc c                           ; increase col counter
    inc hl                          ; increase doc pointer
    djnz skip_col
skip_cols_done:
    or 1                            ; return NZ
    ret

skip_spaces:
    ; We are pointing to the doc in hl.
    ; This skips along a line and stops when a non-space, non-tab is found
    ; If a TAB is found we need to take that into account.
    ; Returns Z if could not skip that number of cols, or NZ if all good.
    ; Returns the new doc pointer in hl.
    ; Returns the new cursor_x in c.
    ld c, 0                         ; c = current col = 0
skip_space:
    ld a, (hl)
    cp ' '
    jr z, skip_spaces_not_tab
    cp TAB
    jr nz, skip_spaces_done
skip_tab:
    ; If we are on a tab we need to swallow 1-7 increments
    ld a, c
    and TAB_MASK
    ld d, a
    ld a, TAB_WIDTH
    dec a
    sub d                   ; for first char of tab, a = 7, 2nd a = 6, 3rd a = 5, last a = 0

    add a, c
    ld c, a
skip_spaces_not_tab:
    inc c                           ; increase col counter
    inc hl                          ; increase doc pointer
    jr skip_space
skip_spaces_done:
    or 1                            ; return NZ
    ret

skip_lines:
    ; We are pointing to the doc in hl.
    ; This skips down "bc" lines.
    ld a, b
    or c
    ret z
    call skip_to_start_of_next_line
    dec bc
    jr skip_lines

skip_to_start_of_next_line:
    ; We are pointing to the doc in hl.
    ; This skips to the start of the next line.
    push af
skip_a_line_loop
    ld a, (hl)
    cp END_OF_TEXT 
    jr z, skip_a_line2
    inc hl
    cp EOL 
    jr nz, skip_a_line_loop
skip_a_line2:
    pop af
    ret

skip_to_start_of_previous_line:
    ; We are pointing to the doc in hl.
    ; This skips to the start of the previous line.
    ; This means move back until we hit the start of the file, or CR.
    ; Then skip back again until we hit another CR, or start of file again.
    ; Then move forward one.
    dec hl
    ld a, (hl)
    cp START_OF_TEXT
    jr z, found_start
    cp EOL
    jr nz, skip_to_start_of_previous_line
    ; Found end of previous line
skip_to_start_of_line:
    dec hl
    ld a, (hl)
    cp START_OF_TEXT
    jr z, found_start
    cp EOL
    jr nz, skip_to_start_of_line
found_start:
    inc hl
    ret

get_line_length:
    ; We are pointing to the start of a line in the doc in hl.
    ; Return in A the length of the line.
    ; Preserve hl
    push hl
    ld b, 1
get_line_length1:
    ld a, (hl)
    cp END_OF_TEXT
    jr z, get_line_length_done
    cp EOL
    jr z, get_line_length_done
    inc hl
    inc b
    jr get_line_length1
get_line_length_done:
    ld a, b
    pop hl
    ret

inc_doc_lines:
    push hl
    ld hl, (doc_lines)
    inc hl
    ld (doc_lines), hl
    pop hl
    ret

clear_keybuff:
    ld hl, keybuff
    ld (keypointer), hl
    ld a, $00
    ld (keybuff), a
    ld (keybuff+1), a
    ld (keybuff+2), a
    ld (keybuff+3), a
    ld (keybuff+4), a
    ld (keybuff+5), a
    ld (keybuff+6), a
    ld (keybuff+7), a
    ld (keybuff+8), a
    xor a
    ld (keycounter), a
    ret

get_user_action:
    ; Read a key from the keyboard and decide on what it means.
    ; It can be:
    ; A normal key press. If so return the ASCII char.
    ; A cursor key. If so return one of the ACTION values.
    ; Another special key like delete or enter. Return the ACTION value.
    ; Return 0 if no user_action.
    ;
    ; The key definitions are stored like this:
    ; DELETE = 05, 23, 47, 90, 22, 33, 44, 55, 00, ACTION
    ; If they are not 8 keys long they are padded with 00s:
    ; CURSOR_UP = 12, 65, 00, 00, 00, 00, 00, 00, 00, ACTION
    ; ENTER = 13, 00, 00, 00, 00, 00, 00, 00, 00, ACTION
    ; The ACTION is the number of the desired action, e.g. CURSOR_UP = 128
    ; When you press a key, you may get 1 to 8 actual keys from it.
    ; These are compared to each definition in the table, in turn.
    ; If more than one match then we need to wait for another key.
    ; Some keys are not configurable. These are all single key
    ; presses, and are all >= 32 and < 127.
    ; The keys go into a buffer, called keybuff.
    ; It's 8 spaces long. It has a pointer called keypointer, and a counter called keycounter.
    ; When we get a good key, we clear the buffer.

    ; Let's just show the keybuff quickly
;     ld a, ESC
;     call print_a
;     ld a, '['
;     call print_a
;     ld a, 25
;     call print_a_as_decimal
;     ld a, ';'
;     call print_a
;     ld a, 30
;     call print_a_as_decimal
;     ld a, 'H'
;     call print_a

;     ld hl, keybuff
;     ld b, 5
; show_keybuff_loop:
;     ld a, (hl)
;     push hl
;     push bc
;     call show_a_as_hex
;     pop bc
;     pop hl
;     ld a, ' '
;     call print_a
;     inc hl
;     djnz show_keybuff_loop

    call get_key_with_timeout           ; c = key
    ld a, (keycounter)
    or a                                ; Are we at the start of the keybuff?
    jr nz, get_user_action1
    ld a, c
    cp 0
    jr z, get_user_action               ; If nothing pressed, start again
    cp ' '
    jr c, get_user_action1              ; Not ordinary key press if < 32
    cp 127
    jr nc, get_user_action1             ; Not ordinary key press if >= 127
    ret                                 ; Otherwise ordinary key press, like "G"
get_user_action1:
    ; Have we read a 9th key? If so something is wrong and need to start again.
    ld a, (keycounter)
    cp 8
    jr c, get_user_action2
    call clear_keybuff
    jp get_user_action4
get_user_action2:
    ; Is it one of the programmable keys?
    ld hl, (keypointer)                 ; By now hl points to the appropriate place in keybuff
    ld a, c
    ld (hl), a                          ; Store the key in the buffer
    inc hl                              ; Increase keypointer
    ld (keypointer), hl
    ld a, (keycounter)
    inc a
    ld (keycounter), a                  ; Increase the keycounter

    ld de, keytable                     ; Start looking in the keytable for a match
get_user_action3:
    ld a, (de)
    cp $00                              ; Have we run out of possible matches?
    jr z, get_user_action4
    push de                             ; Store de for now
    ld hl, keybuff                      ; hl starts at the beginning of the key buffer
    ld b, 8                             ; Match 8 keys max
get_user_action_loop:
    ld a, (de)
    cp (hl)
    jr nz, get_action_no_match
    inc de
    inc hl
    djnz get_user_action_loop           ; After 8 good matches, we have our action
    call clear_keybuff                  ; reset ready for next time
    inc de                              ; de now points to the user action
    ld a, (de)
    pop de                              ; Drain de from stack
    ret                                 ; Return the action
get_action_no_match:
    pop de                              ; restore keytable pointer
    inc de
    inc de
    inc de
    inc de
    inc de
    inc de
    inc de
    inc de
    inc de
    inc de                              ; move to next entry in table
    jp get_user_action3
get_user_action4:
    xor a                               ; Failed to find any matches
    ret

include "constants.asm"
include "funcs.asm"
    
; variables
cursor_x:
    db 0
cursor_y:
    dw 0
shown_lines:
    db 0
doc_start:  
    dw 0
doc_end:  
    dw 0
doc_lines:
    dw 0
need_to_redraw_screen:
    db 0
selection_start:  
    dw 0
selection_end:  
    dw 0
screen_top:
    dw 0
screen_left:
    db 0
current_col:
    db 0
doc_pointer:
    dw 0
ram_end:
    dw 0
file_extension:
    db '---'
temp_file_extension:
    db 'TMP'
read_pointer:
    dw 0
write_pointer:
    dw 0
hang_over:
    db 0
all_done:
    db 0
keybuff:
    ds 10
keycounter:
    db 0
keypointer:
    dw 0

filename_buffer:
    ds 15
stack:
    ds 31
stacktop:
    db 0

save_file:
    call save_as_temp_file
    cp 255
    jr z, failed_to_save
    call erase_original_file
    call rename_temp_to_original_file
    ret

rename_temp_to_original_file:
    ; Copy the filename to FCB+16
    ld de, FCB+16
    ld hl, FCB
    ld bc, 16
    ldir

    ; Set temp file extension for "from" file
    ld de, FCB+9
    ld hl, temp_file_extension
    ld bc, 3
    ldir

    ld de, FCB
    ld c, BDOS_Rename_File
    call BDOS
    ret

erase_original_file:
    ; restore the filename extension, then erase that file
    ld de, FCB+9
    ld hl, file_extension
    ld bc, 3
    ldir

    ld de, FCB
    ld c, BDOS_Delete_File
    call BDOS
    ret

failed_to_save:
    ld de, failed_to_save_message
    jp show_string_de
failed_to_save_message:
    db 'ERROR saving file!',13,10,'$'

save_as_temp_file:
    ; This saves the current doc as a temp file.
    ; Returns 0 for success, 255 for failure.

    ; Copy the file extension to a variable
    ld hl, FCB+9
    ld de, file_extension
    ld bc, 3
    ldir

    call clear_remainder_of_fcb

    ; Copy the temp file extension
    ld hl, temp_file_extension
    ld de, FCB+9
    ld bc, 3
    ldir

    ; Erase the temp file, if it exists
    ld de, FCB
    ld c, BDOS_Delete_File
    call BDOS

    call clear_remainder_of_fcb

    ; Create the temp file
    ld de, FCB
    ld c, BDOS_Make_File
    call BDOS
    cp 0
    ret nz

    ld de, DMA
    ld c, BDOS_Set_DMA_Address
    call BDOS

    ; Work through the file one sector at a time, saving it.
    ; We need to keep track of:
    ; The place in memory we are reading from: "read_pointer". We are done if this reaches End_of_text.
    ; The place in the DMA area we are writing to: "write_pointer".
    ; How many bytes are left in the DMA area: "b". If this reaches 0 we need to write out the sector.
    ; To complicate matters further, if we hit a CR we need to add a LF. This may hang over the end of a sector. 
    ld hl, (doc_start)
    ld (read_pointer), hl

    xor a
    ld (hang_over), a
    ld (all_done), a

save_main_loop
    ld hl, DMA
    ld (write_pointer), hl
    ld b, 128                       ; Counter for bytes written to DMA area

    ld a, (hang_over)
    cp 0
    jr z, save_as_temp_file_loop

    ld a, LF 
    call write_a
    dec b
save_as_temp_file_loop:
    call read_a
    cp END_OF_TEXT
    jr z, finish_this_sector
    cp EOL
    jr nz, save_not_eol
    ; For eol send 2 chars
    ld a,EOL
    ld (hang_over), a
    call write_a
    dec b
    jr z, sector_complete
    xor a
    ld (hang_over), a
    ld a, LF
save_not_eol:
    call write_a
    djnz save_as_temp_file_loop
    jr sector_complete
finish_this_sector:
    ld c, a
    ld a, 1
    ld (all_done), a
    ld a, c
    call write_a
    djnz finish_this_sector
sector_complete:
    ; Now write the sector out to disk
    ld de, FCB
    ld c, BDOS_Write_Sequential
    call BDOS
    cp 255
    jr z, sector_complete_end

    ; Any more to do?
    ld a, (all_done)
    cp 0
    jr z, save_main_loop

sector_complete_end:
    ; Close temp file
    ld c, BDOS_Close_File
    ld de, FCB
    call BDOS
    ret

write_a:
    ld hl, (write_pointer)
    ld (hl), a
    inc hl
    ld (write_pointer), hl
    ret

read_a:
    ld hl, (read_pointer)
    ld a, (hl)
    inc hl
    ld (read_pointer), hl
    ret

load_file:
    ; Test if the file can be opened for reading
    ld c, BDOS_Open_File
    ld de, FCB
    call BDOS
    inc a
    jr z, could_not_open_file

    ld de, DMA                      ; Use the standard DMA area
    ld c, BDOS_Set_DMA_Address
    call BDOS

load_file_loop:
    ; Read in a sector at a time until finished, or out of memory.
    ; The sector gets read into the standard DMA area.
    ld de, FCB
    ld c, BDOS_Read_Sequential
    call BDOS
    cp 0
    jr nz, load_file_done

    ; Now copy 128 bytes of data from the DMA area into our internal storage for it.
    ; Any CR/LF combos are relaced by a single CR.
    ld de, (doc_end)
    ld hl, DMA
    ld b, 128
load_file_loop1:
    ld a, (hl)
    cp TAB
    jr z, load_file_loop_good_char
    cp EOL
    jr z, load_file_loop_eol
    cp 32
    jr c, load_file_loop_bad_char
    cp 127
    jr nc, load_file_loop_bad_char
load_file_loop_good_char:    
    ld (de), a
    inc de
load_file_loop_bad_char:    
    inc hl
    djnz load_file_loop1

    ; Increase the doc end pointer
    ld (doc_end), de

    ; If doc end pointer is too near top of memory then we are out of mem.
    ld hl, (ram_end)
    or a                                ; clear carry
    sbc hl, de
    ld a, h
    cp 0
    jr nz, load_file_loop
    ld a, l
    cp 129
    jp nc, load_file_loop
    jp out_of_memory

load_file_loop_eol:
    push hl
    ld hl, (doc_lines)
    inc hl
    ld (doc_lines), hl
    pop hl
    jr load_file_loop_good_char

load_file_done:
    ld de, FCB
    ld c, BDOS_Close_File
    call BDOS

    ld hl, (doc_end)
    ld (hl), END_OF_TEXT
    ret

could_not_open_file:
    ld de, could_not_open_file_message
    call show_string_de
    jp 0
could_not_open_file_message:
    db 'File not found.',13,10,'$'

clear_selection:
    ; turn off any selection
    ld hl, $ffff
    ld (selection_start), hl
    ld (selection_end), hl
    ret

clear_doc_lines:
    ; clear doc_lines
    ld hl, 0
    ld (doc_lines), hl
    ret

show_cursor_coords:
    ld c, 10
    ld b, 25
    call move_to_xy
    ld a, (cursor_x)
    call print_a_as_decimal
    ld a, ' '
    call print_a
    ld a, ' '
    call print_a
    ret    

include "readkeys.asm"

; show_current_char:
;     ; Show at the bottom of the screen what the cursor is pointing to
;     ld a, ESC
;     call print_a
;     ld a, '['
;     call print_a
;     ld a, 25
;     call print_a_as_decimal
;     ld a, ';'
;     call print_a
;     ld a, 1
;     call print_a_as_decimal
;     ld a, 'H'
;     call print_a
;     ld hl, (doc_pointer)
;     ld a, (hl)
;     cp EOL
;     jr z, show_eol
;     cp END_OF_TEXT
;     jr z, show_eot
;     cp TAB
;     jr z, show_tab
;     call print_a
;     ld a, ' '
;     call print_a
;     ld a, ' '
;     call print_a
;     ret
; show_eol:
;     ld a, 'C'
;     call print_a
;     ld a, 'R'
;     call print_a
;     ret
; show_eot:
;     ld a, 'E'
;     call print_a
;     ld a, 'N'
;     call print_a
;     ld a, 'D'
;     call print_a
;     ret
; show_tab:
;     ld a, 'T'
;     call print_a
;     ld a, 'A'
;     call print_a
;     ld a, 'B'
;     call print_a
;     ret


; From here on is free space for the text file
end_of_code:
    db 0

