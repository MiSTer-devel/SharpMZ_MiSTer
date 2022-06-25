        ORG    0000H
        ;****************************************************************
        ;
        ; Personal Computer
        ;    MZ-80B
        ;
        ;    Initial Program Loader
        ;****************************************************************
        ;
        JR      START
        ;
        ; NST RESET
        ;
NST:    LD      A,03H
        OUT     (PPICTL),A                           ;Set PC1 NST=1
        ;
START:  LD      A,82H                                ;8255 A=OUT B=IN C=OUT
        OUT     (PPICTL),A
        LD      A,0FH                                ;PIO A=OUT
        OUT     (PIOCTLA),A
        LD      A,0CFH                               ;PIO B=IN
        OUT     (PIOCTLB),A
        LD      A,0FFH
        OUT     (PIOCTLB),A
        LD      A,58H                                ;BST=1 NST=0 OPEN=1 WRITE=1
        OUT     (PPIC),A
        LD      A,12H
        OUT     (PPIA),A
        XOR     A
        OUT     (GRPHCTL),A                          ;Set Graphics VRAM to default, input to GRPH I, no output.
        LD      SP,0FFE0H
        LD      HL,0D000H
        LD      A,0B3H
        OUT     (PIOA),A
CLEAR:  LD      (HL),00H                            ;DISPLAY CLEAR
        INC     HL
        LD      A,H
        OR      L
        JR      NZ,CLEAR
        LD      A,13H
        OUT     (PIOA),A
        XOR     A
        LD      (DRINO),A    
        LD      (MTFG),A
KEYIN:  CALL    KEYS1
        BIT     3,A                                  ;C - Cassette.
        JR      Z,CMT
        BIT     0,A                                  ;/ - Boot external rom.
        JP      Z,EXROMT
        JR      NKIN                                 ;No selection, so standard startup, try FDC then CMT.
        ;
KEYS1:  LD      B,14H                                ;Preserve A4-A7, set A4 to prevent all strobes low, the select line 5 (0-4).
KEYS:   IN      A,(PIOA)
        AND     0F0H
        OR      B
        OUT     (PIOA),A
        IN      A,(PIOB)                             ;Read the strobed key.
        RET     
        ;
        ;
NKIN:   CALL    FDCC
        JP      Z,FD
        JR      CMT
        ;
FDCC:   LD      A,0A5H
        LD      B,A
        OUT     (0D9H),A
        CALL    DLY80U
        IN      A,(0D9H)
        CP      B
        RET     
        ;
        ;                                       ;
        ;  CMT CONTROL                          ;
        ;                                       ;
        ;
CMT:    CALL    MSTOP
        CALL    DEL6
        CALL    KYEMES
        CALL    ?RDI
        JR      C,ST1
        CALL    LDMSG
        LD      HL,NAME
        LD      E,010H
        LD      C,010H
        CALL    DISP2
        LD      A,(ATRB)
        CP      01H
        JR      NZ,MISMCH
        CALL    ?RDD
ST1:    PUSH    AF
        CALL    DEL6
        CALL    REW
        POP     AF
        JP      C,TRYAG
        JP      NST
                  ;
MISMCH: LD      HL,MES16
        LD      E,0AH
        LD      C,0FH
        CALL    DISP
        CALL    MSTOP
        SCF     
        JR      ST1
        ;
        ;READ INFORMATION
        ;      CF=1:ERROR
RDINF:
?RDI:   DI      
        LD      D,04H
        LD      BC,0080H
        LD      HL,IBUFE
RD1:    CALL    MOTOR
        JR      C,STPEIR
        CALL    TMARK
        JR      C,STPEIR
        CALL    RTAPE
        JR      C,STPEIR
RET2S:  BIT     3,D
        JR      Z,EIRTN
STPEIR: CALL    MSTOP
EIRTN:  EI      
        RET     
        ;
        ;
        ;READ DATA
RDDAT:
?RDD:   DI      
        LD      D,08H
        LD      BC,(SIZE)
        LD      HL,8000H
        JR      RD1
        ;
        ;
        ;READ TAPE
        ;      BC=SIZE
        ;      DE=LOAD ADDRSS
RTAPE:  PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      H,02H
RTP2:   CALL    SPDIN
        JR      C,TRTN1                                ;BREAK
        JR      Z,RTP2
        LD      D,H
        LD      HL,0000H
        LD      (SUMDT),HL
        POP     HL
        POP     BC
        PUSH    BC
        PUSH    HL
RTP3:   CALL    RBYTE
        JR      C,TRTN1
        LD      (HL),A
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,RTP3
        LD      HL,(SUMDT)
        CALL    RBYTE
        JR      C,TRTN1
        LD      E,A
        CALL    RBYTE
        JR      C,TRTN1
        CP      L
        JR      NZ,RTP5
        LD      A,E
        CP      H
        JR      Z,TRTN1
RTP5:   DEC     D
        JR      Z,RTP6
        LD      H,D
        JR      RTP2
RTP6:   CALL    BOOTER
        SCF     
TRTN1:  POP     HL
        POP     BC
        POP     DE
        RET     
        ;EDGE
EDGE:   IN      A,(PPIB)
        CPL     
        RLCA    
        RET     C                                ;BREAK
        RLCA    
        JR      NC,EDGE                                ;WAIT ON LOW
EDGE1:  IN      A,(PPIB)
        CPL     
        RLCA    
        RET     C                                ;BREAK
        RLCA    
        JR      C,EDGE1                                ;WAIT ON HIGH
        RET     
        ; 1 BYTE READ
        ;      DATA=A
        ;      SUMDT STORE
RBYTE:  PUSH    HL
        LD      HL,0800H                            ; 8 BITS
RBY1:   CALL    SPDIN
        JR      C,RBY3                                ;BREAK
        JR      Z,RBY2                                ;BIT=0
        PUSH    HL
        LD      HL,(SUMDT)                            ;CHECKSUM
        INC     HL
        LD      (SUMDT),HL
        POP     HL
        SCF     
RBY2:   RL      L
        DEC     H
        JR      NZ,RBY1
        CALL    EDGE
        LD      A,L
RBY3:   POP     HL
        RET     
        ;TAPE MARK DETECT
        ;      E=L:INFORMATION
        ;      E=S:DATA
TMARK:  PUSH    HL
        LD      HL,1414H
        BIT     3,D
        JR      NZ,TM0
        ADD     HL,HL
TM0:    LD      (TMCNT),HL
TM1:    LD      HL,(TMCNT)
TM2:    CALL    SPDIN
        JR      C,RBY3
        JR      Z,TM1
        DEC     H
        JR      NZ,TM2
TM3:    CALL    SPDIN
        JR      C,RBY3
        JR      NZ,TM1
        DEC     L
        JR      NZ,TM3
        CALL    EDGE
        JR      RBY3
        ;READ 1 BIT
SPDIN:  CALL    EDGE                                ;WAIT ON HIGH
        RET     C                                ;BREAK

        CALL    DLY2
        IN      A,(PPIB)                            ;READ BIT
        AND     40H
        RET     
        ;
        ;
        ;MOTOR ON
MOTOR:  PUSH    DE
        PUSH    BC
        PUSH    HL
        IN      A,(PPIB)
        AND     20H
        JR      Z,MOTRD
        LD      HL,MES6
        LD      E,0AH
        LD      C,0EH
        CALL    DISP
        CALL    OPEN
MOT1:   IN      A,(PIOB)
        CPL     
        RLCA    
        JR      C,MOTR
        IN      A,(PPIB)
        AND     20H
        JR      NZ,MOT1
        CALL    KYEMES
        CALL    DEL1M
MOTRD:  CALL    PLAY
MOTR:   POP     HL
        POP     BC
        POP     DE
        RET     
        ;
        ;
        ;MOTOR STOP
MSTOP:  LD      A,0DH
        OUT     (PPICTL),A                            ;Set PC6 - READ MODE
        LD      A,1AH
        OUT     (PPIA),A
        CALL    DEL6
        JR      BLK3
        ;EJECT
OPEN:   LD      A,08H                                 ;Reset PC4 - EJECT activate
        OUT     (PPICTL),A
        CALL    DEL6
        LD      A,09H
        OUT     (PPICTL),A                            ;Set PC4 - Deactivate EJECT
        RET     
        ;
        ;
KYEMES: LD      HL,MES3
        LD      E,04H
        LD      C,1CH
        CALL    DISP
        RET     
        ;
        ;PLAY
PLAY:   CALL    FR
        CALL    DEL6
        LD      A,16H
        OUT     (PPIA),A
        JR      BLK3
BLK1:   CALL    DEL6
        CALL    BLK3
        LD      A,13H
BLK2:   OUT     (PPIA),A
BLK3:   LD      A,12H
        OUT     (PPIA),A
        RET     
        ;
        ;
FR:     LD      A,12H
FR1:    OUT     (PPIA),A
        CALL    DEL6
        LD      A,0BH
        OUT     (PPICTL),A                            ;Set PC5
        CALL    DEL6
        LD      A,0AH
        OUT     (PPICTL),A                            ;Reset PC5
        RET     

RRW:    LD      A,010H
        JR      FR1
        ;REWIND
REW:    CALL    RRW
        JR      BLK1
        ;
        ;TIMING DEL
DM1:    PUSH    AF
L0211:  XOR     A
L0212:  DEC     A
        JR      NZ,L0212
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,L0211
        POP     AF
        POP     BC
        RET     

DEL6:   PUSH    BC
        LD      BC,00E9H                            ;233D
        JR      DM1
DEL1M:  PUSH    BC
        LD      BC,060FH                            ;1551D
        JR      DM1
        ;
        ;TAPE DELAY TIMING
        ;
        ;
DLY2:   LD      A,31H
L022B:  DEC     A
        JP      NZ,L022B
        RET     
        ;
        ;
        ;
        ;
        ;
LDMSG:  LD      HL,MES1
        LD      E,00H
        LD      C,0EH
        JR      DISP
        ;
DISP2:  LD      A,93H
        OUT     (PIOA),A
        JR      DISP1
                    ;
BOOTER: LD      HL,MES8
        LD      E,0AH
        LD      C,0DH
        ;
DISP:   LD      A,93H
        OUT     (PIOA),A
        EXX     
        LD      HL,0D000H
DISP3:  LD      (HL),00H
        INC     HL
        LD      A,H
        OR      L
        JR      NZ,DISP3
        EXX     
DISP1:  XOR     A
        LD      B,A
        LD      D,0D0H
        LDIR    
        LD      A,13H
        OUT     (PIOA),A
        RET     
        ;
        ;
MES1:   DB    "IPL is loading"
MES3:   DB    "IPL is looking for a program"
MES6:   DB    "Make ready CMT"
MES8:   DB    "Loading error"
MES9:   DB    "Make ready FD"
MES10:  DB    "Press F or C"
MES11:  DB    "F:Floppy diskette"
MES12:  DB    "C:Cassette tape"
MES13:  DB    "Drive No? (1-4)"
MES14:  DB    "This diskette is not master"
MES15:  DB    "Pressing S key starts the CMT"
MES16:  DB    "File mode error"
                    ;
IPLMC:  DB    01H
        DB    "IPLPRO"
        ;
        ;
        ;FD
FD:     LD      IX,IBADR1
        XOR     A
        LD      (0CF1EH),A
        LD      (0CF1FH),A
        LD      IY,0FFE0H
        LD      HL,0100H
        LD      (IY+2),L
        LD      (IY+3),H
        CALL    BREAD                                ;INFORMATION INPUT
        LD      HL,0CF00H                            ;MASTER CHECK
        LD      DE,IPLMC
        LD      B,06H
MCHECK: LD      C,(HL)
        LD      A,(DE)
        CP      C
        JP      NZ,NMASTE
        INC     HL
        INC     DE
        DJNZ    MCHECK
        CALL    LDMSG
        LD      HL,0CF07H
        LD      E,010H
        LD      C,0AH
        CALL    DISP2
        LD      IX,IBADR2
        LD      HL,(0CF14H)
        LD      (IY+2),L
        LD      (IY+3),H
        CALL    BREAD
        CALL    MOFF
        JP      NST
        ;
        ;
NODISK: LD      HL,MES9
        LD      E,0AH
        LD      C,0DH
        CALL    DISP
        JP      ERR1
        ;
        ; READY CHECK
        ;
READY:  LD      A,(MTFG)
        RRCA    
        CALL    NC,MTON
        LD      A,(DRINO)                            ;DRIVE NO GET
        OR      84H
        OUT     (DM),A                                ;DRIVE SELECT MOTON
        XOR     A
        CALL    DLY60M
        LD      HL,0000H
REDY0:  DEC     HL
        LD      A,H
        OR      L
        JR      Z,NODISK
        IN      A,(CR)                                ;STATUS GET
        CPL     
        RLCA    
        JR      C,REDY0
        LD      A,(DRINO)
        LD      C,A
        LD      HL,CLBF0
        LD      B,00H
        ADD     HL,BC
        BIT     0,(HL)
        RET     NZ
        CALL    RCLB
        SET     0,(HL)
        RET     
        ;
        ; MOTOR ON
                  ;
MTON:   LD      A,80H
        OUT     (DM),A
        LD      B,0AH                                ;1SEC DELAY
MTD1:   LD      HL,3C19H
MTD2:   DEC     HL
        LD      A,L
        OR      H
        JR      NZ,MTD2
        DJNZ    MTD1
        LD      A,01H
        LD      (MTFG),A
        RET     
        ;
        ;SEEK TREATMENT
        ;
SEEK:   LD      A,1BH
        CPL     
        OUT     (CR),A
        CALL    BUSY
        CALL    DLY60M
        IN      A,(CR)
        CPL     
        AND     99H
        RET     
        ;
        ;MOTOR OFF
        ;
MOFF:   CALL    DLY1M
        XOR     A
        OUT     (DM),A
        LD      (CLBF0),A
        LD      (CLBF1),A
        LD      (CLBF2),A
        LD      (CLBF3),A
        LD      (MTFG),A
        RET     
        ;
        ;RECALIBRATION
        ;
RCLB:   PUSH    HL
        LD      A,0BH
        CPL     
        OUT     (CR),A
        CALL    BUSY
        CALL    DLY60M
        IN      A,(CR)
        CPL     
        AND     85H
        XOR     04H
        POP     HL
        RET     Z
        JP      ERR
        ;
        ;BUSY AND WAIT
        ;
BUSY:   PUSH    DE
        PUSH    HL
        CALL    DLY80U
        LD      E,07H
BUSY2:  LD      HL,0000H
BUSY0:  DEC     HL
        LD      A,H
        OR      L
        JR      Z,BUSY1
        IN      A,(CR)
        CPL     
        RRCA    
        JR      C,BUSY0
        POP     HL
        POP     DE
        RET
        ;
BUSY1:  DEC     E
        JR      NZ,BUSY2
        JP      ERR
        ;
        ;DATA CHECK
        ;
CONVRT: LD      B,00H
        LD      DE,0010H
        LD      HL,(0CF1EH)
        XOR     A
TRANS:  SBC     HL,DE
        JR      C,TRANS1
        INC     B
        JR      TRANS
TRANS1: ADD     HL,DE
        LD      H,B
        INC     L
        LD      (IY+4),H
        LD      (IY+5),L
DCHK:   LD      A,(DRINO)
        CP      04H
        JR      NC,DTCK1
        LD      A,(IY+4)
        CP      46H                                ;70D
        JR      NC,DTCK1
        LD      A,(IY+5)
        OR      A
        JR      Z,DTCK1
        CP      11H                                ;17D
        JR      NC,DTCK1
        LD      A,(IY+2)
        OR      (IY+3)
        RET     NZ
DTCK1:  JP      ERR
        ;
        ;SEQUENTIAL READ
        ;
BREAD:  DI      
        CALL    CONVRT
        LD      A,0AH
        LD      (RETRY),A
READ1:  CALL    READY
        LD      D,(IY+3)
        LD      A,(IY+2)
        OR      A
        JR      Z,RE0
        INC     D
RE0:    LD      A,(IY+5)
        LD      (IY+1),A
        LD      A,(IY+4)
        LD      (IY+0),A
        PUSH    IX
        POP     HL
RE8:    SRL     A
        CPL     
        OUT     (DR),A
        JR      NC,RE1
        LD      A,01H
        JR      RE2
RE1:    LD      A,00H
RE2:    CPL     
        OUT     (HS),A
        CALL    SEEK
        JR      NZ,REE
        LD      C,0DBH
        LD      A,(IY+0)
        SRL     A
        CPL     
        OUT     (TR),A
        LD      A,(IY+1)
        CPL     
        OUT     (SCR),A
        EXX     
        LD      HL,RE3
        PUSH    HL
        EXX     
        LD      A,94H
        CPL     
        OUT     (CR),A
        CALL    WAIT
RE6:    LD      B,00H
RE4:    IN      A,(CR)
        RRCA    
        RET     C
        RRCA    
        JR      C,RE4
        INI     
        JR      NZ,RE4
        INC     (IY+1)
        LD      A,(IY+1)
        CP      11H                                ;17D
        JR      Z,RETS
        DEC     D
        JR      NZ,RE6
        JR      RE5
RETS:   DEC     D
RE5:    LD      A,0D8H                                ;FORCE INTERRUPT
        CPL     
        OUT     (CR),A
        CALL    BUSY
RE3:    IN      A,(CR)
        CPL     
        AND     0FFH
        JR      NZ,REE
        EXX     
        POP     HL
        EXX     
        LD      A,(IY+1)
        CP      11H                                ;17D
        JR      NZ,REX
        LD      A,01H
        LD      (IY+1),A
        INC     (IY+0)
REX:    LD      A,D
        OR      A
        JR      NZ,RE7
        LD      A,80H
        OUT     (DM),A
        RET     
RE7:    LD      A,(IY+0)
        JR      RE8
REE:    LD      A,(RETRY)
        DEC     A
        LD      (RETRY),A
        JR      Z,ERR
        CALL    RCLB
        JP      READ1
        ;
        ; WAIT AND BUSY OFF
        ;
WAIT:   PUSH    DE
        PUSH    HL
        CALL    DLY80U
        LD      E,08H
WAIT2:  LD      HL,0000H
WAIT0:  DEC     HL
        LD      A,H
        OR      L
        JR      Z,WAIT1
        IN      A,(CR)
        CPL     
        RRCA    
        JR      NC,WAIT0
        POP     HL
        POP     DE
        RET     
WAIT1:  DEC     E
        JR      NZ,WAIT2
        JR      ERR
                  ;
NMASTE: LD      HL,MES14
        LD      E,07H
        LD      C,1BH                                ;27D
        CALL    DISP
        JR      ERR1
        ;
        ;                                                 ;
        ;   ERRROR OR BREAK                               ;
        ;                                                 ;
        ;
ERR:    CALL    BOOTER
ERR1:   CALL    MOFF
TRYAG2: LD      SP,0FFE0H
        ;
        ;TRYAG
        ;
TRYAG:  CALL    FDCC
        JR      NZ,TRYAG3
        LD      HL,MES10
        LD      E,5AH
        LD      C,0CH                                ;12D
        CALL    DISP2
        LD      E,0ABH
        LD      C,11H                                ;17D
        CALL    DISP2
        LD      E,0D3H
        LD      C,0FH                                ;15D
        CALL    DISP2
TRYAG1: CALL    KEYS1
        BIT     3,A
        JP      Z,CMT
        BIT     6,A
        JR      Z,DNO
        JR      TRYAG1
DNO:    LD      HL,MES13                            ;DRIVE NO SELECT
        LD      E,0AH
        LD      C,0FH
        CALL    DISP
DNO10:  LD      D,12H
        CALL    DNO0
        JR      NC,DNO3
        LD      D,18H
        CALL    DNO0
        JR      NC,DNO3
        JR      DNO10
DNO3:   LD      A,B
        LD      (DRINO),A
        JP      FD
        ;
TRYAG3: LD      HL,MES15
        LD      E,54H
        LD      C,1DH                                ;29D
        CALL    DISP2
TRYAG4: LD      B,06H
TRYAG5: CALL    KEYS
        BIT     3,A
        JP      Z,CMT
        JR      TRYAG5
        ;
DNO0:   IN      A,(PIOA)
        AND     0F0H
        OR      D
        OUT     (PIOA),A
        IN      A,(PIOB)
        LD      B,00H
        LD      C,04H
        RRCA    
DNO1:   RRCA    
        RET     NC
        INC     B
        DEC     C
        JR      NZ,DNO1
        RET     
        ;
        ;  TIME DELAY (1M &60M &80U )
        ;
DLY80U: PUSH    DE
        LD      DE,000DH                            ;13D
        JP      DLYT
DLY1M:  PUSH    DE
        LD      DE,0082H                            ;130D
        JP      DLYT
DLY60M: PUSH    DE
        LD      DE,1A2CH                            ;6700D
DLYT:   DEC     DE
        LD      A,E
        OR      D
        JR      NZ,DLYT
        POP     DE
        RET     
        ;
        ;
        ;                                             ;
        ;   INTRAM EXROM                              ;
        ;                                             ;
        ;
EXROMT: LD      HL,8000H
        LD      IX,EROM1
        JR      SEROMA
EROM1:  IN      A,(0F9H)
        CP      00H
        JP      NZ,NKIN
        LD      IX,EROM2
ERMT1:  JR      SEROMA
EROM2:  IN      A,(0F9H)
        LD      (HL),A
        INC     HL
        LD      A,L
        OR      H
        JR      NZ,ERMT1
        OUT     (0F8H),A
        JP      NST
        ;
SEROMA: LD      A,H
        OUT     (0F8H),A
        LD      A,L
        OUT     (0F9H),A
        LD      D,04H
SEROMD: DEC     D
        JR      NZ,SEROMD
        JP      (IX)

;----------------------------------------------------------
; Variables/Work area
;----------------------------------------------------------

IBUFE:  EQU    0CF00H
ATRB:   EQU    0CF00H
NAME:   EQU    0CF01H
SIZE:   EQU    0CF12H
DTADR:  EQU    0CF14H
SUMDT:  EQU    0FFE0H
TMCNT:  EQU    0FFE2H
        ;
        ;
        ;INPUT BUFFER ADDRESS
        ;
IBADR1: EQU    0CF00H
IBADR2: EQU    8000H
        ;
        ;   SUBROUTINE WORK
        ;
NTRACK: EQU    0FFE0H
NSECT:  EQU    0FFE1H
BSIZE:  EQU    0FFE2H
STTR:   EQU    0FFE4H
STSE:   EQU    0FFE5H
MTFG:   EQU    0FFE6H
CLBF0:  EQU    0FFE7H
CLBF1:  EQU    0FFE8H
CLBF2:  EQU    0FFE9H
CLBF3:  EQU    0FFEAH
RETRY:  EQU    0FFEBH
DRINO:  EQU    0FFECH

        ;
        ;
        ;
        ;
        ;
        ;  MFM MINIFLOPPY CONTROL
        ;
        ;
        ;
        ;  CASE OF DISK INITIALIZE
        ;     DRIVE NO=DRINO (0-3)
        ;
        ;  CASE OF SEQUENTIAL READ
        ;     DRIVE NO=DRINO (0-3)
        ;     BYTE SIZE     =IY+2,3
        ;     ADDRESS       =IX+0,1
        ;     NEXT TRACK    =IY+0
        ;     NEXT SECTOR   =IY+1
        ;     START TRACK   =IY+4
        ;     START SECTOR  =IY+5
        ;
        ;
        ; I/O PORT ADDRESS
        ;
CR:     EQU    0D8H                                ;STATUS/COMMAND PORT
TR:     EQU    0D9H                                ;TRACK REG PORT
SCR:    EQU    0DAH                                ;SECTOR REG PORT
DR:     EQU    0DBH                                ;DATA REG PORT
DM:     EQU    0DCH                                ;MOTOR/DRIVE PORT
HS:     EQU    0DDH                                ;HEAD SIDE SELECT PORT
PPIA:   EQU    0E0H
PPIB:   EQU    0E1H
PPIC:   EQU    0E2H
PPICTL: EQU    0E3H
PIOA:   EQU    0E8H
PIOCTLA:EQU    0E9H
PIOB:   EQU    0EAH
PIOCTLB:EQU    0EBH
GRPHCTL:EQU    0F4H
