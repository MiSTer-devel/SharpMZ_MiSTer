        ; MONITOR PROGRAM 1Z-013A 
        ;    (MZ700) FOR PAL 
        ;      REV. 83.4.7
        ; Tuesday, 02 of June 1998 at 10:02 PM
        ; Tuesday, 09 of June 1998 at 07:17 AM
; Configurable parameters. These are set in the wrapper file, ie monitor_SA1510.asm
;
;COLW:   EQU     40                      ; Width of the display screen (ie. columns).
;ROW:    EQU     25                      ; Number of rows on display screen.
;SCRNSZ: EQU     COLW * ROW              ; Total size, in bytes, of the screen display area.

        ORG     0000h        ; 0000h Entrypoint 
MONIT:  JP      START                                                    ; MONITOR ON
GETL:   JP      QGETL                                                    ; GET LINE (END "CR")
LETNL:  JP      QLTNL                                                    ; NEW LINE
NL:     JP      QNL                                                      ;
PRNTS:  JP      QPRTS                                                    ; PRINT SPACE
PRNTT:  JP      QPRTT                                                    ; PRINT TAB
PRNT:   JP      QPRNT                                                    ; 1 CHARACTER PRINT
MSG:    JP      QMSG                                                     ; 1 LINE PRINT (END "0DH")
MSGX:   JP      QMSGX                                                    ; RST 18H
GETKY:  JP      QGET                                                     ; GET KEY
BRKEY:  JP      QBRK                                                     ; GET BREAK
WRINF:  JP      QWRI                                                     ; WRITE INFORMATION
WRDAT:  JP      QWRD                                                     ; WRITE DATA
RDINF:  JP      QRDI                                                     ; READ INFORMATION
RDDAT:  JP      QRDD                                                     ; READ DATA
VERFY:  JP      QVRFY                                                    ; VERIFYING CMT
MELDY:  JP      QMLDY                                                    ; RST 30H
TIMST:  JP      QTMST                                                    ; TIME SET
        NOP
        NOP
        JP      1038H                                                    ; INTERRUPT ROUTINE (8253)
TIMRD:  JP      QTMRD                                                    ; TIME READ
BELL:   JP      QBEL                                                     ; BELL ON
XTEMP:  JP      QTEMP                                                    ; TEMPO SET (1 - 7)
MSTA:   JP      MLDST                                                    ; MELODY START
MSTP:   JP      MLDSP                                                    ; MELODY STOP

START:  LD      SP,SPV                                                   ; STACK SET (10F0H)
        IM      1                                                        ; IM 1 SET
        CALL    QMODE                                                    ; 8255 MODE SET
        CALL    QBRK                                                     ; CTRL ?
        JR      NC,ST0
        CP      20H                                                      ; KEY IS CTRL KEY
        JR      NZ,ST0
CMY0:   OUT     (0E1H),A                                                 ; D000-FFFFH IS DRAM
        LD      DE,0FFF0H                                                ; TRANS. ADR.
        LD      HL,DMCP                                                  ; MEMORY CHANG PROGRAM
        LD      BC,05H                                                   ; BYTE SIZE
        LDIR    
        JP      0FFF0H                                                   ; JUMP $FFF0

DMCP:   OUT     (0E0H),A                                                 ; 0000H-0FFFH IS DRAM
        JP      0000H

ST0:    LD      B,0FFH                                                   ; BUFFER CLEAR
        LD      HL,NAME                                                  ; 10F1H-11F0H CLEAR
        CALL    QCLER
        LD      A,16H                                                    ; LASTER CLR.
        CALL    PRNT
        LD      A,71H                                                    ; BACK:BLUE CHA.:WRITE
        LD      HL,0D800H                                                ; COLOR ADDRESS
        CALL    NCLR8
        LD      HL,TIMIN                                                 ; INTERRUPT JUMP ROUTINE
        LD      A,0C3H
        LD      (1038H),A
        LD      (1039H),HL
        LD      A,04H                                                    ; NORMAL TEMPO
        LD      (TEMPW),A
        CALL    MLDSP                                                    ; MELODY STOP
        CALL    NL
        LD      DE,MSGQ3                                                 ; ** MONITOR 1Z-013A **
        RST     18H                                                      ; CALL MGX
        CALL    QBEL
SS:     LD      A,01H
        LD      (SWRK),A                                                 ; KEY IN SILENT
        LD      HL,0E800H                                                ; USR ROM?
        LD      (HL),A                                                   ; ROM CHECK
        JR      FD2

ST1:    CALL    NL
        LD      A,2AH                                                    ; "*" PRINT
        CALL    PRNT
        LD      DE,BUFER                                                 ; GET LINE WORK (11A3H)
        CALL    GETL
ST2:    LD      A,(DE)
        INC     DE
        CP      0DH
        JR      Z,ST1
        CP      'J'                                                      ; JUMP
        JR      Z,GOTO
        CP      'L'                                                      ; LOAD PROGRAM
        JR      Z,LOAD
        CP      'F'                                                      ; FLOPPY ACCESS
        JR      Z,FD
        CP      'B'                                                      ; KEY IN BELL
        JR      Z,SG
        CP      '#'                                                      ; CHANG MEMORY
        JR      Z,CMY0
        CP      'P'                                                      ; PRINTER TEST
        JR      Z,PTEST
        CP      'M'                                                      ; MEMORY CORRECTION
        JP      Z,MCOR
        CP      'S'                                                      ; SAVE DATA
        JP      Z,SAVE
        CP      'V'                                                      ; VERIFYING DATA
        JP      Z,VRFY
        CP      'D'                                                      ; DUMP DATA
        JP      Z,DUMP
        NOP     
        NOP     
        NOP     
        NOP     
        JR      ST2                                                      ; NO COMMAND

        ;    JUMP COMMAND

GOTO:   CALL    HEXIY
        JP      (HL)

        ;    KEY SOUND ON/OFF

SG:     LD      A,(SWRK)                                                 ; D0=SOUND WORK
        RRA     
        CCF                                                              ; CHANGE MODE
        RLA     
        JR      SS+2

        ;    FLOPPY

FD:     LD      HL,0F000H                                                ; FLOPPY I/O CHECK
FD2:    LD      A,(HL)
        OR      A
        JR      NZ,ST1
FD1:    JP      (HL)

        ;    ERROR (LOADING)

QER:    CP      02H                                                      ; A=02H : BREAK IN
        JR      Z,ST1
        LD      DE,MSGE1                                                 ; CHECK SUM ERROR
        RST     18H                                                      ; CALL MSGX
L010F:    JR      ST1

        ;    LOAD COMMAND

LOAD:      CALL    QRDI
        JR      C,QER
LOA0:   CALL    NL
        LD      DE,MSGQ2                                                 ; LOADING
        RST     18H                                                      ; CALL MSGX
        LD      DE,NAME                                                  ; FILE NAME
        RST     18H                                                      ; CALL MSGX
        CALL    QRDD
        JR      C,QER
        LD      HL,(EXADR)                                               ; EXECUTE ADDRESS
        LD      A,H
        CP      12H                                                      ; EXECUTE CHECK
        JR      C,L010F
        JP      (HL)

        ;    GETLINE AND BREAK IN CHECK
        ;
        ;    EXIT BREAK IN THEN JUMP (ST1)
        ;    ACC=TOP OF LINE DATA

BGETL:  EX      (SP),HL
        POP     BC                                                       ; STACK LOAD
        LD      DE,BUFER                                                 ; MONITOR GETLINE BUFF
        CALL    GETL
        LD      A,(DE)
        CP      1BH                                                      ; BREAK CODE
        JR      Z,L010F                                                  ; JP Z,ST1
        JP      (HL)

        ;    ASCII TO HEX CONVERT
        ;    INPUT (DE)=ASCII
        ;    CY=1 THEN JUMP (ST1)

HEXIY:  EX      (SP),IY
        POP     AF
        CALL    HLHEX
        JR      C,L010F                                                  ; JP C,ST1
        JP      (IY)

MSGE1:    DB    "CHECK SUM ER.\r"

        ;    PLOTTER PRINTER TEST COMMAND
        ;    (DPG23)
        ;    &=CONTROL COMMANDS GROUP
        ;    C=PEN CHANGE
        ;    G=GRAPH MODE
        ;    S=80 CHA. IN 1 LINE
        ;    L=40 CHA. IN 1 LINE
        ;    T=PLOTTER TEST
        ;    IN (DE)=PRINT DATA

PTEST:  LD      A,(DE)
        CP      '&'
        JR      NZ,PTST1
PTST0:  INC     DE
        LD      A,(DE)
        CP      'L'                                                      ; 40 IN 1 LINE
        JR      Z,PLPT
        CP      'S'                                                      ; 80 IN 1 LINE
        JR      Z,PPLPT
        CP      'C'                                                      ; PEN CHANGE
        JR      Z,PEN
        CP      'G'                                                      ; GRAPH MODE
        JR      Z,PLOT
        CP      'T'                                                      ; TEST
        JR      Z,PTRN
PTST1:  CALL    PMSG                                                     ; PLOT MESSAGE
        JP      ST1

PLPT:   LD      DE,LLPT                                                  ; 01-09-09-0B-0D
        JR      PTST1

PPLPT:  LD      DE,SLPT                                                  ; 01-09-09-09-0D
        JR      PTST1

PTRN:   LD      A,04H                                                    ; TEST PATTERN
        JR      PLOT+2

PLOT:   LD      A,02H                                                    ; GRAPH CODE
    CALL    LPRNT
        JR      PTST0

PEN:    LD      A,1DH                                                    ; 1 CHANGE CODE (TEXT MODE)
        JR      PLOT+2

        ;    1CHA. PRINT TO $LPT
        ;    IN: ACC PRINT DATA

LPRNT:  LD      C,0                                                      ; RDA TEST (READY? RDA=0)
        LD      B,A                                                      ; PRINT DATA STORE
        CALL    RDA
        LD      A,B
        OUT     (0FFH),A                                                 ; DATA OUT 
        LD      A,80H                                                    ; RDP HIGH
        OUT     (0FEH),A
        LD      C,01H                                                    ; RDA TEST
        CALL    RDA
    XOR     A                                                            ; RDP LOW
        OUT     (0FEH),A
        RET     

        ;    $LPT MSG
        ;    IN: DE DATA LOW ADDRESS
        ;    0DH MSG END

PMSG:   PUSH    DE
        PUSH    BC
        PUSH    AF
PMSG1:  LD      A,(DE)                                                   ; ACC=DATA
        CALL    LPRNT
        LD      A,(DE)
        INC     DE
        CP      0DH                                                      ; END?
        JR      NZ,PMSG1
        POP     AF
        POP     BC
        POP     DE
        RET     

        ;    RDA CHECK
        ;    BRKEY IN TO MONITOR RETURN
        ;    IN: C RDA CODE

RDA:    IN      A,(0FEH)
        AND     0DH                                                      ; RDA ONLY
        CP      C
        RET     Z
        CALL    BRKEY
        JR      NZ,RDA
        LD      SP,SPV
        JP      ST1

        ;    MELODY
        ;    DE=DATA LOW ADDRESS
        ;    EXIT CF=1 BREAK
        ;         CF=0 OK

QMLDY:  PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      A,02H
        LD      (OCTV),A
        LD      B,01H
MLD1:   LD      A,(DE)
        CP      0DH                                                      ; CR
        JR      Z,MLD4
        CP      0C8H                                                     ; END MARK
        JR      Z,MLD4
        CP      0CFH                                                     ; UNDER OCTAVE
        JR      Z,MLD2
        CP      2DH                                                      ; "-" 
        JR      Z,MLD2
        CP      2BH                                                      ; "+"
        JR      Z,MLD3
        CP      0D7H                                                     ; UPPER OCTAVE
        JR      Z,MLD3
        CP      23H                                                      ; "#" HANON
        LD      HL,MTBL
        JR      NZ,L01F5
        LD      HL,MNTBL
        INC     DE
L01F5:    CALL    ONPU                                                   ; ONTYO SET
        JR      C,MLD1
        CALL    RYTHM
        JR      C,MLD5
        CALL    MLDST                                                    ; MELODY START
        LD      B,C
        JR      MLD1

MLD2:   LD      A,3
L0207:    LD      (OCTV),A
        INC     DE
        JR      MLD1

MLD3:   LD      A,01H
        JR      L0207

MLD4:   CALL    RYTHM
MLD5:   PUSH    AF
        CALL    MLDSP
        POP     AF
        JP      RET3

        ;    ONPU TO RATIO CONV
        ;    EXIT (RATIO)=RATIO VALUE
        ;    C=ONTYO*TEMPO

ONPU:   PUSH    BC
        LD      B,8
ONP1:   LD      A,(DE)
L0220:    CP      (HL)
        JR      Z,ONP2
        INC     HL
        INC     HL
        INC     HL
        DJNZ    L0220
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
        JR      Z,L023F
        LD      A,(OCTV)                                                 ; 11A0H OCTAVE WORK
L0239:  DEC     A
        JR      Z,L023F
        ADD     HL,HL
        JR      L0239

L023F:  LD      (RATIO),HL                                               ; 11A1H ONPU RATIO
        LD      HL,OCTV
        LD      (HL),02H
        DEC     HL
        POP     DE
        INC     DE
        LD      A,(DE)
        LD      B,A
        AND     0F0H                                                     ; ONTYO ?
        CP      30H
        JR      Z,L0255
        LD      A,(HL)                                                   ; HL=ONTYO
        JR      L025A

L0255:  INC     DE
        LD      A,B
        AND     0FH
        LD      (HL),A                                                   ; HL=ONTYO
L025A:  LD      HL,OPTBL
        ADD     A,L
        LD      L,A
        LD      C,(HL)
        LD      A,(TEMPW)
        LD      B,A
        XOR     A
ONP3:   ADD     A,C
        DJNZ    ONP3
        POP     BC
        LD      C,A
        XOR     A
        RET     

MTBL:    DB    "C"
    DW    0846H
    DB    "D"
    DW    075FH
    DB    "E"
    DW    0691H
    DB    "F"
    DW    0633H
    DB    "G"
    DW    0586H
    DB    "A"
    DW    04ECH
    DB    "B"
    DW    0464H
    DB    "R"
    DW    0000H
MNTBL:    DB    "C"                                                      ; #C
    DW    07CFH
    DB    "D"                                                            ; #D
    DW    06F5H
    DB    "E"                                                            ; #E
    DW    0633H
    DB    "F"                                                            ; #F
    DW    05DAH
    DB    "G"                                                            ; #G
    DW    0537H
    DB    "A"                                                            ; #A
    DW    04A5H
    DB    "B"                                                            ; #B
    DW    0423H
    DB    "R"                                                            ; #R
    DW    0000H
OPTBL:    DB    01H
    DB    02H
    DB    03H
    DB    04H
    DB    06H
    DB    08H
    DB    0CH
    DB    10H
    DB    18H
    DB    20H

        ;    INCREMENT DE REG.

P4DE:   INC     DE
    INC    DE
        INC     DE
        INC     DE
        RET     

        ;    MELODY START & STOP

MLDST:  LD      HL,(RATIO)
        LD      A,H
        OR      A
        JR      Z,MLDSP
        PUSH    DE
        EX      DE,HL
        LD      HL,CONT0
        LD      (HL),E
        LD      (HL),D
        LD      A,01H
        POP     DE
        JR      MLDS1

MLDSP:  LD      A,36H                                                    ; MODE SET (8253 C0)
        LD      (CONTF),A                                                ; E007H
        XOR     A
MLDS1:  LD      (SUNDG),A                                                ; E008H
        RET                                                              ; TEHRO SET

        ;    RHYTHM
        ;    B=COUNT DATA
        ;    IN
        ;    EXIT CF=1 BREAK
        ;         CF=0 OK

RYTHM:  LD      HL,KEYPA                                                 ; E000H
        LD      (HL),0F8H
        INC     HL
        LD      A,(HL)
        AND     81H                                                      ; BREAK IN CHECK
        JR      NZ,L02D5
        SCF     
        RET     

L02D5:  LD      A,(TEMP)                                                 ; E008H
        RRCA                                                             ; TEMPO OUT
        JR      C,L02D5
L02DB:  LD      A,(TEMP)
        RRCA    
        JR      NC,L02DB
        DJNZ    L02D5
        XOR     A
        RET     

        ;    TEMPO SET
        ;    ACC=VALUE (1-7)

QTEMP:  PUSH    AF
        PUSH    BC
        AND     0FH
        LD      B,A
        LD      A,8
        SUB     B
        LD      (TEMPW),A
        POP     BC
        POP     AF
        RET     

        ;    CRT MANAGEMENT
        ;    EXIT HL:DSPXY H=Y,L=X
        ;    DE:MANG ADR. (ON DSPXY)
        ;    A :MANG DATA
        ;    CY:MANG=1

PMANG:  LD      HL,MANG                                                  ; CRT MANG POINTER
        LD      A,(1172H)                                                ; DSPXY+1
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

        ;    TIME SET
        ;    ACC=0 : AM
        ;       =1 : PM
        ;    DE=SEC: BINARY

QTMST:  DI      
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      (AMPM),A                                                 ; AMPM DATA
        LD      A,0F0H
        LD      (TIMFG),A                                                ; TIME FLAG
        LD      HL,0A8C0H                                                ; 12 HOURS (43200 SECONDS)
        XOR     A
        SBC     HL,DE                                                    ; COUNT DATA = 12H-IN DATA
        PUSH    HL
        NOP     
        EX      DE,HL
        LD      HL,CONTF                                                 ; E007H
        LD      (HL),74H                                                 ; C1
        LD      (HL),0B0H                                                ; C2
        DEC     HL                                                       ; CONT2
        LD      (HL),E                                                   ; E006H
        LD      (HL),D
        DEC     HL                                                       ; CONT1
        LD      (HL),0AH                                                 ; E005H STROBE 640,6µSECONDS COUNT2
        LD      (HL),0
        INC     HL
        INC     HL                                                       ; CONTF
        LD      (HL),80H                                                 ; E007H
        DEC     HL                                                       ; CONT2
QTMS1:  LD      C,(HL)                                                   ; E006H
        LD      A,(HL)
        CP      D
        JR      NZ,QTMS1
        LD      A,C
        CP      E
        JR      NZ,QTMS1
        DEC     HL                                                       ; E005H
        NOP     
        NOP     
        NOP     
        LD      (HL),0FBH                                                ; 1 SECOND (15611HZ) E005H
        LD      (HL),3CH
        INC     HL
        POP     DE
QTMS2:  LD      C,(HL)                                                   ; E006H
        LD      A,(HL)
        CP      D
        JR      NZ,QTMS2
        LD      A,C
        CP      E
        JR      NZ,QTMS2
        POP     HL
        POP     DE
        POP     BC
        EI      
        RET     

        ;    BELL DATA
        ;    
QBELD:    DB    0D7H
    DB    "A0"
    DB    0DH
        NOP     
        NOP     

        ;    TIME READ
        ;    EXIT ACC=0 :AM
        ;            =1 :PM
        ;         DE=SEC. BINARY

QTMRD:  PUSH    HL
        LD      HL,CONTF
        LD      (HL),80H                                                 ; E007H C2
        DEC     HL                                                       ; CONT2
        DI      
        LD      E,(HL)
        LD      D,(HL)                                                   ; e006H C2 MODE0
        EI      
L0363:  LD      A,E
        OR      D
        JR      Z,QTMR1
        XOR     A
        LD      HL,0A8C0H                                                ; 12 HOURS
        SBC     HL,DE
        JR      C,QTMR2
        EX      DE,HL
        LD      A,(AMPM)
        POP     HL
        RET     

QTMR1:  LD      DE,0A8C0H
L0378:  LD      A,(AMPM)
        XOR     01H
        POP     HL
        RET     

QTMR2:  DI      
        LD      HL,CONT2
        LD      A,(HL)
        CPL     
        LD      E,A
        LD      A,(HL)
        CPL     
        LD      D,A
        EI      
        INC     DE
        JR      L0378

        ;    TIME INTERRUPT

TIMIN:  PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      HL,AMPM
        LD      A,(HL)
        XOR     01H
        LD      (HL),A
        LD      HL,CONTF
        LD      (HL),80H                                                 ; CONT2
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

        ;    SPACE PRINT AND DISP ACC
        ;    INPUT:HL=DISP. ADR.

SPHEX:  CALL    QPRTS                                                    ; SPACE PRINT
        LD      A,(HL)
        CALL    PRTHX                                                    ; DSP OF ACC (ASCII)
        LD      A,(HL)
        RET     

        ;    (ASCII PRINT) FOR HL

PRTHL:  LD      A,H
        CALL    PRTHX
        LD      A,L
        JR      PRTHX

        NOP     
        NOP     

        ;    (ASCII PRINT) FOR ACC

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

        ;    80 CHA. 1 LINE CODE (DATA)

SLPT:    DB    01H                                                       ; TEXT MODE
    DB    09H
    DB    09H
    DB    09H
    DB    0DH

        ;    HEXADECIMAL TO ASCII
        ;    IN  : ACC (D3-D0)=HEXADECIMAL
        ;    EXIT: ACC = ASCII
ASC:    AND     0FH
        CP      0AH
        JR      C,NOADD
        ADD     A,07H
NOADD:  ADD     A,30H
        RET     

        ;    ASCII TO HEXADECIMAL
        ;    IN  : ACC = ASCII
        ;    EXIT: ACC = HEXADECIMAL
        ;          CY  = 1 ERROR

HEXJ:   SUB     30H
        RET     C                                                        ; <0
        CP      0AH
        CCF     
        RET     NC                                                       ; 0-9
        SUB     07H
        CP      10H
        CCF     
        RET     C
        CP      0AH
        RET     

        NOP     
        NOP     
        NOP     
        NOP     

HEX:    JR      HEXJ

        ;    PRESS PLAY MESSAGE

MSGN1:    DW    207FH
MSGN2:    DB    "PLAY\r"
MSGN3:    DW    207FH
    DB    "RECORD.\r"                                                    ; PRESS RECORD

        NOP     
        NOP     
        NOP     
        NOP     

        ;    4 ASCII TO (HL)
        ;    IN  DE=DATA LOW ADDRESS
        ;    EXIT CF=0 : OK
        ;           =1 : OUT

HLHEX:  PUSH    DE
        CALL    L2HEX
        JR      C,L041D
        LD      H,A
        CALL    L2HEX
        JR      C,L041D
        LD      L,A
L041D:  POP     DE
        RET     

        ;    2 ASCII TO (ACC)
        ;    IN  DE=DATA LOW ADRRESS
        ;    EXIT CF=0 : OK
        ;           =1 : OUT

L2HEX:  PUSH    BC
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

        ;    WRITE INFORMATION

QWRI:   DI      
        PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      D,0D7H                                                   ; "W"
        LD      E,0CCH                                                   ; "L"
        LD      HL,IBUFE                                                 ; 10F0H
        LD      BC,80H                                                   ; WRITE BYTE SIZE
WRI1:   CALL    CKSUM                                                    ; CHECK SUM
        CALL    MOTOR                                                    ; MOTOR ON
        JR      C,WRI3
        LD      A,E
        CP      0CCH                                                     ; "L"
        JR      NZ,WRI2
        CALL    NL
        PUSH    DE
        LD      DE,MSGN7                                                 ; WRITING
        RST     18H                                                      ; CALL MSGX
        LD      DE,NAME                                                  ; FILE NAME
        RST     18H                                                      ; CALL MSGX
        POP     DE
WRI2:   CALL    GAP
        CALL    WTAPE
WRI3:   JP      RET2

MSGN7:    DB    "WRITING \r"

        ;    40 CHA. IN 1 LINE CODE (DATA)

LLPT:    DB    01H                                                       ; TEXT MODE
    DB    09H
    DB    09H
    DB    0BH
    DB    0DH

        ;    WRITE DATA
        ;    EXIT CF=0 : OK
        ;           =1 : BREAK

QWRD:   DI      
        PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      D,0D7H                                                   ; "W"
        LD      E,53H                                                    ; "S"
L047D:  LD      BC,(SIZE)                                                ; WRITE DATA BYTE SIZE
        LD      HL,(DTADR)                                               ; WRITE DATA ADDRESS
        LD      A,B
        OR      C
        JR      Z,RET1
        JR      WRI1

        ;    TAPE WRITE
        ;    BC=BYTE SIZE
        ;    HL=DATA LOW ADDRESS
        ;    EXIT CF=0 : OK
        ;           =1 : BREAK

WTAPE:  PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      D,02H
        LD      A,0F8H                                                   ; 88H WOULD BE BETTER!!
        LD      (KEYPA),A                                                ; E000H
WTAP1:  LD      A,(HL)
        CALL    WBYTE                                                    ; 1 BYTE WRITE
        LD      A,(KEYPB)                                                ; E001H
        AND     81H                                                      ; SHIFT & BREAK
        JP      NZ,WTAP2
        LD      A,02H                                                    ; BREAK IN CODE
        SCF     
        JR      WTAP3

WTAP2:  INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JP      NZ,WTAP1
        LD      HL,(SUMDT)                                               ; SUM DATA SET
        LD      A,H
        CALL    WBYTE
        LD      A,L
        CALL    WBYTE
        CALL    LONG
        DEC     D
        JP      NZ,L04C2
        OR      A
        JP      WTAP3

L04C2:  LD      B,0
L04C4:  CALL    SHORT
        DEC     B
        JP      NZ,L04C4
        POP     HL
        POP     BC
        PUSH    BC
        PUSH    HL
        JP      WTAP1

WTAP3:
RET1:   POP     HL
        POP     BC
        POP     DE
        RET     

    DB    2FH
    DB    4EH

        ;    READ INFORMATION (FROM $CMT)
        ;    EXIT ACC=0: OK CF=0
        ;            =1: ER CF=1
        ;            =2: BREAK CF=1

QRDI:   DI      
        PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      D,0D2H                                                   ; "R"
        LD      E,0CCH                                                   ; "L"
        LD      BC,80H
        LD      HL,IBUFE
RD1:    CALL    MOTOR
        JP      C,RTP6
        CALL    TMARK
        JP      C,RTP6
        CALL    RTAPE
        JP      RTP4

        ;    READ DATA (FROM $CMT)
        ;    EXIT SAME UP

QRDD:   DI      
        PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      D,0D2H                                                   ; "R"
        LD      E,53H                                                    ; "S"
        LD      BC,(SIZE)
        LD      HL,(DTADR)
        LD      A,B
        OR      C
        JP      Z,RTP4
        JR      RD1

        ;    READ TAPE
        ;    IN  BC=SIZE
        ;        DE=LOAD ADDRESS
        ;    EXIT ACC=0 : OK CF=0
        ;            =1 : ER   =1
        ;            =2 : BREAK=1
 
RTAPE:  PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      H,02H                                                    ; TWICE WRITE
RTP1:   LD      BC,KEYPB
        LD      DE,CSTR
RTP2:   CALL    EDGE                                                     ; 1-->0 EDGE DETECT
        JR      C,RTP6
        CALL    DLY3                                                     ; CALL DLY2*3
        LD      A,(DE)                                                   ; DATA (1 BIT) READ
        AND     20H
        JP      Z,RTP2
        LD      D,H
        LD      HL,0
        LD      (SUMDT),HL
        POP     HL
        POP     BC
        PUSH    BC
        PUSH    HL
RTP3:   CALL    RBYTE                                                    ; 1 BYTE READ
        JR      C,RTP6
        LD      (HL),A
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,RTP3
        LD      HL,(SUMDT)                                               ; CHECK SUM
        CALL    RBYTE                                                    ; CHECK SUM DATA
        JR      C,RTP6
        LD      E,A
        CALL    RBYTE                                                    ; CHECK SUM DATA
        JR      C,RTP6
        CP      L
        JR      NZ,RTP5
        LD      A,E
        CP      H
        JR      NZ,RTP5
RTP8:   XOR     A
RTP4:
RET2:   POP     HL
        POP     BC
        POP     DE
        CALL    MSTOP
        PUSH    AF
        LD      A,(TIMFG)                                                ; INT. CHECK
        CP      0F0H
        JR      NZ,L0563
        EI      
L0563:  POP     AF
        RET     

RTP5:   DEC     D
        JR      Z,RTP7
        LD      H,D
        CALL    GAPCK
        JR      RTP1

RTP7:   LD      A,01H
        JR      RTP9

RTP6:   LD      A,02H
RTP9:   SCF     
        JR      RTP4

        ;    BELL

QBEL:   PUSH    DE
        LD      DE,QBELD
        RST     30H                                                      ; CALL MELODY
        POP     DE
        RET     

        ;    FLASHING AND KEYIN
        ;    EXIT: ACC INPUT KEY DATA (DSP.CODE)
        ;    H=F0H THEN NO KEYIN (Z FLAG)

FLKEY:  CALL    QFLAS
        CALL    QKEY
        CP      0F0H
        RET     

        NOP     

        ;    VERIFY (FROM $CMT)
        ;    EXIT ACC=0 : OK CF=0
        ;            =1 : ER CF=1
        ;            =2 : BREAK CF=1

QVRFY:  DI      
        PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      BC,(SIZE)
        LD      HL,(DTADR)
        LD      D,0D2H                                                   ; "R"
        LD      E,53H                                                    ; "S"
        LD      A,B
        OR      C
        JR      Z,RTP4                                                   ; END
        CALL    CKSUM
        CALL    MOTOR
        JR      C,RTP6                                                   ; BRK
        CALL    TMARK                                                    ; TAPE MARK DETECT
        JR      C,RTP6                                                   ; BRK
        CALL    TVRFY
        JR      RTP4

        ;    DATA VERIFY
        ;    BC=SIZE
        ;    HL=DATA LOW ADDRESS
        ;    CSMDT=CHECK SUM
        ;    EXIT ACC=0 : OK  CF=0
        ;            =1 : ER    =1
        ;            =2 : BREAK =1

TVRFY:  PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      H,02H                                                    ; COMPARE TWICE
TVF1:   LD      BC,KEYPB
        LD      DE,CSTR
TVF2:   CALL    EDGE
        JP      C,RTP6                                                   ; BRK
        CALL    DLY3                                                     ; CALL DLY2*3
        LD      A,(DE)
        AND     20H
        JP      Z,TVF2
        LD      D,H
        POP     HL
        POP     BC
        PUSH    BC
        PUSH    HL
        ;    COMPARE TAPE DATA AND STORAGE
TVF3:   CALL    RBYTE
        JR      C,RTP6                                                   ; BRK
        CP      (HL)
        JR      NZ,RTP7                                                  ; ERROR, NOT EQUAL
        INC     HL                                                       ; STORAGE ADDRESS + 1
        DEC     BC                                                       ; SIZE - 1
        LD      A,B
        OR      C
        JR      NZ,TVF3
        ;    COMPARE CHECK SUM (1199H/CSMDT) AND TAPE
        LD      HL,(CSMDT)
        CALL    RBYTE
        CP      H
        JR      NZ,RTP7                                                  ; ERROR, NOT EQUAL
        CALL    RBYTE
        CP      L
        JR      NZ,RTP7                                                  ; ERROR, NOT EQUAL
        DEC     D                                                        ; NUMBER OF COMPARES (2) - 1
        JP      Z,RTP8                                                   ; OK, 2 COMPARES
        LD      H,D                                                      ; (-->05C7H), SAVE NUMBER OF COMPARES
        JR      TVF1                                                     ; NEXT COMPARE

        ;    FLASHING DATA LOAD

QLOAD:  PUSH    AF
        LD      A,(FLASH)
        CALL    QPONT
        LD      (HL),A
        POP     AF
        RET     

        ;    NEW LINE AND PRINT HL REG (ASCII)

NLPHL:  CALL    NL
        CALL    PRTHL
        RET     

        ;    EDGE (TAPE DATA EDGE DETECT)
        ;    BC=KEYPB (E001H)
        ;    DE=CSTR  (E002H)
        ;    EXIT CF=0 OK   CF=1 BREAK

EDGE:   LD      A,0F8H                                                   ; BREAK KEY IN (88H WOULD BE BETTER!!) 
        LD      (KEYPA),A
        NOP     
EDG1:   LD      A,(BC)
        AND     81H                                                      ; SHIFT & BREAK
        JR      NZ,L060E
        SCF     
        RET     

L060E:  LD      A,(DE)
        AND     20H
        JR      NZ,EDG1                                                  ; CSTR D5 = 0
EDG2:   LD      A,(BC)                                                   ; 8
        AND     81H                                                      ; 9
        JR      NZ,L061A                                                 ; 10/14
        SCF     
        RET     

L061A:  LD      A,(DE)                                                   ; 8
        AND     20H                                                      ; 9
        JR      Z,EDG2                                                   ; CSTR D5 = 1  10/14
        RET                                                              ; 11

        NOP     
        NOP     
        NOP     
        NOP     
        ;    1 BYTE READ
        ;    EXIT SUMDT=STORE
        ;    CF=1 : BREAK
        ;    CF=0 : DATA=ACC

RBYTE:  PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      HL,0800H                                                 ; 8 BITS
        LD      BC,KEYPB                                                 ; KEY DATA E001H
        LD      DE,CSTR                                                  ; $TAPE DATA E002H
RBY1:   CALL    EDGE                                                     ; 41 OR 101
        JP      C,RBY3                                                   ; 13 (SHIFT & BREAK)
        CALL    DLY3                                                     ; 20+18*63+33
        LD      A,(DE)                                                   ; DATA READ :8
        AND     20H
        JP      Z,RBY2                                                   ; 0
        PUSH    HL
        LD      HL,(SUMDT)
        INC     HL                                                       ; CHECK SUM                                ; COUNT HIGH BITS ON TAPE
        LD      (SUMDT),HL
        POP     HL
        SCF     
RBY2:   LD      A,L                                                      ; BUILD CHAR
        RLA     
        LD      L,A
        DEC     H                                                        ; BITCOUNT-1
        JP      NZ,RBY1
        CALL    EDGE
        LD      A,L                                                      ; CHAR READ
RBY3:   POP     HL
        POP     DE
        POP     BC
        RET     

        NOP     
        NOP     
        NOP     

        ;    TAPE MARK DETECT
        ;    E=@L@ : INFORMATION
        ;     =@S@ : DATA
        ;    EXIT CF=0 OK
        ;           =1 BREAK

TMARK:  CALL    GAPCK
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      HL,2828H
        LD      A,E
        CP      0CCH                                                     ; "L"
        JR      Z,L066C
        LD      HL,1414H
L066C:  LD      (TMCNT),HL
        LD      BC,KEYPB
        LD      DE,CSTR
TM1:    LD      HL,(TMCNT)
TM2:    CALL    EDGE
        JR      C,TM4
        CALL    DLY3                                                     ; CALL DLY2*3
        LD      A,(DE)
        AND     20H
        JR      Z,TM1
        DEC     H
        JR      NZ,TM2
TM3:    CALL    EDGE
        JR      C,TM4
        CALL    DLY3                                                     ; CALL DLY2*3
        LD      A,(DE)
        AND     20H
        JR      NZ,TM1
        DEC     L
        JR      NZ,TM3
        CALL    EDGE
TM4:
RET3:   POP     HL
        POP     DE
        POP     BC
        RET     

        ;    MOTOR ON
        ;    IN  D=@W@ :WRITE
        ;         =@R@ :READ
        ;    EXIT CF=0 OK
        ;           =1 BREAK
        ;
        ; If the button is pressed, 

MOTOR:  PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      B,0AH                                                    ; Pulse motor upto 10 times if sense is low. Each pulse flips on->off or off->on
MOT1:   LD      A,(CSTR)                                                 ; Check sense, if low then pulse motor to switch it on.
        AND     10H
        JR      Z,MOT4                                                   ; If NZ (bit PC4 is high), then wait a bit and return, motor running.
                                                                         ; If Z then pulse the motor on circuit.
MOT2:   LD      B,0FFH                                                   ; 2 SEC DELAY 
L06AD:  CALL    DLY12                                                    ; 7 MSEC DELAY
        JR      L06B4                                                    ; MOTOR ENTRY ADJUST

        JR      MOTOR                                                    ; ORG 06B2H

L06B4:  DJNZ    L06AD
        XOR     A
MOT7:   JR      RET3

MOT4:   LD      A,06H                                                    ;  
        LD      HL,CSTPT                                                 ; 8255 Control register
        LD      (HL),A                                                   ; Set PC3 low
        INC     A
        LD      (HL),A                                                   ; Set PC3 high
        DJNZ    MOT1                                                     ; Check to see if sense now active.
        CALL    NL                                                       ; Sense not active so play button hasnt been pressed.
        LD      A,D                                                      ; Determine if we are Loading or Saving, display correct message.
        CP      0D7H                                                     ; "W"
        JR      Z,MOT8
        LD      DE,MSGN1                                                 ; PLAY MARK
        JR      MOT9

MOT8:   LD      DE,MSGN3                                                 ; "RECORD."
        RST     18H                                                      ; CALL MSGX
        LD      DE,MSGN2                                                 ; "PLAY"
MOT9:   RST     18H                                                      ; CALL MSGX
MOT5:   LD      A,(CSTR)                                                 ; Check sense input and wait until it is high.
        AND     10H
        JR      NZ,MOT2
        CALL    QBRK                                                     ; If sense is low, check for User Key Break entry.
        JR      NZ,MOT5
        SCF     
        JR      MOT7   

        ;    INITIAL MESSAGE

MSGQ3:    DB    "**  MONITOR 1Z-013A  **\r"
    NOP

        ;    MOTOR STOP

MSTOP:  PUSH    AF
        PUSH    BC
        PUSH    DE
        LD      B,0AH
MST1:   LD      A,(CSTR)
        AND     10H
        JR      Z,MST3
        LD      A,06H
        LD      (CSTPT),A
        INC     A
        LD      (CSTPT),A
        DJNZ    MST1
MST3:   JP      QRSTR1

        ;    CHECK SUM
        ;    IN   BC=SIZE
        ;         HL=DATA ADDRESS
        ;    EXIT SUMDT=STORE
        ;         CSMDT=STORE

CKSUM:  PUSH    BC
        PUSH    DE
L071C:  PUSH    HL
        LD      DE,0
CKS1:   LD      A,B
        OR      C
        JR      NZ,CKS2
        EX      DE,HL
L0725:  LD      (SUMDT),HL                                               ; NUMBER OF HIGHBITS IN DATA
        LD      (CSMDT),HL
        POP     HL
        POP     DE
        POP     BC
        RET     

CKS2:   LD      A,(HL)
        PUSH    BC
        LD      B,8
CKS3:   RLCA    
        JR      NC,L0737
        INC     DE
L0737:  DJNZ    CKS3
L0739:  POP     BC
        INC     HL
        DEC     BC
        JR      CKS1

        ;    MODE SET OF KEYPORT

QMODE:  LD      HL,KEYPF
        LD      (HL),8AH                                                 ; 10001010 CTRL WORD MODE0
        LD      (HL),07H                                                 ; PC3=1 M-ON
        LD      (HL),05H                                                 ; PC2=1 INTMSK
        RET     

        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     

        ;    107 MICRO SEC DELAY

DLY1:   LD      A,15H                                                    ; 18*21+20
L075B:  DEC     A
        JP      NZ,L075B
        RET     

DLY2:   LD      A,13H                                                    ; 18*19+20
L0762:  DEC     A
        JP      NZ,L0762
        RET     

        ;    1 BYTE WRITE

WBYTE:  PUSH    BC
        LD      B,8
        CALL    LONG
WBY1:   RLCA    
        CALL    C,LONG
        CALL    NC,SHORT
        DEC     B
        JP      NZ,WBY1
        POP     BC
        RET     

        ;    GAP + TAPEMARK
        ;    E=@L@ LONG GAP
        ;     =@s@ SHORT GAP

GAP:    PUSH    BC
        PUSH    DE
        LD      A,E
        LD      BC,55F0H
        LD      DE,2828H
        CP      0CCH                                                     ; "L"
        JP      Z,GAP1
        LD      BC,2AF8H
        LD      DE,1414H
GAP1:   CALL    SHORT
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,GAP1
GAP2:   CALL    LONG
        DEC     D
        JR      NZ,GAP2
GAP3:   CALL    SHORT
        DEC     E
        JR      NZ,GAP3
        CALL    LONG
        POP     DE
        POP     BC
        RET     

        ;    MEMORY CORRECTION
        ;    COMMAND "M"

MCOR:   CALL    HEXIY                                                    ; CORRECTION ADDRESS
MCR1:   CALL    NLPHL                                                    ; CORRECTION ADDRESS PRINT
        CALL    SPHEX                                                    ; ACC-->ASCII DISP.
        CALL    QPRTS                                                    ; SPACE PRINT
        CALL    BGETL                                                    ; GET DATA & CHECK DATA
        CALL    HLHEX                                                    ; HL<--ASCII(DE)
        JR      C,MCR3
        CALL    P4DE                                                     ; (INC DE)*4
        INC     DE
        CALL    L2HEX                                                    ; DATA CHECK
        JR      C,MCR1
        CP      (HL)
        JR      NZ,MCR1
        INC     DE
        LD      A,(DE)
        CP      0DH                                                      ; NOT CORRECTION ?
        JR      Z,MCR2
        CALL    L2HEX                                                    ; ACC<--HL(ASCII)
        JR      C,MCR1
        LD      (HL),A                                                   ; DATA CORRECT
MCR2:   INC     HL
        JR      MCR1

MCR3:   LD      H,B                                                      ; MEMORY ADDRESS
        LD      L,C
        JR      MCR1

    DB    "(HL)"
    DB    0F1H
    DB    9EH
    DB    "SUB ("

        ;    GET 1 LINE STATEMENT *
        ;    DE=DATA STORE LOW ADDRESS
        ;    (END=CR)

QGETL:  PUSH    AF
        PUSH    BC
        PUSH    HL
        PUSH    DE
GETL1:  CALL    QQKEY                                                    ; ENTRY KEY
AUTO3:  PUSH    AF                                                       ; IN KEY DATA SAVE
        LD      B,A
        LD      A,(SWRK)                                                 ; BELL WORK
        RRCA    
        CALL    NC,QBEL                                                  ; ENTRY BELL
        LD      A,B
        LD      HL,KANAF                                                 ; KANA & GRAPH FLAGS
        AND     0F0H
        CP      0C0H
        POP     DE                                                       ; EREG=FLAGREG
        LD      A,B
        JR      NZ,GETL2                                                 ; NOT C0H
        CP      0CDH                                                     ; CR
        JR      Z,GETL3
        CP      0CBH                                                     ; BREAK
        JP      Z,GETLC
        CP      0CFH                                                     ; NIKO MARK WH.
        JR      Z,GETL2
        CP      0C7H                                                     ; CRT EDITION
        JR      NC,GETL5                                                 ; <=C7H
        RR      E                                                        ; >C7H & CFLAG, CY ? GRAPHIC MODE,CURS.DISPL.
        LD      A,B
        JR      NC,GETL5
GETL2:  CALL    QDSP                                                     ; DISPL.
        JR      GETL1

GETL5:  CALL    QDPCT                                                    ; CRT CONTROL
        JR      GETL1

        ;    BREAK IN

GETLC:  POP     HL
        PUSH    HL
        LD      (HL),1BH                                                 ; BREAK CODE
        INC     HL
        LD      (HL),0DH
        JR      GETLR

        ;    GETLA

GETLA:  RRCA                                                             ; CY<--D7
        JR      NC,GETL6
        JR      GETLB

        ;    DELAY 7 MSEC AND SWEP

DSWEP:  CALL    DLY12
        CALL    QSWEP
        RET     

        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     

GETL3:  CALL    PMANG                                                    ; CR
        LD      B,COLW                                                   ; 1 LINE
        JR      NC,GETLA
        DEC     H                                                        ; BEFORE LINE
GETLB:  LD      B,COLW*2                                                 ; 2 LINE
GETL6:  LD      L,0
        CALL    QPNT1
        POP     DE                                                       ; STORE TOP ADDRESS
        PUSH    DE
GETLZ:  LD      A,(HL)
        CALL    QDACN
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    GETLZ
        EX      DE,HL
GETLU:  LD      (HL),0DH
        DEC     HL
        LD      A,(HL)
        CP      20H                                                      ; SPACE THEN CR

        ;    CR AND NEW LINE

        JR      Z,GETLU

        ;    NEW LINE RETURN

GETLR:  CALL    QLTNL
        POP     DE
        POP     HL
        POP     BC
        POP     AF
        RET     

        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     

        ;    MESSAGE PRINT
        ;    DE PRINT DATA LOW ADDRESS
        ;    END=CR

QMSG:   PUSH    AF
        PUSH    BC
        PUSH    DE
MSG1:   LD      A,(DE)
        CP      0DH                                                      ; CR
        JR      Z,MSGX2
        CALL    QPRNT
        INC     DE
        JR      MSG1

        ;    ALL PRINT MESSAGE

QMSGX:  PUSH    AF
        PUSH    BC
        PUSH    DE
MSGX1:  LD      A,(DE)
        CP      0DH
MSGX2:  JP      Z,QRSTR1
        CALL    QADCN
        CALL    PRNT3
        INC     DE
        JR      MSGX1

        ;    TOP OF KEYTBLS

QKYSM:  LD      DE,KTBLS                                                 ; SHIFT ALSO
        JR      QKY5

        ;    BREAK CODE IN

NBRK:   LD      A,0CBH                                                   ; BREAK CODE
        OR      A
        JR      QKY1

        ;    GETKEY
        ;    NO ECHO BACK
        ;    EXIT ACC=ASCII CODE

QGET:   CALL    QKEY                                                     ; KEY IN (DISPLAY CODE)
        SUB     0F0H                                                     ; NOT KEYIN CODE
        RET     Z
        ADD     A,0F0H
        JP      QDACN                                                    ; DISPLAY TO ASCII CODE

        NOP     
        NOP     

        ;    1 KEY INPUT
        ;    IN   B=KEY MODE (SHIFT, CTRL, BREAK)
        ;         C=KEY DATA (COLUMN & ROW)
        ;    EXIT ACC=DISPLAY CODE
        ;         IF NO KEY  ACC=F0H
        ;         IF CY=1 THEN ATTRIBUTE ON
        ;                      (SMALL, HIRAKANA)

QKEY:   PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    DSWEP                                                    ; DELAY AND KEY SWEP
        LD      A,B
        RLCA    
        JR      C,QKY2
        LD      A,0F0H                                                   ; SHIFT OR CTRL HERE
QKY1:   POP     HL
        POP     DE
        POP     BC
        RET     

QKY2:   LD      DE,KTBL                                                  ; NORMAL KEY TABLE
        LD      A,B
        CP      88H                                                      ; BREAK IN (SHIFT & BRK)
        JR      Z,NBRK
        LD      H,0                                                      ; HL=ROW & COLUMN
        LD      L,C
        BIT     5,A                                                      ; CTRL CHECK
        JR      NZ,L08F7                                                 ; YES, CTRL
        LD      A,(KANAF)                                                ; 0=NR., 1=GRAPH
        RRCA    
        JP      C,QKYGRP                                                 ; GRAPH MODE
        LD      A,B                                                      ; CTRL KEY CHECK
        RLA     
        RLA     
        JR      C,QKYSM
        JR      QKY5

L08F7:  LD      DE,KTBLC                                                 ; CONTROL KEY TABLE
QKY5:   ADD     HL,DE                                                    ; TABLE
QKY55:  LD      A,(HL)
        JR      QKY1

QKYGRP: BIT     6,B
        JR      Z,QKYGRS
        LD      DE,KTBLG
        ADD     HL,DE
        SCF     
        JR      QKY55

QKYGRS: LD      DE,KTBLGS
        JR      QKY5

        ;    NEWLINE

QLTNL:  XOR     A
        LD      (DPRNT),A                                                ; ROW POINTER
        LD      A,0CDH                                                   ; CR
        JR      PRNT5

        NOP     
        NOP     

QNL:    LD      A,(DPRNT)
        OR      A
        RET     Z
        JR      QLTNL

        NOP     

        ;    PRINT SPACE

QPRTS:  LD      A,20H
        JR      QPRNT

        ;    PRINT TAB

QPRTT:  CALL    PRNTS
        LD      A,(DPRNT)
        OR      A
        RET     Z
L092C:  SUB     10
        JR      C,QPRTT
        JR      NZ,L092C
        NOP     
        NOP     
        NOP     

        ;    PRINT
        ;    IN ACC=PRINT DATA (ASCII)

QPRNT:  CP      0DH                                                      ; CR
        JR      Z,QLTNL
        PUSH    BC
        LD      C,A
        LD      B,A
        CALL    QPRT
        LD      A,B
        POP     BC
        RET     

MSGOK:    DB    "OK!\r"

        ;    PRINT ROUTINE
        ;    1 CHARACTER
        ;    INPUT:C=ASCII DATA (QDSP+QDPCT)

QPRT:    LD    A,C 
        CALL    QADCN                                                    ; ASCII TO DSPLAY
        LD      C,A
        CP      0F0H
        RET     Z                                                        ; ZERO=ILLEGAL DATA
        AND     0F0H                                                     ; MSD CHECK
        CP      0C0H
        LD      A,C
        JR      NZ,PRNT3
        CP      0C7H
        JR      NC,PRNT3                                                 ; CRT EDITOR
PRNT5:  CALL    QDPCT
        CP      0C3H                                                     ; "->"
        JR      Z,PRNT4
        CP      0C5H                                                     ; HOME
        JR      Z,PRNT2
        CP      0C6H                                                     ; CLR
        RET     NZ
PRNT2:  XOR     A
L0968:  LD      (DPRNT),A
        RET     

PRNT3:  CALL    QDSP
PRNT4:  LD      A,(DPRNT)                                                ; TAB POINT+1
        INC     A
        CP      COLW*2
        JR      C,L0968
        SUB     COLW*2
        JR      L0968

        ;    FLASHING BYPASS 1

FLAS1:  LD      A,(FLASH)
        JR      FLAS2

        ;    BREAK SUBROUTINE BYPASS 1
        ;    CTRL OR NOT KEY

QBRK2:  BIT     5,A                                                      ; NOT OR CTRL
        JR      Z,QBRK3                                                  ; CTRL
        OR      A                                                        ; NOTKEY A=7FH
        RET     

QBRK3:  LD      A,20H                                                    ; CTRL D5=1
        OR      A                                                        ; ZERO FLG CLR
        SCF     
        RET     

MSGSV:    DB    "FILENAME? "
    DB    0DH

        ;    DLY 7 MSEC
DLY12:  PUSH    BC
        LD      B,15H
L0999:  CALL    DLY3
        DJNZ    L0999
        POP     BC
        RET     

        ;    LOADING MESSAGE

MSGQ2:    DB    "LOADING \r"

        ;    DELAY FOR LONG PULSE

DLY4:   LD      A,59H                                                    ; 18*89+20
L09AB:  DEC     A
        JP      NZ,L09AB
        RET     

        NOP     
        NOP     
        NOP     

        ;    KEY BOARD SEARCH
        ;    & DISPLAY CODE CONVERSION
        ;    EXIT A=DISPLAY CODE
        ;         CY=GRAPH MODE
        ;    WITH CURSOR DISPLAY

QQKEY:  PUSH    HL
        CALL    QSAVE
KSL1:   CALL    FLKEY                                                    ; KEY
        JR      NZ,KSL1                                                  ; KEY IN THEN JUMP
KSL2:   CALL    FLKEY
        JR      Z,KSL2                                                   ; NOT KEY IN THEN JUMP
        LD      H,A
        CALL    DLY12                                                    ; DELAY CHATTER
        CALL    QKEY
        PUSH    AF
        CP      H                                                        ; CHATTER CHECK
        POP     HL
        JR      NZ,KSL2
        PUSH    HL
        POP     AF                                                       ; IN KEY DATA
        CALL    QLOAD                                                    ; FLASHING DATA LOAD
        POP     HL
        RET     

        ;    CLEAR 2

NCLR08: XOR     A                                                        ; CY FLAG
NCLR8:  LD      BC,0800H
CLEAR:  PUSH    DE                                                       ; BC=CLR BYTE SIZE, A=CLR DATA
        LD      D,A
CLEAR1: LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,CLEAR1
        POP     DE
        RET     

        ;    FLASHING 2

QFLS:   PUSH    AF
        PUSH    HL
        LD      A,(KEYPC)
        RLCA    
        RLCA    
        JR      C,FLAS1
        LD      A,(FLSDT)
FLAS2:  CALL    QPONT                                                    ; DISPLAY POSITION
        LD      (HL),A
        POP     HL
        POP     AF
        RET     

        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     

QFLAS:  JR      QFLS

        ;    SHORT AND LONG PULSE FOR 1 BIT WRITE

SHORT:  PUSH    AF                                                       ; 12
        LD      A,03H                                                    ; 9
        LD      (CSTPT),A                                                ; E003H PC3=1:16
        CALL    DLY1                                                     ; 20+18*21+20
        CALL    DLY1                                                     ; 20+18*21+20
        LD      A,02H                                                    ; 9
        LD      (CSTPT),A                                                ; E003H PC3=0:16
        CALL    DLY1                                                     ; 20+18*21+20
        CALL    DLY1                                                     ; 20+18*21+20
        POP     AF                                                       ; 11
        RET                                                              ; 11

LONG:   PUSH    AF                                                       ; 11
        LD      A,03H                                                    ; 9
        LD      (CSTPT),A                                                ; 16
        CALL    DLY4                                                     ; 20+18*89+20
        LD      A,02H                                                    ; 9
        LD      (CSTPT),A                                                ; 16
        CALL    DLY4                                                     ; 20+18*89+20
        POP     AF                                                       ; 11
        RET                                                              ; 11

        NOP     
        NOP     
        NOP     
        NOP     
        NOP     

        ;    BREAK KEY CHECK
        ;    AND SHIFT, CTRL KEY CHECK
        ;    EXIT BREAK ON : ZERO=1
        ;               OFF: ZERO=0
        ;         NO KEY   : CY  =0
        ;         KEY IN   : CY  =1
        ;          A D6=1  : SHIFT ON
        ;              =0  :       OFF
        ;            D5=1  : CTRL ON
        ;              =0  :      OFF
        ;        D4=1  : SHIFT+CNT ON
        ;          =0  :           OFF

QBRK:   LD      A,0F8H                                                   ; LINE 8SWEEP
        LD      (KEYPA),A
        NOP     
        LD      A,(KEYPB)
        OR      A
        RRA     
        JP      C,QBRK2                                                  ; SHIFT ?
        RLA     
        RLA     
        JR      NC,QBRK1                                                 ; BREAK ?
        LD      A,40H                                                    ; SHIFT D6=1
        SCF     
        RET     

QBRK1:  XOR     A                                                        ; SHIFT ?
        RET     

        ;    320 U SEC DELAY

DLY3:   LD      A,3FH                                                    ; 18*63+33
        JP      L0762                                                    ; JP DLY2+2

        NOP     

        ;    KEY BOARD SWEEP
        ;    EXIT B,D7=0  NO DATA
        ;             =1  DATA
        ;           D6=0  SHIFT OFF
        ;         =1  SHIFT ON
        ;           D5=0  CTRL OFF
        ;         =1  CTRL ON
        ;           D4=0  SHIFT+CTRL OFF
        ;         =1  SHIFT+CTRL ON
        ;         C   = ROW & COLUMN
        ;        7 6 5 4 3 2 1 0
        ;        * * ^ ^ ^ < < <

QSWEP:  PUSH    DE
        PUSH    HL
        XOR     A
        LD      B,0F8H
        LD      D,A
        CALL    QBRK
        JR      NZ,SWEP6
        LD      D,88H                                                    ; BREAK ON
        JR      SWEP9

SWEP6:  JR      NC,SWEP0
        LD      D,A
        JR      SWEP0

SWEP01: SET     7,D
SWEP0:  DEC     B
        LD      A,B
        LD      (KEYPA),A
        CP      0EFH                                                     ; MAP SWEEP END ?
        JR      NZ,SWEP3
        CP      0F8H                                                     ; BREAK KEY ROW
        JR      Z,SWEP0
SWEP9:  LD      B,D
        POP     HL
        POP     DE
        RET     

SWEP3:  LD      A,(KEYPB)
        CPL     
        OR      A
        JR      Z,SWEP0
        LD      E,A
SWEP2:  LD      H,8
        LD      A,B
        AND     0FH
        RLCA    
        RLCA    
        RLCA    
        LD      C,A
        LD      A,E
L0A89:  DEC     H
        RRCA    
        JR      NC,L0A89
        LD      A,H
        ADD     A,C
        LD      C,A
        JR      SWEP01
        ;
        ;
        ;   ASCII TO DISPLAY CODE TABL
        ;
ATBL:    
        ;  00 - 0F
    DB    0F0H                                                           ; ^ @
    DB    0F0H                                                           ; ^ A
    DB    0F0H                                                           ; ^ B
    DB    0F3H                                                           ; ^ C
    DB    0F0H                                                           ; ^ D
    DB    0F5H                                                           ; ^ E
    DB    0F0H                                                           ; ^ F
    DB    0F0H                                                           ; ^ G
    DB    0F0H                                                           ; ^ H
    DB    0F0H                                                           ; ^ I
    DB    0F0H                                                           ; ^ J
    DB    0F0H                                                           ; ^ K
    DB    0F0H                                                           ; ^ L
    DB    0F0H                                                           ; ^ M
    DB    0F0H                                                           ; ^ N
    DB    0F0H                                                           ; ^ O
        ;  10 - 1F
    DB    0F0H                                                           ; ^ P
    DB    0C1H                                                           ; ^ Q CUR. DOWN
    DB    0C2H                                                           ; ^ R CUR. UP
    DB    0C3H                                                           ; ^ S CUR. RIGHT
    DB    0C4H                                                           ; ^ T CUR. LEFT
    DB    0C5H                                                           ; ^ U HOME
    DB    0C6H                                                           ; ^ V CLEAR
    DB    0F0H                                                           ; ^ W
    DB    0F0H                                                           ; ^ X
    DB    0F0H                                                           ; ^ Y
    DB    0F0H                                                           ; ^ Z SEP.
    DB    0F0H                                                           ; ^ [
    DB    0F0H                                                           ; ^ \
    DB    0F0H                                                           ; ^ ]
    DB    0F0H                                                           ; ^ ^
    DB    0F0H                                                           ; ^ -
        ;  20 - 2F
    DB    00H                                                            ; SPACE
    DB    61H                                                            ; !
    DB    62H                                                            ; "
    DB    63H                                                            ; #
    DB    64H                                                            ; $
    DB    65H                                                            ; %
    DB    66H                                                            ; &
    DB    67H                                                            ; '
    DB    68H                                                            ; (
    DB    69H                                                            ; )
    DB    6BH                                                            ; *
    DB    6AH                                                            ; +
    DB    2FH                                                            ; ,
    DB    2AH                                                            ; -
    DB    2EH                                                            ; .
    DB    2DH                                                            ; /
        ;  30 - 3F
    DB    20H                                                            ; 0
    DB    21H                                                            ; 1
    DB    22H                                                            ; 2
    DB    23H                                                            ; 3
    DB    24H                                                            ; 4
    DB    25H                                                            ; 5
    DB    26H                                                            ; 6
    DB    27H                                                            ; 7
    DB    28H                                                            ; 8
    DB    29H                                                            ; 9
    DB    4FH                                                            ; :
    DB    2CH                                                            ;         ;
    DB    51H                                                            ; <
    DB    2BH                                                            ; =
    DB    57H                                                            ; >
    DB    49H                                                            ; ?
        ;  40 - 4F
    DB    55H                                                            ; @
    DB    01H                                                            ; A
    DB    02H                                                            ; B
    DB    03H                                                            ; C
    DB    04H                                                            ; D
    DB    05H                                                            ; E
    DB    06H                                                            ; F
    DB    07H                                                            ; G
    DB    08H                                                            ; H
    DB    09H                                                            ; I
    DB    0AH                                                            ; J
    DB    0BH                                                            ; K
    DB    0CH                                                            ; L
    DB    0DH                                                            ; M
    DB    0EH                                                            ; N
    DB    0FH                                                            ; O
        ;  50 - 5F
    DB    10H                                                            ; P
    DB    11H                                                            ; Q
    DB    12H                                                            ; R
    DB    13H                                                            ; S
    DB    14H                                                            ; T
    DB    15H                                                            ; U
    DB    16H                                                            ; V
    DB    17H                                                            ; W
    DB    18H                                                            ; X
    DB    19H                                                            ; Y
    DB    1AH                                                            ; Z
    DB    52H                                                            ; [
    DB    59H                                                            ; \
    DB    54H                                                            ; ]
    DB    50H                                                            ; 
    DB    45H                                                            ; 
        ;  60 - 6F
    DB    0C7H                                                           ; UFO
    DB    0C8H
    DB    0C9H
    DB    0CAH
    DB    0CBH
    DB    0CCH
    DB    0CDH
    DB    0CEH
    DB    0CFH
    DB    0DFH
    DB    0E7H
    DB    0E8H
    DB    0E5H
    DB    0E9H
    DB    0ECH
    DB    0EDH
        ;  70 - 7F
    DB    0D0H
    DB    0D1H
    DB    0D2H
    DB    0D3H
    DB    0D4H
    DB    0D5H
    DB    0D6H
    DB    0D7H
    DB    0D8H
    DB    0D9H
    DB    0DAH
    DB    0DBH
    DB    0DCH
    DB    0DDH
    DB    0DEH
    DB    0C0H
        ;  80 - 8F
    DB    80H                                                            ; }
    DB    0BDH
    DB    9DH
    DB    0B1H
    DB    0B5H
    DB    0B9H
    DB    0B4H
    DB    9EH
    DB    0B2H
    DB    0B6H
    DB    0BAH
    DB    0BEH
    DB    9FH
    DB    0B3H
    DB    0B7H
    DB    0BBH
        ;  90 - 9F
    DB    0BFH                                                           ; _
    DB    0A3H
    DB    85H
    DB    0A4H                                                           ; `
    DB    0A5H                                                           ; ~
    DB    0A6H
    DB    94H
    DB    87H
    DB    88H
    DB    9CH
    DB    82H
    DB    98H
    DB    84H
    DB    92H
    DB    90H
    DB    83H
        ;  A0 - AF
    DB    91H
    DB    81H
    DB    9AH
    DB    97H
    DB    93H
    DB    95H
    DB    89H
    DB    0A1H
    DB    0AFH
    DB    8BH
    DB    86H
    DB    96H
    DB    0A2H
    DB    0ABH
    DB    0AAH
    DB    8AH
        ;  B0 - BF
    DB    8EH
    DB    0B0H
    DB    0ADH
    DB    8DH
    DB    0A7H
    DB    0A8H
    DB    0A9H
    DB    8FH
    DB    8CH
    DB    0AEH
    DB    0ACH
    DB    9BH
    DB    0A0H
    DB    99H
    DB    0BCH                                                           ; {
    DB    0B8H
        ;  C0 - CF
    DB    40H
    DB    3BH
    DB    3AH
    DB    70H
    DB    3CH
    DB    71H
    DB    5AH
    DB    3DH
    DB    43H
    DB    56H
    DB    3FH
    DB    1EH
    DB    4AH
    DB    1CH
    DB    5DH
    DB    3EH
        ;  D0 - DF
    DB    5CH
    DB    1FH
    DB    5FH
    DB    5EH
    DB    37H
    DB    7BH
    DB    7FH
    DB    36H
    DB    7AH
    DB    7EH
    DB    33H
    DB    4BH
    DB    4CH
    DB    1DH
    DB    6CH
    DB    5BH
        ;  E0 - EF
    DB    78H
    DB    41H
    DB    35H
    DB    34H
    DB    74H
    DB    30H
    DB    38H
    DB    75H
    DB    39H
    DB    4DH
    DB    6FH
    DB    6EH
    DB    32H
    DB    77H
    DB    76H
    DB    72H
        ;  F0 - FF
    DB    73H
    DB    47H
    DB    7CH
    DB    53H
    DB    31H
    DB    4EH
    DB    6DH
    DB    48H
    DB    46H
    DB    7DH
    DB    44H
    DB    1BH
    DB    58H
    DB    79H
    DB    42H
    DB    60H

        ;    FLASHING DATA SAVE

QSAVE:  LD      HL,FLSDT
        LD      (HL),0EFH                                                ; NORMAL CURSOR
        LD      A,(KANAF)
        RRCA    
        JR      C,L0BA0                                                  ; GRAPH MODE
        RRCA    
        JR      NC,SV0                                                   ; NORMAL MODE
L0BA0:  LD      (HL),0FFH                                                ; GRAPH CURSOR
SV0:    LD      A,(HL)
        PUSH    AF
        CALL    QPONT                                                    ; FLASHING POSITION
        LD      A,(HL)
        LD      (FLASH),A
        POP     AF
        LD      (HL),A
        XOR     A
        LD      HL,KEYPA
L0BB1:  LD      (HL),A
        CPL                                                              ; OH NO! UNUSED BITS WERE TOUCHED TOO!!!
        LD      (HL),A
        RET     

SV1:    LD      (HL),43H                                                 ; KANA CURSOR
        JR      SV0

        ;    ASCII TO DISPLAY CODE CONVERT
        ;    IN ACC:ASCII
        ;    EXIT ACC:DISPLAY CODE

QADCN:  PUSH    BC
        PUSH    HL
        LD      HL,ATBL
        LD      C,A
        LD      B,0
        ADD     HL,BC
        LD      A,(HL)
        JR      DACN3

VRNS:    DB    "V1.0A\r"                                                 ; VERSION MANAGEMENT
        NOP     
        NOP     
        NOP     

        ;    DISPLAY CODE TO ASCII CONVERSION
        ;    IN ACC=DISPLAY CODE
        ;    EXIT ACC=ASCII

QDACN:  PUSH    BC
        PUSH    HL
        PUSH    DE
        LD      HL,ATBL
        LD      D,H
        LD      E,L
        LD      BC,0100H
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

        ;
        ;
        ;   KEY MATRIX TO DISPLAY CODE TABL
        ;
KTBL:
        ;S0   00 - 07
    DB    0BFH                                                           ; SPARE
    DB    0CAH                                                           ; GRAPH
    DB    58H                                                            ; 
    DB    0C9H                                                           ; ALPHA
    DB    0F0H                                                           ; NO
    DB    2CH                                                            ;         ;
    DB    4FH                                                            ; :
    DB    0CDH                                                           ; CR
        ;S1   08 - 0F
    DB    19H                                                            ; Y
    DB    1AH                                                            ; Z
    DB    55H                                                            ; @
    DB    52H                                                            ; [
    DB    54H                                                            ; ]
    DB    0F0H                                                           ; NULL
    DB    0F0H                                                           ; NULL
    DB    0F0H                                                           ; NULL
        ;S2   10 - 17
    DB    11H                                                            ; Q
    DB    12H                                                            ; R
    DB    13H                                                            ; S
    DB    14H                                                            ; T
    DB    15H                                                            ; U
    DB    16H                                                            ; V
    DB    17H                                                            ; W
    DB    18H                                                            ; X
        ;S3   18 - 1F
    DB    09H                                                            ; I
    DB    0AH                                                            ; J
    DB    0BH                                                            ; K
    DB    0CH                                                            ; L
    DB    0DH                                                            ; M
    DB    0EH                                                            ; N
    DB    0FH                                                            ; O
    DB    10H                                                            ; P
        ;S4   20 - 27
    DB    01H                                                            ; A
    DB    02H                                                            ; B
    DB    03H                                                            ; C
    DB    04H                                                            ; D
    DB    05H                                                            ; E
    DB    06H                                                            ; F
    DB    07H                                                            ; G
    DB    08H                                                            ; H
        ;S5   28 - 2F
    DB    21H                                                            ; 1
    DB    22H                                                            ; 2
    DB    23H                                                            ; 3
    DB    24H                                                            ; 4
    DB    25H                                                            ; 5
    DB    26H                                                            ; 6
    DB    27H                                                            ; 7
    DB    28H                                                            ; 8
        ;S6   30 - 37
    DB    59H                                                            ; \
    DB    50H                                                            ; 
    DB    2AH                                                            ; -
    DB    00H                                                            ; SPACE
    DB    20H                                                            ; 0
    DB    29H                                                            ; 9
    DB    2FH                                                            ; ,
    DB    2EH                                                            ; .
        ;S7   38 - 3F
    DB    0C8H                                                           ; INST.
    DB    0C7H                                                           ; DEL.
    DB    0C2H                                                           ; CURSOR UP
    DB    0C1H                                                           ; CURSOR DOWN
    DB    0C3H                                                           ; CURSOR RIGHT
    DB    0C4H                                                           ; CURSOR LEFT
    DB    49H                                                            ; ?
    DB    2DH                                                            ; /
        ;
        ;
        ;   KTBL SHIFT ON
        ;
KTBLS:
        ;S0   00 - 07
    DB    0BFH                                                           ; SPARE
    DB    0CAH                                                           ; GRAPH
    DB    1BH                                                            ; POND
    DB    0C9H                                                           ; ALPHA
    DB    0F0H                                                           ; NO
    DB    6AH                                                            ; +
    DB    6BH                                                            ; *
    DB    0CDH                                                           ; CR
        ;S1   08 - 0F
    DB    99H                                                            ; y
    DB    9AH                                                            ; z
    DB    0A4H                                                           ; `
    DB    0BCH                                                           ; {
    DB    40H                                                            ; }
    DB    0F0H                                                           ; NULL
    DB    0F0H                                                           ; NULL
    DB    0F0H                                                           ; NULL
        ;S2   10 - 17
    DB    91H                                                            ; q
    DB    92H                                                            ; r
    DB    93H                                                            ; s
    DB    94H                                                            ; t
    DB    95H                                                            ; u
    DB    96H                                                            ; v
    DB    97H                                                            ; w
    DB    98H                                                            ; x
        ;S3   18 - 1F
    DB    89H                                                            ; i
    DB    8AH                                                            ; j
    DB    8BH                                                            ; k
    DB    8CH                                                            ; l
    DB    8DH                                                            ; m
    DB    8EH                                                            ; n
    DB    8FH                                                            ; o
    DB    90H                                                            ; p
        ;S4   20 - 27
    DB    81H                                                            ; a
    DB    82H                                                            ; b
    DB    83H                                                            ; c
    DB    84H                                                            ; d
    DB    85H                                                            ; e
    DB    86H                                                            ; f
    DB    87H                                                            ; g
    DB    88H                                                            ; h
        ;S5   28 - 2F
    DB    61H                                                            ; !
    DB    62H                                                            ; "
    DB    63H                                                            ; #
    DB    64H                                                            ; $
    DB    65H                                                            ; %
    DB    66H                                                            ; &
    DB    67H                                                            ; '
    DB    68H                                                            ; (
        ;S6   30 - 37
    DB    80H                                                            ; \
    DB    0A5H                                                           ; POND MARK
    DB    2BH                                                            ; YEN
    DB    00H                                                            ; SPACE
    DB    60H                                                            ; ¶
    DB    69H                                                            ; )
    DB    51H                                                            ; <
    DB    57H                                                            ; >
        ;S7   38 - 3F
    DB    0C6H                                                           ; CLR
    DB    0C5H                                                           ; HOME
    DB    0C2H                                                           ; CURSOR UP
    DB    0C1H                                                           ; CURSOR DOWN
    DB    0C3H                                                           ; CURSOR RIGHT
    DB    0C4H                                                           ; CURSOR LEFT
    DB    5AH                                                            ;
    DB    45H                                                            ;
        ;
        ;
        ;   GRAPHIC
        ;
KTBLGS:
        ;S0   00 - 07
    DB    0BFH                                                           ; SPARE
    DB    0F0H                                                           ; GRAPH BUT NULL
    DB    0E5H                                                           ; #
    DB    0C9H                                                           ; ALPHA
    DB    0F0H                                                           ; NO
    DB    42H                                                            ; #        ;
    DB    0B6H                                                           ; #:
    DB    0CDH                                                           ; CR
        ;S1   08 - 0F
    DB    75H                                                            ; #Y
    DB    76H                                                            ; #Z
    DB    0B2H                                                           ; #@
    DB    0D8H                                                           ; #[
    DB    4EH                                                            ; #]
    DB    0F0H                                                           ; #NULL
    DB    0F0H                                                           ; #NULL
    DB    0F0H                                                           ; #NULL
        ;S2   10 - 17
    DB    3CH                                                            ; #Q
    DB    30H                                                            ; #R
    DB    44H                                                            ; #S
    DB    71H                                                            ; #T
    DB    79H                                                            ; #U
    DB    0DAH                                                           ; #V
    DB    38H                                                            ; #W
    DB    6DH                                                            ; #X
        ;S3   18 - 1F
    DB    7DH                                                            ; #I
    DB    5CH                                                            ; #J
    DB    5BH                                                            ; #K
    DB    0B4H                                                           ; #L
    DB    1CH                                                            ; #M
    DB    32H                                                            ; #N
    DB    0B0H                                                           ; #O
    DB    0D6H                                                           ; #P
        ;S4   20 - 27
    DB    53H                                                            ; #A
    DB    6FH                                                            ; #B
    DB    0DEH                                                           ; #C
    DB    47H                                                            ; #D
    DB    34H                                                            ; #E
    DB    4AH                                                            ; #F
    DB    4BH                                                            ; #G
    DB    72H                                                            ; #H
        ;S5   28 - 2F
    DB    37H                                                            ; #1
    DB    3EH                                                            ; #2
    DB    7FH                                                            ; #3
    DB    7BH                                                            ; #4
    DB    3AH                                                            ; #5
    DB    5EH                                                            ; #6
    DB    1FH                                                            ; #7
    DB    0BDH                                                           ; #8
        ;S6   30 - 37
    DB    0D4H                                                           ; #YEN
    DB    9EH                                                            ; #+
    DB    0D2H                                                           ; #-
    DB    00H                                                            ; SPACE
    DB    9CH                                                            ; #0
    DB    0A1H                                                           ; #9
    DB    0CAH                                                           ; #,
    DB    0B8H                                                           ; #.
        ;S7   38 - 3F
    DB    0C8H                                                           ; INST
    DB    0C7H                                                           ; DEL.
    DB    0C2H                                                           ; CURSOR UP
    DB    0C1H                                                           ; CURSOR DOWN
    DB    0C3H                                                           ; CURSOR RIGHT
    DB    0C4H                                                           ; CURSOR LEFT
    DB    0BAH                                                           ; #?
    DB    0DBH                                                           ; #/
        ;
        ;
        ;   CONTROL CODE
        ;
KTBLC:
        ;S0   00 - 07
    DB    0F0H
    DB    0F0H
    DB    0F0H                                                           ; ^
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H
        ;S1   08 - 0F
    DB    0F0H                                                           ; ^Y E3
    DB    5AH                                                            ; ^Z E4 (CHECKER)
    DB    0F0H                                                           ; ^@
    DB    0F0H                                                           ; ^[ EB/E5
    DB    0F0H                                                           ; ^] EA/E7 
    DB    0F0H                                                           ; #NULL
    DB    0F0H                                                           ; #NULL
    DB    0F0H                                                           ; #NULL
        ;S2   10 - 17
    DB    0C1H                                                           ; ^Q
    DB    0C2H                                                           ; ^R
    DB    0C3H                                                           ; ^S
    DB    0C4H                                                           ; ^T
    DB    0C5H                                                           ; ^U
    DB    0C6H                                                           ; ^V
    DB    0F0H                                                           ; ^W E1
    DB    0F0H                                                           ; ^X E2
        ;S3   18 - 1F
    DB    0F0H                                                           ; ^I F9
    DB    0F0H                                                           ; ^J FA
    DB    0F0H                                                           ; ^K FB
    DB    0F0H                                                           ; ^L FC
    DB    0F0H                                                           ; ^M CD
    DB    0F0H                                                           ; ^N FE
    DB    0F0H                                                           ; ^O FF
    DB    0F0H                                                           ; ^P E0
        ;S4   20 - 27
    DB    0F0H                                                           ; ^A F1
    DB    0F0H                                                           ; ^B F2
    DB    0F0H                                                           ; ^C F3
    DB    0F0H                                                           ; ^D F4
    DB    0F0H                                                           ; ^E F5
    DB    0F0H                                                           ; ^F F6
    DB    0F0H                                                           ; ^G F7
    DB    0F0H                                                           ; ^H F8
        ;S5   28 - 2F
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H
        ;S6   30 - 37 (ERROR? 7 VALUES ONLY!!)
    DB    0F0H                                                           ; ^YEN E6
    DB    0F0H                                                           ; ^    EF
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H                                                           ; ^,
    DB    0F0H
        ;S7   38 - 3F
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H
    DB    0F0H                                                           ; ^/ EE
        ;
        ;
        ;   KANA
        ;
KTBLG:
        ;S0   00 - 07
    DB    0BFH                                                           ; SPARE
    DB    0F0H                                                           ; GRAPH BUT NULL
    DB    0CFH                                                           ; NIKO WH.
    DB    0C9H                                                           ; ALPHA
    DB    0F0H                                                           ; NO
    DB    0B5H                                                           ; MO
    DB    4DH                                                            ; DAKU TEN
    DB    0CDH                                                           ; CR
        ;S1   08 - 0F
    DB    35H                                                            ; HA
    DB    77H                                                            ; TA
    DB    0D7H                                                           ; WA
    DB    0B3H                                                           ; YO
    DB    0B7H                                                           ; HANDAKU
    DB    0F0H
    DB    0F0H
    DB    0F0H
        ;S2   10 - 17
    DB    7CH                                                            ; KA
    DB    70H                                                            ; KE
    DB    41H                                                            ; SHI
    DB    31H                                                            ; KO
    DB    39H                                                            ; HI
    DB    0A6H                                                           ; TE
    DB    78H                                                            ; KI
    DB    0DDH                                                           ; CHI
        ;S3   18 - 1F
    DB    3DH                                                            ; FU
    DB    5DH                                                            ; MI
    DB    6CH                                                            ; MU
    DB    56H                                                            ; ME
    DB    1DH                                                            ; RHI
    DB    33H                                                            ; RA
    DB    0D5H                                                           ; HE
    DB    0B1H                                                           ; HO
        ;S4   20 - 27
    DB    46H                                                            ; SA
    DB    6EH                                                            ; TO
    DB    0D9H                                                           ; THU
    DB    48H                                                            ; SU
    DB    74H                                                            ; KU
    DB    43H                                                            ; SE
    DB    4CH                                                            ; SO
    DB    73H                                                            ; MA
        ;S5   28 - 2F
    DB    3FH                                                            ; A
    DB    36H                                                            ; I
    DB    7EH                                                            ; U
    DB    3BH                                                            ; E
    DB    7AH                                                            ; O
    DB    1EH                                                            ; NA
    DB    5FH                                                            ; NI
    DB    0A2H                                                           ; NU
        ;S6   30 - 37
    DB    0D3H                                                           ; YO
    DB    9FH                                                            ; YU
    DB    0D1H                                                           ; YA
    DB    00H                                                            ; SPACE
    DB    9DH                                                            ; NO
    DB    0A3H                                                           ; NE
    DB    0D0H                                                           ; RU
    DB    0B9H                                                           ; RE
        ;S7   38 - 3F
    DB    0C6H                                                           ; ?CLR
    DB    0C5H                                                           ; ?HOME
    DB    0C2H                                                           ; ?CURSOR UP
    DB    0C1H                                                           ; ?CURSOR DOWN
    DB    0C3H                                                           ; ?CURSOR RIGHT
    DB    0C4H                                                           ; ?CURSOR LEFT 
    DB    0BBH                                                           ; DASH
    DB    0BEH                                                           ; RO

        ;    MEMORY DUMP COMMAND "D"

DUMP:   CALL    HEXIY                                                    ; START ADDRESS
        CALL    P4DE
        PUSH    HL
        CALL    HLHEX                                                    ; END ADDRESS
        POP     DE
        JR      C,DUM1                                                   ; DATA ERROR THEN
L0D36:  EX      DE,HL
DUM3:   LD      B,08H                                                    ; DISPLAY 8 BYTES
        LD      C,23                                                     ; CHANGE PRINT BIAS
        CALL    NLPHL                                                    ; NEWLINE PRINT
DUM2:   CALL    SPHEX                                                    ; SPACE PRINT + ACC PRINT
        INC     HL
        PUSH    AF
        LD      A,(DSPXY)                                                ; DISPLAY POINT
        ADD     A,C
        LD      (DSPXY),A                                                ; X AXIS=X+CREG
        POP     AF
        CP      20H
        JR      NC,L0D51
        LD      A,2EH                                                    ; "."
L0D51:  CALL    QADCN                                                    ; ASCII TO DISPLAY CODE
        CALL    PRNT3
        LD      A,(DSPXY)
        INC     C
        SUB     C                                                        ; ASCII DISPLAY POSITION
        LD      (DSPXY),A
        DEC     C
        DEC     C
        DEC     C
        PUSH    HL
        SBC     HL,DE
        POP     HL
        JR      Z,L0D85
        LD      A,0F8H
        LD      (KEYPA),A
        NOP     
        LD      A,(KEYPB)
        CP      0FEH                                                     ; SHIFT KEY ?
        JR      NZ,L0D78
        CALL    QBLNK                                                    ; 64MSEC DELAY
L0D78:  DJNZ    DUM2
L0D7A:  CALL    QKEY                                                     ; STOP DISPLAY
        OR      A
        JR      Z,L0D7A                                                  ; SPACE KEY THEN STOP
        CALL    QBRK                                                     ; BREAK IN ?
        JR      NZ,DUM3
L0D85:  JP      ST1                                                      ; COMMAND IN !

DUM1:   LD      HL,160                                                   ; 20*8 BYTES
        ADD     HL,DE
        JR      L0D36

        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     

        ;    V-BLANK CHECK

QBLNK:  PUSH    AF
L0DA7:  LD      A,(KEYPC)                                                ; V-BLANK
        RLCA    
        JR      NC,L0DA7
L0DAD:  LD      A,(KEYPC)                                                ; 64
        RLCA                                                             ;
        JR      C,L0DAD                                                  ; MSEC
        POP     AF
        RET     
        ;    DISPLAY ON POINTER
        ;    ACC=DISPLAY CODE
        ;    EXCEPT F0H

QDSP:   PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
DSP01:  CALL    QPONT                                                    ; DISPLAY POSITION
        LD      (HL),A
        LD      HL,(DSPXY)
        LD      A,L
        CP      COLW-1
        JR      NZ,DSP04
        CALL    PMANG
        JR      C,DSP04
        EX      DE,HL
        LD      (HL),1                                                   ; LOGICAL 1ST COLUMN
        INC     HL
        LD      (HL),0                                                   ; LOGICAL 2ND COLUMN
DSP04:  LD      A,0C3H                                                   ; CURSL
        JR      L0DE0

        ;    GRAPHIC STATUS CHECK

GRSTAS: LD      A,(KANAF)
        CP      01H
        LD      A,0CAH
        RET     

        ;    DISPLAY CONTROL
        ;    ACC=CONTROL CODE

QDPCT:  PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
L0DE0:  LD      B,A
        AND     0F0H
        CP      0C0H
        JR      NZ,CURS5
        XOR     B
        RLCA    
        LD      C,A
        LD      B,0
        LD      HL,CTBL                                                  ; PAGE MODE1
        ADD     HL,BC
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      HL,(DSPXY)
        EX      DE,HL
        JP      (HL)

CURSD:  EX      DE,HL                                                    ; LD HL,(DSPXY)
        LD      A,H
        CP      24
        JR      Z,CURS4
        INC     H
CURS1:  
CURS3:    LD      (DSPXY),HL
CURS5:  JP      QRSTR

CURSU:  EX      DE,HL                                                    ; LD HL,(DSPXY)
        LD      A,H
        OR      A
        JR      Z,CURS5
        DEC     H
CURSU1: JR      CURS3

CURSR:  EX      DE,HL                                                    ; LD HL,(DSPXY)
        LD      A,L
        CP      COLW-1
        JR      NC,CURS2
        INC     L
        JR      CURS3

CURS2:  LD      L,0
        INC     H
        LD      A,H
        CP      25
        JR      C,CURS1
        LD      H,24
        LD      (DSPXY),HL
CURS4:  JR      SCROL

CURSL:  EX      DE,HL                                                    ; LD HL,(DSPXY)
        LD      A,L
        OR      A
        JR      Z,L0E2D
        DEC     L
        JR      CURS3

L0E2D:  LD      L,COLW-1
        DEC     H
        JP      P,CURSU1
        LD      H,0
        LD      (DSPXY),HL
        JR      CURS5

CLRS:   LD      HL,MANG
        LD      B,27
        CALL    QCLER
        LD      HL,0D000H                                                ; SCRN TOP
        CALL    NCLR08
        LD      A,71H                                                    ; COLOR DATA
        CALL    NCLR8                                                    ; D800H-DFFFH CLEAR
HOME:   LD      HL,0                                                     ; DSPXY:0 X=0,Y=0
        JR      CURS3

        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     
        NOP     

        ;    CR

CR:     CALL    PMANG
        RRCA    
        JR      NC,CURS2
        LD      L,0
        INC     H
        CP      24
        JR      Z,CR1
        INC     H
        JR      CURS1

CR1:    LD      (DSPXY),HL

        ;    SCROLL

SCROL:  LD      BC,SCRNSZ - COLW
        LD      DE,SCRN                                                  ; TOP OF $CRT ADDRESS
        LD      HL,SCRN+COLW                                               ; COLUMN
        PUSH    BC                                                       ; 1000 STORE
        LDIR    
        POP     BC
        PUSH    DE
        LD      DE,SCRN + 800H                                           ; COLOR RAM SCROLL
        LD      HL,SCRN + 800H + COLW                                    ; SCROLL TOP + 1 LINE
        LDIR    
        LD      B,COLW                                                   ; ONE LINE
        EX      DE,HL
        LD      A,71H                                                    ; COLOR RAM INITIAL DATA
        CALL    QDINT
        POP     HL
        LD      B,COLW
        CALL    QCLER                                                    ; LAST LINE CLEAR
        LD      BC,ROW + 1                                               ; ROW NUMBER+1
        LD      DE,MANG                                                  ; LOGICAL MANAGEMENT
        LD      HL,MANG+1
        LDIR    
        LD      (HL),0
        LD      A,(MANG)
        OR      A
        JR      Z,QRSTR
        LD      HL,DSPXY+1
        DEC     (HL)
        JR      SCROL

        ;    CONTROL CODE TABLE

CTBL:   DW    SCROL                                                     ; SCROLLING 10H
        DW    CURSD                                                     ; CURSOR DOWN 11H
        DW    CURSU                                                     ; CURSOR UP 12H
        DW    CURSR                                                     ; CURSOR RIGHT 13H
        DW    CURSL                                                     ; CURSOR LEFT 14H
        DW    HOME                                                      ; 15H
        DW    CLRS                                                      ; 16H
        DW    DEL                                                       ; 17H
        DW    INST                                                      ; 18H
        DW    ALPHA                                                     ; 19H
        DW    KANA                                                      ; GRAPHIC 1AH
        DW    QRSTR                                                     ; 1BH
        DW    QRSTR                                                     ; 1CH
        DW    CR                                                        ; 1DH
        DW    QRSTR                                                     ; 1EH
        DW    QRSTR                                                     ; 1FH

        ;    INST BYPASS

INST2:    SET    3,H                                                     ; COLOR RAM
    LD    A,(HL)                                                         ; FROM
    INC    HL
    LD      (HL),A                                                       ; TO
        DEC     HL                                                       ; ADDRESS ADJUST
        RES     3,H
        LDD                                                              ; CHANGE TRNS.
        LD      A,C
        OR      B                                                        ; BC=0 ?
        JR      NZ,INST2
        EX      DE,HL
        LD      (HL),0
        SET     3,H                                                      ; COLOR RAM
        LD      (HL),71H
        JR      QRSTR

ALPHA:  XOR     A
ALPH1:  LD      (KANAF),A

        ;    RESTORE

QRSTR:  POP     HL
QRSTR1: POP     DE
        POP     BC
        POP     AF
        RET     

        NOP     
        NOP     
        NOP     
        NOP     

KANA:   CALL    GRSTAS
        JP      Z,DSP01                                                  ; NOT GRAPH KEY THEN JUMP
        LD      A,01H
        JR      ALPH1

DEL:    EX      DE,HL                                                    ; LD HL,(DSPXY)
        LD      A,H                                                      ; HOME ?
        OR      L
        JR      Z,QRSTR
        LD      A,L
        OR      A
        JR      NZ,DEL1                                                  ; LEFT SIDE ?
        CALL    PMANG
        JR      C,DEL1
        CALL    QPONT
        DEC     HL
        LD      (HL),0
        JR      L0F33                                                    ; JUMP CURSL

DEL1:   CALL    PMANG
        RRCA    
        LD      A,COLW
        JR      NC,L0F17
        RLCA                                                             ; ACC=80
L0F17:  SUB     L
        LD      B,A                                                      ; TRNS. BYTE
        CALL    QPONT
DEL2:   LD      A,(HL)                                                   ; CHANGE FROM ADDRESS
        DEC     HL
        LD      (HL),A                                                   ; TO
        INC     HL
        SET     3,H                                                      ; COLOR RAM
        LD      A,(HL)
        DEC     HL
        LD      (HL),A
        RES     3,H                                                      ; CHANGE
        INC     HL
        INC     HL                                                       ; NEXT
        DJNZ    DEL2
        DEC     HL                                                       ; ADDRESS ADJUST
        LD      (HL),0
        SET     3,H
        LD      HL,71H                                                   ; BLUE + WHITE
L0F33:  LD      A,0C4H                                                   ; JP CURSL
        JP      L0DE0

INST:   CALL    PMANG
        RRCA    
        LD      L,COLW - 1
        LD      A,L
        JR      NC,L0F42
        INC     H
L0F42:  CALL    QPNT1
        PUSH    HL
        LD      HL,(DSPXY)
        JR      NC,L0F4D
        LD      A,(COLW*2) - 1
L0F4D:  SUB     L
        LD      B,0
        LD      C,A
        POP     DE
        JR      Z,QRSTR
        LD      A,(DE)
        OR      A
        JR      NZ,QRSTR
        LD      H,D                                                      ; HL<-DE
        LD      L,E
        DEC     HL
        JP      INST2                                                    ; JUMP NEXT (BYPASS)

        ;    PROGRAM SAVE
        ;    COMMAND "S"

SAVE:   CALL    HEXIY                                                    ; START ADDRESS
        LD      (DTADR),HL                                               ; DATA ADDRESS BUFFER
        LD      B,H
        LD      C,L
        CALL    P4DE
        CALL    HEXIY                                                    ; END ADDRESS
        SBC     HL,BC                                                    ; BYTE SIZE
        INC     HL
        LD      (SIZE),HL                                                ; BYTE SIZE BUFFER
        CALL    P4DE
        CALL    HEXIY                                                    ; EXECUTE ADDRESS
        LD      (EXADR),HL                                               ; BUFFER
        CALL    NL
        LD      DE,MSGSV                                                 ; SAVED FILENAME
        RST     18H                                                      ; CALL MSGX
        CALL    BGETL                                                    ; FILENAME INPUT
        CALL    P4DE
        CALL    P4DE
        LD      HL,NAME                                                  ; NAME BUFFER
SAV1:   INC     DE
        LD      A,(DE)
        LD      (HL),A                                                   ; FILENAME TRANS.
        INC     HL
        CP      0DH                                                      ; END CODE
        JR      NZ,SAV1
        LD      A,01H                                                    ; ATTRIBUTE: OBJECT CODE
        LD      (ATRB),A
        CALL    QWRI
        JP      C,QER                                                    ; WRITE ERROR
        CALL    QWRD                                                     ; DATA
        JP      C,QER
        CALL    NL
        LD      DE,MSGOK                                                 ; OK MESSAGE
        RST     18H                                                      ; CALL MSGX
        JP      ST1

        ;    COMPUTE POINT ADDRESS
        ;    HL=SCREEN COORDINATE
        ;    EXIT HL=POINT ADDRESS ON SCREEN

QPONT:  LD      HL,(DSPXY)
QPNT1:  PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        POP     BC
        LD      DE,COLW                                                ; 40
        LD      HL,SCRN-COLW
QPNT2:  ADD     HL,DE
        DEC     B
        JP      P,QPNT2
        LD      B,0
        ADD     HL,BC
        POP     DE
        POP     BC
        POP     AF
        RET     

        ;    VERIFYING COMMAND "V"

VRFY:   CALL    QVRFY
        JP      C,QER
        LD      DE,MSGOK
        RST     18H
        JP      ST1

        ;    CLER
        ;    B=SIZE
        ;    HL=LOW ADDRESS

QCLER:  XOR     A
        JR      QDINT

QCLRFF: LD      A,0FFH
QDINT:  LD      (HL),A
        INC     HL
        DJNZ    QDINT
        RET     

        ;    GAP CHECK

GAPCK:  PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      BC,KEYPB
        LD      DE,CSTR
GAPCK1: LD      H,100
GAPCK2: CALL    EDGE
        JR      C,GAPCK3
        CALL    DLY3                                                     ; CALL DLY2*3
        LD      A,(DE)
        AND     20H
        JR      NZ,GAPCK1
        DEC     H
        JR      NZ,GAPCK2
GAPCK3: JP      RET3

        ;    MONITOR WORK AREA
        ;    (MZ700)

        ORG     10F0H
SPV:
IBUFE:                                                                   ; TAPE BUFFER (128 BYTES)
ATRB:   DS      virtual 1                                                ; ATTRIBUTE
NAME:   DS      virtual 17                                               ; FILE NAME
SIZE:   DS      virtual 2                                                ; BYTESIZE
DTADR:  DS      virtual 2                                                ; DATA ADDRESS
EXADR:  DS      virtual 2                                                ; EXECUTION ADDRESS
COMNT:  DS      virtual 104                                              ; COMMENT
KANAF:  DS      virtual 1                                                ; KANA FLAG (01=GRAPHIC MODE)
DSPXY:  DS      virtual 2                                                ; DISPLAY COORDINATES
MANG:   DS      virtual 27                                               ; COLUMN MANAGEMENT
FLASH:  DS      virtual 1                                                ; FLASHING DATA
FLPST:  DS      virtual 2                                                ; FLASHING POSITION
FLSST:  DS      virtual 1                                                ; FLASHING STATUS
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
        ;    MONITOR WORK AREA

SCRN:   EQU    0D000H
KANST:  EQU    0E003H                                                  ; KANA STATUS REPORT


