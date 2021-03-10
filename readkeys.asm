; This is the routine for reading in the JED.KEY file

JED_KEY_FILENAME:
    db 'JED     CFG'

read_jed_keys:
    ; Check if jed.key exists in the current directory.
    ; If so, use it. If not, return.
    ; Using it means reading in the file and writing it over the top of the keytable.

    ; Temporarily store the FCB the user passed in
    ld de, temp_store
    ld hl, FCB
    ld bc, 36
    ldir

    ld hl, FCB
    ld (hl), 0                      ; Select current directory
    ld hl, JED_KEY_FILENAME
    ld de, FCB+1
    ld bc, 11
    ldir                            ; Set FCB to point to "JED.KEY"
    call clear_remainder_of_fcb

    ld c, BDOS_Open_File
    ld de, FCB
    call BDOS
    inc a
    jr z, read_jed_keys_done        ; File not found, so just use default keys

    ld de, DMA                      ; Use the standard DMA area for data read from the file
    ld c, BDOS_Set_DMA_Address
    call BDOS

    ; We need to read in 13*10+1 bytes, so 131 bytes, so 1 full sector plus 3 bytes

    ld de, FCB
    ld c, BDOS_Read_Sequential
    call BDOS                       ; Read 128 bytes from JED.KEY to the DMA area

    ld de, keytable
    ld hl, DMA
    ld bc, 128
    ldir                            ; Copy the first 128 bytes into the keytable

    ld de, FCB
    ld c, BDOS_Read_Sequential
    call BDOS                       ; Read next 128 bytes from JED.KEY to the DMA area

    ld de, keytable+128
    ld hl, DMA
    ld bc, 3
    ldir                            ; Copy the remaining bytes into the keytable

read_jed_keys_done:
    ; Restore the original FCB the user passed in
    ld de, FCB
    ld hl, temp_store
    ld bc, 36
    ldir
    ret

temp_store:
    ds 36
