
.const debug = false
:BasicUpstart2(start)

.import source "macros.asm"

//----------------------------------------------------------
//              Variables
//----------------------------------------------------------
.const irq0line = $10
.const textmodeswitchline = 50+200-12
.const rastercolorline = 50+200-9

// VIC-II BANK 1
.const VIC_BASE = $4000

start: {
    lda #0
    sta charpos
    sta charpos+1
    sta framecount

    // Take a copy of the system font and invert the bits in it (for raster
    // bars). The memory map in this routine is slightly funky, with a proper
    // font we could just use the inverted version of the font by orring $80
    // to the char code.
    jsr copy_inverted_system_font

    lda $DD00
    and #%11111100
    ora #%00000010 // VIC-II bank 1
    sta $dd00

    lda #0
    sta $d020
    sta $d021

    // screen ram ($0400), bitmap $2000
//Bits #1-#3: In text mode, pointer to character memory (bits #11-#13), relative to VIC bank, memory address $DD00. Values:
//
//%000, 0: $0000-$07FF, 0-2047.
//%100, 4: $2000-$27FF, 8192-10239.

// Bits #4-#7: Pointer to screen memory (bits #10-#13), relative to VIC bank, memory address $DD00. Values:
// %0000, 0: $0000-$03FF, 0-1023.
// %0001, 1: $0400-$07FF, 1024-2047.
    lda #$18
    sta $d018

    // clear out two last rows of the bitmap
    lda #0
    .for (var i = 0; i < 40; i++) {
        sta colora + 40*23 + i
        sta colorb + 40*23 + i
    }

    ldx #$00
copyimage:
    .for (var i = 0; i < 4; i++) {
        lda colora+2+i*256, x
        sta (VIC_BASE+$0400)+i*256, x
        lda colorb+i*256, x
        sta $d800+i*256, x
    }
    inx
    bne copyimage

    ldx #$00
clearlastrow:
    lda #BLACK
    sta $d800+24*40, x
    lda #' '
    sta (VIC_BASE+$0400)+24*40, x
    inx
    cpx #40
    bne clearlastrow

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
    jmp infloop
}

// Copy ROM font from $D000 ROM to $4000
// Code adapted from: https://dustlayer.com/vic-ii/2013/4/23/vic-ii-for-beginners-part-2-to-have-or-to-not-have-character
copy_inverted_system_font: {
    sei         // disable interrupts while we copy
    ldx #$08    // we loop 8 times (8x255 = 2Kb)
    lda #$33    // make the CPU see the Character Generator ROM...
    sta $01     // ...at $D000 by storing %00110011 into location $01
    lda #$d0    // load high byte of $D000
    sta $fc     // store it in a free location we use as vector
    ldy #$00    // init counter with 0
    sty $fb     // store it as low byte in the $FB/$FC vector

    lda #$40    // load high byte of $4000
    sta $f1     // store it in a free location we use as vector
    ldy #$00    // init counter with 0
    sty $f0     // store it as low byte in the $FB/$FC vector

loop:
    lda ($fb),y // read byte from vector stored in $fb/$fc
    eor #255
    sta ($f0),y // write to the RAM under ROM at same position
    iny         // do this 255 times...
    bne loop    // ..for low byte $00 to $FF
    inc $fc     // when we passed $FF increase high byte...
    inc $f1     // when we passed $FF increase high byte...
    dex         // ... and decrease X by one before restart
    bne loop    // We repeat this until X becomes Zero
    lda #$37    // switch in I/O mapped registers again...
    sta $01     // ... with %00110111 so CPU can see them
    cli         // turn off interrupt disable flag
    rts         // return from subroutine
}

framecount: .byte 0
charpos:    .byte 0, 0

irq0: {
    irq_start(end)

    inc framecount

    // Set screen mode
    lda #$3b // bitmap mode
    sta $d011
    lda #$18 // multicolor
    sta $d016
    // screen memory ptr
    lda #$18
    sta $d018

    jsr scroller_update_char_row

    irq_end(irq1, textmodeswitchline)
end:
    rti
}

irq1: {
    irq_start(end)

    lda #$1b        // screen on, text mode
    sta $d011

    lda framecount
    and #7
    eor #7 // xor bits 0-2 and leave bit 3 zero for 38 column mode
    sta $d016

    lda #$10 // bank + $0400
    sta $d018

    irq_end(irq2, rastercolorline)
end:
}

// Stable raster IRQ for color bars
irq2: {
    double_irq(end, irq3)

irq3:
    txs

    // Wait exactly 9 * (2+3) cycles so that the raster line is in the border
    ldx #$09
    dex
    bne *-1

    // First line is a bad line (so we have only 23 cycles!)
    lda colors1+0           // 4 cycles
    sta $d021               // 4 cycles
    .for (var i = 0; i < 6; i++) {
        nop
    }
    bit $fe

    // Next 7 lines are normal lines, so 63 cycles per color change
    ldx #$01
    // the loop total must be 63 cycles
!:
    lda colors1,x           // 4 cycles
    sta $d021               // 4 cycles
    .for (var i = 0; i < (63-15)/2; i++) {
        nop
    }
    inx                     // 2
    cpx #colorend-colors1   // 2
    bne !-                  // 3

    lda #0
    sta $d021

    irq_end(irq0, irq0line)
end:
}

//----------------------------------------------------------
scroller_update_char_row: {
    DebugRaster(GREEN)
    lda framecount
    and #7
    bne noscroll
    ldx #$00
moveline:
    lda (VIC_BASE+$0400)+24*40+1, x
    sta (VIC_BASE+$0400)+24*40, x
    inx
    cpx #39
    bne moveline

    clc
    lda charpos
    adc #<scrolltext
    sta $20
    lda charpos+1
    adc #>scrolltext
    sta $21

    ldy #0
    lda ($20),y
    sta (VIC_BASE+$0400)+24*40 + 39

    add16_imm8(charpos, 1)

    // wrap around for scroll char pos
    lda charpos+0
    cmp #<(scrolltextend-scrolltext)
    bne noscroll
    lda charpos+1
    cmp #>(scrolltextend-scrolltext)
    bne noscroll
    lda #0
    sta charpos
    sta charpos+1
noscroll:
    DebugRaster(0)
    rts
}

.align 64
colors1:
                .text "cmagcmag"
colorend:

scrolltext:
    .text "lorem ipsum     "
    .text "lorem ipsum     "
    .text "lorem ipsum     "
    .text "lorem ipsum     "
    .text "lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt"
    .text "                "
scrolltextend:

// We don't need the pad for anything but we don't want to allocate data or
// code there.
 *=$4000 "reserve VIC memory - don't let this overlap any other segment" virtual
pad: .fill $1000,0

* = $6000 "image"
gfx:
.import source "titleimage.txt"
