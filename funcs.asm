find_address_of_bios
    ; Find address of BIOS
    ld hl, (1)
    inc hl
    inc hl
    inc hl                  ; hl points to BIOS_CONST
    ld (BIOS_CONST), hl
    inc hl
    inc hl
    inc hl                  ; hl points to BIOS_CON_IN
    ld (BIOS_CON_IN), hl
    inc hl
    inc hl
    inc hl                  ; hl points to BIOS_CON_OUT
    ld (BIOS_CON_OUT), hl
    ret

BIOS_CONST:
    dw 0
BIOS_CON_IN:
    dw 0
BIOS_CON_OUT:
    dw 0

JP_HL:
	jp	(hl)

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

newline:
    ld a, 13
    call print_a
    ld a, 10
    jp print_a

print_a:
    ; Prints "a" to the screen
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

get_key:
    ; Reads keyboard into "c"
    push hl
    push bc
    push de
    ld hl, (BIOS_CON_IN)
    call JP_HL
    pop de
    pop bc
    pop hl
    ld c, a
    ret

key_ready:
    ; Checks if there is a key to input.
    ; Returns Z if so, NZ if not.
    push hl
    push bc
    push de
    ld hl, (BIOS_CONST)
    call JP_HL
    pop de
    pop bc
    pop hl
    cp $FF
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

get_key_with_timeout:
    ; Wait for a key. Return it in C. If it takes too long to arrive, return 0.
    ld bc, 2000
get_key_with_timeout_loop:    
    push bc
    call key_ready
    pop bc
    jr z, get_key_with_timeout1
    dec bc
    ld a, b
    or c
    cp 0
    jr nz, get_key_with_timeout_loop
    ld c, 0                             ; Failed to get key, so return 0
    ret
get_key_with_timeout1:
    call get_key
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

move_to_xy:
    ; Pass in x coord in c, y coord in b
    ; This moves the cursor to the requested location on screen.
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, b
    push bc
    call print_a_as_decimal
    ld a, ';'
    call print_a
    pop bc
    ld a, c
    call print_a_as_decimal
    ld a, 'H'
    call print_a
    ret

show_string_de:
    ld c, BDOS_Print_String
    call BDOS
    ret

show_a_as_hex:
    push af
    srl a
    srl a
    srl a
    srl a
    add a,'0'
	cp ':'
	jr c, show_a_as_hex1
	add a, 7
show_a_as_hex1:
    call print_a
    pop af
    and %00001111
    add a,'0'
	cp ':'
	jr c, show_a_as_hex2
	add a, 7
show_a_as_hex2:
    call print_a
    ret

set_background_color:
    ; Pass in the color in "a"
    push af
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, '4'
    call print_a
    pop af
    call print_a
    ld a, 'm'
    jp print_a

set_bold_on:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, '1'
    call print_a
    ld a, 'm'
    jp print_a

set_bold_off:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, '0'
    call print_a
    ld a, 'm'
    jp print_a

clear_remainder_of_fcb:
    ; This puts zeros in the rest of a FCB, for +12 to +35
    ld hl, FCB+12
    ld b, 24
clear_remainder_of_fcb1:
    ld (hl), 0
    inc hl
    djnz clear_remainder_of_fcb1
    ret





; TODO: Remove this debug code...
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

