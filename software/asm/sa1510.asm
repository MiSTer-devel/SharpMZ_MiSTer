; Disassembly of the file "sa1510.rom"
; 

; Configurable parameters. These are set in the wrapper file, ie monitor_SA1510.asm
;
;COLW:   EQU     40                      ; Width of the display screen (ie. columns).
;ROW:    EQU     25                      ; Number of rows on display screen.
;SCRNSZ: EQU     COLW * ROW              ; Total size, in bytes, of the screen display area.

        ORG     00000H
MONIT:  JP      START
GETL:   JP      ?GETL
LETNL:  JP      ?LTNL
NL:     JP      ?NL
PRNTS:  JP      ?PRTS
PRNTT:  JP      ?PRTT
PRNT:   JP      ?PRNT
MSG:    JP      ?MSG
MSGX:   JP      ?MSGX                   ; RST 3
GETKY:  JP      ?GET
BRKEY:  JP      ?BRK
WRINF:  JP      ?WRI
WRDAT:  JP      ?WRD
RDINF:  JP      ?RDI
RDDAT:  JP      ?RDD
VERFY:  JP      ?VRFY
MELDY:  JP      ?MLDY
TIMST:  JP      ?TMST
        NOP     
        NOP     
        JP      1038H                   ; Interrupt routine
TIMRD:  JP      ?TMRD
BELL:   JP      ?BEL
XTEMP:  JP      ?TEMP
MSTA:   JP      MLDST
MSTP:   JP      MLDSP
START:  LD      SP,STACK
        IM      1
        CALL    ?MODE
        LD      B,0FFH
        LD      HL,NAME
        CALL    ?CLER
        LD      A,016H
        CALL    PRNT
        ;LD      A,0CFH                  ; Original attribute is white background in colour mode.
        LD      A,071H                  ; MZ700 Blue background in colour mode.
        LD      HL,ARAM
        JR      STRT1                   
        JP      1035H                   ; NMI routine.
STRT1:  CALL    CLR8
        LD      HL,TIMIN
        LD      A,0C3H
        LD      (1038H),A
        LD      (01039H),HL
        LD      A,004H
        LD      (TEMPW),A
        CALL    MLDSP
        CALL    NL
        LD      DE,00100H
        RST     018H
        IF      MODE80C = 0             ; For 80 char mode we need a hook to setup SPAGE mode.
        CALL    ?BEL
        ELSE
        CALL    HOOK                    ; Call new routine to setup SPAGE.
        ENDIF
SS:     LD      A,0FFH
SS1:    LD      (SWRK),A
        LD      HL,0E800H
        LD      (HL),055H
        JR      FD2                   

ST1:    CALL    NL
        LD      A,02AH
        CALL    PRNT
        LD      DE,BUFER
        CALL    GETL
ST2:    LD      A,(DE)
        INC     DE
        CP      00DH
        JR      Z,ST1                 
        CP      'J'                    ; JUMP?
        JR      Z,GOTO                 
        CP      'L'                    ; LOAD?
        JR      Z,LOAD                 
        CP      'F'                    ; FLOPPY?
        JR      Z,FD                 
        CP      'B'                     ; BELL?
        JR      Z,SG                 
        JR      ST2                   

        ; JUMP COMMAND
GOTO:   CALL    HLHEX
        JR      C,ST1                 
        JP      (HL)

        ; KEY SOUND ON OFF
SG:     LD      A,(SWRK)
        CPL     
        JR      SS1                   

        ; FLOPPY ROM CHECK AND RUN
FD:     LD      HL,0F000H
FD2:    LD      A,(HL)
        OR      A
        JR      NZ,ST1                
        JP      (HL)

?ER:    CP      002H
        JR      Z,ST1                 
        LD      DE,MSGE1
        RST     018H
        JR      ST1                   

        ; LOAD COMMAND
LOAD:   CALL    ?RDI
        JR      C,?ER                 
        CALL    NL
        LD      DE,MSG?2
        RST     018H
        LD      DE,NAME
        RST     018H
        CALL    ?RDD
        JR      C,?ER                 
        LD      HL,(EXADR)
        LD      A,H
        CP      012H
        JR      C,ST1                 
        JP      (HL)

        ; LOADING
MSG?2:  DB      04CH, 0B7H, 0A1H, 09CH
        DB      0A6H, 0B0H, 097H, 020H
        DB      00DH

        ; SIGN ON BANNER
MSG?3:  DB      "**  MONITOR SA-1510  **", 0DH

        ; For 80 Character mode we need some space, so shorten the Check Sum Error message.
        ;
        ; CHECK SUM ERROR
MSGE1:  IF      MODE80C = 0
        DB      043H, 098H, 092H, 09FH, 0A9H, 020H, 0A4H, 0A5H
        DB      0B3H, 020H, 092H, 09DH, 09DH, 0B7H, 09DH, 00DH
        ELSE
        DB      "CK SUM?", 0DH
        ENDIF

        ; Hook = 7 bytes.
HOOK:   IF      MODE80C = 1
        LD      A,0FFH
        LD      (SPAGE),A
        JP      ?BEL                     ; Original called routine
        ENDIF

        ; CR PAGE MODE1
.CR:    CALL    .MANG
        RRCA    
        JP      NC,CURS2
        LD      L,000H
        INC     H
        CP      ROW - 1                 ; End of line?
        JR      Z,.CP1                 
        INC     H
        JP      CURS1

.CP1:   LD      (DSPXY),HL

        ; SCROLLER
.SCROL: LD      BC,SCRNSZ - COLW        ; Scroll COLW -1 lines
        LD      DE,SCRN                 ; Start of the screen.
        LD      HL,SCRN + COLW          ; Start of screen + 1 line.
        LDIR    
        EX      DE,HL
        LD      B,COLW                  ; Clear last line at bottom of screen.
        CALL    ?CLER
        LD      BC,0001AH
        LD      DE,MANG
        LD      HL,MANG + 1
        LDIR    
        LD      (HL),000H
        LD      A,(MANG)
        OR      A
        JP      Z,?RSTR
        LD      HL,DSPXY + 1
        DEC     (HL)
        JR      .SCROL                   


        ; CTBL PAGE MODE1
.CTBL:  DW      .SCROL
        DW      CURSD
        DW      CURSU
        DW      CURSR
        DW      CURSL
        DW      HOM0
        DW      CLRS
        DW      DEL
        DW      INST
        DW      ALPHA
        DW      KANA
        DW      ?RSTR
        DW      REV
        DW      .CR
        DW      ?RSTR
        DW      ?RSTR

?MLDY:  PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      A,002H
        LD      (OCTV),A
        LD      B,001H
MLD1:   LD      A,(DE)
        CP      00DH
        JR      Z,MLD4                 
        CP      0C8H
        JR      Z,MLD4                 
        CP      0CFH
        JR      Z,MLD2                 
        CP      02DH
        JR      Z,MLD2                 
        CP      02BH
        JR      Z,MLD3                 
        CP      0D7H
        JR      Z,MLD3                 
        CP      023H
        LD      HL,MTBL
        JR      NZ,MLD1A                
        LD      HL,M?TBL
        INC     DE
MLD1A:  CALL    ONPU
        JR      C,MLD1                 
        CALL    RYTHM
        JR      C,MLD5                 
        CALL    MLDST
        LD      B,C
        JR      MLD1                   
MLD2:   LD      A,003H
MLD2A:  LD      (OCTV),A
        INC     DE
        JR      MLD1                   
MLD3:   LD      A,001H
        JR      MLD2A                   
MLD4:   CALL    RYTHM
MLD5:   PUSH    AF
        CALL    MLDSP
        POP     AF
        JP      RET3

ONPU:   PUSH    BC
        LD      B,008H
        LD      A,(DE)
ONP1A:  CP      (HL)
        JR      Z,ONP2                 
        INC     HL
        INC     HL
        INC     HL
        DJNZ    ONP1A                   
        SCF     
        INC     DE
        POP     BC
        RET     

ONP2:   INC     HL
        PUSH    DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        LD      A,H
        OR      A
        JR      Z,ONP2B                 
        LD      A,(OCTV)
ONP2A:  DEC     A
        JR      Z,ONP2B                 
        ADD     HL,HL
        JR      ONP2A                   
ONP2B:  LD      (RATIO),HL
        LD      HL,OCTV
        LD      (HL),002H
        DEC     HL
        POP     DE
        INC     DE
        LD      A,(DE)
        LD      B,A
        AND     0F0H
        CP      030H
        JR      Z,ONP2C                 
        LD      A,(HL)
        JR      ONP2D                   
ONP2C:  INC     DE
        LD      A,B
        AND     00FH
        LD      (HL),A
ONP2D:  LD      HL,OPTBL
        ADD     A,L
        LD      L,A
        LD      C,(HL)
        LD      A,(TEMPW)
        LD      B,A
        XOR     A
        JP      L09AB

MTBL:   DB      043H
        DB      077H
        DB      007H
        DB      044H
        DB      0A7H
        DB      006H
        DB      045H
        DB      0EDH
        DB      005H
        DB      046H
        DB      098H
        DB      005H
        DB      047H
        DB      0FCH
        DB      004H
        DB      041H
        DB      071H
        DB      004H
        DB      042H
        DB      0F5H
        DB      003H
        DB      052H
        DB      000H
        DB      000H
M?TBL:  DB      043H
        DB      00CH
        DB      007H
        DB      044H
        DB      047H
        DB      006H
        DB      045H
        DB      098H
        DB      005H
        DB      046H
        DB      048H
        DB      005H
        DB      047H
        DB      0B4H
        DB      004H
        DB      041H
        DB      031H
        DB      004H
        DB      042H
        DB      0BBH
        DB      003H
        DB      052H
        DB      000H
        DB      000H

OPTBL:  DB      001H
        DB      002H
        DB      003H
        DB      004H
        DB      006H
        DB      008H
        DB      00CH
        DB      010H
        DB      018H
        DB      020H

?SAVE:  LD      HL,FLSDT
        LD      (HL),0EFH
        LD      A,(KANAF)
        OR      A
        JR      Z,L0270                 
        LD      (HL),0FFH
L0270:  LD      A,(HL)
        PUSH    AF
        CALL    ?PONT
        LD      A,(HL)
        LD      (FLASH),A
        POP     AF
        LD      (HL),A
        XOR     A
        LD      HL,KEYPA
        LD      (HL),A
        CPL     
        LD      (HL),A
        RET     

MGP.I:  PUSH    AF
        PUSH    HL
        LD      HL,MGPNT
        LD      A,(HL)
        INC     A
        CP      033H
        JR      NZ,L028F                
        XOR     A
L028F:  PUSH    HL
        LD      L,A
        LD      A,(SPAGE)
        OR      A
        LD      A,L
        POP     HL
        JR      NZ,L029A                
        LD      (HL),A
L029A:  POP     HL
        POP     AF
        RET     

MGP.D:  PUSH    AF
        PUSH    HL
        LD      HL,MGPNT
        LD      A,(HL)
        DEC     A
        JP      P,L028F
        LD      A,032H
        JR      L028F                   
MLDST:  LD      HL,(RATIO)
        LD      A,H
        OR      A
        JR      Z,MLDSP                 
        PUSH    DE
        EX      DE,HL
        LD      HL,CONT0
        LD      (HL),E
        LD      (HL),D
        LD      A,001H
        POP     DE
        JR      L02C4                   
MLDSP:  LD      A,034H
        LD      (CONTF),A
        XOR     A
L02C4:  LD      (SUNDG),A
        RET     

RYTHM:  LD      HL,KEYPA
        LD      (HL),0F0H
        INC     HL
        LD      A,(HL)
        AND     081H
        JR      NZ,L02D5                
        SCF     
        RET     

L02D5:  LD      A,(SUNDG)
        RRCA    
        JR      C,L02D5                 
L02DB:  LD      A,(SUNDG)
        RRCA    
        JR      NC,L02DB                
        DJNZ    L02D5                   
        XOR     A
        RET     

?BEL:   PUSH    DE
        LD      DE,00DB1H
        RST     030H
        POP     DE
        RET     

?TEMP:  PUSH    AF
        PUSH    BC
        AND     00FH
        LD      B,A
        LD      A,008H
        SUB     B
        LD      (TEMPW),A
        POP     BC
        POP     AF
        RET     

?TMST:  DI      
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      (AMPM),A
        LD      A,0F0H
        LD      (TIMFG),A
        LD      HL,0A8C0H
        XOR     A
        SBC     HL,DE
        PUSH    HL
        INC     HL
        EX      DE,HL
        LD      HL,CONTF
        LD      (HL),074H
        LD      (HL),0B0H
        DEC     HL
        LD      (HL),E
        LD      (HL),D
        DEC     HL
        LD      (HL),00AH
        LD      (HL),000H
        INC     HL
        INC     HL
        LD      (HL),080H
        DEC     HL
L0323:  LD      C,(HL)
        LD      A,(HL)
        CP      D
        JR      NZ,L0323                
        LD      A,C
        CP      E
        JR      NZ,L0323                
        DEC     HL
        NOP     
        NOP     
        NOP     
        LD      (HL),00CH
        LD      (HL),07BH
        INC     HL
        POP     DE
L0336:  LD      C,(HL)
        LD      A,(HL)
        CP      D
        JR      NZ,L0336                
        LD      A,C
        CP      E
        JR      NZ,L0336                
        POP     HL
        POP     DE
        POP     BC
        EI      
        RET     

?TMRD:  PUSH    HL
        LD      HL,CONTF
        LD      (HL),080H
        DEC     HL
        DI      
        LD      E,(HL)
        LD      D,(HL)
        EI      
        LD      A,E
        OR      D
        JR      Z,?TMR1                 
        XOR     A
        LD      HL,0A8C0H
        SBC     HL,DE
        JR      C,?TMR2                 
        EX      DE,HL
        LD      A,(AMPM)
        POP     HL
        RET     

?TMR1:  LD      DE,0A8C0H
?TMR1A: LD      A,(AMPM)
        XOR     001H
        POP     HL
        RET     

?TMR2:  DI      
        LD      HL,CONT2
        LD      A,(HL)
        CPL     
        LD      E,A
        LD      A,(HL)
        CPL     
        LD      D,A
        EI      
        INC     DE
        JR      ?TMR1A                   

TIMIN:  PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      HL,AMPM
        LD      A,(HL)
        XOR     001H
        LD      (HL),A
        LD      HL,CONTF
        LD      (HL),080H
        DEC     HL
        PUSH    HL
        LD      E,(HL)
        LD      D,(HL)
        LD      HL,0A8C0H
        ADD     HL,DE
        DEC     HL
        DEC     HL
        EX      DE,HL
        POP     HL
        LD      (HL),E
        LD      (HL),D
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        EI      
        RET     

.DSP03:  EX      DE,HL
        LD      (HL),001H
        INC     HL
        LD      (HL),000H
        JP      CURSR
.MANG2: LD      A,(DSPXY + 1)
        ADD     A,L
        LD      L,A
        LD      A,(HL)
        INC     HL
        RL      (HL)
        OR      (HL)
        RR      (HL)
        RRCA    
        EX      DE,HL
        LD      HL,(DSPXY)
        RET     

PRTHL:  LD      C,H
        POP     AF
        LD      A,H
        CALL    PRTHX
        LD      A,L
        JR      PRTHX                   
        LD      B,E
        LD      B,E
PRTHX:  PUSH    AF
        RRCA    
        RRCA    
        RRCA    
        RRCA    
        CALL    ASC
        CALL    PRNT
        POP     AF
        CALL    ASC
        JP      PRNT
L03D5:  POP     DE
        POP     HL
        POP     BC
        POP     AF
        RET     

ASC:    AND     00FH
        CP      00AH
        JR      C,NOADD                 
        ADD     A,007H
NOADD:  ADD     A,030H
        RET     

HEXJ:   CP      030H
        RET     C
        CP      03AH
        JR      C,HEX1                 
        SUB     007H
        CP      040H
        JR      NC,HEX2                
HEX1:   AND     00FH
        RET     
HEX2:   SCF     
        RET     

        ; Unused memory.
        LD      C,B
        LD      C,H

HEX:    JR      HEXJ                   

HOME:   LD      HL,(DSPXY)
        LD      A,(MGPNT)
        SUB     H
        JR      NC,HOM1                
        ADD     A,032H
HOM1:   LD      (MGPNT),A
HOM0:   LD      HL,00000H
        JP      CURS3

        ; Unused memory.
        INC     L

HLHEX:  PUSH    DE
        CALL    L041F
        JR      C,L041D                 
        LD      H,A
        CALL    L041F
        JR      C,L041D                 
        LD      L,A
L041D:  POP     DE
        RET     

L041F:  PUSH    BC
        LD      A,(DE)
        INC     DE
        CALL    HEX
        JR      C,L0434                 
        RRCA    
        RRCA    
        RRCA    
        RRCA    
        LD      C,A
        LD      A,(DE)
        INC     DE
        CALL    HEX
        JR      C,L0434                 
        OR      C
L0434:  POP     BC
        RET     

?WRI:   DI      
        PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      D,0D7H
        LD      E,0CCH
        LD      HL,STACK
        LD      BC,00080H
L0444:  CALL    L071A
        CALL    MOTOR
        JR      C,L0464                 
        LD      A,E
        CP      0CCH
        JR      NZ,L045E                
        CALL    NL
        PUSH    DE
        LD      DE,MSG?7                ; Writing Message
        RST     018H
        LD      DE,NAME
        RST     018H
        POP     DE
L045E:  CALL    L077A
        CALL    L0485
L0464:  JP      L0552

        ; Writing
MSG?7:  DB      057H, 09DH, 0A6H, 096H, 0A6H
        DB      0B0H, 097H, 020H, 00DH

?WRD:   DI      
        PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      D,0D7H
        LD      E,053H
        LD      BC,(SIZE)
        LD      HL,(DTADR)
        LD      A,B
        OR      C
        JR      Z,L04CB                 
        JR      L0444                   
L0485:  PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      D,002H
        LD      A,0F0H
        LD      (KEYPA),A
L048F:  LD      A,(HL)
        CALL    L0767
        LD      A,(KEYPB)
        AND     081H
        JP      NZ,L049E
        SCF     
        JR      L04CB                   
L049E:  INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JP      NZ,L048F
        LD      HL,(SUMDT)
        LD      A,H
        CALL    L0767
        LD      A,L
        CALL    L0767
        CALL    L0D57
        DEC     D
        JP      NZ,L04BB
        OR      A
        JP      L04CB
L04BB:  LD      B,000H
L04BD:  CALL    L0D3E
        DEC     B
        JP      NZ,L04BD
        POP     HL
        POP     BC
        PUSH    BC
        PUSH    HL
        JP      L048F
L04CB:  POP     HL
        POP     BC
        POP     DE
        RET     

?RDI:   DI      
        PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      D,0D2H
        LD      E,0CCH
        LD      BC,00080H
        LD      HL,STACK
L04DD:  CALL    MOTOR
        JP      C,L0570
        CALL    TMARK
        JP      C,L0570
        CALL    L0505
        JP      L0552

?RDD:   DI      
        PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      D,0D2H
        LD      E,053H
        LD      BC,(SIZE)
        LD      HL,(DTADR)
        LD      A,B
        OR      C
        JP      Z,L0552
        JR      L04DD                   
L0505:  PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      H,002H
L050A:  LD      BC,KEYPB
        LD      DE,KEYPC
L0510:  CALL    EDGE
        JP      C,L0570
        CALL    DLY3
        LD      A,(DE)
        AND     020H
        JP      Z,L0510
        LD      D,H
        LD      HL,00000H
        LD      (SUMDT),HL
        POP     HL
        POP     BC
        PUSH    BC
        PUSH    HL
L052A:  CALL    RBYTE
        JP      C,L0570
        LD      (HL),A
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JP      NZ,L052A
        LD      HL,(SUMDT)
        CALL    RBYTE
        JP      C,L0570
        LD      E,A
        CALL    RBYTE
        JP      C,L0570
        CP      L
        JP      NZ,L0563
        LD      A,E
        CP      H
        JP      NZ,L0563
L0551:  XOR     A
L0552:  POP     HL
        POP     BC
        POP     DE
        CALL    MSTOP
        PUSH    AF
        LD      A,(TIMFG)
        CP      0F0H
        JR      NZ,L0561                
        EI      
L0561:  POP     AF
        RET     

L0563:  DEC     D
        JR      Z,L056C                 
        LD      H,D
        CALL    GAPCK
        JR      L050A                   
L056C:  LD      A,001H
        JR      L0572                   
L0570:  LD      A,002H
L0572:  SCF     
        JR      L0552                   


?VRFY:  DI      
        PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      BC,(SIZE)
        LD      HL,(DTADR)
        LD      D,0D2H
        LD      E,053H
        LD      A,B
        OR      C
        JR      Z,L0552                 
        CALL    L071A
        CALL    MOTOR
        JR      C,L0570                 
        CALL    TMARK
        JP      C,L0570
        CALL    TVRFY
        JR      L0552                   

TVRFY:  PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      H,002H
TVF1:   LD      BC,KEYPB
        LD      DE,KEYPC
TVF2:   CALL    EDGE
        JP      C,L0570
        CALL    DLY3
        LD      A,(DE)
        AND     020H
        JP      Z,TVF2
        LD      D,H
        POP     HL
        POP     BC
        PUSH    BC
        PUSH    HL
TVF3:   CALL    RBYTE
        JP      C,L0570
        CP      (HL)
        JP      NZ,L056C
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JP      NZ,TVF3
        LD      HL,(CSMDT)
        CALL    RBYTE
        CP      H
        JR      NZ,L056C                
        CALL    RBYTE
        CP      L
        JR      NZ,L056C                
        DEC     D
        JP      Z,L0551
        LD      H,D
        JR      TVF1                   

        ; PRINT '00'
GETLD:  LD      DE,009FCH
        RST     018H
        JP      AUTO2

        ; ROLL UP
ROLUP:  LD      HL,PBIAS
        LD      A,(ROLEND)
        CP      (HL)
        JP      Z,?RSTR
        JP      ROLU1

?LOAD:  PUSH    AF
        LD      A,(FLASH)
        CALL    ?PONT
        LD      (HL),A
        POP     AF
        RET     

        ; Unused memory
        XOR     E
        LD      C,A

EDGE:   LD      A,0F0H
        LD      (KEYPA),A
        NOP     
EDG1:   LD      A,(BC)
        AND     081H
        JP      NZ,EDG1A
        SCF     
        RET     
EDG1A:  LD      A,(DE)
        AND     020H
        JP      NZ,EDG1
EDG2:   LD      A,(BC)
        AND     081H
        JP      NZ,EDG3
        SCF     
        RET     
EDG3:   LD      A,(DE)
        AND     020H
        JP      Z,EDG2
        RET     

RBYTE:  PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      HL,00800H
        LD      BC,KEYPB
        LD      DE,KEYPC
RBY1:   CALL    EDGE
        JP      C,RBY3
        CALL    DLY3
        LD      A,(DE)
        AND     020H
        JP      Z,RBY2
        PUSH    HL
        LD      HL,(SUMDT)
        INC     HL
        LD      (SUMDT),HL
        POP     HL
        SCF     
RBY2:   LD      A,L
        RLA     
        LD      L,A
        DEC     H
        JP      NZ,RBY1
        CALL    EDGE
        LD      A,L
RBY3:   POP     HL
        POP     DE
        POP     BC
        RET     

TMARK:  CALL    GAPCK
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      HL,02828H              ; 40 short and 40 long gap pulses
        LD      A,E
        CP      0CCH
        JP      Z,TM0
        LD      HL,01414H              ; 20 short and 20 long tape mark pulses
TM0:    LD      (TMCNT),HL
        LD      BC,KEYPB
        LD      DE,KEYPC
TM1:    LD      HL,(TMCNT)
TM2:    CALL    EDGE
        JP      C,RET3
        CALL    DLY3
        LD      A,(DE)
        AND     020H
        JP      Z,TM1
        DEC     H
        JP      NZ,TM2
TM3:    CALL    EDGE
        JP      C,RET3
        CALL    DLY3
        LD      A,(DE)
        AND     020H
        JP      NZ,TM1
        DEC     L
        JP      NZ,TM3
        CALL    EDGE
RET3:
TM4:    POP     HL
        POP     DE
        POP     BC
        RET     

MOTOR:  PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      B,00AH
MOT1:   LD      A,(KEYPC)
        AND     010H
        JR      Z,MOT4                 
MOT2:   LD      B,0A6H
L06B1:  CALL    DLY12
        DJNZ    L06B1                   
        XOR     A
MOT7:   JR      RET3                   
MOT4:   LD      A,006H
        LD      HL,KEYPF
        LD      (HL),A
        INC     A
        LD      (HL),A
        DJNZ    MOT1                   
        CALL    NL
        LD      A,D
        CP      0D7H
        JR      Z,MOT8                 
        LD      DE,00D9EH
        JR      MOT9                   
MOT8:   LD      DE,MSG_3                ; RECORD message.
        RST     018H
        LD      DE,00DA0H
MOT9:   RST     018H
MOT5:   LD      A,(KEYPC)
        AND     010H
        JR      NZ,MOT2                
        CALL    ?BRK
        JR      NZ,MOT5                
        SCF     
        JR      MOT7                   

L06E7:  LD      B,0C9H
        LD      A,(KANAF)
        OR      A
        JR      NZ,L06F0                
        INC     B
L06F0:  LD      A,B
        JP      ?KY1

        ; PRESS RECORD message.
MSG_3:  DB      07FH, 020H
        DB      052H, 045H, 043H, 04FH, 052H
        DB      044H, 02EH, 00DH

        ; Padding not used
        DB      034H
        DB      044H

MSTOP:  PUSH    AF
        PUSH    BC
        PUSH    DE
        LD      B,00AH
L0705:  LD      A,(KEYPC)
        AND     010H
        JR      Z,L0717                 
        LD      A,006H
        LD      (KEYPF),A
        INC     A
        LD      (KEYPF),A
        DJNZ    L0705                   
L0717:  JP      ?RSTR1
L071A:  PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      DE,00000H
L0720:  LD      A,B
        OR      C
        JR      NZ,L072F                
        EX      DE,HL
        LD      (SUMDT),HL
        LD      (CSMDT),HL
        POP     HL
        POP     DE
        POP     BC
        RET     

L072F:  LD      A,(HL)
        PUSH    BC
        LD      B,008H
L0733:  RLCA    
        JR      NC,L0737                
        INC     DE
L0737:  DJNZ    L0733                   
        POP     BC
        INC     HL
        DEC     BC
        JR      L0720                   
L073E:  RLCA    
        RLCA    
        RLCA    
        LD      C,A
        LD      A,E
L0743:  DEC     H
        RRCA    
        JR      NC,L0743                
        LD      A,H
        ADD     A,C
        LD      C,A
        JP      SWEP01
?MODE:  LD      HL,KEYPF
        LD      (HL),08AH
        LD      (HL),007H
        LD      (HL),005H
        LD      (HL),001H
        RET     

L0759:  LD      A,00EH
L075B:  DEC     A
        JP      NZ,L075B
        RET     

L0760:  LD      A,00DH
L0762:  DEC     A
        JP      NZ,L0762
        RET     

L0767:  PUSH    BC
        LD      B,008H
        CALL    L0D57
L076D:  RLCA    
        CALL    C,L0D57
        CALL    NC,L0D3E
        DEC     B
        JP      NZ,L076D
        POP     BC
        RET     

L077A:  PUSH    BC
        PUSH    DE
        LD      A,E
        LD      BC,055F0H
        LD      DE,02828H
        CP      0CCH
        JP      Z,L078E
        LD      BC,02AF8H
        LD      DE,01414H
L078E:  CALL    L0D3E
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,L078E                
L0796:  CALL    L0D57
        DEC     D
        JR      NZ,L0796                
L079C:  CALL    L0D3E
        DEC     E
        JR      NZ,L079C                
        CALL    L0D57
        POP     DE
        POP     BC
        RET     

?GETL:  PUSH    AF
        PUSH    BC
        PUSH    HL
        PUSH    DE
GETL0:  CALL    ?SAVE
GETL0A: CALL    ?KEY
        CP      0CBH
        JR      Z,GETL0A                 
GETL0B: CALL    ?KEY
        CALL    ?FLAS
        JR      Z,GETL0B                 
GETL0C: PUSH    AF
        XOR     A
        LD      (STRGF),A
        POP     AF
AUTO3:  LD      B,A
GETL0D: CALL    ?LOAD
        LD      A,(SWRK)
        OR      A
        CALL    Z,?BEL
        LD      A,B
        CP      0E7H
        JP      Z,GETLD
        CP      0E6H
        JR      Z,CHGPK                 
        CP      0EEH
        JR      Z,CHGPA                 
        CP      0E5H
        JR      Z,DMT                 
        CP      0E0H
        JP      Z,LOCK
        JR      NC,GETL0B                
        AND     0F0H
        CP      0C0H
        JR      NZ,GETL2                
        LD      A,B
        CP      0CDH
        JR      Z,GETL3                 
        CP      0CBH
        JP      Z,GETLC
        CP      0C7H
        JR      NC,GETL5                
        LD      A,(KANAF)
        OR      A
        LD      A,B
        JR      Z,GETL5                 
GETL2:  LD      A,B
        CALL    ?DSP
AUTO2:  CALL    ?SAVE
        LD      A,(STRGF)
        OR      A
        JR      NZ,AUTO5                
AUTOL:  LD      E,014H
AUTOL1: CALL    ?KEY
        JR      NZ,AUTO3                
        CALL    AUTCK
GETL1:  JR      C,GETL0B                 
        DEC     E
        JR      NZ,AUTOL1                
        LD      A,001H
        LD      (STRGF),A
AUTO5:  CALL    DLY12
        CALL    DLY12
        CALL    ?KEY
        CALL    ?FLAS
        JR      NZ,GETL0C                
        CALL    AUTCK
        JR      C,GETL1                 
        JR      GETL0D                   
GETL5:  CALL    ?DPCT
        JR      AUTO2                   

CHGPA:  XOR     A
        IF      MODE80C = 1
        JR      CHGPK
        ELSE
        JR      CHGPK1                   
        ENDIF
CHGPK:  LD      A,0FFH
CHGPK1: LD      (SPAGE),A
        LD      A,0C6H
        CALL    ?DPCT
CHGP1:  JP      GETL0

GETLC:  POP     HL
        PUSH    HL
        LD      (HL),01BH
        INC     HL
        LD      (HL),00DH
        JR      GETLR                   

DMT:    LD      B,05AH
        JR      GETL2                   

GETL3:  CALL    .MANG
        LD      B,COLW     ; PDS was 028H
        JR      NC,GETLA                
        DEC     H
GETLB:  LD      B,COLW*2   ; 050H
GETL6:  LD      L,000H
        CALL    ?PNT1
        POP     DE
        PUSH    DE
GETL6A: LD      A,(HL)
        CALL    ?DACN
        LD      (DE),A
        INC     HL
        RES     3,H
        INC     DE
        DJNZ    GETL6A                   
        EX      DE,HL
GETL6B: LD      (HL),00DH
        DEC     HL
        LD      A,(HL)
        CP      020H
        JR      Z,GETL6B                 
GETLR:  CALL    ?LTNL
        JP      L03D5

GETLA:  RRCA    
        JR      NC,GETL6                
        JR      GETLB                   

LOCK:   LD      HL,SFTLK
        LD      A,(HL)
        CPL     
        LD      (HL),A
        JR      CHGP1                   

?MSG:   PUSH    AF
        PUSH    BC
        PUSH    DE
MSG1:   LD      A,(DE)
        CP      00DH
        JR      Z,MSGX2                 
        CALL    ?PRNT
        INC     DE
        JR      MSG1                   

?MSGX:  PUSH    AF
        PUSH    BC
        PUSH    DE
MSGX1:  LD      A,(DE)
        CP      00DH
MSGX2:  JP      Z,?RSTR1
        CALL    ?ADCN
        CALL    PRNT3
        INC     DE
        JR      MSGX1                   

?GET:   PUSH    BC
        PUSH    HL
        LD      B,009H
        LD      HL,01165H
        CALL    ?CLRFF
        POP     HL
        POP     BC
        CALL    ?KEY
        SUB     0F0H
        RET     Z
        ADD     A,0F0H
        JP      ?DACN

?KEY:  PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    ?SWEP
        LD      A,B
        RLCA    
        JR      C,?KY2                 
        LD      A,0F0H
?KY1:  LD      E,A
        CALL    AUTCK
        LD      A,(KDATW)
        OR      A
        JR      Z,?KY11                 
        CALL    DLY12
        CALL    ?SWEP
        LD      A,B
        RLCA    
        JR      C,?KY2                 
?KY11:  LD      A,E
        CP      0F0H
        JR      NZ,?KY9                
?KY10:  JP      RET3
?KY2:   RLCA    
        RLCA    
        RLCA    
        JP      C,L06E7
        RLCA    
        JP      C,_BRK
        LD      H,000H
        LD      L,C
        LD      A,C
        CP      038H
        JR      NC,?KY6                
        LD      A,(KANAF)
        OR      A
        LD      A,B
        RLCA    
        JR      NZ,?KY4                
        LD      B,A
        LD      A,(SFTLK)
        OR      A
        LD      A,B
        JR      Z,L0917                 
        RLA     
        CCF     
        RRA     
L0917:  RLA     
        RLA     
        JR      NC,?KY3                
L091B:  LD      DE,KTBLC
?KY5:   ADD     HL,DE
        LD      A,(HL)
        JR      ?KY1                   
?KY3:   RRA     
        JR      NC,?KY6                
        LD      DE,KTBLS
        JR      ?KY5                   
?KY6:   LD      DE,KTBL ; 00BEAH
        JR      ?KY5                   
?KY4:   RLCA    
        JR      C,?KY7                 
        RLCA    
        JR      C,L091B                 
        LD      DE,KTBLG
        JR      ?KY5                   
?KY7:   LD      DE,KTBLGS
        JR      ?KY5                   
?KY9:   CALL    AUTCK
        INC     A
        LD      A,E
        JR      ?KY10                   

?PRT:   LD      A,C
        CALL    ?ADCN
        LD      C,A
        AND     0F0H
        CP      0F0H
        RET     Z

        CP      0C0H
        LD      A,C
        JR      NZ,PRNT3                
PRNT5:  CALL    ?DPCT
        CP      0C3H
        JR      Z,PRNT4                 
        CP      0C5H
        JR      Z,PRNT2                 
        CP      0CDH                   ; CR
        JR      Z,PRNT2                 
        CP      0C6H
        RET     NZ

PRNT2:  XOR     A
PRNT2A: LD      (DPRNT),A
        RET     

PRNT3:  CALL    ?DSP
PRNT4:  LD      A,(DPRNT)
        INC     A
        CP      COLW*2                 ; 050H
        JR      C,PRNT4A                 
        SUB     COLW*2                 ; 050H
PRNT4A: JR      PRNT2A                   

?NL:    LD      A,(DPRNT)
        OR      A
        RET     Z

?LTNL:  LD      A,0CDH
        JR      PRNT5                   
?PRTT:  CALL    PRNTS
        LD      A,(DPRNT)
        OR      A
        RET     Z

L098C:  SUB     00AH
        JR      C,?PRTT                 
        JR      NZ,L098C                
        RET     

?PRTS:  LD      A,020H
?PRNT:  CP      00DH
        JR      Z,?LTNL                 
        PUSH    BC
        LD      C,A
        LD      B,A
        CALL    ?PRT
        LD      A,B
        POP     BC
        RET     

DLY3:  NEG     
        NEG     
        LD      A,02AH
        JP      L0762
L09AB:  ADD     A,C
        DJNZ    L09AB                   
        POP     BC
        LD      C,A
        XOR     A
        RET     

        DJNZ    PRNT4A                   
        PUSH    DE
        PUSH    HL
        CALL    ?SAVE
L09B9:  CALL    ?KEY
        CALL    ?FLAS
        JR      Z,L09B9                 
        CALL    ?LOAD
        JP      RET3
L09C7:  PUSH    DE
        PUSH    HL
        LD      HL,PBIAS
        XOR     A
        RLD     
        LD      D,A
        LD      E,(HL)
        RRD     
        XOR     A
        RR      D
        RR      E
        LD      HL,SCRN
        ADD     HL,DE
        LD      (PAGETP),HL
        POP     HL
        POP     DE
        RET     

L09E2:  XOR     A
CLR8:   LD      BC,00800H
        PUSH    DE
        LD      D,A
L09E8:  LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,L09E8                
        POP     DE
        RET     

AUTCK:  LD      HL,KDATW
        LD      A,(HL)
        INC     HL
        LD      D,(HL)
        LD      (HL),A
        SUB     D
        RET     NC
        INC     (HL)
        RET     

        DB      030H
        DB      030H
        DB      00DH

?FLAS:  PUSH    AF
        PUSH    HL
        LD      A,(KEYPC)
        RLCA    
        RLCA    
        JR      C,FLAS1                 
        LD      A,(FLSDT)
FLAS2:  CALL    ?PONT
        LD      (HL),A
FLAS3:  POP     HL
        POP     AF
        RET     

FLAS1:  LD      A,(FLASH)
        JR      FLAS2                   

REV:    LD      HL,REVFLG
        LD      A,(HL)
        OR      A
        CPL     
        LD      (HL),A
        JR      Z,REV1                 
        LD      A,(INVDSP)
        JR      REV2                   
REV1:   LD      A,(NRMDSP)
REV2:   JP      ?RSTR

.MANG:  LD      HL,MANG
        LD      A,(SPAGE)
        OR      A
        JP      NZ,.MANG2
        LD      A,(MGPNT)
.MANG3: SUB     008H
        INC     HL
        JR      NC,.MANG3                
        ADD     A,008H
        LD      C,(HL)
        DEC     HL
        LD      B,A
        INC     B
        PUSH    BC
        LD      A,(HL)
.MANG4: RR      C
        RRA     
        DJNZ    .MANG4                   
        POP     BC
        EX      DE,HL
.MANG1: LD      HL,(DSPXY)
        RET     

?SWEP:  PUSH    DE
        PUSH    HL
        XOR     A
        LD      (KDATW),A
        LD      B,0FAH
        LD      D,A
        CALL    ?BRK
        JR      NZ,SWEP6                
        LD      D,088H
        JR      SWEP9                   
SWEP6:  LD      HL,SWPW
        PUSH    HL
        JR      NC,SWEP11                
        LD      D,A
        AND     060H
        JR      NZ,SWEP11                
        LD      A,D
        XOR     (HL)
        BIT     4,A
        LD      (HL),D
        JR      Z,SWEP0                 
SWEP01: SET     7,D
SWEP0:  DEC     B
        POP     HL
        INC     HL
        LD      A,B
        LD      (KEYPA),A
        CP      0F0H
        JR      NZ,SWEP3                
        LD      A,(HL)
        CP      003H
        JR      C,SWEP9                 
        LD      (HL),000H
        RES     7,D
SWEP9:  LD      B,D
        POP     HL
        POP     DE
        RET     

SWEP11: LD      (HL),000H
        JR      SWEP0                   
SWEP3:  LD      A,(KEYPB)
        LD      E,A
        CPL     
        AND     (HL)
        LD      (HL),E
        PUSH    HL
        LD      HL,KDATW
        PUSH    BC
        LD      B,008H
SWEP8:  RLC     E
        JR      C,SWEP7                 
        INC     (HL)
SWEP7:  DJNZ    SWEP8                   
        POP     BC
        OR      A
        JR      Z,SWEP0                 
        LD      E,A
SWEP2:  LD      H,008H
        LD      A,B
        DEC     A
        AND     00FH
        JP      L073E

; ASCII TO DISPLAY CODE TABLE
ATBL:   DB      0CCH
        DB      0E0H
        DB      0F2H
        DB      0F3H
        DB      0CEH
        DB      0CFH
        DB      0F6H
        DB      0F7H
        DB      0F8H
        DB      0F9H
        DB      0FAH
        DB      0FBH
        DB      0FCH
        DB      0FDH
        DB      0FEH
        DB      0FFH
        DB      0E1H
        DB      0C1H
        DB      0C2H
        DB      0C3H
        DB      0C4H
        DB      0C5H
        DB      0C6H
        DB      0E2H
        DB      0E3H
        DB      0E4H
        DB      0E5H
        DB      0E6H
        DB      0EBH
        DB      0EEH
        DB      0EFH
        DB      0F4H
        DB      000H
        DB      061H
        DB      062H
        DB      063H
        DB      064H
        DB      065H
        DB      066H
        DB      067H
        DB      068H
        DB      069H
        DB      06BH
        DB      06AH
        DB      02FH
        DB      02AH
        DB      02EH
        DB      02DH
        DB      020H
        DB      021H
        DB      022H
        DB      023H
        DB      024H
        DB      025H
        DB      026H
        DB      027H
        DB      028H
        DB      029H
        DB      04FH
        DB      02CH
        DB      051H
        DB      02BH
        DB      057H
        DB      049H
        DB      055H
        DB      001H
        DB      002H
        DB      003H
        DB      004H
        DB      005H
        DB      006H
        DB      007H
        DB      008H
        DB      009H
        DB      00AH
        DB      00BH
        DB      00CH
        DB      00DH
        DB      00EH
        DB      00FH
        DB      010H
        DB      011H
        DB      012H
        DB      013H
        DB      014H
        DB      015H
        DB      016H
        DB      017H
        DB      018H
        DB      019H
        DB      01AH
        DB      052H
        DB      059H
        DB      054H
        DB      050H
        DB      045H
        DB      0C7H
        DB      0C8H
        DB      0C9H
        DB      0CAH
        DB      0CBH
        DB      0CCH
        DB      0CDH
        DB      0CEH
        DB      0CFH
        DB      0DFH
        DB      0E7H
        DB      0E8H
        DB      0E9H
        DB      0EAH
        DB      0ECH
        DB      0EDH
        DB      0D0H
        DB      0D1H
        DB      0D2H
        DB      0D3H
        DB      0D4H
        DB      0D5H
        DB      0D6H
        DB      0D7H
        DB      0D8H
        DB      0D9H
        DB      0DAH
        DB      0DBH
        DB      0DCH
        DB      0DDH
        DB      0DEH
        DB      0C0H
        DB      040H
        DB      0BDH
        DB      09DH
        DB      0B1H
        DB      0B5H
        DB      0B9H
        DB      0B4H
        DB      09EH
        DB      0B2H
        DB      0B6H
        DB      0BAH
        DB      0BEH
        DB      09FH
        DB      0B3H
        DB      0B7H
        DB      0BBH
        DB      0BFH
        DB      0A3H
        DB      085H
        DB      0A4H
        DB      0A5H
        DB      0A6H
        DB      094H
        DB      087H
        DB      088H
        DB      09CH
        DB      082H
        DB      098H
        DB      084H
        DB      092H
        DB      090H
        DB      083H
        DB      091H
        DB      081H
        DB      09AH
        DB      097H
        DB      093H
        DB      095H
        DB      089H
        DB      0A1H
        DB      0AFH
        DB      08BH
        DB      086H
        DB      096H
        DB      0A2H
        DB      0ABH
        DB      0AAH
        DB      08AH
        DB      08EH
        DB      0B0H
        DB      0ADH
        DB      08DH
        DB      0A7H
        DB      0A8H
        DB      0A9H
        DB      08FH
        DB      08CH
        DB      0AEH
        DB      0ACH
        DB      09BH
        DB      0A0H
        DB      099H
        DB      0BCH
        DB      0B8H
        DB      080H
        DB      03BH
        DB      03AH
        DB      070H
        DB      03CH
        DB      071H
        DB      05AH
        DB      03DH
        DB      043H
        DB      056H
        DB      03FH
        DB      01EH
        DB      04AH
        DB      01CH
        DB      05DH
        DB      03EH
        DB      05CH
        DB      01FH
        DB      05FH
        DB      05EH
        DB      037H
        DB      07BH
        DB      07FH
        DB      036H
        DB      07AH
        DB      07EH
        DB      033H
        DB      04BH
        DB      04CH
        DB      01DH
        DB      06CH
        DB      05BH
        DB      078H
        DB      041H
        DB      035H
        DB      034H
        DB      074H
        DB      030H
        DB      038H
        DB      075H
        DB      039H
        DB      04DH
        DB      06FH
        DB      06EH
        DB      032H
        DB      077H
        DB      076H
        DB      072H
        DB      073H
        DB      047H
        DB      07CH
        DB      053H
        DB      031H
        DB      04EH
        DB      06DH
        DB      048H
        DB      046H
        DB      07DH
        DB      044H
        DB      01BH
        DB      058H
        DB      079H
        DB      042H
        DB      060H
        DB      0FDH
        DB      0CBH
        DB      000H
        DB      01EH

?ADCN:  PUSH    BC
        PUSH    HL
        LD      HL,ATBL      ;00AB5H
        LD      C,A
        LD      B,000H
        ADD     HL,BC
        LD      A,(HL)
        JR      DACN3                   

_BRK:   LD      A,0CBH
        OR      A
        JP      ?KY10

        ; Unused memory.
        DB      029H
        DB      0F4H
        DB      0DDH

?DACN:  PUSH    BC
        PUSH    HL
        PUSH    DE
        LD      HL,00AB5H
        LD      D,H
        LD      E,L
        LD      BC,00100H
        CPIR    
        JR      Z,DACN1                 
        LD      A,0F0H
DACN2:  POP     DE
DACN3:  POP     HL
        POP     BC
        RET     

DACN1:  OR      A
        DEC     HL
        SBC     HL,DE
        LD      A,L
        JR      DACN2                   

KTBL:   DB      022H
        DB      021H
        DB      017H
        DB      011H
        DB      001H
        DB      0C7H
        DB      000H
        DB      01AH
        DB      024H
        DB      023H
        DB      012H
        DB      005H
        DB      004H
        DB      013H
        DB      018H
        DB      003H
        DB      026H
        DB      025H
        DB      019H
        DB      014H
        DB      007H
        DB      006H
        DB      016H
        DB      002H
        DB      028H
        DB      027H
        DB      009H
        DB      015H
        DB      00AH
        DB      008H
        DB      00EH
        DB      000H
        DB      020H
        DB      029H
        DB      010H
        DB      00FH
        DB      00CH
        DB      00BH
        DB      02FH
        DB      00DH
        DB      0BEH
        DB      02AH
        DB      052H
        DB      055H
        DB      04FH
        DB      02CH
        DB      02DH
        DB      02EH
        DB      0C5H
        DB      059H
        DB      0C3H
        DB      0C2H
        DB      0CDH
        DB      054H
        DB      000H
        DB      049H
        DB      028H
        DB      027H
        DB      025H
        DB      024H
        DB      022H
        DB      021H
        DB      0E7H
        DB      020H
        DB      06AH
        DB      029H
        DB      02AH
        DB      026H
        DB      000H
        DB      023H
        DB      000H
        DB      02EH

KTBLS:  DB      062H
        DB      061H
        DB      097H
        DB      091H
        DB      081H
        DB      0C8H
        DB      000H
        DB      09AH
        DB      064H
        DB      063H
        DB      092H
        DB      085H
        DB      084H
        DB      093H
        DB      098H
        DB      083H
        DB      066H
        DB      065H
        DB      099H
        DB      094H
        DB      087H
        DB      086H
        DB      096H
        DB      082H
        DB      068H
        DB      067H
        DB      089H
        DB      095H
        DB      08AH
        DB      088H
        DB      08EH
        DB      000H
        DB      0BFH
        DB      069H
        DB      090H
        DB      08FH
        DB      08CH
        DB      08BH
        DB      051H
        DB      08DH
        DB      0A5H
        DB      02BH
        DB      0BCH
        DB      0A4H
        DB      06BH
        DB      06AH
        DB      045H
        DB      057H
        DB      0C6H
        DB      080H
        DB      0C4H
        DB      0C1H
        DB      0CDH
        DB      040H
        DB      000H
        DB      050H

KTBLG:  DB      03EH
        DB      037H
        DB      038H
        DB      03CH
        DB      053H
        DB      0C7H
        DB      000H
        DB      076H
        DB      07BH
        DB      07FH
        DB      030H
        DB      034H
        DB      047H
        DB      044H
        DB      06DH
        DB      0DEH
        DB      05EH
        DB      03AH
        DB      075H
        DB      071H
        DB      04BH
        DB      04AH
        DB      0DAH
        DB      06FH
        DB      0BDH
        DB      01FH
        DB      07DH
        DB      079H
        DB      05CH
        DB      072H
        DB      032H
        DB      000H
        DB      09CH
        DB      0A1H
        DB      0D6H
        DB      0B0H
        DB      0B4H
        DB      05BH
        DB      060H
        DB      01CH
        DB      09EH
        DB      0D2H
        DB      0D8H
        DB      0B2H
        DB      0B6H
        DB      042H
        DB      0DBH
        DB      0B8H
        DB      0C5H
        DB      0D4H
        DB      0C3H
        DB      0C2H
        DB      0CDH
        DB      04EH
        DB      000H
        DB      0BAH

KTBLGS: DB      036H
        DB      03FH
        DB      078H
        DB      07CH
        DB      046H
        DB      0C8H
        DB      000H
        DB      077H
        DB      03BH
        DB      07EH
        DB      070H
        DB      074H
        DB      048H
        DB      041H
        DB      0DDH
        DB      0D9H
        DB      01EH
        DB      07AH
        DB      035H
        DB      031H
        DB      04CH
        DB      043H
        DB      0A6H
        DB      06EH
        DB      0A2H
        DB      05FH
        DB      03DH
        DB      039H
        DB      05DH
        DB      073H
        DB      033H
        DB      000H
        DB      09DH
        DB      0A3H
        DB      0B1H
        DB      0D5H
        DB      056H
        DB      06CH
        DB      0D0H
        DB      01DH
        DB      09FH
        DB      0D1H
        DB      0B3H
        DB      0D7H
        DB      04DH
        DB      0B5H
        DB      01BH
        DB      0B9H
        DB      0C6H
        DB      0D3H
        DB      0C4H
        DB      0C1H
        DB      0CDH
        DB      0B7H
        DB      000H
        DB      0BBH

KTBLC:  DB      0F0H
        DB      0F0H
        DB      0E2H
        DB      0C1H
        DB      0E0H
        DB      0F0H
        DB      000H
        DB      0E5H
        DB      0F0H
        DB      0F0H
        DB      0C2H
        DB      0CFH
        DB      0CEH
        DB      0C3H
        DB      0E3H
        DB      0F3H
        DB      0F0H
        DB      0F0H
        DB      0E4H
        DB      0C4H
        DB      0F7H
        DB      0F6H
        DB      0C6H
        DB      0F2H
        DB      0F0H
        DB      0F0H
        DB      0F9H
        DB      0C5H
        DB      0FAH
        DB      0F8H
        DB      0FEH
        DB      0F0H
        DB      0F0H
        DB      0F0H
        DB      0E1H
        DB      0FFH
        DB      0FCH
        DB      0FBH
        DB      0F0H
        DB      0FDH
        DB      0EFH
        DB      0F4H
        DB      0E6H
        DB      0CCH
        DB      0F0H
        DB      0F0H
        DB      0F0H
        DB      0F0H
        DB      0F0H
        DB      0EBH
        DB      0F0H
        DB      0F0H
        DB      0F0H
        DB      0EEH
        DB      0F0H

?BRK:  LD      A,0F0H
        LD      (KEYPA),A
        NOP     
        LD      A,(KEYPB)
        OR      A
        RLA     
        JR      NC,L0D37                
        RRA     
        RRA     
        JR      NC,L0D27                
        RRA     
        JR      NC,L0D2B                
        CCF     
        RET     

L0D27:  LD      A,040H
        SCF     
        RET     

L0D2B:  LD      A,(KDATW)
        LD      A,001H
        LD      (KDATW),A
        LD      A,010H
        SCF     
        RET     

L0D37:  AND     002H
        RET     Z

        LD      A,020H
        SCF     
        RET     

L0D3E:  PUSH    AF
        LD      A,003H
        LD      (KEYPF),A
        CALL    L0759
        CALL    L0759
        LD      A,002H
        LD      (KEYPF),A
        CALL    L0759
        CALL    L0759
        POP     AF
        RET     

L0D57:  PUSH    AF
        LD      A,003H
        LD      (KEYPF),A
        CALL    L0759
        CALL    L0759
        CALL    L0759
        CALL    L0759
        LD      A,002H
        LD      (KEYPF),A
        CALL    L0759
        CALL    L0759
        CALL    L0759
        CALL    L0760
        POP     AF
        RET     

?DSPA:  CP      008H
        JR      Z,L0D90                 
L0D80:  RRC     (HL)
        DJNZ    L0D80                   
        SET     0,(HL)
        RES     1,(HL)
        LD      B,A
L0D89:  RLC     (HL)
        DJNZ    L0D89                   
DSP04:  JP      CURSR
L0D90:  INC     HL
        SET     0,(HL)
        RES     1,(HL)
        JR      DSP04                   
DSP02:  SET     7,(HL)
        INC     HL
        RES     0,(HL)
        JR      DSP04                   


MSG_1:  DB      07FH, 020H
MSG_2:  DB      050H, 04CH, 041H, 059H, 00DH, 0F3H

?BLNK:  RET     

DLY12:  PUSH    BC
        LD      B,023H
DLY12A: CALL    DLY3
        DJNZ    DLY12A                   
        POP     BC
        RET     

        ; BELL DATA
?BELD:  DB      0D7H, 041H, 030H, 00DH

?DSP:   PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      B,A
        CALL    ?PONT
        LD      (HL),B
        LD      HL,(DSPXY)
        LD      A,L
DSP01:  CP      COLW - 1                ; End of line.
        JR      NZ,DSP04                
        CALL    .MANG
        JR      C,DSP04                 
        LD      A,(SPAGE)
        OR      A
        JP      NZ,.DSP03
        EX      DE,HL
        LD      A,B
        CP      007H
        JR      Z,DSP02                 
        JR      ?DSPA                   

        ; Unused memory.
        INC     H
        DI      

?DPCT:  PUSH    AF                      ; Display control, character is mapped to a function call.
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      B,A
        AND     0F0H
        CP      0C0H
        JP      NZ,?RSTR
        XOR     B
        RLCA    
        LD      C,A
        LD      B,000H
        LD      HL,CTBL
        LD      A,(SPAGE)
        OR      A
        JR      Z,DPCT1                 
        LD      HL,.CTBL
DPCT1:  ADD     HL,BC
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        JP      (HL)


CTBL:   DW      SCROL
        DW      CURSD
        DW      CURSU
        DW      CURSR
        DW      CURSL
        DW      HOME
        DW      CLRS
        DW      DEL
        DW      INST
        DW      ALPHA
        DW      KANA
        DW      ?RSTR
        DW      REV
        DW      CR
        DW      ROLUP
        DW      ROLD

;.CTBL: DW      .SCROL
;       DW      CURSD
;       DW      CURSU
;       DW      CURSR
;       DW      CURSL
;       DW      HOM0
;       DW      CLRS
;       DW      DEL
;       DW      INST
;       DW      ALPHA
;       DW      KANA
;       DW      ?RSTR
;       DW      REV
;       DW      .CR
;       DW      ?RSTR
;       DW      ?RSTR

SCROL:  LD      HL,PBIAS
        LD      C,005H
        LD      A,(ROLEND)
        ADD     A,C
        LD      (ROLEND),A
        LD      A,(ROLTOP)
        ADD     A,C
        LD      (ROLTOP),A
SCROL1: LD      A,C
        ADD     A,(HL)
        LD      (HL),A
        CALL    L09C7
        LD      HL,(PAGETP)
        LD      DE,SCRNSZ
        ADD     HL,DE                    ; HL=PAGETOP + 1000/2000
        LD      B,COLW
        XOR     A
SCROL2: RES     3,H
        LD      (HL),A
        INC     HL
        DJNZ    SCROL2                   
        LD      A,(PBIAS)                ; PBIAS is the offest for hardware scroll.
        LD      L,A
        LD      H,0E2H                   ; Hardware scroll region, E2<xx>
        LD      A,(HL)
        LD      HL,MANGE
        OR      A
        LD      B,007H
SCROL3: RR      (HL)
        DEC     HL
        DJNZ    SCROL3                   
        JP      ?RSTR

CURSD:  LD      HL,(DSPXY)
        LD      A,H
        CP      ROW - 1
        JR      Z,CURS4                 
        INC     H
CURS1:  CALL    MGP.I
CURS3:  LD      (DSPXY),HL
        JR      ?RSTR                   

CURSU:  LD      HL,(DSPXY)
        LD      A,H
        OR      A
        JR      Z,CURS5                 
        DEC     H
CURSU1: CALL    MGP.D
        JR      CURS3                   

CURSR:  LD      HL,(DSPXY)
        LD      A,L
        CP      COLW - 1                ; End of line
        JR      NC,CURS2                
        INC     L
        JR      CURS3                   
CURS2:  LD      L,000H
        INC     H
        LD      A,H
        CP      ROW 
        JR      C,CURS1                 
        LD      H,ROW - 1
        LD      (DSPXY),HL
CURS4:  JR      CURS6                   

CURSL:  LD      HL,(DSPXY)
        LD      A,L
        OR      A
        JR      Z,CURS5A                 
        DEC     L
        JR      CURS3                   
CURS5A: LD      L,COLW - 1              ; End of line
        DEC     H
        JP      P,CURSU1
        LD      H,000H
        LD      (DSPXY),HL
CURS5:  LD      A,(SPAGE)
        OR      A
        JR      NZ,?RSTR                
        JP      ROLD

CLRS:   LD      HL,MANG
        LD      B,01BH
        CALL    ?CLER
        LD      HL,SCRN
        PUSH    HL
        CALL    L09E2
        POP     HL
        LD      A,(SPAGE)
        OR      A
        JR      NZ,CLRS1                
        LD      (PAGETP),HL
        LD      A,07DH
        LD      (ROLEND),A
CLRS1:  LD      A,(SCLDSP)
HOM00:  JP      HOM0

CURS6:  LD      A,(SPAGE)
        OR      A
        JP      NZ,.SCROL
        JP      ROLU

ALPHA:  XOR     A
ALPHI:  LD      (KANAF),A
?RSTR:  POP     HL
?RSTR1: POP     DE
        POP     BC
        POP     AF
        RET     

        ; Unused memory
        DEC     C
        DEC     C
        DEC     C
        DEC     C

KANA:   LD      A,001H
        JR      ALPHI                   

DEL:    LD      HL,(DSPXY)
        LD      A,H
        OR      L
        JR      Z,?RSTR                 
        LD      A,L
        OR      A
        JR      NZ,DEL1                
        CALL    .MANG
        JR      C,DEL1                 
        CALL    ?PONT
        DEC     HL
        LD      (HL),000H
        JR      CURSL                   
DEL1:   CALL    .MANG
        RRCA    
        LD      A,COLW
        JR      NC,L0F13                
        RLCA    
L0F13:  SUB     L
        LD      B,A
        CALL    ?PONT
        PUSH    HL
        POP     DE
        DEC     DE
        SET     4,D
DEL2:   RES     3,H
        RES     3,D
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    DEL2                   
        DEC     HL
        LD      (HL),000H
        JP      CURSL

INST:   CALL    .MANG
        RRCA    
        LD      L,COLW - 1              ; End of line
        LD      A,L
        JR      NC,INST1A                
        INC     H
INST1A: CALL    ?PNT1
        PUSH    HL
        LD      HL,(DSPXY)
        JR      NC,INST2                
        LD      A,(COLW*2)-1            ; 04FH
INST2:  SUB     L
        LD      B,A
        POP     DE
        LD      A,(DE)
        OR      A
        JR      NZ,?RSTR                
        CALL    ?PONT
        LD      A,(HL)
        LD      (HL),000H
INST1:  INC     HL
        RES     3,H
        LD      E,(HL)
        LD      (HL),A
        LD      A,E
        DJNZ    INST1                   
        JR      ?RSTR                   

ROLD:   LD      HL,PBIAS
        LD      A,(ROLTOP)
        CP      (HL)
        JR      Z,?RSTR                 
        CALL    MGP.D
        LD      A,(HL)
        SUB     005H
ROL2:   LD      (HL),A
        LD      L,A
        LD      H,0E2H
        LD      A,(HL)
        CALL    L09C7
        JP      ?RSTR

CR:     CALL    .MANG
        RRCA    
        JP      NC,CURS2
        LD      L,000H
        INC     H
        LD      A,H
        CP      ROW - 1                   ; End of line?
        JR      Z,CR3                 
        JR      NC,CR2                
        CALL    MGP.I
        INC     H
        JP      CURS1
CR2:    DEC     H
        LD      (DSPXY),HL
        LD      HL,ROLU
        PUSH    HL
        PUSH    AF
        PUSH    BC
        PUSH    DE
        CALL    ROLU
CR3:    LD      (DSPXY),HL
        CALL    MGP.I

ROLU:   LD      HL,PBIAS
        LD      A,(ROLEND)
        CP      (HL)
        JP      Z,SCROL
ROLU1:  CALL    MGP.I
        LD      A,(HL)
        ADD     A,005H
        JR      ROL2                   

?PONT:  LD      HL,(DSPXY)
?PNT1:  PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        POP     BC
        LD      DE,COLW
        LD      HL,SCRN - COLW
        LD      A,(SPAGE)
        OR      A
        JR      NZ,?PNT2                
        LD      HL,(PAGETP)
        SBC     HL,DE
?PNT2:  ADD     HL,DE
        DEC     B
        JP      P,?PNT2
        LD      B,000H
        ADD     HL,BC
        RES     3,H
        POP     DE
        POP     BC
        POP     AF
        RET     

?CLER:  XOR     A
        JR      ?DINT                   
?CLRFF: LD      A,0FFH
?DINT:  LD      (HL),A
        INC     HL
        DJNZ    ?DINT                   
        RET     

GAPCK:  PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      BC,KEYPB
        LD      DE,KEYPC
GAPCK1: LD      H,064H
GAPCK2: CALL    EDGE
        JR      C,GAPCK3                 
        CALL    DLY3
        LD      A,(DE)
        AND     020H
        JR      NZ,GAPCK1                
        DEC     H
        JR      NZ,GAPCK2                
GAPCK3: JP      RET3

        ;    MONITOR WORK AREA
        ;    (MZ700)

STACK:  EQU     010F0H

        ORG     STACK
SPV:
IBUFE:                                                                   ; TAPE BUFFER (128 BYTES)
ATRB:   DS      virtual 1                                                ; ATTRIBUTE
NAME:   DS      virtual 17                                               ; FILE NAME
SIZE:   DS      virtual 2                                                ; BYTESIZE
DTADR:  DS      virtual 2                                                ; DATA ADDRESS
EXADR:  DS      virtual 2                                                ; EXECUTION ADDRESS
COMNT:  DS      virtual 92                                               ; COMMENT
SWPW:   DS      virtual 10                                               ; SWEEP WORK
KDATW:  DS      virtual 2                                                ; KEY WORK
KANAF:  DS      virtual 1                                                ; KANA FLAG (01=GRAPHIC MODE)
DSPXY:  DS      virtual 2                                                ; DISPLAY COORDINATES
MANG:   DS      virtual 6                                                ; COLUMN MANAGEMENT
MANGE:  DS      virtual 1                                                ; COLUMN MANAGEMENT END
PBIAS:  DS      virtual 1                                                ; PAGE BIAS
ROLTOP: DS      virtual 1                                                ; ROLL TOP BIAS
MGPNT:  DS      virtual 1                                                ; COLUMN MANAG. POINTER
PAGETP: DS      virtual 2                                                ; PAGE TOP
ROLEND: DS      virtual 1                                                ; ROLL END
        DS      virtual 14                                               ; BIAS
FLASH:  DS      virtual 1                                                ; FLASHING DATA
SFTLK:  DS      virtual 1                                                ; SHIFT LOCK
REVFLG: DS      virtual 1                                                ; REVERSE FLAG
SPAGE:  DS      virtual 1                                                ; PAGE CHANGE
FLSDT:  DS      virtual 1                                                ; CURSOR DATA
STRGF:  DS      virtual 1                                                ; STRING FLAG
DPRNT:  DS      virtual 1                                                ; TAB COUNTER
TMCNT:  DS      virtual 2                                                ; TAPE MARK COUNTER
SUMDT:  DS      virtual 2                                                ; CHECK SUM DATA
CSMDT:  DS      virtual 2                                                ; FOR COMPARE SUM DATA
AMPM:   DS      virtual 1                                                ; AMPM DATA
TIMFG:  DS      virtual 1                                                ; TIME FLAG
SWRK:   DS      virtual 1                                                ; KEY SOUND FLAG
TEMPW:  DS      virtual 1                                                ; TEMPO WORK
ONTYO:  DS      virtual 1                                                ; ONTYO WORK
OCTV:   DS      virtual 1                                                ; OCTAVE WORK
RATIO:  DS      virtual 2                                                ; ONPU RATIO
BUFER:  DS      virtual 81                                               ; GET LINE BUFFER

        ;    EQU TABLE I/O REPORT

SCRN:   EQU     0D000H
ARAM:   EQU     0D800H
KEYPA:  EQU     0E000H
KEYPB:  EQU     0E001H
KEYPC:  EQU     0E002H
KEYPF:  EQU     0E003H
CSTR:   EQU     0E002H
CSTPT:  EQU     0E003H
CONT0:  EQU     0E004H
CONT1:  EQU     0E005H
CONT2:  EQU     0E006H
CONTF:  EQU     0E007H
SUNDG:  EQU     0E008H
TEMP:   EQU     0E008H
MEMSW:  EQU     0E00CH
MEMSWR: EQU     0E010H
INVDSP: EQU     0E014H
NRMDSP: EQU     0E015H
SCLDSP: EQU     0E200H
