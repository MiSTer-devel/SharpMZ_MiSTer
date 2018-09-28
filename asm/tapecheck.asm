
KEYPA:     EQU     0E000h
KEYPB:     EQU     0E001h
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
TPSTART:   EQU     10F0h
MSTART:    EQU     0C000h


           ORG     TPSTART

SPV:
IBUFE:                                                                   ; TAPE BUFFER (128 BYTES)
;ATRB:      DS       virtual 1                                           ; ATTRIBUTE
ATRB:      DB       01h                                                  ; Code Type, 01 = Machine Code.
;NAME:      DS       virtual 17                                          ; FILE NAME
NAME:      DB       "TAPE CHECK V1.0", 0Dh, 00h                          ; Title/Name (17 bytes).
;SIZE:      DS       virtual 2                                           ; BYTESIZE
SIZE:      DW       MEND - MSTART                                        ; Size of program.
;DTADR:     DS       virtual 2                                           ; DATA ADDRESS
DTADR:     DW       MSTART                                               ; Load address of program.
;EXADR:     DS       virtual 2                                           ; EXECUTION ADDRESS
EXADR:     DW       MSTART                                               ; Exec address of program.
COMNT:     DS       104                                                  ; COMMENT
KANAF:     DS       virtual 1                                            ; KANA FLAG (01=GRAPHIC MODE)
DSPXY:     DS       virtual 2                                            ; DISPLAY COORDINATES
MANG:      DS       virtual 27                                           ; COLUMN MANAGEMENT
FLASH:     DS       virtual 1                                            ; FLASHING DATA
FLPST:     DS       virtual 2                                            ; FLASHING POSITION
FLSST:     DS       virtual 1                                            ; FLASHING STATUS
FLSDT:     DS       virtual 1                                            ; CURSOR DATA
STRGF:     DS       virtual 1                                            ; STRING FLAG
DPRNT:     DS       virtual 1                                            ; TAB COUNTER
TMCNT:     DS       virtual 2                                            ; TAPE MARK COUNTER
SUMDT:     DS       virtual 2                                            ; CHECK SUM DATA
CSMDT:     DS       virtual 2                                            ; FOR COMPARE SUM DATA
AMPM:      DS       virtual 1                                            ; AMPM DATA
TIMFG:     DS       virtual 1                                            ; TIME FLAG
SWRK:      DS       virtual 1                                            ; KEY SOUND FLAG
TEMPW:     DS       virtual 1                                            ; TEMPO WORK
ONTYO:     DS       virtual 1                                            ; ONTYO WORK
OCTV:      DS       virtual 1                                            ; OCTAVE WORK
RATIO:     DS       virtual 2                                            ; ONPU RATIO
BUFER:     DS       virtual 81                                           ; GET LINE BUFFER



           ORG     MSTART

ENTRYLOAD: JP       START
ENTRYSAVE: JP       SAVE

START:     LD       DE,TITLE
           CALL     MSG
           CALL     LETNL
           CALL     NL
           CALL     NL
           LD       HL,1200h
           LD       BC,0A000h
CLEAR1:    LD       A,00h
           LD       (HL),A
           INC      HL
           DEC      BC
           LD       A,B
           OR       C
           JP       NZ,CLEAR1
           CALL     LOAD
           JP       ST1

           ;
           ; LOAD COMMAND
           ;
LOAD:      CALL     ?RDI
           JP       C,?ER
LOA0:      CALL     NL
           LD       DE,MSG_LOADFROM
           CALL     MSG
           LD       HL,(DTADR)
           CALL     PRTHL
           CALL     NL
           LD       DE,MSG_LOADEXEC
           CALL     MSG
           LD       HL,(EXADR)
           CALL     PRTHL
           CALL     NL
           LD       DE,MSG_LOADSIZE
           CALL     MSG
           LD       HL,(SIZE)
           CALL     PRTHL
           CALL     NL
           LD       DE,MSG_LOADFILE
           CALL     MSGX
           LD       DE,NAME
           CALL     MSGX
           CALL     NL
           CALL     ?RDD
           JP       C,?ER
           LD       HL,(EXADR)
           LD       A,H
           CP       12h
           JP       C,ST1
           JP       (HL)


           ; SAVE COMMAND

SAVE:      CALL     NL
           LD       DE,MSG_SAVEFROM
           CALL     MSG
           LD       HL,(DTADR)
           CALL     PRTHL
           CALL     NL
           LD       DE,MSG_SAVEEXEC
           CALL     MSG
           LD       HL,(EXADR)
           CALL     PRTHL
           CALL     NL
           LD       DE,MSG_SAVESIZE
           CALL     MSG
           LD       HL,(SIZE)
           CALL     PRTHL
           CALL     NL
           LD       DE,MSG_SAVEFILE
           CALL     MSGX
           LD       DE,NAME
           CALL     MSGX
           CALL     NL
           LD       A,01H                                                    ; ATTRIBUTE: OBJECT CODE
           LD       (ATRB),A
           CALL     QWRI
           JP       C,QER                                                    ; WRITE ERROR
           CALL     QWRD                                                     ; DATA
           JP       C,QER
           CALL     NL
           LD       DE,MSGOK                                                 ; OK MESSAGE
           CALL     MSGX                                                     ; CALL MSGX
           JP       ST1           

           ;
           ; ERROR (LOADING)
           ;
QER:       CP       02h
           JP       Z,ST1
           LD       DE,MSG_ERRWRITE
           CALL     MSG
           JP       ST1
           ;
           ; ERROR (LOADING)
           ;
?ER:       CP       02h
           JP       Z,ST1
           LD       DE,MSG_ERRCHKSUM
           CALL     MSG
           JP       ST1
           ;
           ; READ INFORMATION
           ;
           ; EXIT ACC = 0 : OK CF=0
           ;          = 1 : ER CF=1
           ;          = 2 : BREAK CF=1
           ;
?RDI:      DI
           PUSH     DE
           PUSH     BC
           PUSH     HL
           LD       D,0D2h
           LD       E,0CCh
           LD       BC,80h
           LD       HL,IBUFE
RD1:       CALL     MOTOR
           JP       C,RTP6
           CALL     TMARK
           JP       C,RTP6
;   CALL     PRTHL
           CALL     RTAPE
           POP      HL
           POP      BC
           POP      DE
           ;CALL     MSTOP
           PUSH     AF
           LD       A,(TIMFG)
           CP       0F0h
           JR       NZ,RD2
           EI
RD2:       POP      AF
           RET

           ;
           ; READ DATA
           ;
?RDD:      DI
           PUSH     DE
           PUSH     BC
           PUSH     HL
           LD       D,0D2h
           LD       E,53h
           LD       BC,(SIZE)
           LD       HL,(DTADR)
           LD       A,B
           OR       C
           JP       Z,RDD1
           JR       RD1
RDD1:      POP      HL
           POP      BC
           POP      DE
           ;CALL     MSTOP
           PUSH     AF
           LD       A,(TIMFG)
           CP       0F0h
           JR       NZ,RDD2
           EI
RDD2:      POP      AF
           RET

           ;
           ; READ TAPE
           ;
RTAPE:     ;PUSH     BC
           ;PUSH     DE
           ;LD       DE,MSG_READTAPE
           ;CALL     MSG
           ;CALL     NL
           ;POP      DE
           ;POP      BC
           PUSH     DE
           PUSH     BC
           PUSH     HL
           LD       H,2
RTP1:      LD       BC,KEYPB
           LD       DE,CSTR
RTP2:      CALL     EDGE
           JP       C,RTP6
           CALL     DLY3
           LD       A,(DE)
           AND      20h
           JP       Z,RTP2
           LD       D,H
           LD       HL,0
           LD       (SUMDT),HL
           POP      HL
           POP      BC
           PUSH     BC
           PUSH     HL
RTP3:      CALL     RBYTE
           JP       C,RTP6
           LD       (HL),A
           INC      HL
           DEC      BC
           LD       A,B
           OR       C
           JP       NZ,RTP3
           LD       HL,(SUMDT)
           CALL     RBYTE                 ; Checksum MSB
           JP       C,RTP6
           LD       D,A
           CALL     RBYTE                 ; Checksum LSB
           JP       C,RTP6
           LD       E,A
           CP       L
           JP       NZ,RTP5
           LD       A,D
           CP       H
           JP       NZ,RTP5
RTP0:      XOR      A
           ;
           PUSH     HL
           PUSH     DE
           PUSH     DE
           LD       DE,MSG_CHKSUM_MZ1
           CALL     MSGX
           CALL     PRTHL
           CALL     NL
           LD       DE,MSG_CHKSUM_TP1
           CALL     MSGX
           POP      DE
           EX       DE,HL
           CALL     PRTHL
           CALL     NL
           POP      DE
           POP      HL
           ;
RTP4:      
RET2:      POP      HL
           POP      BC
           POP      DE
           CALL     MSTOP
           PUSH     AF
           LD       A,(TIMFG)
           CP       0F0h
           JR       NZ,RTP8
           EI
RTP8:      POP      AF
           RET

RTP5:      PUSH     HL
           PUSH     DE
           PUSH     DE
           LD       DE,MSG_CHKSUM_MZ2
           CALL     MSGX
           CALL     PRTHL
           CALL     NL
           LD       DE,MSG_CHKSUM_TP2
           CALL     MSGX
           POP      DE
           EX       DE,HL
           CALL     PRTHL
           CALL     NL
           POP      DE
           POP      HL
           ;
           LD       D,1
           DEC      D
           JR       Z,RTP7
           LD       H,D
           CALL     GAPCK
           JP       RTP1
RTP7:      LD       A,1
           JR       RTP9
RTP6:      LD       A,2
RTP9:      SCF
           JR       RTP4


           ;
           ; EDGE
           ;  BC = KEYPB
           ;  DE = CSTR
           ; EXIT CF = 0 : EDGE
           ;         = 1 : BREAK
           ;
EDGE:      LD       A,0F0h
           LD       (KEYPA),A
           NOP
EDG1:      LD       A,(BC)
           AND      81h             ; SHIFT & BREAK
           JP       NZ,EDG0
           SCF
           RET
EDG0:      LD       A,(DE)
           AND      20h
           JP       NZ,EDG1
EDG2:      LD       A,(BC)
           AND      81h
           JP       NZ,EDG3
           SCF
           RET
EDG3:      LD       A,(DE)
           AND      20h
           JP       Z,EDG2
           RET


           ;
           ; 1 BYTE READ
           ;
           ; EXIT  SUMDT=STORE
           ; CF = 1 : BREAK
           ;    = 0 : DATA=ACC
           ;
RBYTE:     PUSH     BC
           PUSH     DE
           PUSH     HL
           LD       HL,0800h
           LD       BC,KEYPB
           LD       DE,CSTR
RBY1:      CALL     EDGE
           JP       C,RBY3
           CALL     DLY3
           LD       A,(DE)
           AND      20h
           JP       Z,RBY2
           PUSH     HL
           LD       HL,(SUMDT)
           INC      HL
           LD       (SUMDT),HL
           POP      HL
           SCF
RBY2:      LD       A,L
           RLA
           LD       L,A
           DEC      H
           JP       NZ,RBY1
           CALL     EDGE
           LD       A,L
RBY3:      POP      HL
           POP      DE
           POP      BC
           RET

           ;
           ; TAPE MARK DETECT
           ;
           ;    E=@L@     : INFORMATION
           ;     =@S@     : DATA
           ; EXIT CF = 0  : OK
           ;         = 1  : BREAK
           ;
TMARK:     CALL     GAPCK
           PUSH     BC
           PUSH     DE
           PUSH     HL
           PUSH     BC
           PUSH     DE
           LD       DE,MSG_TAPEMARK
           CALL     MSG
           CALL     NL
           POP      DE
           POP      BC
           LD       HL,2828h
           LD       A,E
           CP       0CCh
           JP       Z,TM0
           LD       HL,1414h
TM0:       LD       (TMCNT),HL
           LD       BC,KEYPB
           LD       DE,CSTR
TM1:       LD       HL,(TMCNT)
TM2:       CALL     EDGE
           JP       C,TM4
           CALL     DLY3
           LD       A,(DE)
           AND      20h
           JP       Z,TM1
           DEC      H
           JP       NZ,TM2
;  CALL     PRTHL
TM3:       CALL     EDGE
           JP       C,TM4
           CALL     DLY3
           LD       A,(DE)
           AND      20h
           JP       NZ,TM1
           DEC      L
           JP       NZ,TM3
           CALL     EDGE
RET3:
TM4:       POP      HL
           POP      DE
           POP      BC
           RET

TM4A:      CALL     NL
           CALL     PRTHL       ; Print HL as 4digit hex.
           LD       A,0C4h      ; Move cursor left.
TM4B:      CALL     DPCT
           CALL     DPCT
           CALL     DPCT
           CALL     DPCT
           CALL     NL
           JP       ST1

           ;
           ; MOTOR ON
           ;
           ;    D=@W@   : WRITE
           ;     =@R@   : READ
           ; EXIT CF=0  : OK
           ;        =1  : BREAK
MOTOR:     PUSH     BC
           PUSH     DE
           PUSH     HL
           PUSH     BC
           PUSH     DE
           LD       DE,MSG_MOTORTG
           CALL     MSG
           CALL     NL
           POP      DE
           POP      BC
           LD       B,10
MOT1:      LD       A,(CSTR)
           AND      10h
           JR       Z,MOT4
MOT2:      LD       B,0A6h
MOT3:      CALL     DLY12
           DJNZ     MOT3
           XOR      A
MOT7:      JR       RET3
MOT4:      LD       A,06h
           LD       HL,CSTPT
           LD       (HL),A
           INC      A
           LD       (HL),A
           DJNZ     MOT1
           CALL     NL
           LD       A,D
           CP       0D7h
           JR       Z,MOT8
           LD       DE,MSG1
           JR       MOT9
MOT8:      LD       DE,MSG3
           CALL     MSGX
           LD       DE,MSG2
MOT9:      CALL     MSGX
MOT5:      LD       A,(CSTR)
           AND      10h
           JR       NZ,MOT2
           CALL     ?BRK
           JR       NZ,MOT5
           SCF
           JR       MOT7

           ;
           ; MOTOR STOP
           ;
MSTOP:     PUSH     AF
           PUSH     BC
           PUSH     DE
           PUSH     BC
           PUSH     DE
           LD       DE,MSG_MOTORSTP
           CALL     MSG
           CALL     NL
           POP      DE
           POP      BC
           LD       B,10
MST1:      LD       A,(CSTR)
           AND      10H
           JR       Z,MST3
MST2:      LD       A,06h
           LD       (CSTPT),A
           INC      A
           LD       (CSTPT),A
           DJNZ     MST1
MST3:      JP       ?RSTR1

           ;
           ; CHECK SUM
           ;
           ;   BC = SIZE
           ;   HL = DATA ADR
           ; EXIT SUMDT=STORE
           ;      CSMDT=STORE
           ;
CKSUM:     PUSH     BC
           PUSH     DE
           PUSH     HL
           LD       DE,0
CKS1:      LD       A,B
           OR       C
           JR       NZ,CKS2
           EX       DE,HL
           LD       (SUMDT),HL
           LD       (CSMDT),HL
           POP      HL
           POP      DE
           POP      BC
           RET
CKS2:      LD       A,(HL)
           PUSH     BC
           LD       B,+8
CKS3:      RLCA
           JR       NC,CKS4
           INC      DE
CKS4:       DJNZ     CKS3
           POP      BC
           INC      HL
           DEC      BC
           JR       CKS1


           ;
           ; 107 uS DELAY
           ;
DLY1:      LD       A,14
DLY1A:     DEC      A
           JP       NZ,DLY1A
           RET

           ;
           ; 240 uS DELAY
           ;
DLY2:      LD       A,13
DLY2A:     DEC      A
           JP       NZ,DLY2A
           RET

           ;
           ; 240 uS x 3 DELAY
           ;
DLY3:      NEG
           NEG
           LD       A,42
           JP       DLY2A

           ;
           ; 12mS DELAY
DLY12:     PUSH     BC
           LD       B,35
DLY12A:    CALL     DLY3
           DJNZ     DLY12A
           POP      BC
           RET


           ;
           ; GAP * TAPEMARK
           ;
           ;  E = @L@   : LONG GAP
           ;    = @S@   : SHORT GAP
           ;
GAP:       PUSH     BC
           PUSH     DE
           LD       A,E
           LD       BC,55F0h
           LD       DE,2028h
           CP       0CCh
           JP       Z,GAP1
           LD       BC,2AF8h
           LD       DE,1414h
GAP1:      CALL     SHORT
GAP1A:     DEC      BC
           LD       A,B
           OR       C
           JR       NZ,GAP1A
GAP2:      CALL     LONG
           DEC      D
           JR       NZ,GAP2
GAP3:      CALL     SHORT
           DEC      E
           JR       NZ,GAP3
           CALL     LONG
           POP      DE
           POP      BC
           RET

           ;
           ; GAP CHECK
           ;
GAPCK:     PUSH     BC
           PUSH     DE
           PUSH     HL
           LD       DE,MSG_GAPCK
           CALL     MSG
           CALL     NL
           LD       BC,KEYPB
           LD       DE,CSTR
GAPCK1:    LD       H,100
GAPCK2:    CALL     EDGE
           JR       C,GAPCK3
           CALL     DLY3
           LD       A,(DE)
           AND      20h
           JR       NZ,GAPCK1
           DEC      H
           JR       NZ,GAPCK2
GAPCK3:    JP       RET3

           ;
           ; 1 bit write
           ; Short Pulse
           ;
SHORT:     PUSH     AF
           LD       A,03h
           LD       (CSTPT),A
           CALL     DLY1
           CALL     DLY1
           LD       A,02h
           LD       (CSTPT),A
           CALL     DLY1
           CALL     DLY1
           POP      AF
           RET

           ;
           ; 1 bit write
           ; Long Pulse
           ;
LONG:      PUSH     AF
           LD       A,03h
           LD       (CSTPT),A
           CALL     DLY1
           CALL     DLY1
           CALL     DLY1
           CALL     DLY1
           LD       A,02h
           LD       (CSTPT),A
           CALL     DLY1
           CALL     DLY1
           CALL     DLY1
           CALL     DLY1
           POP      AF
           RET


           ;    WRITE INFORMATION

QWRI:      DI      
           PUSH    DE
           PUSH    BC
           PUSH    HL
           LD      D,0D7H                                                   ; "W"
           LD      E,0CCH                                                   ; "L"
           LD      HL,IBUFE                                                 ; 10F0H
           LD      BC,80H                                                   ; WRITE BYTE SIZE
WRI1:      CALL    CKSUM                                                    ; CHECK SUM
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
WRI2:      CALL    GAP
           CALL    WTAPE
WRI3:      JP      RET2


           ;    WRITE DATA
           ;    EXIT CF=0 : OK
           ;           =1 : BREAK

QWRD:      DI      
           PUSH    DE
           PUSH    BC
           PUSH    HL
           LD      D,0D7H                                                   ; "W"
           LD      E,53H                                                    ; "S"
L047D:     LD      BC,(SIZE)                                                ; WRITE DATA BYTE SIZE
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

WTAPE:     PUSH    DE
           PUSH    BC
           PUSH    HL
           LD      D,02H
           LD      A,0F8H                                                   ; 88H WOULD BE BETTER!!
           LD      (KEYPA),A                                                ; E000H
WTAP1:     LD      A,(HL)
           CALL    WBYTE                                                    ; 1 BYTE WRITE
           LD      A,(KEYPB)                                                ; E001H
           AND     81H                                                      ; SHIFT & BREAK
           JP      NZ,WTAP2
           LD      A,02H                                                    ; BREAK IN CODE
           SCF     
           JR      WTAP3

WTAP2:     INC     HL
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

L04C2:     LD      B,0
L04C4:     CALL    SHORT
           DEC     B
           JP      NZ,L04C4
           POP     HL
           POP     BC
           PUSH    BC
           PUSH    HL
           JP      WTAP1

WTAP3:
RET1:      POP     HL
           POP     BC
           POP     DE
           RET     

           DB    2FH
           DB    4EH

           ;    VERIFY (FROM $CMT)
           ;    EXIT ACC=0 : OK CF=0
           ;            =1 : ER CF=1
           ;            =2 : BREAK CF=1

QVRFY:     DI      
           PUSH    DE
           PUSH    BC
           PUSH    HL
           LD      BC,(SIZE)
           LD      HL,(DTADR)
           LD      D,0D2H                                                   ; "R"
           LD      E,53H                                                    ; "S"
           LD      A,B
           OR      C
           JP      Z,RTP4                                                   ; END
           CALL    CKSUM
           CALL    MOTOR
           JP      C,RTP6                                                   ; BRK
           CALL    TMARK                                                    ; TAPE MARK DETECT
           JP      C,RTP6                                                   ; BRK
           CALL    TVRFY
           JP      RTP4

           ;    DATA VERIFY
           ;    BC=SIZE
           ;    HL=DATA LOW ADDRESS
           ;    CSMDT=CHECK SUM
           ;    EXIT ACC=0 : OK  CF=0
           ;            =1 : ER    =1
           ;            =2 : BREAK =1

TVRFY:     PUSH    DE
           PUSH    BC
           PUSH    HL
           LD      H,02H                                                    ; COMPARE TWICE
TVF1:      LD      BC,KEYPB
           LD      DE,CSTR
TVF2:      CALL    EDGE
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
TVF3:      CALL    RBYTE
           JP      C,RTP6                                                   ; BRK
           CP      (HL)
           JP      NZ,RTP7                                                  ; ERROR, NOT EQUAL
           INC     HL                                                       ; STORAGE ADDRESS + 1
           DEC     BC                                                       ; SIZE - 1
           LD      A,B
           OR      C
           JR      NZ,TVF3
           ;    COMPARE CHECK SUM (1199H/CSMDT) AND TAPE
           LD      HL,(CSMDT)
           CALL    RBYTE
           CP      H
           JP      NZ,RTP7                                                  ; ERROR, NOT EQUAL
           CALL    RBYTE
           CP      L
           JP      NZ,RTP7                                                  ; ERROR, NOT EQUAL
           DEC     D                                                        ; NUMBER OF COMPARES (2) - 1
           JP      Z,RTP8                                                   ; OK, 2 COMPARES
           LD      H,D                                                      ; (-->05C7H), SAVE NUMBER OF COMPARES
           JR      TVF1                                                     ; NEXT COMPARE

           ;    1 BYTE WRITE

WBYTE:     PUSH    BC
           LD      B,8
           CALL    LONG
WBY1:      RLCA    
           CALL    C,LONG
           CALL    NC,SHORT
           DEC     B
           JP      NZ,WBY1
           POP     BC
           RET     



            
MSG1:      DW       207Fh
MSG2:      DB       "PLAY", 0Dh, 00h
MSG3:      DW       207Fh                     ; PRESS RECORD
           DB       "RECORD.", 0Dh, 00h
MSGN7:     DB       "WRITING", 0Dh, 00h
MSGOK:     DB       "OK", 0Dh, 00h
MSG_ERRCHKSUM:
           DB       "CHECKSUM ERROR", 0Dh
MSG_ERRWRITE:
           DB       "WRITE ERROR", 0Dh

MSG_READTAPE:
           DB       "READ TAPE", 0Dh, 00h
MSG_TAPEMARK:
           DB       "TAPEMARK", 0Dh, 00h
MSG_MOTORTG:
           DB       "MOTOR TOGGLE", 0Dh, 00h
MSG_MOTORSTP:
           DB       "MOTOR STOP", 0Dh, 00h
MSG_TPMARK:
           DB       "TAPE MARK START", 0Dh, 00h
MSG_GAPCK:
           DB       "GAP CHECK", 0Dh, 00h
MSG_LOADFILE:
           DB       "LOAD FILE          = ",0Dh, 00h
MSG_LOADFROM:
           DB       "LOAD ADDRESS       = ", 0Dh, 00h
MSG_LOADEXEC:
           DB       "EXEC ADDRESS       = ", 0Dh, 00h
MSG_LOADSIZE:
           DB       "LOAD SIZE          = ", 0Dh, 00h
MSG_SAVEFILE:
           DB       "SAVE FILE          = ",0Dh, 00h
MSG_SAVEFROM:
           DB       "SAVE ADDRESS       = ", 0Dh, 00h
MSG_SAVEEXEC:
           DB       "SAVE ADDRESS       = ", 0Dh, 00h
MSG_SAVESIZE:
           DB       "SAVE SIZE          = ", 0Dh, 00h
MSG_CHKSUM_MZ1:
           DB       "  MZ CHECKSUM (OK) = ", 0Dh, 00h
MSG_CHKSUM_TP1:
           DB       "TAPE CHECKSUM (OK) = ", 0Dh, 00h
MSG_CHKSUM_MZ2:
           DB       "  MZ CHECKSUM (ER) = ", 0Dh, 00h
MSG_CHKSUM_TP2:
           DB       "TAPE CHECKSUM (ER) = ", 0Dh, 00h
TITLE:     DB      "SHARPMZ TAPE TESTER (C) P. SMART 2018", 0Dh, 00h
















































;           LD      B, 20       ; Number of loops
;LOOP:      LD      HL,MSTART   ; Start of checked memory,
;           LD      D,0CEh      ; End memory check CE00
;LOOP1:     LD      A,000h
;           CP      L
;           JR      NZ,LOOP1b
;           CALL    PRTHL       ; Print HL as 4digit hex.
;           LD      A,0C4h      ; Move cursor left.
;           LD      E,004h      ; 4 times.
;LOOP1a:    CALL    DPCT
;           DEC     E
;           JR      NZ,LOOP1a
;LOOP1b:    INC     HL
;           LD      A,H
;           CP      D           ; Have we reached end of memory.
;           JR      Z,LOOP3     ; Yes, exit.
;           LD      A,(HL)      ; Read memory location under test, ie. 0.
;           CPL                 ; Subtract, ie. FF - A, ie FF - 0 = FF.
;           LD      (HL),A      ; Write it back, ie. FF.
;           SUB     (HL)        ; Subtract written memory value from A, ie. should be 0.
;           JR      NZ,LOOP2    ; Not zero, we have an error.
;           LD      A,(HL)      ; Reread memory location, ie. FF
;           CPL                 ; Subtract FF - FF
;           LD      (HL),A      ; Write 0
;           SUB     (HL)        ; Subtract 0
;           JR      Z,LOOP1     ; Loop if the same, ie. 0
;LOOP2:     LD      A,16h
;           CALL    PRNT        ; Print A
;           CALL    PRTHX       ; Print HL as 4 digit hex.
;           CALL    PRNTS       ; Print space.
;           XOR     A
;           LD      (HL),A
;           LD      A,(HL)      ; Get into A the failing bits.
;           CALL    PRTHX       ; Print A as 2 digit hex.
;           CALL    PRNTS       ; Print space.
;           LD      A,0FFh      ; Repeat but first load FF into memory
;           LD      (HL),A
;           LD      A,(HL)
;           CALL    PRTHX       ; Print A as 2 digit hex.
;           NOP
;           JR      LOOP4
;
;LOOP3:     LD      DE,OKCHECK
;           CALL    MSG         ; Print check message in DE
;           LD      A,B         ; Print loop count.
;           CALL    PRTHX
;           LD      DE,OKMSG
;           CALL    MSG         ; Print ok message in DE
;           DEC     B
;           JR      NZ,LOOP
;           LD      DE,DONEMSG
;           CALL    MSG         ; Print check message in DE
;           JP      MONIT
;
;OKCHECK:   DB      11h
;           DB      "CHECK: ", 0Dh
;OKMSG:     DB      "OK.", 0Dh
;DONEMSG:   DB      11h
;           DB      "RAM TEST COMPLETE.", 0Dh
;
;LOOP4:     LD      B,09h
;           CALL    PRNTS        ; Print space.
;           XOR     A            ; Zero A
;           SCF                  ; Set Carry
;LOOP5:     PUSH    AF           ; Store A and Flags
;           LD      (HL),A       ; Store 0 to bad location.
;           LD      A,(HL)       ; Read back
;           CALL    PRTHX        ; Print A as 2 digit hex.
;           CALL    PRNTS        ; Print space
;           POP     AF           ; Get back A (ie. 0 + C)
;           RLA                  ; Rotate left A. Bit LSB becomes Carry (ie. 1 first instance), Carry becomes MSB
;           DJNZ    LOOP5        ; Loop if not zero, ie. print out all bit locations written and read to memory to locate bad bit.
;           XOR     A            ; Zero A, clears flags.
;           LD      A,80h
;           LD      B,08h
;LOOP6:     PUSH    AF           ; Repeat above but AND memory location with original A (ie. 80) 
;           LD      C,A          ; Basically walk through all the bits to find which one is stuck.
;           LD      (HL),A
;           LD      A,(HL)
;           AND     C
;           NOP
;           JR      Z,LOOP8      ; If zero then print out the bit number
;           NOP
;           NOP
;           LD      A,C
;           CPL
;           LD      (HL),A
;           LD      A,(HL)
;           AND     C
;           JR      NZ,LOOP8     ; As above, if the compliment doesnt yield zero, print out the bit number.
;LOOP7:     POP     AF
;           RRCA
;           NOP
;           DJNZ    LOOP6
;           JP      MONIT
;
;LOOP8:     CALL    LETNL        ; New line.
;           LD      DE,BITMSG    ; BIT message
;           CALL    MSG          ; Print message in DE
;           LD      A,B
;           DEC     A
;           CALL    PRTHX        ; Print A as 2 digit hex, ie. BIT number.
;           CALL    LETNL        ; New line
;           LD      DE,BANKMSG   ; BANK message
;           CALL    MSG          ; Print message in DE
;           LD      A,H
;           CP      50h          ; 'P'
;           JR      NC,LOOP9     ; Work out bank number, 1, 2 or 3.
;           LD      A,01h
;           JR      LOOP11
;
;LOOP9:     CP      90h
;           JR      NC,LOOP10
;           LD      A,02h
;           JR      LOOP11
;
;LOOP10:    LD      A,03h
;LOOP11:    CALL    PRTHX        ; Print A as 2 digit hex, ie. BANK number.
;           JR      LOOP7
;
;BITMSG:    DB      " BIT:  ", 0Dh
;BANKMSG:   DB      " BANK: ", 0Dh

MEND:
