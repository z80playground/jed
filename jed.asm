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
; We keep track on the number of lines in the doc in the variable doc_lines.
; No lines wrap, so doc_lines = total lines in the editor.
;
; There is a cursor that can move around inside the document.
; Top-most location is 0,0.
; There is also a doc_pointer that points to the current char that the cursor is on.
;
; The current view of the document is displayed on the screen in
; an area VIEW_WIDTH x VIEW_HEIGHT

    org $0100

    ; Load a file into ram
    ; We need to know the start and end of the ram space
    ; Start is the end of this code+1
    ; End is BDOS-1

    ; Set the stack to point to our local stack
    ld sp, stacktop

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
    ld (doc_start), hl
    ld (doc_pointer), hl

    ; Find address of BIOS
    ld hl, (1)
    ld de, 9
    add hl, de              ; hl points to BIOS_con_out
    ld (BIOS_CON_OUT), hl

    ; Put some test stuff into memory
    call test_fill

    ;jp key_reader_loop

    call show_screen
main_loop:
    call show_screen_if_scrolled
    call show_cursor_coords
main_loop_no_scroll_change:
    call show_current_char
    call set_cursor_position
main_loop_get_key:
    call get_user_action
    or a
    jr z, main_loop_get_key
    cp BACKSPACE
    jr z, backspace_pressed
    cp ENTER
    jp z, insert_char
    cp 127
    jp c, insert_char
    cp USER_QUIT
    jp z, exit
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

backspace_pressed:
    ; User has pressed "< BACKSPACE"
    ; Not allowed if right at start of doc...
    xor a
    ld (need_to_redraw_screen), a
    ld hl, (doc_pointer)
    dec hl
    ld a, (hl)
    cp START_OF_TEXT
    jr z, main_loop

    ; Did we just backspace into the previous line?
    cp EOL
    jr nz, normal_delete

join_with_previous_line:
    ; Deleting into the previous line
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

normal_delete:
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
    jr nz, backspace_redraw

    ; Redraw the current row
    call show_current_line
    jp main_loop

backspace_redraw:
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
    and %00000011
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
    ld hl, (cursor_y)
    ld de, (screen_top)
    or a
    sbc hl, de          ; y coord is in l
    inc l               ; adjust because VT100 screen coords start at 1, but we start at 0
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, l
    call print_a_as_decimal
    ld a, ';'
    call print_a
    ld a, '1'
    call print_a
    ld a, 'H'
    call print_a

    ; Now redraw the row
    ld hl, (doc_pointer)
    call skip_to_start_of_line
    ld a, (screen_left)
    ld (current_col), a                 ; Keep track of the current column we are displaying
    call skip_cols
    ld b, VIEW_WIDTH                     ; b = cols left to show
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
    ret
show_current_line2:
    ; Fill remainer of row with spaces
    ld a, ' '
    call print_a
    djnz show_current_line2
    ret
show_current_line_tab:
    ld c, b
    ld a, (current_col)
    and %00000011
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
    ret

out_of_memory:
    jp exit

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
    add a, VIEW_WIDTH
    ld e, a
    ld a, (cursor_x)
    cp e
    jr c, show_screen_if_scrolled2
    sub VIEW_WIDTH
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
    ld e, VIEW_HEIGHT
    dec e
    ld d, 0
    add hl, de
    ld de, (cursor_y)
    or a                                ; clear carry
    sbc hl, de
    jr nc, show_screen_if_scrolled4
    ld hl, (cursor_y)
    ld d, 0
    ld e, VIEW_HEIGHT
    or a                                ; clear carry
    sbc hl, de
    inc hl
    ld (screen_top), hl
    ld b, 'B'
show_screen_if_scrolled4:
    ld a, b
    or a
    jr z, didnt_go_off
    push af
    call show_screen
    pop af
    call show_went_off_direction
    ret
didnt_go_off:
    ld a, '-'
    call show_went_off_direction
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
    and %00000011
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

    ld b, VIEW_HEIGHT
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

    ld b, VIEW_HEIGHT
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

exit:
    call cls
    jp 0

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
    ld b, a             ; x coord is in b
    inc b               ; adjust because VT100 screen coords start at 1, but we start at 0
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, l
    push bc
    call print_a_as_decimal
    pop bc
    ld a, ';'
    call print_a
    ld a, b
    call print_a_as_decimal
    ld a, 'H'
    call print_a
    ret

print_a_as_decimal:
    ; Prints a number (in a) from 0 to 255 in decimal
    ld c, 0                         ; c tells us if we have started printing digits
    ld b, a
    cp 100
    jr c, print_a_as_decimal_tens
    cp 200
    jr c, print_a_as_decimal_100
    ld a, '2'
    call print_a
    ld a, b
    sub 200
    jr print_a_as_decimal_101
print_a_as_decimal_100:
    ld a, '1'
    call print_a
    ld a, b
    sub 100
print_a_as_decimal_101:
    ld c, 1                         ; Yes, we have started printing digits
print_a_as_decimal_tens:
    ld b, 0
print_a_as_decimal_tens1:
    cp 10
    jr c, print_a_as_decimal_units
    sub 10
    inc b
    jp print_a_as_decimal_tens1

print_a_as_decimal_units:
    ld d, a
    ld a, b
    cp 0
    jr nz, print_a_as_decimal_show_tens
    ld a, c
    cp 0
    jr z, print_a_as_decimal_units1
print_a_as_decimal_show_tens:
    add a, '0'
    call print_a
print_a_as_decimal_units1:
    ld a, '0'
    add a, d
    call print_a
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
    ld b, VIEW_WIDTH                     ; b = cols left to show
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
    cp VIEW_HEIGHT
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
    and %00000011
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
    jr nz, skip_cols_end_tab0
    ; If we are on a tab we need to swallow 1, 2 or 3 increments
    ld a, c
    and %00000011
    ld d, a
    ld a, 3
    sub d                   ; for first char of tab, a = 3, 2nd a = 2, 3rd a = 1, 4th a = 0
    jr z, skip_cols_end_tab0
    dec b
    jr z, skip_cols_done
    dec a
    jr z, skip_cols_end_tab1        ; max 2
    dec b
    jr z, skip_cols_done
    dec a
    jr z, skip_cols_end_tab2        ; max 1
    dec b
    jr z, skip_cols_done
skip_cols_end_tab3:
    inc c
skip_cols_end_tab2:
    inc c
skip_cols_end_tab1:
    inc c
skip_cols_end_tab0:
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
    jr z, skip_spaces_end_tab0
    cp TAB
    jr nz, skip_spaces_done
skip_tab:
    ; If we are on a tab we need to swallow 1, 2 or 3 increments
    ld a, c
    and %00000011
    ld d, a
    ld a, 3
    sub d                   ; for first char of tab, a = 3, 2nd a = 2, 3rd a = 1, 4th a = 0
    jr z, skip_spaces_end_tab0
    dec a
    jr z, skip_spaces_end_tab1        ; max 2
    dec a
    jr z, skip_spaces_end_tab2        ; max 1
skip_spaces_end_tab3:
    inc c
skip_spaces_end_tab2:
    inc c
skip_spaces_end_tab1:
    inc c
skip_spaces_end_tab0:
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

get_key:
    ; Wait for a key
    ld c, BDOS_CONSOLE_INPUT
    ld e, $FF
    call BDOS
    cp 0
    jr z, get_key
    ret

JP_HL:
	jp	(hl)

print_a:
    push hl
    push bc
    push de
    ld hl, (BIOS_CON_OUT)
    ld c, a
    call JP_HL
    pop de
    pop bc
    pop hl
    ret

cls:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, 'H'
    call print_a
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, 'J'
    call print_a
    ret

hide_cursor:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, '?'
    call print_a
    ld a, '2'
    call print_a
    ld a, '5'
    call print_a
    ld a, 'l'
    call print_a
    ret

show_cursor:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, '?'
    call print_a
    ld a, '2'
    call print_a
    ld a, '5'
    call print_a
    ld a, 'h'
    call print_a
    ret

inc_doc_lines:
    push hl
    ld hl, (doc_lines)
    inc hl
    ld (doc_lines), hl
    pop hl
    ret

get_user_action:
    ; Read a key from the keyboard and decide on what it means.
    ; It can be:
    ; A normal key press. If so return the ASCII char.
    ; A cursor key. If so return one of the ACTION values.
    ; Another special key like delete or enter. Return the ACTION value.
    call get_key
    cp ' '
    ret nc                              ; Ordinary key press
    cp BACKSPACE
    ret z
    cp ENTER
    ret z
    cp TAB
    ret z
    cp $18                              ; CTRL_X
    jr z, get_user_action_quit
    cp ESC                              ; ESC
    jr nz, get_user_action_none
    call get_key
    cp '['                              ; '['
    jp nz, get_user_action_none
    call get_key
    cp $41                              ; Cursor UP
    jp z, get_user_action_up
    cp $42                              ; Cursor down
    jp z, get_user_action_down
    cp $43                              ; Cursor right
    jp z, get_user_action_right
    cp $44                              ; Cursor left
    jp z, get_user_action_left
    cp $48                              ; Cursor home
    jp z, get_user_action_home
    cp $46                              ; Cursor end
    jp z, get_user_action_end
    cp $35
    jp z, get_user_action_page_up
    cp $36
    jp z, get_user_action_page_down
get_user_action_none:
    ld a, 0
    ret
get_user_action_quit:
    ld a, USER_QUIT
    ret
get_user_action_up:
    ld a, USER_CURSOR_UP
    ret
get_user_action_down:
    ld a, USER_CURSOR_DOWN
    ret
get_user_action_left:
    ld a, USER_CURSOR_LEFT
    ret
get_user_action_right:
    ld a, USER_CURSOR_RIGHT
    ret
get_user_action_home:
    ld a, USER_CURSOR_HOME
    ret
get_user_action_end:
    ld a, USER_CURSOR_END
    ret
get_user_action_page_up:
    call get_key
    cp $7e
    jr nz, get_user_action_none
    ld a, USER_CURSOR_PGUP
    ret
get_user_action_page_down:
    call get_key
    cp $7e
    jr nz, get_user_action_none
    ld a, USER_CURSOR_PGDN
    ret
        
test_stuff:
db 'Example file',EOL
db 'With',EOL
db 'not',EOL
db 'much',EOL
db 'in',EOL
db 'it! I have made it a really long line so that there is the option to scroll right if needed to prove a point.',EOL
db TAB,'But these lines',EOL
db TAB,'are indented',EOL
db TAB,'by one tab each!!!',EOL
db EOL
db ' ',TAB,'And this line goes "space", "tab"',EOL
db '  ',TAB,'And this line goes "space", "space", "tab"',EOL
db '   ',TAB,'And this line goes 3x"space" "tab"',EOL
db '0123456789ABCDEFGHIJ0123456789ABCDEFGHIJ0123456789ABCDEFGHIJ0123456789ABCDEFGHIJ0123456789ABCDEFGHIJ0123456789ABCDEFGHIJ',EOL
db '1',EOL
db '2',EOL
db '3',EOL
db '4',EOL
db '5',EOL
db '6',EOL
db '7',EOL
db '8',EOL
db '9',EOL
db 'ten!!!',EOL
db '11',EOL
db '12',EOL
db '13 with some extra text',EOL
db '14 with even more text',EOL
db '15',EOL
db '16',EOL
db '17',EOL
db 'eighteen is here',EOL
db '19',EOL
db '20',EOL
db '21',EOL
db 'The end.',END_OF_TEXT

include "../cpm-fat/message.asm"

; CONSTANTS
VIEW_WIDTH equ 80
VIEW_HEIGHT equ 20
TAB_WIDTH equ 4
END_OF_TEXT equ 26
START_OF_TEXT equ 2
EOL equ 13
TAB equ 9
ESC equ 27
BDOS equ 5
BACKSPACE equ $7F
ENTER equ $0D
BDOS_CONSOLE_INPUT equ 6

USER_CURSOR_UP equ 128
USER_CURSOR_DOWN equ 129
USER_CURSOR_LEFT equ 130
USER_CURSOR_RIGHT equ 131
USER_CURSOR_HOME equ 132
USER_CURSOR_END equ 133
USER_CURSOR_PGUP equ 134
USER_CURSOR_PGDN equ 135
USER_QUIT equ 255
    
; variables
cursor_x:
    db 0
cursor_y:
    dw 0
BIOS_CON_OUT:
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

stack:
    ds 31
stacktop:
    db 0

;;;;;;;;;;;;;;;;;;;;;
; debug routines

test_fill:
    ; turn off any selection
    ld hl, $ffff
    ld (selection_start), hl
    ld (selection_end), hl

    ; clear doc_lines
    ld hl, 0
    ld (doc_lines), hl

    ; Fill ram with some test stuff
    ld de, (doc_start)
    ld hl, test_stuff
test_fill1:
    ld a, (hl)
    cp EOL 
    call z, inc_doc_lines
    cp END_OF_TEXT
    jp z, test_fill2
    ld (de), a
    inc hl
    inc de
    jr test_fill1
test_fill2:
    ld (de), a
    ld (doc_end), de
    ret


show_cursor_coords:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, 25
    call print_a_as_decimal
    ld a, ';'
    call print_a
    ld a, 10
    call print_a_as_decimal
    ld a, 'H'
    call print_a
    ld a, (cursor_x)
    call print_a_as_decimal
    ld a, ' '
    call print_a
    ld a, ' '
    call print_a
    ret    

show_current_char:
    ; Show at the bottom of the screen what the cursor is pointing to
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, 25
    call print_a_as_decimal
    ld a, ';'
    call print_a
    ld a, 1
    call print_a_as_decimal
    ld a, 'H'
    call print_a
    ld hl, (doc_pointer)
    ld a, (hl)
    cp EOL
    jr z, show_eol
    cp END_OF_TEXT
    jr z, show_eot
    cp TAB
    jr z, show_tab
    call print_a
    ld a, ' '
    call print_a
    ld a, ' '
    call print_a
    ret
show_eol:
    ld a, 'C'
    call print_a
    ld a, 'R'
    call print_a
    ret
show_eot:
    ld a, 'E'
    call print_a
    ld a, 'N'
    call print_a
    ld a, 'D'
    call print_a
    ret
show_tab:
    ld a, 'T'
    call print_a
    ld a, 'A'
    call print_a
    ld a, 'B'
    call print_a
    ret

show_went_off_direction:
    ; Show at the bottom of the screen an indicator "a"
    push af
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, 25
    call print_a_as_decimal
    ld a, ';'
    call print_a
    ld a, 5
    call print_a_as_decimal
    ld a, 'H'
    call print_a
    pop af
    call print_a
    ret



; key_reader_loop:
;     call get_key
;     cp 'q'
;     jp z, exit
;     call show_a_as_hex
;     ld a, ' '
;     call print_a
;     jr key_reader_loop

;     ld b, 50
; number_loop:
;     push bc
;     call get_key
;     pop bc
;     cp 'q'
;     jp z, exit
;     cp 'h'
;     jr nz, not_h
;     inc b
;     jr number_loop_cont
; not_h:
;     cp 'l'
;     jr nz, not_l
;     dec b
;     jr number_loop_cont
; not_l:
;     jp number_loop
; number_loop_cont:
;     push bc
;     call cls
;     pop bc
;     push bc
;     ld a, b
;     call print_a_as_decimal
;     pop bc
;     jr number_loop

; From here on is free space for the text file
end_of_code:
    db 0

