;ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;³ VMODE - The Video Mode Selector Program               July, 2003 ³
;ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´
;³ Copyright (C) HiTech Laboratories, Denis Andrianov               ³
;³                                                                  ³
;³ This program is licenced under GNU!                              ³
;³ My E-mail address is                     d_andrianov@mail15.com  ³
;³                                                                  ³
;ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ

.8086

Code SEGMENT
ASSUME CS:Code,DS:Code,ES:Code

org 100h


Start:

;******************************
;Read the command line.
;******************************

mov  si, 81h                   ;Command line offset from beginning of code seg
call SkipSpaces                ;Skip to the first parameter.

mov  al, ds:[si]               ;Have we reached the end of the command
cmp  al, 13                    ;line already?
je   NoParams

mov  di, offset Param1$        ;Get the first parameter...
call GetParam
mov  di, offset Param1$        ;...and convert it to upper case.
call Upper

call SkipSpaces                ;Skip to the second parameter.

mov  di, offset Param2$        ;Get the second parameter.
call GetParam

;********************************************
;Convert the first argument from HEX string.
;********************************************

mov  si, offset Param1$
call fromHEX                        ;bx = Arg1

cmp  bx, 0
je   NoParams

;*******************************
;Interpret the second argument.
;*******************************

mov  si, offset Param2$
lodsb
cmp  al, '+'
jne  NormalModes
cmp  bx, 03h
jne  NormalModes

;*******************************
;Switch to 80x50 VGA text mode.
;*******************************

mov  ax, 1202h                  ;Set vertical resolution.
mov  bl, 30h
int  10h

mov  ax, 03h                    ;Set text mode.
int  10h

mov  ax, 1112h                  ;Set ROM font 8x8.
xor  bl, bl
int  10h

jmp  Exit

;****************************************
;Switch to any other mode via VESA call.
;****************************************

NormalModes:

mov  ax, 4f02h
int  10h

cmp  al, 4fh
je   FunctionSupported

mov  ah, 09h                           ;Function not supported.
mov  dx, offset NoVESAErr$
int  21h
jmp  Exit

FunctionSupported:
cmp  ah, 01h
jne  Exit

mov  ah, 09h                           ;Cannot set mode.
mov  dx, offset ModeErr$
int  21h
jmp  Exit

;********************************
;No parameters?
;********************************

NoParams:

mov  dx,offset Help$
mov  ah,09
int  21h

;******************************
;You can guess what this is...
;******************************

Exit:

mov  ah,4ch
int  21h


;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;                                 Procedures
;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;Note: all procs preserve all temporarily used registers.

;-----------------------------------------------------------------------------
;This proc takes:
;                  DS:SI -- pointer to the string to scan
;        returns:
;                  DS:SI -- pointer to the string without spaces
;-----------------------------------------------------------------------------
SkipSpaces PROC near

    push ax
    dec  si

SkipChar:

    inc  si
    mov  al, ds:[si]
    cmp  al, ' '
    je   SkipChar

    pop  ax
    ret

SkipSpaces ENDP

;-----------------------------------------------------------------------------
;This proc takes:
;                  DS:SI -- pointer to the string to scan
;                  ES:DI -- pointer to write the result to
;        returns:
;                 * string (ES:DI) which is equivalent to the string in DS:SI
;                   but is only up to the first space or char 13
;                 * updates DS:SI to point to next space or char 13
;-----------------------------------------------------------------------------
GetParam PROC near

    push ax
    cld                 ;Set SI, DI increment

GetChar:

    lodsb
    cmp  al, ' '
    je   GetParamExit
    cmp  al, 13
    je   GetParamExit
    stosb
    jmp  GetChar

GetParamExit:

    dec  si
    pop  ax
    ret

GetParam ENDP

;-----------------------------------------------------------------------------
;This proc takes:
;                  ES:DI -- pointer to the string to capitalize
;        returns:
;                  ES:DI -- pointer to the end of the string (char 0)
;-----------------------------------------------------------------------------
Upper PROC near

    push ax
    dec  di

UpperChar:

    inc  di
    mov  al, es:[di]

    cmp  al, 0
    je   UpperExit

    cmp  al, 'a'
    jb   UpperChar

    cmp  al, 'z'
    jg   UpperChar

    sub  al, 20h               ;Convert to upper case
    mov  es:[di], al
    jmp  UpperChar

UpperExit:

    pop  ax
    ret

Upper ENDP

;-----------------------------------------------------------------------------
;This proc takes:
;                  DS:SI -- pointer to the hex string (capitalized)
;        returns:
;                 result in BX
;                 DS:SI point to end of the string (past char 0)
;-----------------------------------------------------------------------------
FromHEX PROC near

    push ax
    push cx
    push di

    xor  bx, bx                ;Set result to 0
    cld                        ;SI must increment

FromHEXNextChar:

    lodsb
    cmp  al, 0
    je   FromHEXEnd

    mov  ah, al                ;Save string char in ah.
    xor  cx, cx                ;Position in the table is 0.

FromHEXNextCompare:

    mov  di, offset HEXTable$
    add  di, cx
    mov  al, ds:[di]

    cmp  al, ah
    je   FromHexTableEnds

    inc  cx
    cmp  cx, 16
    jb   FromHEXNextCompare
    jmp  FromHEXNextChar

FromHexTableEnds:

    shl  bx, 4
    add  bx, cx
    jmp  FromHEXNextChar


FromHEXEnd:

    pop  di
    pop  cx
    pop  ax
    ret

FromHEX ENDP


;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;                                    Data
;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ

Help$      db   '                       Command Line Video Mode Selector', 13, 10
           db   '               Copyright (C) HiTech Laboratories, Denis Andrianov', 13, 10
           db   'VMODE v1.1                                                           July, 2003', 13, 10
           db   'ÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄÍÄ', 13, 10
           db   13, 10
           db   'Syntax:  vmode [hex_value] [+]', 13, 10
           db   13, 10
           db   'Parameters:    hex_value   the value of the mode (in HEX) to be set', 13, 10
           db   '                       +   sets the 50 line text mode when hex_value = 03', 13, 10
           db   13, 10
           db   'Commonly used VGA text modes:   03h   80x25 and 80x50', 13, 10
           db   'Commonly used VESA text modes:  108h  80x60', 13, 10
           db   '                                109h  132x25', 13, 10
           db   '                                10Ah  132x43', 13, 10
           db   '                                10Bh  132x50', 13, 10
           db   '                                10Ch  132x60', 13, 10
           db   'Examples:  vmode 10C', 13, 10
           db   '           vmode 3', 13, 10
           db   '           vmode 3 +', 13, 10
           db   13, 10
           db   'WARNING: The program will attempt to set any mode you specify, even graphical', 13, 10
           db   '         modes!', 13, 10, '$'

NoVESAErr$ db   'VESA call not supported.', 13, 10, '$'
ModeErr$   db   'Cannot set mode.', 13, 10, '$'

HEXTable$  db   '0123456789ABCDEF'

Param1$    db   128 dup(0)
Param2$    db   128 dup(0)


Code ENDS
END Start

;*****************************************************************************
;                        A bit of additional info
;*****************************************************************************
;
;INT 10 - VESA SuperVGA BIOS - SET SuperVGA VIDEO MODE
;       AX = 4F02h
;       BX = new video mode (see #04082,#00083,#00084)
;       ES:DI -> (VBE 3.0+) CRTC information block, bit mode bit 11 set
;                 (see #04083)
;Return: AL = 4Fh if function supported
;       AH = status
;           00h successful
;           01h failed
;Notes: bit 13 may only be set if the video mode is present in the list of
;         accelerated video modes returned by AX=4F00h
;       if the DAC supports both 8 bits per primary color and 6 bits, it will
;         be reset to 6 bits after a mode set; use AX=4F08h to restore 8 bits
;SeeAlso: AX=4E03h,AX=4F00h,AX=4F01h,AX=4F03h,AX=4F08h
;
;(Table 00083)
;Values for VESA video mode:
; 00h-FFh OEM video modes (see #00010 at AH=00h)
; 100h  640x400x256
; 101h  640x480x256
; 102h  800x600x16
; 103h  800x600x256
; 104h  1024x768x16
; 105h  1024x768x256
; 106h  1280x1024x16
; 107h  1280x1024x256
; 108h  80x60 text
; 109h  132x25 text
; 10Ah  132x43 text
; 10Bh  132x50 text
; 10Ch  132x60 text
;---VBE v1.2+ ---
; 10Dh  320x200x32K
; 10Eh  320x200x64K
; 10Fh  320x200x16M
; 110h  640x480x32K
; 111h  640x480x64K
; 112h  640x480x16M
; 113h  800x600x32K
; 114h  800x600x64K
; 115h  800x600x16M
; 116h  1024x768x32K
; 117h  1024x768x64K
; 118h  1024x768x16M
; 119h  1280x1024x32K (1:5:5:5)
; 11Ah  1280x1024x64K (5:6:5)
; 11Bh  1280x1024x16M
;---VBE 2.0+ ---
; 120h  1600x1200x256
; 121h  1600x1200x32K
; 122h  1600x1200x64K
;81FFh  special full-memory access mode
;Notes: the special mode 81FFh preserves the contents of the video memory and
;         gives access to all of the memory; VESA recommends that the special
;         mode be a packed-pixel mode.  For VBE 2.0+, it is required that the
;         VBE implement the mode, but not place it in the list of available
;         modes (mode information for this mode can be queried directly,
;         however).
;       as of VBE 2.0, VESA will no longer define video mode numbers
;SeeAlso: #00010,#00011,#00084,#00191
;Index: video modes;VESA
;
;(Table 00084)
;Values for S3 OEM video mode:
; 201h  640x480x256
; 202h  800x600x16
; 203h  800x600x256
; 204h  1024x768x16
; 205h  1024x768x256
; 206h  1280x960x16
; 207h  1152x864x256 (Diamond Stealth 64)
; 208h  1280x1024x16
; 209h  1152x864x32K
; 20Ah  1152x864x64K (Diamond Stealth 64)
; 20Bh  1152x864x4G
; 211h  640x480x64K (Diamond Stealth 24)
; 211h  640x400x4G  (Diamond Stealth64 Video / Stealth64 Graphics)
; 212h  640x480x16M (Diamond Stealth 24)
; 301h  640x480x32K
;Note:  these modes are only available on video cards using S3's VESA driver
;SeeAlso: #00083,#00191,#00732 at INT 1A/AX=B102h
;Index: video modes;S3
;
;Format of VESA VBE CRTC Information Block:
;Offset Size    Description     (Table 04083)
; 00h   WORD    total number of pixels horizontally
; 02h   WORD    horizontal sync start (in pixels)
; 04h   WORD    horizontal sync end (in pixels)
; 06h   WORD    total number of scan lines
; 08h   WORD    vertical sync start (in scan lines)
; 0Ah   WORD    vertical sync end (in scan lines)
; 0Ch   BYTE    flags (see #04084)
; 0Dh   DWORD   pixel clock, in Hz
; 11h   WORD    refresh rate, in 0.01 Hz units
;               this field MUST be set to pixel_clock / (HTotal * VTotal),
;                 even though it may not actually be used by the VBE
;                 implementation
; 13h 40 BYTEs  reserved
;
;Bitfields for VESA VBE CRTC Information Block flags:
;Bit(s) Description     (Table 04084)
; 0     enable double scanning
; 1     enable interlacing
; 2     horizontal sync polarity (0 positive, 1 negative)
; 3     vertical sync polarity (0 positive, 1 negative)
;SeeAlso: #04083
;
;
