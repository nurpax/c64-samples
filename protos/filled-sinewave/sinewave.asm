
.const debug = true
:BasicUpstart2(start)

.import source "macros.asm"

//----------------------------------------------------------
//              Variables
//----------------------------------------------------------
.const irq0line = 16
.const textmodeswitchline = 50+200-12
.const rastercolorline = 50+200-9

// VIC-II BANK 1
.const VIC_BASE = $4000

start: {
    lda #0
    sta framecount

    lda #0
    sta $d020
    sta $d021

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
    DebugRaster(BLACK)

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

