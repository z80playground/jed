; CONSTANTS
VIEW_WIDTH equ 80
VIEW_HEIGHT equ 20
TAB_WIDTH equ 8
TAB_MASK equ %00000111
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

GREEN equ '2'
BLACK equ '0'
DEFAULT equ '9'
