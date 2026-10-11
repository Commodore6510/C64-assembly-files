; ============================================================================
; Linecrunch-style raster effect, C64 PAL (6569: 63 cycles per raster line)
; Code unchanged, only the comments were revised.
; ============================================================================
;
; Cycle convention used below: "cycle N of a line" = N cycles after the
; start of that raster line (the first cycle of the line is cycle 0).
;
; BACKGROUND: BAD LINES
; ---------------------
; Default text screen: $D011 = $1B  ->  25 rows, display enabled, YSCROLL = 3.
; YSCROLL = bits #0-2 of $D011.
;
; A "bad line" is a raster line (51-250 here) whose 3 low bits equal YSCROLL.
; The comparison uses the CURRENT raster line number (what a READ of $D012
; returns). It is not the compare value WRITTEN to $D012, which only selects
; the raster IRQ line.
;
; On a bad line the VIC-II
;   - steals the bus from cycle 12 on (BA low) to fetch the 40 character
;     pointers and colors (c-accesses),
;   - resets its row counter RC to 0 at cycle 14, which starts a new
;     character row.
; With YSCROLL = 3: bad lines at 51, 59, 67, 75 ...
;   row 0 = lines 51-58, row 1 = lines 59-66, row 2 (third row) = lines 67-74.
;
; WHAT THE ROUTINE DOES
; ---------------------
; 1. A raster IRQ fires at line 66 (last line of row 1).
; 2. Early in line 67, INC $D011 changes YSCROLL from 3 to 4.
;    This must be done before cycle 14 of line 67 (at the latest), i.e.
;    before the VIC-II checks the bad line condition for this line.
; 3. Line 67 is therefore NOT a bad line any more: no c-accesses, and RC is
;    not reset to 0. It keeps the value 7 it had at the end of row 1. 
;    The output pixels on line 66 are repeated on line 67.
; 4. YSCROLL = 4 now matches line 68, so line 68 is a bad line and the
;    next new row starts there. Every later bad line moves by one line 
;    as well (68, 76, 84 ...) until YSCROLL is restored.
; 5. A second raster IRQ at line 0 restores $D011 = $1B (YSCROLL = 3) and
;    re-arms the first IRQ for the next frame.
;
; The raster is NOT stabilised. The IRQ latency depends on the instruction
; the main program was executing (BASIC editor idle loop), so the write to
; $D011 has a jitter of 7 cycles (see the cycle count in IRQ). The padding
; instructions at the start of IRQ place that window well before cycle 14.
;
; "GHOST BYTE" TEST: uncomment the two lines before RTS in the init code.
; The pattern $AA stored at $3FFF should appear on the line that was
; not a bad line (line 67), because the VIC-II displays $3FFF in idle state.
; ============================================================================

interruptline=$FB   ; Zero page ADDRESS $FB, used as a variable.
                    ; It will hold the raster line number (66) of the
                    ; first interrupt. It is not the line number itself.

*=$1000             ; = 4096, start with SYS 4096

; ----------------------------------------------------------------------------
; Initialisation
; ----------------------------------------------------------------------------
     SEI            ; mask IRQs while the vectors are being changed

     LDA #$7F       ; bit 7 = 0: every bit written as 1 DISABLES that source
     STA $DC0D      ; CIA 1 (timer A etc.): no more IRQ. The KERNAL's 50/60 Hz
                    ; timer IRQ is gone: the raster IRQ replaces it
     STA $DD0D      ; CIA 2: this chip is wired to NMI, not to IRQ

     AND $D011      ; A = $7F AND $D011: clears bit 7 of $D011 = bit 8 of the
     STA $D011      ; raster compare line, so the compare value is below 256

     LDA $DD0D      ; reading a CIA interrupt control register clears
     LDA $DC0D      ; its pending flags: discard any pending CIA interrupt

     LDA #1
     STA $D01A      ; bit 0 = 1: enable the VIC-II raster interrupt

     LDA #50+16     ; raster line 66 = last line of row 1
     STA interruptline  ; keep it, IRQ2 needs it again every frame
     STA $D012      ; bits 0-7 of the raster compare line (bit 8 is 0)

     LDA #<IRQ      ; the KERNAL IRQ routine ends with JMP ($0314).
     STA $0314      ; Make that vector point to IRQ
     LDA #>IRQ
     STA $0315

     CLI            ; IRQs allowed again

; if Y Scroller is used ghostbyte will appear
; these lines make it visible
;        LDA #$AA   ;  
;        STA $3FFF  ;   

     RTS            ; back to BASIC

; ----------------------------------------------------------------------------
; 1st interrupt handler: raster line 66
; ----------------------------------------------------------------------------
IRQ
; The IRQ is requested at the start of line 66 (cycle 0).
; Cycles elapsed since then when the first instruction of IRQ starts:
;
;   2 to 8  : wait for the instruction in progress to end. The IRQ is only
;             taken into account at the second-to-last cycle of an
;             instruction. If it comes later, the whole next instruction
;             (2 to 7 cycles) runs first: worst case 1 + 7 = 8 cycles
;   +7      : IRQ sequence of the 6510 (push PCH, PCL, P, set I flag,
;             read the vector at $FFFE/$FFFF)
;             = 9 to 15 cycles
;   +29     : KERNAL entry at $FF48, up to and including JMP ($0314):
;             PHA, TXA, PHA, TYA, PHA, TSX, LDA $0104,X, AND #$10, BEQ, JMP
;             = 38 to 44 cycles
;
; So the jitter is 7 cycles (38..44).

     INC $323       ; 6 cycles. These five instructions do nothing useful:
     INC $323       ; $0323 is an unused RAM byte. They only delay the
     INC $323       ; write to $D011 (3x6 = 18 cycles)
     NOP            ; +2
     NOP            ; +2

; Padding = 22 cycles, 
;
; INC $D011 starts 60 to 66 cycles after the IRQ request.
; Line 66 lasts 63 cycles, so it starts at cycle 60-62 of line 66 or
; at cycle 0-3 of line 67.
; INC abs is a read-modify-write instruction of 6 cycles. The new value is
; written during the 6th cycle (the 5th cycle writes the old value back),
; i.e. 5 cycles after the start: cycle 2 to 8 of line 67.
; That is before cycle 14, the limit for cancelling the bad line.

     INC $D011      ; $1B -> $1C: YSCROLL 3 -> 4. Line 67 is not a bad line,
                    ; line 68 will be one

     LDX     #10     ; +2 
@-
     DEX             ; (3+2)x9 + (2+2) = +49  
     BNE @-          ; 
     NOP             ; +2   
     NOP             ; +2
     NOP             ; +2

; 57 cycles consumed

     INC $D011

     LDX     #10     ; +2 
@--
     DEX             ; (3+2)x9 + (2+2) = +49  
     BNE @--          ; 
     NOP             ; +2   
     NOP             ; +2
     NOP             ; +2

; 57 cycles consumed

     INC $D011
     LDX     #10     ; +2 
@---
     DEX             ; (3+2)x9 + (2+2) = +49  
     BNE @---          ; 
     NOP             ; +2   
     NOP             ; +2
     NOP             ; +2

; 57 cycles consumed

     INC $D011

     LDA #<IRQ2     ; next interrupt: IRQ2
     STA $0314      ; (low byte of the KERNAL IRQ vector)
     LDA #>IRQ2
     STA $0315      ; (high byte)

     LDA #0         ; raster compare line = 0 for the next interrupt
     STA $D012      ; (end of the frame, then wraps to the top)
     ASL $D019      ; acknowledge the raster IRQ. ASL is a read-modify-write
                    ; instruction: its first write puts back the value read,
                    ; which clears the pending flag (writing 1 clears a flag)

     JMP $EA81      ; KERNAL exit only: pull Y, X, A and RTI.
                    ; The full KERNAL routine ($EA31) is not run here,
                    ; it runs once per frame in IRQ2

; ----------------------------------------------------------------------------
; 2nd interrupt handler: raster line 0
; ----------------------------------------------------------------------------
IRQ2
     ASL $D019      ; acknowledge the raster IRQ (see above)

     LDA #<IRQ      ; give the vector back to IRQ,
     STA $0314      ; for the next frame
     LDA #>IRQ
     STA $0315

     LDA interruptline ; raster compare line = 66 again
     STA $D012

     LDA #$1B       ; default value: 25 rows, display on, YSCROLL = 3
     STA $D011      ; (bit 7 = 0: raster compare bit 8 stays 0)
                    ; Restored here, once per frame, far from line 67.

     JMP $EA31      ; full KERNAL IRQ routine: jiffy clock, cursor blink,
                    ; keyboard scan... Since the CIA 1 timer IRQ is disabled,
                    ; this call, once per frame, takes its place.
                    ; Ends with pull Y, X, A and RTI.
