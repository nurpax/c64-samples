
:BasicUpstart2(mainStartup)

.var debug = false

.var colors = List().add($000000,$838383,$ffffff,$959595)
.var            bintris_sprite_png = LoadPicture("c64_spritelogo_84x21.png", colors)

.import source "macros.asm"

.const SPRITE_LOGO_YSTART = 50
.const irq_top_line = 20
.const irq_warp_line = SPRITE_LOGO_YSTART-1

.const zptmp0 = $60
.const zptmp1 = $62
.const zptmp2 = $64

// total anim size (must be power of two)
.const sintab_len = 256

.macro ClearScreen(screen, clearByte) {
    lda #clearByte
    ldx #0
!loop:
    sta screen, x
    sta screen + $100, x
    sta screen + $200, x
    sta screen + $300, x
    inx
    bne !loop-
}

mainStartup: {

* = mainStartup "Main Startup"
//    lda #$00
//    sta $d020
//    sta $d021

    sei
    lda #$35        // Bank out kernal and basic
    sta $01         // $e000-$ffff

    SetupIRQ(irq_top, irq_top_line, false)
    cli

    jmp *
}

enable_sprites: {
    // double width
    lda #$7f
    sta $d01d
    sta $d017

    // enable sprites for the BINTRIS logo
    lda #%00001111
    sta $d01c
    sta $d015

    lda #(bintris_sprite/64)
    ldx #0
set_sprite_ptr:
    sta $07f8, x
    clc
    adc #1

    tay
    lda #WHITE
    sta $d027, x // sprite zero color
    tya

    inx
    cpx #4
    bne set_sprite_ptr

    lda #GREY
    sta $d025
    sta $d026

    lda #0
    sta $d010

    ldy #SPRITE_LOGO_YSTART // char pos y = 0
    .for (var s = 0; s < 4; s++) {
        ldx #(64+s*24)
        stx $d000+s*2
        sty $d000+s*2+1
    }
    rts
}

irq_top: {
    irq_start(end)

    lda #$18
    sta $d011

    jsr enable_sprites

    irq_end(irq_warp, irq_warp_line)
end:
}

irq_warp: {
    double_irq(end, irq)

.align 256
irq:
    txs

    bit $fe

    .for (var y = 0; y < 21*2; y++) {
        .var cycles = 63
        // skip bad line with FLD
        .var rasty = SPRITE_LOGO_YSTART + y
        .eval cycles = cycles - 3 - 8 // sprite overhead
        lda #$18 | ((rasty+1) & %111)
        sta $d011
        .eval cycles = cycles - 6

        lda logo_spritex+y*4 + 0
        ldx logo_spritex+y*4 + 1
        ldy logo_spritex+y*4 + 2
        .eval cycles -= 3*4

        sta $d000+0
        stx $d000+2
        sty $d000+4
        .eval cycles -= 4*3

        lda logo_spritex+y*4 + 3
        .eval cycles -= 4
        sta $d000+6
        .eval cycles -= 4

        .if (cycles < 0) {
            .error "cycles cannot be less than zero"
        }

        waste_cycles(cycles)
    }

    jsr update_logo_wobble

    irq_end(irq_top, irq_top_line)
end:
}

update_logo_wobble: {
    ldx #0
yloop:
    txa
    clc
    adc logo_phase
    tay

    lda sintab, y
    sta zptmp2
    txa
    tay
    lda zptmp2
    clc
    adc #64
    sta logo_spritex+0, y
    clc
    adc #24*2
    sta logo_spritex+1, y
    clc
    adc #24*2
    sta logo_spritex+2, y
    clc
    adc #24*2
    sta logo_spritex+3, y

    txa
    clc
    adc #4
    tax
    cpx #21*4*2
    bne yloop

    lda logo_phase
    clc
    adc #-3
    sta logo_phase
    rts
}

logo_phase:
    .byte 0

.align 256
sintab:
    .const scale = 12
    .for (var i = 0; i < sintab_len; i++) {
        .byte sin(i/sintab_len*PI*2)*scale + scale
    }

logo_spritex:
    .for (var y = 0; y < 21*2; y++) {
        .for (var s = 0; s < 4; s++) {
            .byte 64+s*24*2
        }
    }

.macro getSprite(spritePic, spriteNo) {
    .for (var y=0; y<21; y++) {
        .for (var x=0; x<3; x++) {
            .byte spritePic.getMulticolorByte(x + spriteNo * 3, y)
        }
    }
    .byte 0
}

* = $2000
bintris_sprite:
.for (var s = 0; s < 4; s++) {
    :getSprite(bintris_sprite_png, s)
}
