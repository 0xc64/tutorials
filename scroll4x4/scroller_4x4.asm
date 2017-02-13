; Dynamic 4x4 scroller
; 
; Platform: C64
; Code: Jesder / 0xc64
; Font: Unknown
; Compiler: win2c64 (http://www.aartbik.com)
; Website: http://www.0xc64.com
; Notes: Builds a 4x4 scroller font based on a 1x1 font
;

                        ; zero page register

REG_ZERO_FD             .equ $fd
REG_ZERO_FE             .equ $fe

                        ; common register definitions

REG_INTSERVICE_LOW      .equ $0314              ; interrupt service routine low byte
REG_INTSERVICE_HIGH     .equ $0315              ; interrupt service routine high byte
REG_SCREENCTL_1         .equ $d011              ; screen control register #1
REG_RASTERLINE          .equ $d012              ; raster line position 
REG_SCREENCTL_2         .equ $d016              ; screen control register #2
REG_MEMSETUP            .equ $d018              ; memory setup register
REG_INTFLAG             .equ $d019              ; interrupt flag register
REG_INTCONTROL          .equ $d01a              ; interrupt control register
REG_BORCOLOUR           .equ $d020              ; border colour register
REG_BGCOLOUR            .equ $d021              ; background colour register
REG_INTSTATUS_1         .equ $dc0d              ; interrupt control and status register #1
REG_INTSTATUS_2         .equ $dd0d              ; interrupt control and status register #2


                        ; constants

C_SCREEN_RAM            .equ $0400
C_CHARSET               .equ $3000
C_CHARSET_HIGH          .equ $3100
C_COLOUR_RAM            .equ $d800

                
                        ; program start

                        .org $0801

                        .byte $0b, $08, $01, $00, $9e, $32, $30, $36
                        .byte $31, $00, $00, $00        ; auto run


                        ; register first interrupt

                        sei
                        lda #$7f
                        sta REG_INTSTATUS_1             ; turn off the CIA interrupts
                        sta REG_INTSTATUS_2
                        and REG_SCREENCTL_1             ; clear high bit of raster line
                        sta REG_SCREENCTL_1

                        ldy #000
                        sty REG_RASTERLINE
                        lda #<init_routine
                        ldx #>init_routine
                        sta REG_INTSERVICE_LOW
                        stx REG_INTSERVICE_HIGH

                        lda #$01                        ; enable raster interrupts
                        sta REG_INTCONTROL
                        cli

forever                 jmp forever


                        ; helper routines -------------------------------------------------------------------------------------------------]
                        ; -----------------------------------------------------------------------------------------------------------------]

apply_interrupt         sta REG_RASTERLINE
                        stx REG_INTSERVICE_LOW
                        sty REG_INTSERVICE_HIGH
apply_interrupt_repeat  inc REG_INTFLAG
                        jmp $ea81


clear_screen_ramroutine lda #032
                        ldx #000                        ; clear screen ram routine
clear_screen_ram_loop   sta C_SCREEN_RAM, x
                        sta C_SCREEN_RAM + $100, x
                        sta C_SCREEN_RAM + $200, x
                        sta C_SCREEN_RAM + $2e8, x
                        inx
                        bne clear_screen_ram_loop
                        rts


clear_colour_ramroutine lda #000
                        ldx #000                        ; clear colour ram routine
clear_colour_ram_loop   sta C_COLOUR_RAM, x
                        sta C_COLOUR_RAM + $100, x
                        sta C_COLOUR_RAM + $200, x
                        sta C_COLOUR_RAM + $2e8, x
                        inx
                        bne clear_colour_ram_loop
                        rts


                        ; init routine ----------------------------------------------------------------------------------------------------]
                        ; -----------------------------------------------------------------------------------------------------------------]

init_routine            jsr clear_screen_ramroutine     ; initialise screen

                        jsr clear_colour_ramroutine

                        ldx #000                        ; relocate character set data
relocate_font_data      lda font_data, x
                        sta C_CHARSET, x
                        lda font_data + $100, x
                        sta C_CHARSET + $100, x
                        lda font_data + $180, x
                        sta C_CHARSET + $180, x
                        inx
                        bne relocate_font_data
                                          
                        ldx #160                        ; init colour ram for scroller
                        lda #001
set_scroller_colour     sta C_COLOUR_RAM + 759, x
                        dex
                        bne set_scroller_colour

                        ldx #019                        ; render short message in 1x1 font to screen
init_short_message      lda short_message, x
                        sta C_SCREEN_RAM + 610, x
                        lda #014
                        sta C_COLOUR_RAM + 610, x
                        dex
                        bpl init_short_message

                        lda #029                        ; switch to character set
                        sta REG_MEMSETUP

                        lda #000                        ; init screen and border colours
                        sta REG_BORCOLOUR
                        sta REG_BGCOLOUR

                        jmp hook_update_scroller


                        ; update & render scroller ----------------------------------------------------------------------------------------]
                        ; -----------------------------------------------------------------------------------------------------------------]

hook_update_scroller    lda #085
                        ldx #<update_scroller
                        ldy #>update_scroller
                        jmp apply_interrupt


update_scroller         ldx scroller_amount + 1
                        dex                             ; advance hardware scroll
                        dex
                        dex
                        bmi shift_scroller_data         ; detect if time to shift screen ram on the scroller
                        stx scroller_amount + 1         ; not time to advance scroller, so just update the hardware scroll value
                        jmp update_scroller_done        ; we're done for now

shift_scroller_data     stx REG_ZERO_FE                 ; cache scroll amount for later use

                        ldy #000                        ; shift screen ram to the left
scroller_shift_loop     lda C_SCREEN_RAM + $2f9, y      ; shift all 4 rows
                        sta C_SCREEN_RAM + $2f8, y
                        lda C_SCREEN_RAM + $321, y
                        sta C_SCREEN_RAM + $320, y
                        lda C_SCREEN_RAM + $349, y
                        sta C_SCREEN_RAM + $348, y
                        lda C_SCREEN_RAM + $371, y
                        sta C_SCREEN_RAM + $370, y
                        iny
                        cpy #039
                        bne scroller_shift_loop

                        ldx scroller_char_step + 1      ; grab step into rendering current scroller character
                        bpl render_next_scroll_colm     ; detect if we need to render a new character, or are still rendering current character (each letter is 4 chars wide)
                                                
scroller_message_index  ldx #000                        ; time to render a new character, so set up some which character to render and the bit mask
read_next_scroller_char lda scroller_message, x         ; grab next character to render
                        bpl advance_scroller_index      ; detect end of message control character
                        lda scroller_message
                        ldx #001                        ; reset index - set to 1 since this update will use first char in message
                        ldy #>scroller_message          ; reset scroller message read source
                        sty read_next_scroller_char + 2 
                        jmp save_scroller_index

advance_scroller_index  inx                             ; advance scroller message index
                        bne save_scroller_index         ; detect if reached 256 offset
                        inc read_next_scroller_char + 2 ; advance high byte for reading message
save_scroller_index     stx scroller_message_index + 1
                        
                        ldy #>C_CHARSET                 ; determine if character is in the low/high section of the charset
                        cmp #031
                        bcc calc_scrollchar_src_low
                        ldy #>C_CHARSET_HIGH

calc_scrollchar_src_low and #031                        ; calculate offset into char set for character bytes
                        asl
                        asl
                        asl

                        sty render_scroller_column + 2  ; store character high/low pointers for rendering
                        sty render_scroller_column2 + 2
                        sta render_scroller_column + 1
                        sta render_scroller_column2 + 1

                        lda #192                        ; reset the scroller character mask
                        sta scroller_character_mask + 1
                        lda #003                        ; reset step into new character mask
                        sta scroller_char_step + 1

render_next_scroll_colm clc
                        lda REG_ZERO_FE                 ; reset the hardware scroll value
                        adc #008
                        tax
                        stx scroller_amount + 1         ; save hardware scroll index

                        ldx #000                        ; init character byte loop counter
                        stx REG_ZERO_FD                 ; reset screen rendering offset and cache on zero page
render_scroller_column  lda C_CHARSET, x                ; load byte from character ram
scroller_character_mask and #192                        ; apply current mask
scroller_char_step      ldy #255                        
                        beq skip_shift_1                ; dont shift if we are already masking bits 0 and 1
shift_scroll_mask_loop1 lsr                             ; shift down until bits 0 and 1 are occupied
                        lsr
                        dey
                        bne shift_scroll_mask_loop1
skip_shift_1            asl                             ; multiply by 4 as a look up into our character matrix
                        asl
                        sta REG_ZERO_FE                 ; cache on zero page to recall shortly

                        inx                             ; advance to next byte in character ram
render_scroller_column2 lda C_CHARSET, x
                        and scroller_character_mask + 1 ; apply current mask
                        ldy scroller_char_step + 1
                        beq skip_shift_2                ; dont shift if we are already masking bits 0 and 1
shift_scroll_mask_loop2 lsr                             ; shift down until bits 0 and 1 are occupied
                        lsr
                        dey
                        bne shift_scroll_mask_loop2
                        
skip_shift_2            clc                             ; calculate characater code to use for this 2x2 block
                        adc REG_ZERO_FE                 ; grab offset calculated earlier
                        adc #064                        ; add offset to the character matrix

scroller_render_offset  ldy REG_ZERO_FD
                        sta C_SCREEN_RAM + $31f, y      ; render character to screen
                        tya
                        adc #040                        ; advance rendering offset for next pass of the loop
                        sta REG_ZERO_FD

                        inx                             ; advance to next byte in character ram
                        cpx #008                        ; detect if entire column now rendered
                        bne render_scroller_column

                        dec scroller_char_step + 1      ; advance scroller character step
                        lda scroller_character_mask + 1 ; advance scroller character mask for next update
                        lsr
                        lsr
                        sta scroller_character_mask + 1

update_scroller_done    jmp hook_apply_hw_scroll
                        

                        ; apply hardware scroll -------------------------------------------------------------------------------------------]
                        ; -----------------------------------------------------------------------------------------------------------------]

hook_apply_hw_scroll    lda #201
                        ldx #<apply_hardware_scroll
                        ldy #>apply_hardware_scroll
                        jmp apply_interrupt


apply_hardware_scroll   lda #$c0                        ; 38 column
scroller_amount         ora #007                        ; add hardware scroll - ready to apply

                        ldy #202                        ; wait for scan line scroller starts on
wait_scroller_start     cpy REG_RASTERLINE
                        bne wait_scroller_start

                        sta REG_SCREENCTL_2             ; apply hardware scroll value

                        jmp hook_reset_hw_scroll


                        ; reset hardware scroll -------------------------------------------------------------------------------------------]
                        ; -----------------------------------------------------------------------------------------------------------------]

hook_reset_hw_scroll    lda #234
                        ldx #<reset_hardware_scroll
                        ldy #>reset_hardware_scroll
                        jmp apply_interrupt


reset_hardware_scroll   lda #$c8                        ; 40 column mode + no scroll

                        ldy #235                        ; wait for scan line scroller end on
wait_scroller_end       cpy REG_RASTERLINE
                        bne wait_scroller_end

                        sta REG_SCREENCTL_2             ; apply reset to scroll & column mode

                        jmp hook_update_scroller


                        ; data & variables ------------------------------------------------------------------------------------------------]
                        ; -----------------------------------------------------------------------------------------------------------------]

scroller_message        .byte 020, 008, 009, 019, 032, 009, 019, 032, 001, 032, 020, 005, 019, 020, 032, 013
                        .byte 005, 019, 019, 001, 007, 005, 032, 006, 015, 018, 032, 020, 008, 005, 032, 052
                        .byte 024, 052, 032, 019, 003, 018, 015, 012, 012, 005, 018, 032, 018, 015, 021, 020
                        .byte 009, 014, 005, 046, 032, 014, 005, 005, 004, 032, 020, 015, 032, 005, 014, 019
                        .byte 021, 018, 005, 032, 009, 020, 032, 012, 015, 015, 016, 019, 032, 001, 018, 015
                        .byte 021, 014, 004, 032, 001, 020, 032, 050, 053, 053, 032, 003, 008, 001, 018, 001
                        .byte 003, 020, 005, 018, 019, 046, 032, 015, 014, 003, 005, 032, 020, 008, 001, 020
                        .byte 039, 019, 032, 023, 015, 018, 011, 009, 014, 007, 032, 009, 032, 023, 009, 012
                        .byte 012, 032, 014, 005, 005, 004, 032, 020, 015, 032, 001, 004, 004, 032, 019, 015
                        .byte 013, 005, 032, 003, 015, 012, 015, 021, 018, 032, 020, 015, 032, 013, 001, 011
                        .byte 005, 032, 009, 020, 032, 016, 018, 005, 020, 020, 025, 046, 046, 046, 032, 032
                        .byte 032, 032, 032, 019, 020, 009, 012, 012, 032, 014, 005, 005, 004, 032, 020, 015
                        .byte 032, 001, 004, 004, 032, 013, 015, 018, 005, 032, 020, 005, 024, 020, 032, 020
                        .byte 015, 032, 006, 009, 012, 012, 032, 015, 021, 020, 032, 020, 008, 005, 032, 050
                        .byte 053, 053, 032, 003, 008, 001, 018, 001, 003, 020, 005, 018, 019, 046, 046, 032
                        .byte 032, 057, 056, 055, 054, 053, 052, 051, 050, 049, 048, 032, 001, 014, 004, 032
                        .byte 012, 015, 015, 016, 045, 255

short_message           .byte 020, 008, 009, 019, 032, 009, 019, 032, 020, 008, 005, 032, 049, 024, 049, 032
                        .byte 006, 015, 014, 020

font_data               .byte $00, $00, $00, $00, $00, $00, $00, $00, $7c, $c6, $de, $c6, $c6, $c6, $c6, $00
                        .byte $fc, $c6, $dc, $c6, $c6, $c6, $fc, $00, $7c, $c6, $c0, $c0, $c0, $c6, $7c, $00
                        .byte $fc, $c6, $c6, $c6, $c6, $c6, $fc, $00, $7c, $c6, $f8, $c0, $c0, $c6, $7c, $00
                        .byte $7c, $c6, $f8, $c0, $c0, $c0, $c0, $c0, $7c, $c0, $ce, $c6, $c6, $c6, $7c, $00
                        .byte $c6, $c6, $de, $c6, $c6, $c6, $c6, $c0, $18, $18, $18, $18, $18, $18, $18, $00
                        .byte $06, $06, $06, $06, $06, $06, $c6, $7c, $c6, $c6, $dc, $c6, $c6, $c6, $c6, $00
                        .byte $c0, $c0, $c0, $c0, $c0, $c6, $7c, $00, $6c, $fe, $c6, $c6, $c6, $c6, $c6, $00
                        .byte $7c, $c6, $c6, $c6, $c6, $c6, $c6, $00, $7c, $c6, $c6, $c6, $c6, $c6, $7c, $00
                        .byte $fc, $c6, $dc, $c0, $c0, $c0, $c0, $c0, $7c, $c6, $c6, $c6, $c6, $c6, $7c, $06
                        .byte $fc, $c6, $dc, $c6, $c6, $c6, $c6, $00, $7c, $c0, $fc, $06, $06, $c6, $7c, $00
                        .byte $7e, $18, $18, $18, $18, $18, $18, $00, $c6, $c6, $c6, $c6, $c6, $c6, $7c, $00
                        .byte $c6, $c6, $c6, $c6, $c6, $6c, $38, $00, $c6, $c6, $c6, $c6, $c6, $fe, $6c, $00
                        .byte $c6, $c6, $7c, $1c, $c6, $c6, $c6, $00, $c6, $c6, $7c, $38, $38, $38, $38, $00
                        .byte $fe, $0c, $18, $30, $60, $c0, $fe, $00, $3c, $30, $30, $30, $30, $30, $3c, $00
                        .byte $00, $00, $00, $00, $00, $00, $00, $00, $3c, $0c, $0c, $0c, $0c, $0c, $3c, $00
                        .byte $00, $18, $3c, $7e, $18, $18, $18, $18, $00, $10, $30, $7f, $7f, $30, $10, $00
                        .byte $00, $00, $00, $00, $00, $00, $00, $00, $18, $18, $18, $18, $00, $00, $18, $00
                        .byte $66, $66, $66, $00, $00, $00, $00, $00, $66, $66, $ff, $66, $ff, $66, $66, $00
                        .byte $18, $3e, $60, $3c, $06, $7c, $18, $00, $62, $66, $0c, $18, $30, $66, $46, $00
                        .byte $3c, $66, $3c, $38, $67, $66, $3f, $00, $06, $0c, $18, $00, $00, $00, $00, $00
                        .byte $0c, $18, $30, $30, $30, $18, $0c, $00, $30, $18, $0c, $0c, $0c, $18, $30, $00
                        .byte $00, $66, $3c, $18, $3c, $66, $00, $00, $00, $18, $18, $7e, $18, $18, $00, $00
                        .byte $00, $00, $00, $00, $00, $18, $18, $30, $00, $00, $00, $7e, $00, $00, $00, $00
                        .byte $00, $00, $00, $00, $00, $30, $30, $00, $00, $03, $06, $0c, $18, $30, $60, $00
                        .byte $7c, $c6, $c6, $c6, $c6, $c6, $7c, $00, $38, $18, $18, $18, $18, $18, $18, $00
                        .byte $7c, $06, $7c, $c0, $c0, $c6, $7c, $00, $7c, $c6, $3c, $06, $06, $c6, $7c, $00
                        .byte $c6, $c6, $7e, $06, $06, $06, $06, $00, $fe, $c0, $fc, $06, $06, $c6, $7c, $00
                        .byte $7c, $c0, $dc, $c6, $c6, $c6, $7c, $00, $7e, $c6, $06, $06, $06, $06, $06, $00
                        .byte $7c, $c6, $7c, $c6, $c6, $c6, $7c, $00, $7e, $c6, $76, $06, $06, $06, $06, $00
                        .byte $00, $30, $30, $00, $30, $30, $00, $00, $00, $00, $18, $00, $00, $18, $18, $30
                        .byte $0e, $18, $30, $60, $30, $18, $0e, $00, $00, $00, $3c, $78, $00, $3c, $78, $00
                        .byte $70, $18, $0c, $06, $0c, $18, $70, $00, $3c, $66, $06, $0c, $18, $00, $18, $00

                        ; scroller characters (16 chars)
                        .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0e, $0e, $0e, $00
                        .byte $00, $00, $00, $00, $e0, $e0, $e0, $00, $00, $00, $00, $00, $ee, $ee, $ee, $00
                        .byte $0e, $0e, $0e, $00, $00, $00, $00, $00, $0e, $0e, $0e, $00, $0e, $0e, $0e, $00
                        .byte $0e, $0e, $0e, $00, $e0, $e0, $e0, $00, $0e, $0e, $0e, $00, $ee, $ee, $ee, $00
                        .byte $e0, $e0, $e0, $00, $00, $00, $00, $00, $e0, $e0, $e0, $00, $0e, $0e, $0e, $00
                        .byte $e0, $e0, $e0, $00, $e0, $e0, $e0, $00, $e0, $e0, $e0, $00, $ee, $ee, $ee, $00
                        .byte $ee, $ee, $ee, $00, $00, $00, $00, $00, $ee, $ee, $ee, $00, $0e, $0e, $0e, $00
                        .byte $ee, $ee, $ee, $00, $e0, $e0, $e0, $00, $ee, $ee, $ee, $00, $ee, $ee, $ee, $00
