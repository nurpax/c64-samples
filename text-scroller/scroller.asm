
.const debug = false
:BasicUpstart2(start)

.import source "macros.asm"

//----------------------------------------------------------
//              Variables
//----------------------------------------------------------
.const irq0line = $10
.const textmodeswitchline = 50+200-12
.const rastercolorline = 50+200-9
.const endofframeline = $ff // 50+200

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

    sta $d021
    lda #0
    sta $d020

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

    lda #0
    ldx #0
    sta $d020
    stx $d021

    // IRQ setup
    sei
    lda #$35        // Bank out kernal and basic
    sta $01         // $e000-$ffff


    lda #$7f   //Disable CIA IRQ's
    sta $dc0d
    sta $dd0d

    lda #<irq0
    ldx #>irq0
    sta $fffe
    stx $ffff

    lda #$01
    sta $d01a
    lda #irq0line   // IRQ raster line
    sta $d012
    lda #$1b        // Clear the High bit (lines 256-318)
    sta $d011

    asl $d019       // Ack any previous raster interrupt
    bit $dc0d       // reading the interrupt control registers
    bit $dd0d       // clears them

    lda #0
    sta framecount
    cli        //Allow IRQ's


infloop:
    jmp infloop
exit:
    rts
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
    //The CPU cycles spent to get in here       [7]
    sta reseta1    //Preserve A,X and Y                [4]
    stx resetx1    //Registers                 [4]
    sty resety1    //using self modifying code         [4]

    lda #<irq1 //Set IRQ Vector                [4]
    ldx #>irq1 //to point to the               [4]
       //next part of the
    sta $fffe  //Stable IRQ                    [4]
    stx $ffff      //                      [4]

    lda #textmodeswitchline                 // IRQ raster line
    sta $d012
    asl $d019  //Ack raster interrupt              [6]

    /////////////////////////////////////////////////////
    // basic per frame updates
    inc framecount

    // Set screen mode
    lda #$3b // bitmap mode
    sta $d011
    lda #$18 // multicolor
    sta $d016
    // screen memory ptr
    lda #$18
    sta $d018

    lda colora+1
    sta $d021

    jsr scroller_update_char_row

    /////////////////////////////////////////////////////
lab_a1: lda #$00    //Reload A,X,and Y
.label reseta1 = lab_a1+1
lab_x1: ldx #$00
.label resetx1 = lab_x1+1
lab_y1: ldy #$00
.label  resety1 = lab_y1+1
    rti
}

irq1: {
    irq_start(end)

    //////////////////////////////////////
    // textmode switch is padded to 63 cycles
    textmodeSwitch()

    irq_end(irq2, rastercolorline)
end:
}

//===========================================================================================
// Main interrupt handler
// [x] denotes the number of cycles
//===========================================================================================
irq2: {
    double_irq(end, irq3)

//===========================================================================================
// Part 2 of the Main interrupt handler
//===========================================================================================
irq3:
    txs         //Restore stack pointer to point the the return
                //information of irq1, being our endless loop.

    ldx #$09   //Wait exactly 9 * (2+3) cycles so that the raster line
    dex        //is in the border              [2]
    bne *-1    //                              [3]

    ///////////////////////////////////////////
    // first line (bad line so have only 23 cycles!)
    lda colors1+0           // 4 cycles
    sta $d021               // 4 cycles
    .for (var i = 0; i < 6; i++) {
        nop
    }
    bit $fe
    ///////////////////////////////////////////

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

    irq_end(irq4, endofframeline)
end:
}

//===========================================================================================
// Part 3 of the Main interrupt handler
//===========================================================================================
irq4: {
    irq_start(end)

    ldy #$13   //Waste time so this line is drawn completely
    dey        //  [2]
    bne *-1    //  [3]
            //same line!

    lda #0   //Back to our original colors
    ldx #0
    sta $d020
    stx $d021

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

    lda charpos
    sta $20
    lda charpos+1
    sta $21
    add16_imm16($20, <scrolltext, >scrolltext)

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

.macro textmodeSwitch() {
    // 2
    lda #$1b        // screen on, text mode
    // 4
    sta $d011

    // 4
    lda framecount
    // 2
    and #7
    // 2
    eor #7 // xor bits 0-2 and leave bit 3 zero for 38 column mode
    // 4
    sta $d016

    // 2
    lda #$10 // bank + $0400
    // 4
    sta $d018
    // 24 cycles so far
}

.align 64
colors1:
                .text "cmagcmag"
//                .byte 0, WHITE, BLUE, GRAY // stability test colors
//                .byte 0, WHITE, BLUE, GRAY
colorend:

scrolltext:
    .text "lorem ipsum     "
    .text "lorem ipsum     "
    .text "lorem ipsum     "
    .text "lorem ipsum     "
    .text "lorem ipsum     "
    .text "                "
scrolltextend:

// We don't need the pad for anything but we don't want to allocate data or
// code there.  Stuff from bintris.asm was overlaid on $4000 and caused bugs.
 *=$4000 "reserve VIC memory - don't let this overlap any other segment" virtual
pad: .fill $1000,0

* = $6000 "image"
gfx:
.import source "titleimage.txt"
