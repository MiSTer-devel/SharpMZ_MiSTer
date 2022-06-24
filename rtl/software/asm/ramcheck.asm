
LETNL:     EQU     0006h
PRNTS:     EQU     000Ch
PRNT:      EQU     0012h
MSG:       EQU     0015h
MONIT:     EQU     0086h
PRTHL:     EQU     03BAh
PRTHX:     EQU     03C3h
DPCT:      EQU     0DDCh
MSTART:    EQU     1200h

           ORG     10F0h

           DB      01h                                                                                     ; Code Type, 01 = Machine Code.
           DB      "RAM TEST V1.0", 0Dh, 00h, 00h                                                         ; Title/Name (17 bytes).
           DW      MSTART - START                                                                          ; Size of program.
           DW      START                                                                                   ; Load address of program.
           DW      START                                                                                   ; Exec address of program.
           DB      00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h          ; Comment (104 bytes).
           DB      00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
           DB      00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
           DB      00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
           DB      00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
           DB      00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
           DB      00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h

           ORG     01200h

START:     LD      DE,TITLE
           CALL    MSG
           CALL    LETNL
           LD      B, 20       ; Number of loops
LOOP:      LD      HL,MSTART   ; Start of checked memory,
           LD      D,0CEh      ; End memory check CE00
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

LOOP3:     LD      DE,OKCHECK
           CALL    MSG         ; Print check message in DE
           LD      A,B         ; Print loop count.
           CALL    PRTHX
           LD      DE,OKMSG
           CALL    MSG         ; Print ok message in DE
           DEC     B
           JR      NZ,LOOP
           LD      DE,DONEMSG
           CALL    MSG         ; Print check message in DE
           JP      MONIT

OKCHECK:   DB      11h
           DB      "CHECK: ", 0Dh
OKMSG:     DB      "OK.", 0Dh
DONEMSG:   DB      11h
           DB      "RAM TEST COMPLETE.", 0Dh

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

BITMSG:    DB      " BIT:  ", 0Dh
BANKMSG:   DB      " BANK: ", 0Dh

TITLE:     DB      "SHARPMZ RAM TEST (C) P. SMART 2018", 0Dh, 00h
