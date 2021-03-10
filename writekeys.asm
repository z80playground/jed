; This is the routine for writing out the JED.KEY file

write_jed_keys:
    ; Look for JED.KEY in current drive, and if it exists, erase it.
    ; Then create a new JED.KEY file and write out the keytable to it.
    ; Then close it.
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
    cp 255
    jr z, write_jed_keys1           ; File not found, so skip erasing it

    ld de, FCB                      ; Erase the existing JED.KEY
    ld c, BDOS_Delete_File
    call BDOS
    cp 255                          ; Check if we could delete
    jr nz, write_jed_keys1

    ld de, could_not_delete_jedkeys_message
    call show_string_de
    jp write_jed_keys_fail

write_jed_keys1:
    call clear_remainder_of_fcb
    ld de, FCB
    ld c, BDOS_Make_File
    call BDOS                       ; Make JED.KEY
    cp 255                          ; Check if we could delete
    jr nz, write_jed_keys2

    ld de, could_not_create_jedkeys_message
    call show_string_de
    jp write_jed_keys_fail

write_jed_keys2:
    ld de, keytable
    ld c, BDOS_Set_DMA_Address
    call BDOS

    ld de, FCB
    ld c, BDOS_Write_Sequential
    call BDOS                       ; Write first 128 bytes

    ld de, keytable+128
    ld c, BDOS_Set_DMA_Address
    call BDOS

    ld de, FCB
    ld c, BDOS_Write_Sequential
    call BDOS                       ; Write remaining bytes

    ld de, FCB
    ld c, BDOS_Close_File
    call BDOS                       ; Close file
    ret

write_jed_keys_fail:
    jp 0

could_not_delete_jedkeys_message:
    db 'Error deleting old JED.KEY file.',13,10,'$'

could_not_create_jedkeys_message:
    db 'Error creating JED.KEY file.',13,10,'$'

