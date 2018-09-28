
KEYPC:     EQU     0E002h
KEYPF:     EQU     0E003h
CSTR:      EQU     0E002h
CSTPT:     EQU     0E003h
CONT0:     EQU     0E004h
CONT1:     EQU     0E005h
CONT2:     EQU     0E006h
CONTF:     EQU     0E007h
SUNDG:     EQU     0E008h
TEMP:      EQU     0E008h
LETNL:     EQU     0006h
NL:        EQU     0009h
PRNTS:     EQU     000Ch
PRNT:      EQU     0012h
MSG:       EQU     0015h
MSGX:      EQU     0018h
MONIT:     EQU     0086h
ST1:       EQU     0095h
PRTHL:     EQU     03BAh
PRTHX:     EQU     03C3h
DPCT:      EQU     0DDCh
?BRK:      EQU     0D11h
?RSTR1:    EQU     0EE6h
GRAMSTART: EQU     0C000h
GRAMEND:   EQU     0FFFFh
TPSTART:   EQU     10F0h
MEMSTART:  EQU     1200h
MSTART:    EQU     0BE00h

           ORG     TPSTART

SPV:
IBUFE:                                                                  ; TAPE BUFFER (128 BYTES)
;ATRB:      DS      virtual 1                                           ; ATTRIBUTE
ATRB:      DB      01h                                                  ; Code Type, 01 = Machine Code.
;NAME:      DS      virtual 17                                          ; FILE NAME
NAME:      DB      "TAPE CHECK V1.0", 0Dh, 00h                          ; Title/Name (17 bytes).
;SIZE:      DS      virtual 2                                           ; BYTESIZE
SIZE:      DW      MEND - MSTART                                        ; Size of program.
;DTADR:     DS      virtual 2                                           ; DATA ADDRESS
DTADR:     DW      MSTART                                               ; Load address of program.
;EXADR:     DS      virtual 2                                           ; EXECUTION ADDRESS
EXADR:     DW      MSTART                                               ; Exec address of program.
COMNT:     DS      104                                                  ; COMMENT
KANAF:     DS      virtual 1                                            ; KANA FLAG (01=GRAPHIC MODE)
DSPXY:     DS      virtual 2                                            ; DISPLAY COORDINATES
MANG:      DS      virtual 27                                           ; COLUMN MANAGEMENT
FLASH:     DS      virtual 1                                            ; FLASHING DATA
FLPST:     DS      virtual 2                                            ; FLASHING POSITION
FLSST:     DS      virtual 1                                            ; FLASHING STATUS
FLSDT:     DS      virtual 1                                            ; CURSOR DATA
STRGF:     DS      virtual 1                                            ; STRING FLAG
DPRNT:     DS      virtual 1                                            ; TAB COUNTER
TMCNT:     DS      virtual 2                                            ; TAPE MARK COUNTER
SUMDT:     DS      virtual 2                                            ; CHECK SUM DATA
CSMDT:     DS      virtual 2                                            ; FOR COMPARE SUM DATA
AMPM:      DS      virtual 1                                            ; AMPM DATA
TIMFG:     DS      virtual 1                                            ; TIME FLAG
SWRK:      DS      virtual 1                                            ; KEY SOUND FLAG
TEMPW:     DS      virtual 1                                            ; TEMPO WORK
ONTYO:     DS      virtual 1                                            ; ONTYO WORK
OCTV:      DS      virtual 1                                            ; OCTAVE WORK
RATIO:     DS      virtual 2                                            ; ONPU RATIO
BUFER:     DS      virtual 81                                           ; GET LINE BUFFER

           ORG     MSTART

START:     LD      A,0FFh      ; Set Red filter.
           OUT     (0EBh),A
           LD      A,000h      ; Set Green filter.
           OUT     (0ECh),A
           LD      A,000h      ; Set Blue filter.
           OUT     (0EDh),A
           LD      A,000h
           CALL    GRAMINIT
           LD      A,005h
           CALL    GRAMINIT
           LD      A,00Ah
           CALL    GRAMINIT
           LD      A, 0CCh     ; Set graphics mode to Indirect Page write.
           OUT     (0EAh),A
           LD      HL,0DE00h
           LD      (GRPHPOS),HL
           JR      SIGNON


GRAMINIT:  LD      HL,GRAMSTART
           LD      BC,GRAMEND - GRAMSTART
GRAM0:     OUT     (0EAh),A
           OUT     (0E8h),A
GRAM1:     LD      A,000h
           LD      (HL),A
           INC     HL
           DEC     BC
           LD      A,B
           OR      C
           JR      NZ,GRAM1
           OUT     (0E9h),A
           RET
            

SIGNON:    CALL    LETNL
           LD      DE,TITLE
           CALL    MSG
           CALL    LETNL
           LD      B,240       ; Number of loops
LOOP:      LD      HL,MEMSTART ; Start of checked memory,
           LD      D,0BEh      ; End memory check BE00
LOOP1:     LD      A,000h
           CP      L
           JR      NZ,LOOP1b
           CALL    PRTHL       ; Print HL as 4digit hex.
           LD      A,0C4h      ; Move cursor left.
           LD      E,004h      ; 4 times.
LOOP1a:    CALL    DPCT
           DEC     E
           JR      NZ,LOOP1a
LOOP1b:    INC     HL
           LD      A,H
           CP      D           ; Have we reached end of memory.
           JR      Z,LOOP3     ; Yes, exit.
           LD      A,(HL)      ; Read memory location under test, ie. 0.
           CPL                 ; Subtract, ie. FF - A, ie FF - 0 = FF.
           LD      (HL),A      ; Write it back, ie. FF.
           SUB     (HL)        ; Subtract written memory value from A, ie. should be 0.
           JR      NZ,LOOP2    ; Not zero, we have an error.
           LD      A,(HL)      ; Reread memory location, ie. FF
           CPL                 ; Subtract FF - FF
           LD      (HL),A      ; Write 0
           SUB     (HL)        ; Subtract 0
           JR      Z,LOOP1     ; Loop if the same, ie. 0
LOOP2:     LD      A,16h
           CALL    PRNT        ; Print A
           CALL    PRTHX       ; Print HL as 4 digit hex.
           CALL    PRNTS       ; Print space.
           XOR     A
           LD      (HL),A
           LD      A,(HL)      ; Get into A the failing bits.
           CALL    PRTHX       ; Print A as 2 digit hex.
           CALL    PRNTS       ; Print space.
           LD      A,0FFh      ; Repeat but first load FF into memory
           LD      (HL),A
           LD      A,(HL)
           CALL    PRTHX       ; Print A as 2 digit hex.
           NOP
           JR      LOOP4

LOOP3:     CALL    PRTHL
           LD      DE,OKCHECK
           CALL    MSG          ; Print check message in DE
           LD      A,B          ; Print loop count.
           CALL    PRTHX
           LD      DE,OKMSG
           CALL    MSG          ; Print ok message in DE
           CALL    NL
           LD      HL,(GRPHPOS) ; Get position of graphics progress line.
           OUT     (0E8h),A     ; Enable graphics memory.
           LD      A,0FFh
           LD      (HL),A
           OUT     (0E9h),A     ; Disable graphics memory.
           INC     HL
           LD      (GRPHPOS),HL
           DEC     B
           JR      NZ,LOOP
           LD      DE,DONEMSG
           CALL    MSG          ; Print check message in DE
           JP      MONIT

LOOP4:     LD      B,09h
           CALL    PRNTS        ; Print space.
           XOR     A            ; Zero A
           SCF                  ; Set Carry
LOOP5:     PUSH    AF           ; Store A and Flags
           LD      (HL),A       ; Store 0 to bad location.
           LD      A,(HL)       ; Read back
           CALL    PRTHX        ; Print A as 2 digit hex.
           CALL    PRNTS        ; Print space
           POP     AF           ; Get back A (ie. 0 + C)
           RLA                  ; Rotate left A. Bit LSB becomes Carry (ie. 1 first instance), Carry becomes MSB
           DJNZ    LOOP5        ; Loop if not zero, ie. print out all bit locations written and read to memory to locate bad bit.
           XOR     A            ; Zero A, clears flags.
           LD      A,80h
           LD      B,08h
LOOP6:     PUSH    AF           ; Repeat above but AND memory location with original A (ie. 80) 
           LD      C,A          ; Basically walk through all the bits to find which one is stuck.
           LD      (HL),A
           LD      A,(HL)
           AND     C
           NOP
           JR      Z,LOOP8      ; If zero then print out the bit number
           NOP
           NOP
           LD      A,C
           CPL
           LD      (HL),A
           LD      A,(HL)
           AND     C
           JR      NZ,LOOP8     ; As above, if the compliment doesnt yield zero, print out the bit number.
LOOP7:     POP     AF
           RRCA
           NOP
           DJNZ    LOOP6
           JP      MONIT

LOOP8:     CALL    LETNL        ; New line.
           LD      DE,BITMSG    ; BIT message
           CALL    MSG          ; Print message in DE
           LD      A,B
           DEC     A
           CALL    PRTHX        ; Print A as 2 digit hex, ie. BIT number.
           CALL    LETNL        ; New line
           LD      DE,BANKMSG   ; BANK message
           CALL    MSG          ; Print message in DE
           LD      A,H
           CP      50h          ; 'P'
           JR      NC,LOOP9     ; Work out bank number, 1, 2 or 3.
           LD      A,01h
           JR      LOOP11

LOOP9:     CP      90h
           JR      NC,LOOP10
           LD      A,02h
           JR      LOOP11

LOOP10:    LD      A,03h
LOOP11:    CALL    PRTHX        ; Print A as 2 digit hex, ie. BANK number.
           JR      LOOP7

OKCHECK:   DB      ", CHECK: ", 0Dh
OKMSG:     DB      " OK.", 0Dh
DONEMSG:   DB      11h
           DB      "RAM TEST COMPLETE.", 0Dh

BITMSG:    DB      " BIT:  ", 0Dh
BANKMSG:   DB      " BANK: ", 0Dh

TITLE:     DB      "SHARPMZ RAM TEST (C) P. SMART 2018", 0Dh, 00h
GRPHPOS:   DB      00h, 00h

MEND:
