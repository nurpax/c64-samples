
.const badline = false
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
.var irq0line = 52+8
.if (badline) {
    .eval irq0line = 52+8-4
}

start: {
    ClearScreen($0400, $20)
    ClearScreen($d800, LIGHT_BLUE)

    lda #0
    sta framecount

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

    jmp infloop
}

framecount: .byte 0

.align 256
irq0: {
    double_irq(end, irq1)
irq1:
    txs
    ldx #$08
    dex
    bne *-1
    bit $00

    // Check if $d012 is incremented and rectify with an aditional cycle if neccessary
    lda $d012
    cmp $d012  // <- critical instruction (ZERO-Flag will indicate if Jitter = 0 or 1)

    // CYCLECOUNT: [61 -> 62] <- Will not work if this timing is wrong

    // cmp $d012 is originally a 5 cycle instruction but due to piplining tech. the
    // 5th cycle responsible for calculating the result is executed simultaniously
    // with the next OP fetch cycle (first cycle of beq *+2).

    // Add one cycle if $d012 wasn't incremented (Jitter / ZERO-Flag = 0)
    beq *+2

    /////////////////////////////////////////////////////////////
    // now at clock 3
    // http://www.lemon64.com/forum/viewtopic.php?t=64250&sid=6b7d7fbfc941f116cb7ca8247b1d748d
    /////////////////////////////////////////////////////////////

.if (!badline) {
    // VICE says this break happens on cycle 3 of the scanline
    break()
    // 0
    nop
    nop
    nop
    nop
    // 8
    // Scanline's first char (at maybe clock 12?)
    inc $d021
    inc $d021
    inc $d021
    inc $d021
    inc $d021
    inc $d021
    // 36 + 8 = 44

    lda #0
    sta $d021
    // 50

    bit $fe
    // 53
    nop
    nop
    nop
    nop
    nop
    // 63

    // next scanline
    // skip border
    nop
    nop
    nop
    nop
    inc $d021
    inc $d021

    lda #0
    sta $d021
} else {
    break()

    .for (var i = 0; i < 30; i++) {
        nop
    }

    // this should be clock 0 of bad line now

    // do 20 cycles of read-only work
    .for (var i = 0; i < 10; i++) {
        nop
    }
    // now we're at clock 0 of normal line

    // skip enough to get the first color write to hit before raster beam gets there
    bit $fe
    nop
    nop
    nop
    nop

    // boom we lost 40 cycles here
    inc $d021
    inc $d021
    // 48
    lda #0
    sta $d021
    // 54
}

    inc framecount

    irq_end(irq0, irq0line)
end:
    rti
}
