
.const debug = true
:BasicUpstart2(start)

.import source "macros.asm"

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

//----------------------------------------------------------
//              Variables
//----------------------------------------------------------
.const irq0line = 16

start: {
    ClearScreen($0400, $20)
    ClearScreen($d800, LIGHT_BLUE)

    lda #$a0
    .for (var y = 16; y < 25; y++) {
        .for (var x = 0; x < 40; x++) {
            sta $0400 + y*40 + x

        }
    }

    lda #0
    sta framecount

    lda #%00010000 | ((charset/2048)*2)
    sta $d018

    lda #0
    sta $d020

    // IRQ setup
    sei
    lda #$35        // Bank out kernal and basic
    sta $01
    // Setup raster IRQ
    SetupIRQ(irq0, irq0line, false)

    lda #0
    sta framecount
    cli


infloop:
    lda framecount
vsync:
    cmp framecount
    beq vsync

    DebugRaster(RED)
    jsr render_sinewave
    DebugRaster(WHITE)
    jsr anim_sinewave
    DebugRaster(BLACK)

    jmp infloop
}

.align 4

sintab1:
.for (var i = 0; i < 256; i++) {
    .byte sin(i/256 * PI * 2)*26
}

sintab2:
.for (var i = 0; i < 256; i++) {
    .byte sin(i/256 * PI * 2)*18 + 64
}

ypos:
    .fill 41, 0

anim_sinewave: {
    .const zp_th0 = $20
    .const zp_th1 = $22

    mov16(zp_th0, phase0)
    mov16(zp_th1, phase1)
    ldx #0
loop:
    ldy zp_th0+1
    lda sintab1, y
    ldy zp_th1+1
    clc
    adc sintab2, y
    lsr
    sta ypos, x

    add16_imm16(zp_th0, 2*1600)
    add16_imm16(zp_th1, 2*1100)

    inx
    cpx #41
    bne loop

    add16_imm16(phase0, 260*2)
    add16_imm16(phase1, -300*2)

    rts
phase0: .word 0
phase1: .word 0
}

.const MULTAB_X_STRIDE = 25
multab40:
.for (var x = 0; x < 40; x++) {
    .for (var y = 0; y < MULTAB_X_STRIDE; y++) {
        .word $0400 + y*40 + x + 14*40
    }
}

.align $100
lsrtab:
    .for (var i = 0; i < 256; i++) {
        .byte (i>>4)<<1
    }

asltab:
    .for (var i = 0; i < 256; i++) {
        .byte ((i+8) << 4)
    }

y0y1tblptr_lo:
    .for (var i = 0; i < 256; i++) {
        .byte (i<<2) + y0y1tbl
    }

y0y1tblptr_hi:
    .for (var i = 0; i < 256; i++) {
        .byte ((i<<2) + y0y1tbl) >> 8
    }

render_sinewave: {
    .const zp_yptr = $20
    .const zp_chrptr = $22
    .for (var i = 0; i < 40; i++) {
        // Compute destination y pointer
        ldy ypos+i
        ldx lsrtab, y
        lda multab40 + 2*MULTAB_X_STRIDE*i, x
        sta zp_yptr+0
        lda multab40 + 2*MULTAB_X_STRIDE*i+1, x
        sta zp_yptr+1

        lda ypos+i+1
        sec
        sbc ypos+i
        tax

        tya
        and #15
        ora asltab, x
        tax
        lda y0y1tblptr_lo, x
        sta zp_chrptr+0
        lda y0y1tblptr_hi, x
        sta zp_chrptr+1

        .for (var y = 0; y < 3; y++) {
            ldy #y
            lda (zp_chrptr),y
            ldy #y*40
            sta (zp_yptr),y
        }
    }
    rts
}

framecount: .byte 0

irq0: {
    irq_start(end)

    inc framecount

    irq_end(irq0, irq0line)
end:
    rti
}

* = $3000
.import source "charset.inc"
