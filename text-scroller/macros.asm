.macro DebugRaster(color) {
    .if (debug) {
        pha
        lda #0 + color
        sta $d020
        sta $d021
        pla
    }
}

//----------------------------------------------------------
//  Macros
//----------------------------------------------------------
.macro SetupIRQ(IRQaddr,IRQline,IRQlineHi) {
    lda #$7f        // Disable CIA IRQ's
    sta $dc0d
    sta $dd0d

    lda #<IRQaddr   // Install RASTER IRQ
    ldx #>IRQaddr   // into Hardware
    sta $fffe       // Interrupt Vector
    stx $ffff

    lda #$01        // Enable RASTER IRQs
    sta $d01a
    lda #IRQline    // IRQ raster line
    sta $d012
    .if (IRQline > 255) {
        .error "supports only less than 256 lines"
    }
    lda $d011   // clear IRQ raster line bit 8
    and #$7f
    sta $d011

    asl $d019  // Ack any previous raster interrupt
    bit $dc0d  // reading the interrupt control registers
    bit $dd0d  // clears them
}
//----------------------------------------------------------
.macro EndIRQ(nextIRQaddr,nextIRQline,IRQlineHi) {
    asl $d019
    lda #<nextIRQaddr
    sta $fffe
    lda #>nextIRQaddr
    sta $ffff
    lda #nextIRQline
    sta $d012
    .if(IRQlineHi) {
        lda $d011
        ora #$80
        sta $d011
    }
}

.macro irq_start(end_lbl) {
    sta end_lbl-6
    stx end_lbl-4
    sty end_lbl-2
}

.macro irq_end(next, line) {
    :EndIRQ(next, line, false)
    lda #$00
    ldx #$00
    ldy #$00
    rti
}

// Setup stable raster IRQ NOTE: cannot be set on a badline or the second
// interrupt happens before we store the stack pointer (among other things)
.macro double_irq(end, stableIRQ) {
    //The CPU cycles spent to get in here                [7]
    irq_start(end) // 4+4+4 cycles

    lda #<stableIRQ     // Set IRQ Vector                [4]
    ldx #>stableIRQ     // to point to the               [4]
                        // next part of the
    sta $fffe           // Stable IRQ                    [4]
    stx $ffff           //                               [4]
    inc $d012           // set raster interrupt to the next line   [6]
    asl $d019           // Ack raster interrupt          [6]
    tsx                 // Store the stack pointer!      [2]
    cli                 //                               [2]
    // Total spent cycles up to this point   [51]
    nop        //                      [53]
    nop        //                      [55]
    nop        //                      [57]
    nop        //                      [59]
    nop        //Execute nop's         [61]
    nop        //until next RASTER     [63]
    nop        //IRQ Triggers
}

.macro add16_imm8(res, lo) {
    clc
    lda res
    adc #lo
    sta res+0
    lda res+1
    adc #0
    sta res+1
}
