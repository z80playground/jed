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
; an area VIEW_WIDTH x VIEW_HEIGHT.
;

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

    ; Clear the doc area
    call clear_selection
    call clear_doc_lines
    ld hl, (doc_start)
    ld (doc_pointer), hl
    ld (doc_end), hl

    call was_filename_provided
    call z, load_file

    call show_screen
main_loop:
    call show_screen_if_scrolled
    call show_cursor_coords
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
    call hide_cursor
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
show_current_line_done:
    call show_cursor
    ret

out_of_memory:
    ld de, out_of_memory_message
    ld c, BDOS_Print_String
    call BDOS
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
    ld c, BDOS_Print_String
    call BDOS

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
    cp $33
    jp z, get_user_action_delete
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
get_user_action_delete:
    call get_key
    cp $7e
    jr nz, get_user_action_none
    ld a, USER_DELETE
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
LF equ 10
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
USER_DELETE equ 136
USER_QUIT equ 255

FCB equ 005CH   ; We use the standard default FCB
DMA equ 0080H   ; Standard DMA area
BDOS_Open_File  equ 15          ; 0F
BDOS_Close_File equ 16          ; 10
BDOS_Read_Sequential equ 20     ; 14
BDOS_Print_String equ 9         ; 09
BDOS_Set_DMA_Address equ 26     ; 1A
BDOS_Delete_File equ 19         ; 13
BDOS_Rename_File equ 23         ; 17
BDOS_Write_Sequential equ 21    ; 15
BDOS_Make_File equ 22           ; 16
BDOS_Read_Console_Buffer equ 10 ; 0A
BDOS_Search_for_First equ 17    ; 11

    
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
filename_buffer:
    ds 15
stack:
    ds 31
stacktop:
    db 0

;;;;;;;;;;;;;;;;;;;;;
; debug routines

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
    ld c, BDOS_Print_String
    call BDOS
    ret
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

    ; Any more to do?
    ld a, (all_done)
    cp 0
    jr z, save_main_loop

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

clear_remainder_of_fcb:
    ; This puts zeros in the rest of a FCB, for +12 to +35
    ld hl, FCB+12
    ld b, 24
clear_remainder_of_fcb1:
    ld (hl), 0
    inc hl
    djnz clear_remainder_of_fcb1
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
    ld c, BDOS_Print_String
    call BDOS
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

test_fill:
    call clear_selection
    call clear_doc_lines

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

; show_fcb_message:
;     db 'FCB: $'
; show_fcb:
;     ; Shows the FCB on screen.
;     ld de, show_fcb_message
;     ld c, BDOS_Print_String
;     call BDOS

;     ld de, FCB

;     ; Show Drive Letter
;     ld a, (de)
;     inc de
;     cp 0
;     jr z, show_fcb1
;     add a, 'A'-1
;     call print_a
;     ld a, ':'
;     call print_a
;     ld a, ' '
;     call print_a
;     jr show_fcb2

; show_fcb1:
;     ld a, 'd'
;     call print_a
;     ld a, 'f'
;     call print_a
;     ld a, 'l'
;     call print_a
;     ld a, 't'
;     call print_a
;     ld a, ':'
;     call print_a
;     ld a, ' '
;     call print_a
; show_fcb2:
;     ; Show filename
;     ld b, 8
; show_fcb3:
;     ld a, (de)
;     inc de
;     call print_a
;     djnz show_fcb3
; show_fcb4:
;     ; Show ext
;     ld a, '.'
;     call print_a
;     ld b, 3
; show_fcb5:
;     ld a, (de)
;     and %01111111
;     inc de
;     call print_a
;     djnz show_fcb5
; show_fcb_end:
;     ld a, 13
;     call print_a
;     ld a, 10
;     call print_a
;     ret


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

