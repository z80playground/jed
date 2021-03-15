; This is where the syntax-highlighting functions are kept

add_syntax_highlighting:
    ; Go through the entire doc and add syntax highlighting.
    ; Syntax highlighting is done by adding bit 7 to certain characters in the text.
    ; So, for label highlighting, the first char of the line may be used to turn on highlighting
    ; at the start of the label. It is turned off by a space after the label with bit 7 set.
    ; For a comment we use bit 7 on a ";".
    ; For a string we use bit 7 on a single or double quote. Bit 7 on a subsequent quote turns it off.
    ; CR or EOF automatically turn it off.
    xor a
    ld (comment_mode), a            ; Reset the comment-mode flag, because we are not mid-comment.
    ld hl, (doc_start)
add_syntax_highlighting1:
    ld a, (hl)                      ; Look at next char in the doc
    cp END_OF_TEXT                  ; If it is the end of the doc, we are done.
    ret z
    cp ';'                          ; Is it the start of a comment?
    jr z, add_syntax_semicolon
    cp EOL                          ; Is it end of line?
    jr nz, add_syntax_highlighting2 ; If not, continue
    xor a
    ld (comment_mode), a            ; If we hit EOL, clear comment_mode
add_syntax_highlighting2:    
    inc hl
    jr add_syntax_highlighting1     ; Loop to next char in text
add_syntax_semicolon:
    ld a, (comment_mode)            ; Are we in comment mode?
    or a
    jr nz, add_syntax_highlighting2 ; If so, nothing to do
    ld a, 1
    ld (comment_mode), a
    ld a, (hl)
    or %10000000
    ld (hl), a
    jr add_syntax_highlighting2

add_syntax_highlighting_to_row:
    ; Go through a row and recalculate the syntax highlighting.
    ; Pass in HL pointing to the start of the row.
    xor a
    ld (comment_mode), a            ; Reset the comment-mode flag, because we are not mid-comment.
add_syntax_row1:
    ld a, (hl)                      ; Look at next char in the row
    and %01111111                   ; Clear bit 7
    cp END_OF_TEXT                  ; If it is the end of the doc, we are done.
    ret z
    cp ';'                          ; Is it the start of a comment?
    jr z, add_syntax_row_semicolon
    cp EOL                          ; Is it end of line?
    ret z
add_syntax_row2:
    ld (hl), a                      ; Store the char back again
    inc hl
    jr add_syntax_row1              ; Loop to next char in row
add_syntax_row_semicolon:
    ld a, (comment_mode)            ; Are we in comment mode?
    or a
    jr nz, add_syntax_row3          ; If so, nothing to do
    ld a, 1
    ld (comment_mode), a
    ld a, (hl)
    or %10000000
    jr add_syntax_row2
add_syntax_row3:
    ld a, (hl)
    jr add_syntax_row2

remove_syntax_highlighting:
    ; This is done by turning off bit 7 on all chars in the document.
    ld hl, (doc_start)
remove_syntax_highlighting1:
    ld a, (hl)                      ; Look at next char in the doc
    cp END_OF_TEXT                  ; If it is the end of the doc, we are done.
    ret z
    and %01111111
    ld (hl), a
    inc hl
    jr remove_syntax_highlighting1

comment_mode:
    db 0

