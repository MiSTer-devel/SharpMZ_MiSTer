; V1.00
;
; To compile use:
;
; GLASS Z80 Assembler
;
; java -jar ../tools/glass.jar mz-1r12.asm mz-1r12.obj mz-1r12.sym



LETNL   EQU     00006h
PRNT    EQU     00012h
MSG     EQU     00015h
GETKY   EQU     0001Bh
RDINF   EQU     00027h
RDDAT   EQU     0002Ah
ST1     EQU     000ADh
QNL     EQU     00918h

NAME    EQU     010F1h
SIZE    EQU     01102h
DTADR   EQU     01104h
COMNT   EQU     01108h

; Macro to align boundaries.
ALIGN:  MACRO ?boundary, ?fill
        DS    ?boundary - 1 - ($ + ?boundary - 1) % ?boundary, ?fill
        ENDM

        ORG 0E800h

MZ1R12:
        NOP
        LD      A,016h
        CALL    PRNT
        CALL    LETNL
        CALL    LETNL
ST1X:
        CALL    LETNL
        CALL    LETNL
        LD      DE,LE83B                                                 ; 'PRESS R, W OR M'
        CALL    MSG
        CALL    LETNL
        CALL    LETNL
        LD      DE,LE85B                                                 ; 'R: READ   S-RAM'
        CALL    MSG
        CALL    LETNL
        LD      DE,LE877                                                 ; 'W: WRITE  S-RAM'
        CALL    MSG
        CALL    LETNL
        LD      DE,LE893                                                 ; 'M: MONITOR'
        CALL    MSG
        CALL    LETNL
        JR      LE8AB


LE83B:  DB      "           P",005h,"RESS",005h," R , W ",005h,"OR",005h," M",00Dh
LE85B:  DB      "            R:",005h,"READ",005h,"  S-RAM",00Dh
LE877:  DB      "            W:",005h,"WRITE",005h," S-RAM",00Dh
LE893:  DB      "            M:",005h,"MONITOR",005h,00Dh


LE8AB:
        NOP
        CALL    GETKY
        CP      'M'
        JP      Z,MON
        CP      'W'
        JP      Z,LE96A
        CP      'R'
        JP      Z,LE8C1
        JP      NZ,LE8AB

LE8C1:
        NOP
        LD      A,016h
        CALL    PRNT
        CALL    LETNL
        CALL    LETNL
        CALL    LETNL
        LD      DE,LEB1B                                                 ; 'LOADING PROGRAM FROM S-RAM'
        CALL    MSG
        CALL    LETNL
        CALL    LETNL
        CALL    CHECK
        IN      A,(0F8h)                                                 ; Counter reset
        IN      A,(0F9h)
        LD      C,A
        IN      A,(0F9h)
        LD      B,A
        IN      A,(0F9h)
        LD      L,A
        IN      A,(0F9h)
        LD      H,A
        IN      A,(0F9h)
        LD      E,A
        IN      A,(0F9h)
        LD      D,A
        PUSH    DE
        LD      D,B
        LD      E,C
        IN      A,(0F9h)
        LD      C,A
        IN      A,(0F9h)
        LD      B,A
        IN      A,(0F9h)
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      C,0F9h
        LD      A,E
        OR      A
        JR      Z,LE90A
        LD      B,A
LE908:
        INIR
LE90A:
        LD      B,000h
        DEC     D
        JP      P,LE908
        POP     DE                                                       ; Data adr
        POP     BC                                                       ; Size
        CALL    SUM
        POP     DE
        OR      A
        SBC     HL,DE
        JR      NZ,LE956
        POP     HL
        JP      (HL)


;
;       sum check
;
; IN BC=Size
;    DE=Data adr
; EXIT HL=Check sum
;
SUM:
        PUSH    BC
        PUSH    DE
        EXX
        LD      HL,00000h                                                ; HL'= Check sum clr
        LD      C,008h                                                   ; C' = Loop count
        EXX
SUMCK1:
        LD      A,B                                                      ; BC = Size
        OR      C
        JR      Z,SUMCK2
        LD      A,(DE)                                                   ; DE = Data adrs
        EXX
        LD      B,C                                                      ; BC'
SUMCK3:
        RLCA
        JR      NC,LE931
        INC     HL                                                       ; HL' = Check sum data
LE931:
        DJNZ    SUMCK3
        EXX
        INC     DE                                                       ; DE
        DEC     BC                                                       ; BC
        JP      SUMCK1
SUMCK2:
        EXX
        POP     DE
        POP     BC
        RET



;
;       Information's sum check
;
CHECK:
        IN      A,(0F8h)                                                 ; Counter reset
        LD      BC,00800h                                                ; B=Byte Counter C=Sum Counter
CK1:
        IN      A,(0F9h)                                                 ; Counter=Counter+1
        PUSH    BC
        LD      B,008h                                                   ; Bit Counter
CK2:
        RLCA
        JR      NC,LE94B
        INC     C
LE94B:
        DJNZ    CK2
        LD      A,C
        POP     BC
        LD      C,A
        DJNZ    CK1
        IN      A,(0F9h)
        CP      C
        RET


LE956:
        LD      A,016h
        CALL    PRNT
        CALL    LETNL
        CALL    LETNL
        LD      DE,LEA8F                                                 ; 'CHECK SUM ERROR'
        CALL    LEA3D
        JP      ST1X

LE96A:
        LD      A,016h
        CALL    PRNT
        CALL    LETNL
        CALL    LETNL
        CALL    LETNL
        LD      DE,LEAAC                                                 ; 'S-RAM PROGRAMMING'
        CALL    LEA36
        LD      DE,LEACB                                                 ; 'SET MASTER TAPE  PLAY'
        LD      A,011h
        LD      HL,0D8F0h
        CALL    LEA4A
        CALL    LETNL
        CALL    LEA39
        CALL    RDINF
        PUSH    AF
        PUSH    BC
        LD      BC,(SIZE)
        LD      A,07Fh
        CP      B
        JR      C,LE9A8
        JR      NZ,LE9A4
        LD      A,0F6h
        CP      C
        JR      C,LE9A8
LE9A4:
        POP     BC
        POP     AF
        JR      LE9AD
LE9A8:
        POP     BC
        POP     AF
        JP      LEA74

LE9AD:
        LD      A,000h
        LD      HL,0D0F0h
        CALL    LEA4A
        LD      A,071h
        LD      HL,0D8F0h
        CALL    LEA4A
        LD      A,002h
        JP      C,LEA42
        CALL    LETNL
        LD      DE,LEAF1                                                 ; 'FOUND : '
        CALL    LEA3D
        LD      DE,NAME
        PUSH    DE
        RST     018h
        CALL    LETNL
        LD      DE,LEB06                                                 ; 'LOADING : '
        CALL    LEA3D
        POP     DE
        RST     018h
;
;       Read data block
;
        CALL    RDDAT
        JR      C,LEA42
;
;       Counter reset
;
        IN      A,(0F8h)
;
;       Sum check for data
;
        LD      DE,(DTADR)
        LD      BC,(SIZE)
        PUSH    DE
        PUSH    BC
        CALL    SUM
        LD      (COMNT),HL
;
;       Write information (8Byte)
;
        LD      HL,SIZE
        LD      BC,008FAh                                                ; B=Byte Counter
        PUSH    HL
        PUSH    BC
        OTIR
        POP     BC
        POP     HL
;
;       Sum check for information block
;           AccCheck sum data
;
        PUSH    DE                                                       ; DE Size
        LD      D,000h                                                   ; Sum Counter
WCK1:
        PUSH    BC
        LD      B,008h
        LD      A,(HL)
WCK2:
        RLCA
        JR      NC,WCK3
        INC     D
WCK3:
        DJNZ    WCK2
        INC     HL
        POP     BC
        DJNZ    WCK1
        LD      A,D
        POP     DE
        OUT     (0FAh),A
;
;       Write data block
;
        POP     DE                                                       ; DE Size
        POP     HL                                                       ; HL Data adrs
        LD      A,E
        OR      A
        JR      Z,LEA1C
        LD      B,E
LEA1A:
        OTIR
LEA1C:
        LD      B,000h
        DEC     D
        JP      P,LEA1A
        LD      A,016h
        CALL    PRNT
        CALL    LETNL
        CALL    LETNL
        LD      DE,LEB8C                                                 ; 'WRITING S-RAM O.K.!'
        CALL    MSG
        JP      ST1X


LEA36:
        CALL    QNL
LEA39:
        RST     018h
        JP      QNL

LEA3D:
        CALL    QNL
        RST     018h
        RET

LEA42:
        CP      002h
        JP      Z,LEA60
        JP      LE956

LEA4A:
        LD      B,006h
LEA4C:
        LD      (HL),A
        INC     HL
        DEC     B
        JR      NZ,LEA4C
        RET

MON:
        LD      A,016h
        CALL    PRNT
        LD      DE,LEB3E                                                 ; '** MONITOR 1Z-009A **'
        CALL    MSG
        JP      ST1

LEA60:
        LD      A,016h
        CALL    PRNT
        CALL    LETNL
        CALL    LETNL
        LD      DE,LEB77                                                 ; 'BREAK !'
        CALL    MSG
        JP      ST1X

LEA74:
        LD      DE,00000h
        LD      (SIZE),DE
        LD      A,016h
        CALL    PRNT
        CALL    LETNL
        CALL    LETNL
        LD      DE,LEBAD                                                 ; 'FILE IS TOO LONG'
        CALL    MSG
        JP      ST1X


LEA8F:  DB      "           C",005h,"HECK SUM ERROR",005h,00Dh
LEAAC:  DB      "           S-RAM ",005h,"PROGRAMMING",005h,00Dh
LEACB:  DB      "        S",005h,"ET MASTER TAPE",005h,"   ",07Fh,"P",005h,"LAY",005h,"  ",00Dh
LEAF1:  DB      "         F",005h,"OUND",005h,"  : ",00Dh
LEB06:  DB      "         L",005h,"OADING",005h,": ",00Dh
LEB1B:  DB      "      L",005h,"OADING PROGRAM FROM ",005h,"S-RAM",00Dh
LEB3E:  DB      "**  MONITOR 1Z-009A  **",00Dh
LEB56:  DB      "           R",005h,"EADING",005h," S-RAM O.K.!",00Dh
LEB77:  DB      "           B",005h,"REAK",005h," !",00Dh
LEB8C:  DB      "           W",005h,"RITING",005h," S-RAM O.K.!",00Dh
LEBAD:  DB      "           F",005h,"ILE IS TOO LONG",005h,00Dh

; the following is only to get the original length of 4096 bytes

        ALIGN   0F7FFh, 0FFh
        DB      0FFh
