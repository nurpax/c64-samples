
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

irq0: {
    irq_start(end)

    inc framecount

    irq_end(irq0, irq0line)
end:
    rti
}
