; This is JEDCONF.COM, the configuration tool for JED.COM (the editor).
; It's job is to ask the user some questions, then write a file
; called JED.KEY that contains the key definitions that have been configured.

    org $0100

    jp main_jed_conf
include "keytable.asm"
include "version.asm"
include "constants.asm"

main_jed_conf:
    call find_address_of_bios

    ; Read in JED.KEY if it exists
    call read_jed_keys

    ; Point to first question
    ld hl, questions+8
    ld (question_pointer), hl

    call cls

; me_loop:
;     call get_key_with_timeout
;     ld a, c
;     cp 0
;     jr z, did_timeout
;     cp 3
;     ret z
;     call show_a_as_hex
;     ld a, ','
;     call print_a
;     jr me_loop
; did_timeout:
;     ld a, 'X'
;     call print_a
;     call newline
;     jp me_loop
;     jp 0

    call hide_cursor
    call set_bold_on
    ld de, jedconf_welcome_message
    call show_string_de
    call set_bold_off

    call show_config    

    call newline
    call newline
    ld de, jedconf_instructions
    call show_string_de

jedconf_main_loop:
    call show_config
jedconf_main_loop1:
    call get_key_with_timeout
    ld a, c
    cp 0
    jr z, jedconf_main_loop1
    cp 'a'
    jr nz, not_up_key
    call try_move_up
    jr jedconf_main_loop
not_up_key:
    cp 'z'
    jr nz, not_down_key
    call try_move_down
    jr jedconf_main_loop
not_down_key:    
    cp 'x'
    jr nz, not_exit_key
    jr jedconf_exit
not_exit_key:
    cp 's'
    jr nz, not_save_key
    call write_jed_keys
    jp jedconf_exit
not_save_key:
    cp ' '
    jr c, get_key_sequence
    cp 127
    jr nc, get_key_sequence
    ; No idea what they just pressed!
    jr jedconf_main_loop

get_key_sequence:
    ; read the keys that are coming in, to get the full sequence.
    ; But first, clear the key buffer.
    push af
    ld hl, jedconf_key_buffer
    ld de, jedconf_key_buffer+1
    ld (hl), 0
    ld bc, 9
    ldir
    pop af

    ld hl, jedconf_key_buffer
    ld b, 8                             ; 8 more keys max
get_key_sequence_loop:
    ld (hl), a
    inc hl
    push hl
    push bc
    call get_key_with_timeout           ; get next key
    ld a, c
    pop bc
    pop hl
    cp 0                                ; Are we finished
    jr z, get_key_sequence_done
    djnz get_key_sequence_loop
    ; Check if any more. If so, error
    call get_key_with_timeout           ; get next key
    ld a, c
    cp 0
    jr z, get_key_sequence_done
    jp jedconf_main_loop                ; More than 8 keys, so ignore it

get_key_sequence_done:
;     ld b, 21
;     ld c, 1
;     call move_to_xy
;     ld hl, key_buffer
;     ld b, 8
; get_key_sequence_done_loop:    
;     push hl
;     push bc
;     ld a, (hl)
;     call show_a_as_hex
;     ld a, ' '
;     call print_a
;     pop bc
;     pop hl
;     inc hl
;     djnz get_key_sequence_done_loop
    ; Put the key sequence of 8 bytes into the correct place in the keytable
    ld hl, (question_pointer)
    inc hl
    inc hl
    ld e, (hl)
    inc hl
    ld d, (hl)                      ; de points to location in keytable
    ld hl, jedconf_key_buffer
    ld bc, 8
    ldir                            ; copy key def into table

    jp jedconf_main_loop

jedconf_exit:
    call show_cursor
    call cls
    jp 0

try_move_down:
    ld hl, (question_pointer)
    ld de, 8
    add hl, de
    ld a, (hl)
    cp 0
    ret z
    ld (question_pointer), hl
    ret

try_move_up:
    ld hl, (question_pointer)
    ld de, -8
    add hl, de
    ld a, (hl)
    cp 0
    ret z
    ld (question_pointer), hl
    ret

show_config:
    ; This shows the current config on the screen.
    ; It highlights the currently selected row.
    ld ix, questions+8
show_questions_loop:
    ld b, (ix+6)                    ; b = row
    ld c, 2                         ; c = column
    call move_to_xy                 ; Move the current print location to c,b

    push ix
    pop hl                          ; Get our question in hl
    ld de, (question_pointer)       ; Get the address of the current question
    ld a, l
    cp e                            ; Are we printing the currently selected question???
    jr nz, show_questions_loop1
    ld a, h
    cp d
    jr nz, show_questions_loop1

    ld a, GREEN
    call set_background_color
    call set_bold_on

show_questions_loop1:
    ld e, (ix+4)
    ld d, (ix+5)                    ; de points to the description text
    ld a, ' '
    call print_a
    call show_string_de 
    ld a, ' '
    call print_a

    ld b, (ix+6)                    ; b = row
    ld c, 40                        ; c = column
    call move_to_xy                 ; Move the current print location to c,b

    ld l, (ix+2)
    ld h, (ix+3)                    ; hl points to location in keytable
    ld a, ' '
    call print_a
    call show_current_key_def
    ld a, ' '
    call print_a

    ld a, DEFAULT
    call set_background_color
    call set_bold_off

    inc ix
    inc ix
    inc ix
    inc ix
    inc ix
    inc ix
    inc ix
    inc ix

    ld a, (ix+0)
    cp 0
    jr nz, show_questions_loop
    ret

show_current_key_def:
    ; hl points to 1-8 bytes in key table. Only show the non-zeros, show '  ' for a zero.
    ld b, 8
show_current_key_def_loop:
    ld a, (hl)
    cp 0
    jr z, show_00
    push bc
    call show_a_as_hex
    pop bc
    ld a, ' '
    call print_a    
    jr show_current_key_def1
show_00:
    ld a, ' '
    call print_a    
    ld a, ' '
    call print_a    
    ld a, ' '
    call print_a    
show_current_key_def1:
    inc hl
    djnz show_current_key_def_loop
    ret

; The format of the questions:
; key-code, location in the keytable, question text, y-coord.
; First and last are all zeros to make finding the first and last easier.
questions:
    dw 0, 0, 0, 0 
    dw ENTER, keytable+0, enter_text, 3
    dw TAB, keytable+10, tab_text, 4
    dw BACKSPACE, keytable+20, backspace_text, 5
    dw USER_DELETE, keytable+30, delete_text, 6
    dw USER_CURSOR_UP, keytable+40, cursor_up_text, 7
    dw USER_CURSOR_DOWN, keytable+50, cursor_down_text, 8
    dw USER_CURSOR_LEFT, keytable+60, cursor_left_text, 9
    dw USER_CURSOR_RIGHT, keytable+70, cursor_right_text, 10
    dw USER_CURSOR_HOME, keytable+80, home_text, 11
    dw USER_CURSOR_END, keytable+90, end_text, 12
    dw USER_CURSOR_PGUP, keytable+100, page_up_text, 13
    dw USER_CURSOR_PGDN, keytable+110, page_down_text, 14
    dw USER_QUIT, keytable+120, quit_text, 15
    dw 0, 0, 0, 0

enter_text:
    db 'Enter / Return','$'
tab_text:
    db 'Tab','$'
backspace_text:
    db 'Backspace','$'
delete_text:
    db 'Forward Delete','$'
cursor_up_text:
    db 'Cursor Up','$'
cursor_down_text:
    db 'Cursor Down','$'
cursor_left_text:
    db 'Cursor Left','$'
cursor_right_text:
    db 'Cursor Right','$'
home_text:
    db 'Home','$'
end_text:
    db 'End','$'
page_up_text:
    db 'Page Up','$'
page_down_text:
    db 'Page Down','$'
quit_text:
    db 'Exit, e.g. Ctrl-X','$'

jedconf_key_buffer:
    ds 10

include "funcs.asm"
include "readkeys.asm"
include "writekeys.asm"

question_pointer:
    dw 0

jedconf_welcome_message:
    db 'These are the current key-definitions for JED:',13,10,'$'    

jedconf_instructions:
    db 'Press "a" and "z" to select a key to configure.',13,10
    db 'When required key is highlighted, press that key on your keyboard.',13,10
    db 'Press "s" to save and exit. Press "x" to exit without saving.',13,10
    db '$'