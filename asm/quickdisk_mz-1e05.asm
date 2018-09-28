; V1.10
;
; To compile use:
;
; AS80 [1.31] - Assembler for 8080/8085/Z80 microprocessor.
;
; Available from:
;   - http://www.falstaff.demon.co.uk/cross.html
;   - ftp://ftp.simtel.net/pub/simtelnet/msdos/crossasm/as80_131.zip
;   - and many Simtel mirrors.
;
; as80 -i -l -n -x2 -v -z mz-1e05.asm




;
;----< MFM Minifloppy control >----
;
;
; Call condition
;
; Case of disk initialize
;       Drive N         = IX+0      (0 - 3)
;
;
; Case of sequential read & write
;       Drive N         = IX+0      (0 - 3)
;
;       Sector addrs    = IX+1,2    (0 - $045F)                      H   C    S
;                                   (0 - 1119) -> 70 x 16 sectors -> 2 x 35 x 16
;       Byte size       = IX+3,4
;       Address         = IX+5,6
;       Next track      = IX+7
;       Next sector     = IX+8
;       Start track     = IX+9
;       Start sector    = IX+10
;
;
;       I/O Port address
;
CR      EQU     0D8h                        ; CommandRegister
TR      EQU     0D9h                        ; TrackRegister
SCR     EQU     0DAh                        ; SeCtorRegister
DR      EQU     0DBh                        ; DataRegister
DM      EQU     0DCh                        ; DriveMotor
HS      EQU     0DDh                        ; HeadSelect



TIMST   EQU     00033h

;
;       Subroutine work
;
BPRO    EQU     0CF00h
BUF     EQU     011A3h
BPARA   EQU     BPRO - 23                   ; BootPARAmeter


CMD     EQU     BPARA + 11                  ; CoMmanD
MTFG    EQU     CMD + 1                     ; MoTorFlaG
CLBF0   EQU     MTFG + 1
CLBF1   EQU     CLBF0 + 1
CLBF2   EQU     CLBF1 + 1
CLBF3   EQU     CLBF2 + 1
VRFCNT  EQU     CLBF3 + 1                   ; VeRiFyCouNT
STAFG   EQU     VRFCNT + 1                  ; STAtusFlaG

; Macro to align boundaries.
ALIGN:  MACRO ?boundary, ?fill
        DS    ?boundary - 1 - ($ + ?boundary - 1) % ?boundary, ?fill
        ENDM

;
;
;--------< Ercode map >--------
;
; 50 : Not ready
; 41 : Data error
;       Track 80 err
;       Write protect err
;       Seek err
;       CRC err
;       Lost data
; 54 : Unformat
;       Recode not found
; 56 : Invalid data
;
;


        ORG     0F000h


MZ_1E05:
        NOP
        LD      HL,000ADh
        JR      L_F007
FDX:
        EX      (SP),HL
L_F007:
        LD      (BPARA + 21),HL
        XOR     A
        LD      DE,0
        CALL    TIMST
        CALL    FDCC                    ; FD i/o check
        JP      NZ,NOTIO
        LD      DE,BPARA                ; destination address
        LD      HL,BOOT                 ; source address
        LD      BC,11                   ; 11 bytes
        LDIR                            ; copy
SJP:
        LD      IX,BPARA
        CALL    BREAD                   ; read from drive 0, sector 0, 
                                        ; 
        LD      HL,BPRO                 ; compare this address
        LD      DE,IPLMC                ; with the IPL MasterCode
        LD      B,7                     ; this are 7 bytes : 3,'IPLPRO'
MCHECK:
        LD      C,(HL)
        LD      A,(DE)
        CP      C
        JP      NZ,MASTE                ; not equal than MasterError
        INC     HL
        INC     DE
        DJNZ    MCHECK
                                        ; else Master was found
        LD      DE,IPLM0                ; 'IPL IS LOADING'
        RST     018h
        LD      DE,BPRO + 7             ; NAME
        RST     018h
        LD      HL,(BPRO + 016h)        ; TARGETADDRESS from BootBlock
        LD      A,H
        OR      L
        JR      NZ,L_F051               ; if it is != 0 than normal file
        LD      HL,(BPRO + 018h)        ; TARGETADDRESS from BootBlock
        LD      A,H
        OR      L
        JR      Z,L_F057                ; if it is also 0 than ROM replace file
L_F051:
        XOR     A                       ; else normal file,
        LD      HL,(BPRO + 018h)        ; TARGETADDRESS from BootBlock
        JR      L_F05C
L_F057:
        LD      A,0FFh                  ; target is at $0000, bankswitching is needed
        LD      HL,01200h               ; for now use temporary buffer at $1200
L_F05C:
        LD      (0CEFDh),A
        
        LD      (IX + 5),L              ; set the TargetAddress
        LD      (IX + 6),H
        
        LD      HL,(BPRO + 014h)        ; BYTE SIZE from BootBlock
        LD      (IX + 3),L
        LD      (IX + 4),H
        
        LD      HL,(BPRO + 01Eh)        ; START SECTOR from BootBlock
        LD      (IX + 1),L
        LD      (IX + 2),H
;
        CALL    BREAD
        CALL    MOFF

        LD      A,(0CEFDh)
        CP      0FFh
        JR      NZ,L_F093
        OUT     (0E0h),A
        LD      HL,01200h               ; SourceAddress
        LD      DE,(BPRO + 016h)        ; TargetAddress
        LD      BC,(BPRO + 014h)        ; ByteCounter
        LDIR                            ; copy
L_F093:
        LD      BC,00200h               ; Default code
        LD      HL,(BPRO + 018h)        ; TARGET/EXECUTION ADDRESS from BootBlock
        JP      (HL)

MASTE:
        CALL    MOFF
        LD      DE,ERRM1                ; 'NOT MASTER'
        JR      ERRTR1
ERRTRT:
        CP      50
NOTIO:
        LD      DE,IPLM3                ; 'MAKE READY FD'
        JR      Z,ERRTR1
        LD      DE,ERRM0                ; 'FD:LOADING ERROR'
ERRTR1:
        CALL    00009h
        RST     018h
        LD      SP,010EEh
        LD      HL,(BPARA + 21)
        EX      (SP),HL
        RET
;
;
; PARAMETER SETTING
;
IPLMC:
        DB      003h                    ; IPL MASTER FLAG
        DB      "IPLPRO"

BOOT:
        DB      000h                    ; DRIVE NO.
        DW      00000h                  ; SECTOR ADDR.
        DW      00100h                  ; IFM BYTE SIZE
        DW      BPRO                    ; IFM LOADING ADDR.
        DW      00000h                  ; IX+7,8 (track 0, sector 0)



ERRM1:
        DB      "FD:NOT MASTER",00Dh
IPLM0:
        DB      "IPL IS LOADING ",00Dh
IPLM3:
        DB      "MAKE READY FD",00Dh
ERRM0:
        DB      "FD:LOADING ERROR",00Dh

FDCC:
        LD      A,0A5h
        LD      B,A
        OUT     (TR),A
        CALL    DLY80U
        IN      A,(TR)
        CP      B
        RET

L_F111:
        DB      000h, 000h
;
;
; READY CHECK
;
READY:
        LD      A,(MTFG)
        RRCA
        CALL    NC,MTON
        LD      A,(IX + 0)              ; DRIVE NO SET
        OR      084h
        OUT     (DM),A                  ; DRIVE SELECT MOTON
        XOR     A
        LD      (CMD),A
        CALL    DLY60M
        LD      HL,0
REDY0:
        DEC     HL
        LD      A,H
        OR      L
        JR      Z,REDY1
        IN      A,(CR)                  ; STATUS GET
        CPL
        RLCA
        JR      C,REDY0
        LD      C,(IX + 0)
        LD      HL,CLBF0
        LD      B,000h
        ADD     HL,BC
        BIT     0,(HL)
        JR      NZ,REDY2
        CALL    RCLB
        SET     0,(HL)
REDY2:
        RET

REDY1:
        LD      A,032h
        JP      ERJMP
;
;
; MOTOR ON
;
MTON:
        LD      A,080h
        OUT     (DM),A
        LD      B,16
MTD1:
        CALL    DLY60M
        DJNZ    MTD1
        LD      A,1
        LD      (MTFG),A
        RET
;
;
; SEEK TREATMENT
;
SEEK:
        LD      A,01Bh                  ; 1x = SEEK, 
        CALL    CMDOT1                  ; load head, no verify, max stepping rate
        AND     099h
        RET
;
;
; MOTOR OFF
;
MOFF:
        PUSH    AF
        CALL    DLY1M                   ; 1000 US DELAY
        XOR     A
        OUT     (DM),A
        LD      (CLBF0),A
        LD      (CLBF1),A
        LD      (CLBF2),A
        LD      (CLBF3),A
        LD      (MTFG),A
        POP     AF
        RET
;
;
; RECALIBRATION
;
RCLB:
        LD      A,00Bh                  ; 0x = RESTORE (seek track 0)
        CALL    CMDOT1                  ; load head, no verify, max stepping rate
        AND     085h
        XOR     004h
        RET     Z

L_F189:
        JP      STERROR
;
;
; COMMAND OUT ROUTINE
;
CMDOT1:
        LD      (CMD),A
        CPL
        OUT     (CR),A
        CALL    BSYON
        CALL    DLY60M
        IN      A,(CR)
        CPL
        LD      (STAFG),A
        RET
;
;
; BUSY AND WAIT
;
BSYON:
        PUSH    DE
        PUSH    HL
        CALL    BSY0
BSYON2:
        LD      HL,00000h
BSYON0:
        DEC     HL
        LD      A,H
        OR      L
        JR      Z,BSYON1
        IN      A,(CR)
        RRCA
        JR      NC,BSYON0
        POP     HL
        POP     DE
        RET
;
BSYON1:
        DEC     E
        JR      NZ,BSYON2
BSYONE:
        LD      A,029h
        POP     HL
        POP     DE
        JP      ERJMP
;
BSYOFF:
        PUSH    DE
        PUSH    HL
        CALL    BSY0
BSYOF2:
        LD      HL,00000h
BSYOF0:
        DEC     HL
        LD      A,H
        OR      L
        JR      Z,BSYOF1
        IN      A,(CR)                  ; Status Register
        RRCA
        JR      C,BSYOF0
        POP     HL
        POP     DE
        RET
;
BSYOF1:
        DEC     E
        JR      NZ,BSYOF2
        JR      BSYONE
;
BSY0:
        CALL    DLY80U
        LD      E,007h
        RET
;
;
; SEQUENTIAL READ
;
BREAD:
        CALL    CNVRT
        CALL    PARST1                  ; HL = IX + 5,6 (TargetAddress)
RE8:
        CALL    SIDST
        CALL    SEEK
        JP      NZ,ERJMP
        CALL    PARST2                  ; C = DataRegister
        DI                              ; disable interrupts
        LD      A,094h                  ; 9x = READ SECTOR, multiple records
        CALL    CMDOT2                  ; compare for side 0, 15ms delay, 
RE6:                                    ; disable side select compare
        LD      B,0                     ; ByteCounter = 0, to load 256 bytes of the sector
RE4:
        IN      A,(CR)
        RRCA
        JR      C,RE3
        RRCA
        JR      C,RE4
        INI                             ; (HL) = in(C), B = B - 1 , HL = HL + 1
        JR      NZ,RE4
        
        INC     (IX + 8)                ; NextSector = NextSector + 1
        LD      A,(IX + 8)
        CP      011h                    ; if NextSector = 17
        JR      Z,L_F213                ; than end
        DEC     D                       ; else SectorCounter = SectorCounter - 1
        JR      NZ,RE6                  ; if SectorCounter = 0
        JR      L_F214                  ; than end
L_F213:
        DEC     D
L_F214:
        CALL    INTER
RE3:
        EI                              ; enable interrupts
        IN      A,(CR)
        CPL
        LD      (STAFG),A
        AND     0FFh
        JR      NZ,STERROR
        CALL    ADJ                     ; adjust sector and track
        JP      Z,REND
        LD      A,(IX + 7)              ; track
        JR      RE8
REND:
        LD      A,080h      
        OUT     (DM),A                  ; motor on
        RET
;
;
; PARAMETER SET
;
;
PARST1:
        CALL    READY
        LD      D,(IX + 4)              ; D = bytes to read (highbyte) (256 bytes)
        LD      A,(IX + 3)              ; A = bytes to read (lowbyte)
        OR      A                       ; if A = 0
        JR      Z,L_F23F                ; than it's ok
        INC     D                       ; else read 256 bytes more (1 sector)
L_F23F:
        LD      A,(IX + 10)             ; NextSector = StartSector
        LD      (IX + 8),A
        
        LD      A,(IX + 9)              ; NextTrack = StartTrack
        LD      (IX + 7),A
        
        LD      L,(IX + 5)              ; HL = TargetAddress
        LD      H,(IX + 6)
        RET

;
;
; SIZE SEEK SET
;
SIDST:
        SRL     A
        CPL
        OUT     (DR),A
        JR      NC,L_F25D               ; NC than Head 0
        LD      A,1                     ; else Head 1
        JR      L_F25E
L_F25D:
        XOR     A
L_F25E:
        CPL
        OUT     (HS),A                  ; set HeadSelect
        RET
;
;
; TRACK & SECTOR SET
;
PARST2:
        LD      C,DR
        LD      A,(IX + 7)              ; A = NextTrack
        SRL     A
        CPL
        OUT     (TR),A
        LD      A,(IX + 8)              ; A = NextSector
        CPL
        OUT     (SCR),A
        RET
;
;
; ADJUST SECT & TRACK
;
ADJ:
        LD      A,(IX + 8)              ; A = NextSector
        CP      17                      ; if NextSector = 17  
        JR      NZ,L_F282               ; than the border is not reached
        LD      A,001h                  ; else
        LD      (IX + 8),A              ; NextSector = 1
        INC     (IX + 7)                ; NextTrack = NextTrack + 1
L_F282:
        LD      A,D
        OR      A
        RET
;
;
; COMMAND OUT & WAIT
;
CMDOT2:
        LD      (CMD),A
        CPL
        OUT     (CR),A
        CALL    BSYOFF
        RET
;
;
; FORCE INTERRUPT
;
INTER:
        LD      A,0D8h
        CPL
        OUT     (CR),A
        CALL    BSYON
        RET

;
;
; STATUS CHECK
;
STERROR:
        LD      A,(CMD)
        CP      00Bh                    ; Restore (seek track 0)
        JR      Z,ERCK1
        CP      01Bh                    ; Seek
        JR      Z,ERCK1
        CP      0F4h                    ; Write track
        JR      Z,ERCK1
        LD      A,(STAFG)
        BIT     7,A
        JR      NZ,ERRET
        BIT     6,A
        JR      NZ,ERRET1
        BIT     4,A
        LD      A,54
        JR      NZ,ERJMP
        JR      ERRET1
ERCK1:
        LD      A,(STAFG)
        BIT     7,A
        JR      NZ,ERRET
ERRET1:
        LD      A,41
        JR      ERJMP
ERRET:
        LD      A,50
ERJMP:
        CALL    MOFF
        JP      ERRTRT
;
;
; SECTOR TO TRACK & SECTOR CONVERT
;
CNVRT:
        LD      B,0                     ; TrackCounter = 0
        LD      DE,16                   ; 16 sectors per track
        LD      L,(IX + 1)              ; HL = SectorAddress
        LD      H,(IX + 2)
        XOR     A
TRANS0:
        SBC     HL,DE                   ; SectorAddress - SectorPerTrack
        JR      C,TRANS1                ; if < 0 than ready
        INC     B                       ; else TrackCounter = TrackCounter + 1
        JR      TRANS0                  ; next try

TRANS1:
        ADD     HL,DE                   ; undo the last substraction
        LD      H,B
        INC     L                       ; adjust sector (sector is 1..16 and not 0..15)
        LD      (IX + 9),H              ; set StartTrack
        LD      (IX + 10),L             ; set StartSector
        RET

;
;
;       TIME DELAY ( 1m & 60m & 80u )
;
DLY80U:
        PUSH    DE
        LD      DE,15
        JP      DLYT

DLY1M:
        PUSH    DE
        LD      DE,160
        JP      DLYT

DLY60M:
        PUSH    DE
        LD      DE,8230
DLYT:
        DEC     DE
        LD      A,E
        OR      D
        JR      NZ,DLYT
        POP     DE
        RET


        ALIGN   0FFF0h, 000h
        DB      "  84.03.14 V1.0A"
