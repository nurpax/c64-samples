
:BasicUpstart2(mainStartup)

.var debug = false

.import source "macros.asm"
.import source "readme_petscii.s"

.const numcolorlines = 184 // must be divisible by 8
.const irq0line = 52
.const irq1line = irq0line + numcolorlines+10

// total anim size (must be power of two)
.const sintab_len = 256

mainStartup: {

* = mainStartup "Main Startup"
    lda #$00
    sta $d020
    sta $d021

    sei
    lda #$35        // Bank out kernal and basic
    sta $01         // $e000-$ffff

    SetupIRQ(irq0, irq0line, false)
    cli

    // copy PETSCII
    ldx #$00
loop:
    .for(var i=0; i<3; i++) {
        lda img+2+i*$100,x
        sta $0400+[i*$100],x
        lda img+2+25*40+i*$100,x
        sta $d800+[i*$100],x
    }
    lda img+2+[$2e8],x
    sta $0400+[$2e8],x
    lda img+2+25*40+[$2e8],x
    sta $d800+[$2e8],x
    inx
    bne loop

infloop:
    lda framecount
vsync:
    cmp framecount
    beq vsync

.if (debug) {
    lda #RED
    sta $d020
}

    jsr rasterbar_anim
.if (debug) {
    lda #BLACK
    sta $d020
}

    jmp infloop
}

render_bar: {
    tax
    .var cols = List().add(DARK_GRAY, BLUE, LIGHT_BLUE, LIGHT_BLUE)
    .var colsize = cols.size()
    .for (var i = 0; i < cols.size(); i++) {
        lda #cols.get(i)
        sta colors + i, x
    }
    .var xx = cols.size()
    .for (var i = cols.size()-2; i >= 0; i--, xx++) {
        lda #cols.get(i)
        sta colors + xx, x
    }
    rts
}

rasterbar_anim: {
    ldx #0
    lda #0
loop:
    lda #0
    sta colors+0, x
    sta colors+1, x
    sta colors+2, x
    sta colors+3, x
    sta colors+4, x
    sta colors+5, x
    sta colors+6, x
    sta colors+7, x
    txa
    clc
    adc #8
    tax
    cpx #numcolorlines
    bne loop

.const PHASEADD = 15
    .for (var i = 0; i < 5; i++) {
        lda sinidx
        clc
        adc #PHASEADD*i
        tax
        lda sintab, x
        jsr render_bar
    }


    inc sinidx
    lda #sintab_len-1
    and sinidx
    sta sinidx
    rts
}

irq0: {
    double_irq(end, irq)
irq:
    txs
    // we're now at cycle 11 (+/- jitter)

    // wait until "almost" end of line.  we do ldx, lda at the end of the
    // raster line and then have the STA instruction set the border color once
    // we're at the last cycle.
    waste_cycles(63-11-2-4)

    .var setbk = false
    .for (var i = 0; i < numcolorlines; i++) {
        ldx #i
        lda colors, x

        .var y = irq0line+i+2
        .var badline = (y & 7) == %011

        .if (!setbk && badline) {
            break()
            .eval setbk = true
        }
        sta $d020
        sta $d021

        .if (badline) {
            waste_cycles(20-(2+4+4+4))
        } else {
            waste_cycles(63-(2+4+4+4))
        }

    }

    lda #0
    sta $d021
.if (debug) {
    lda #WHITE
}
    sta $d020
    irq_end(irq1, irq1line)
end:
}

irq1: {
    irq_start(end)

    lda #BLACK
    sta $d020
    sta $d021

    inc framecount
    irq_end(irq0, irq0line)
end:
}

framecount: .byte 0
sinidx: .byte 0

.align 256
colors: .fill numcolorlines, 0 // (i/4)
.fill 256+32 - numcolorlines, 0 // pad so we don't overwrite

colorbar:
    .byte WHITE
colorbar_end:
.label colorbar_len = colorbar_end - colorbar

sintab:
    .const scale = 86
    .for (var i = 0; i < sintab_len; i++) {
        .byte sin(i/sintab_len*PI*2)*scale + scale
    }
