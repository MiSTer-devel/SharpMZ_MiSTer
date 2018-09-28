; V1.01
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
; as80 -i -l -n -x2 -v mz-1e14.asm




SIOAD   EQU     0F4h
SIOBD   EQU     0F5h
SIOAC   EQU     0F6h
SIOBC   EQU     0F7h



;       RxD_A   <-  RDDT (ReaDDaTa)
;       RxC_A   <-    (read data clock)
;       TxD_A   ->  #WRDT (WRiteDaTa)
;       TxC_A   <-  6.5MHz / 4 / 16 = 101562,5Hz
;       CTS_A    <-    #WRPR (WRitePRotect)
;        RTS_A    ->    #WRGA (WRiteGAte)
;       DCD_A   <-  #HDST (HeaDSeT (disk test)
;
;       RTS_B   ->    (?)
;       DCD_B   <-  #HOME ()
;       DTR_B   ->  #MTON (MoTorON)




GETL    EQU     00003h
NL      EQU     00009h
PRNT    EQU     00012h
GETKY   EQU     0001Bh
BRKEY   EQU     0001Eh
CMY0    EQU     0005Bh
MSGE1   EQU     00147h
DOT4DE  EQU     002A6h
?TMST   EQU     00308h
SPHEX   EQU     003B1h
SLPT    EQU     003D5h
HLHEX   EQU     00410h
_2HEX   EQU     0041Fh
?WRI    EQU     00436h
LLPT    EQU     00470h
?WRD    EQU     00475h
?RDI    EQU     004D8h
?RDD    EQU     004F8h
?VRFY   EQU     00588h
NLPHL   EQU     005FAh
?KEY    EQU     008CAh
?PRTS   EQU     00920h
MSGOK   EQU     00942h
PRNT3   EQU     0096Ch
MSGSV   EQU     0098Bh
MSG?2   EQU     009A0h
?BRK    EQU     00A32h
?ADCN   EQU     00BB9h
?BLNK   EQU     00DA6h
?DPCT   EQU     00DDCh

BRKCD   EQU     00
NTFECD  EQU     40
HDERCD  EQU     41
WPRTCD  EQU     46
QNTRCD  EQU     50
NFSECD  EQU     53
UNFMCD  EQU     54

ATRB    EQU     010F0h
NAME    EQU     010F1h
SIZE    EQU     01102h
DTADR   EQU     01104h
EXADR   EQU     01106h
COMNT   EQU     01108h

NAMSIZ  EQU     011h
OBJCD   EQU     001h
                                                                         ; QD command table
QDPA    EQU     01130h                                                   ; QD code 1
QDPB    EQU     01131h                                                   ; QD code 2
QDPC    EQU     01132h                                                   ; QD header startaddress
QDPE    EQU     01134h                                                   ; QD header length
QDCPA   EQU     0113Bh                                                   ; QD error flag
HDPT    EQU     0113Ch                                                   ; QD new headpoint possition
HDPT0   EQU     0113Dh                                                   ; QD actual headpoint possition
FNUPS   EQU     0113Eh
FNUPF   EQU     01140h
FNA     EQU     01141h                                                   ; File Number A (actual file number)
FNB     EQU     01142h                                                   ; File Number B (next file number)
MTF     EQU     01143h                                                   ; QD motor flag
RTYF    EQU     01144h
SYNCF   EQU     01146h                                                   ; SyncFlags
RETSP   EQU     01147h
DSPXY   EQU     01171h
DPRNT   EQU     01194h
SWRK    EQU     0119Dh
BUFER   EQU     011A3h
QDIRBF  EQU     0CD90h



        ORG     0E800h

MZ1E14:
LE800:
        NOP
        JP LE80A
        JP ST1X
QDIOS:
        JP QDIOS1

LE80A:
        LD A,0C6h                                                        ; clear screen
        CALL ?DPCT
        XOR A
        LD (DPRNT),A
        DI
        XOR A
        LD DE,00000h
        CALL ?TMST
        LD A,001h
        OUT (SIOBC),A                                                    ; select Write Register 1
        XOR A
        OUT (SIOBC),A                                                    ; Rx INT DISABLE
        CALL GETKY
        CP 'M'
        JR Z,MON
        CP 'Q'
        JR Z,QBT
        CALL LEB22                                                       ; check ROM at 0xF000 (FDD)
        CALL Z,0F006h
        JR QBT
;
;===============================
;
;       Quick disk boot-up
;
;===============================
;
QBT:
        CALL IOFRS                                                       ; IO Flag ReSet
        CALL NL
        CALL QDRCK                                                       ; QuickDisk Ready ChecK
        JR C,LE868
        LD A,00Dh                                                        ; set filename to ""
        LD (BUFER),A
        CALL HDPCL                                                       ; HeaD Point CLear
;
;       Error return set
;
        LD A,001h
        LD (QDCPA),A
        LD HL,LE86B
        LD SP,010EEh
        EX (SP),HL
;
;
        CALL FILSCH                                                      ; filesearch
        JP C,LEBAC
        LD A,(ATRB)
        CP OBJCD                                                         ; is it an "OBJ" file
        JR NZ,LE871
;
;       Quick disk boot
;
        LD DE,LEB27
        RST 018h
        JP DSFLNA

LE868:
        LD DE,LEB37
LE86B:
        CALL NL
        RST 018h
        JR LE87D
LE871:
        LD A,006h                                                        ; Motor off
        LD (QDPA),A
        CALL QDIOS
        LD DE,LED4C
        RST 018h
LE87D:
        CALL NL

MON:
        LD DE,DISCLR                                                     ; '**  MONITOR 9Z-503M  **'
        RST 018h


ST1X:
        CALL NL
        LD A,'*'
        CALL PRNT
        LD DE,BUFER
        CALL GETL
ST2X:
        LD A,(DE)
        INC DE
        CP 00Dh
        JR Z,ST1X
        CP 'J'                                                           ; JUMP
        JR Z,GOTOX
        CP 'L'                                                           ; Load CMT
        JR Z,LOADX
        CP 'F'                                                           ; Floppy boot
        JR Z,FDCK
        CP 'B'                                                           ; Bell
        JP Z,SGX
        CP '#'
        JP Z,LEA6A
        CP 'P'                                                           ; Printer test
        JP Z,PTESTX
        CP 'M'                                                           ; Memory correction
        JP Z,MCORX
        CP 'S'                                                           ; Save CMT
        JP Z,SAVEX
        CP 'V'                                                           ; Verify
        JP Z,VRFYX
        CP 'D'                                                           ; Dump memory
        JP Z,DUMPX
        CP 'Q'                                                           ; Quick disk cmd.
        JR NZ,ST2X
;
;       Quick disk cmd.
;
QUICK:
        LD HL,00000h
        LD (0113Ah),HL
        LD A,(DE)
        CP 'L'                                                           ; Load QD
        JP Z,QL
        CP 'D'                                                           ; Directory
        JP Z,QD
ST1X1:
        JR ST1X


FDCK:
        LD A,(DE)
        CP 00Dh
        JR NZ,ST1X1
        CALL LEB22
        CALL Z,0F006h
        JR ST1X1
?ERX:
        CP 002h
        JR Z,ST1X1
        CALL NL
        LD DE,MSGE1                                                      ; 'CHECK SUM ER.'
        RST 018h
        JR ST1X1
BGETLX:
        EX (SP),HL
        POP BC
        LD DE,BUFER
        CALL GETL
        LD A,(DE)
        CP 01Bh
        JR Z,ST1X1
        JP (HL)

HEXIYX:
        EX (SP),IY
        POP AF
        CALL HLHEX
        JR C,ST1X1
        JP (IY)

GOTOX:
        CALL HEXIYX
        JP (HL)

               
LOADX:
        CALL ?RDI
        JR C,?ERX
        CALL NL
        LD DE,MSG?2                                                      ; 'LOADING '
        RST 018h
        LD DE,NAME
        RST 018h
        XOR A
        LD (BUFER),A
        LD HL,(DTADR)
        LD A,H
        OR L
        JR NZ,LE941
        LD HL,(EXADR)
        LD A,H
        OR L
        JR NZ,LE941
        LD A,0FFh
        LD (BUFER),A
        LD HL,01200h
        LD (DTADR),HL
LE941:
        CALL ?RDD
        JR C,?ERX
        LD A,(BUFER)
        CP 0FFh
        JR Z,LE954
        LD BC,00100h
        LD HL,(EXADR)
        JP (HL)
LE954:
        OUT (0E0h),A
        LD HL,01200h
        LD DE,00000h
        LD BC,(SIZE)
        LDIR
        LD BC,00100h
        JP 00000h

PTESTX:
        LD A,(DE)
        CP '&'                                                           ; plotter test
        JR NZ,PTST1X
PTST0X:
        INC DE
        LD A,(DE)
        CP 'L'                                                           ; 40 in 1 line
        JR Z,.LPTX
        CP 'S'                                                           ; 80 in 1 line
        JR Z,..LPTX
        CP 'C'                                                           ; Pen change
        JR Z,PENX
        CP 'G'                                                           ; Graph mode
        JR Z,PLOTX
        CP 'T'                                                           ; Test
        JR Z,PTRNX
;
PTST1X:
        CALL PMSGX
ST1X2:
        JP ST1X1
.LPTX:
        LD DE,LLPT                                                       ; 01-09-09-0B-0D
        JR PTST1X
..LPTX:
        LD DE,SLPT                                                       ; 01-09-09-09-0D
        JR PTST1X
PTRNX:
        LD A,004h                                                        ; Test pattern
        JR LE999
PLOTX:
        LD A,002h                                                        ; Graph mode
LE999:
        CALL LPRNTX
        JR PTST0X
PENX:
        LD A,01Dh                                                        ; 1 change code (text mode)
        JR LE999
;
;
;       1 char print to $LPT
;
;        in: ACC print data
;
;
LPRNTX:
        LD C,000h                                                        ; RDAX test
        LD B,A                                                           ; print data store
        CALL RDAX
        LD A,B
        OUT (0FFh),A                                                     ; data out
        LD A,080h                                                        ; RDP high
        OUT (0FEh),A
        LD C,001h                                                        ; RDA test
        CALL RDAX
        XOR A                                                            ; RDP low
        OUT (0FEh),A
        RET
;
;       $LPT msg.
;       in: DE data low address
;       0D msg. end
;
PMSGX:
        PUSH DE
        PUSH BC
        PUSH AF
PMSGX1:
        LD A,(DE)                                                        ; ACC = data
        CALL LPRNTX
        LD A,(DE)
        INC DE
        CP 00Dh                                                          ; end ?
        JR NZ,PMSGX1
        POP AF
        POP BC
        POP DE
        RET
;
;       RDA check
;
;       BRKEY in to monitor return
;       in: C RDA code
;
RDAX:
        IN A,(0FEh)
        AND 00Dh
        CP C
        RET Z
        CALL BRKEY
        JR NZ,RDAX
        LD SP,ATRB
        JR ST1X2
;
;       Memory correction
;       command 'M'
;
MCORX:
        CALL HEXIYX                                                      ; correction address
MCORX1:
        CALL NLPHL                                                       ; corr. adr. print
        CALL SPHEX                                                       ; ACC ASCII display
        CALL ?PRTS                                                       ; space print
        CALL BGETLX                                                      ; get data & check data
        CALL HLHEX                                                       ; HLASCII(DE)
        JR C,MCRX3
        CALL DOT4DE                                                      ; INC DE * 4
        INC DE
        CALL _2HEX                                                       ; data check
        JR C,MCORX1
        CP (HL)
        JR NZ,MCORX1
        INC DE
        LD A,(DE)
        CP 00Dh                                                          ; not correction
        JR Z,MCRX2
        CALL _2HEX                                                       ; ACCHL(ASCII)
        JR C,MCORX1
        LD (HL),A                                                        ; data correct
MCRX2:
        INC HL
        JR MCORX1
MCRX3:
        LD H,B                                                           ; memory address
        LD L,C
        JR MCORX1
;
;       Programm save
;
;       cmd. 'S'
;
SAVEX:
        CALL HEXIYX                                                      ; Start address
        LD (DTADR),HL                                                    ; data adress buffer
        LD B,H
        LD C,L
        CALL DOT4DE
        CALL HEXIYX                                                      ; End address
        SBC HL,BC                                                        ; byte size
        INC HL
        LD (SIZE),HL                                                     ; byte size buffer
        CALL DOT4DE
        CALL HEXIYX                                                      ; execute address
        LD (EXADR),HL                                                    ; buffer
        CALL NL
        LD DE,MSGSV                                                      ; 'FILENAME? '
        RST 018h
        CALL BGETLX                                                      ; filename input
        CALL DOT4DE
        CALL DOT4DE
        LD HL,NAME                                                       ; name buffer
SAVX1:
        INC DE
        LD A,(DE)
        LD (HL),A                                                        ; filename trans.
        INC HL
        CP 00Dh                                                          ; end code
        JR NZ,SAVX1
        LD A,OBJCD                                                       ; attribute: OBJ
        LD (ATRB),A
        CALL ?WRI
?ERX1:
        JP C,?ERX
        CALL ?WRD                                                        ; data
        JR C,?ERX1
        CALL NL
        LD DE,MSGOK                                                      ; 'OK!'
        RST 018h
LEA5B:
        JP ST1X

VRFYX:
        CALL ?VRFY
        JP C,?ERX
        LD DE,MSGOK                                                      ; 'OK!'
        RST 018h
        JR LEA5B
LEA6A:
        JP CMY0

SGX:
        LD A,(SWRK)
        RRA
        CCF
        RLA
        LD (SWRK),A
LEA76:
        JR LEA5B

DUMPX:
        CALL HEXIYX
        CALL DOT4DE
        PUSH HL
        CALL HLHEX
        POP DE
        JR C,LEAD6
LEA85:
        EX DE,HL
LEA86:
        LD B,008h
        LD C,017h
        CALL NLPHL
LEA8D:
        CALL SPHEX
        INC HL
        PUSH AF
        LD A,(DSPXY)
        ADD A,C
        LD (DSPXY),A
        POP AF
        CP 020h
        JR NC,LEAA0
        LD A,02Eh
LEAA0:
        CALL ?ADCN
        CALL PRNT3
        LD A,(DSPXY)
        INC C
        SUB C
        LD (DSPXY),A
        DEC C
        DEC C
        DEC C
        PUSH HL
        SBC HL,DE
        POP HL
        JR Z,LEAD3
        LD A,0F8h
        LD (0E000h),A
        NOP
        LD A,(0E001h)
        CP 0FEh
        JR NZ,LEAC7
        CALL ?BLNK
LEAC7:
        DJNZ LEA8D
LEAC9:
        CALL ?KEY
        OR A
        JR Z,LEAC9
        CALL ?BRK
        DB  020h
LEAD3:
        DB  0B2h
      
        JR LEA76
LEAD6:
        LD HL,000A0h
        ADD HL,DE
        JR LEA85

FNINP:
        CALL NL
        LD DE,MSGSV                                                      ; 'FILENAME? '
        RST 018h
        LD DE,BUFER
        CALL GETL
        LD A,(DE)
        CP #1B
        JR NZ,LEAF3
        LD HL,ST1X
        EX (SP),HL
        RET

LEAF3:
        LD B,000h
        LD DE,011ADh
        LD HL,BUFER
        LD A,(DE)
        CP 00Dh
        JR Z,LEB20
LEB00:
        CP 020h
        JR NZ,LEB08
        INC DE
        LD A,(DE)
        JR LEB00
LEB08:
        CP 022h
        JR Z,LEB14
LEB0C:
        LD (HL),A
        INC HL
        INC B
        LD A,011h
        CP B
        JR Z,FNINP
LEB14:
        INC DE
        LD A,(DE)
        CP 022h
        JR Z,LEB1E
        CP 00Dh
        JR NZ,LEB0C
LEB1E:
        LD A,00dh
LEB20:
        LD (HL),A
        RET

LEB22:
        LD A,(0F000h)
        OR A
        RET
               

LEB27:  DB      "IPL IS LOADING ",00Dh
LEB37:  DB      "MAKE READY QD",00Dh
DISCLR: DB      "**  MONITOR 9Z-503M  **",00Dh

;
;====================================
;
;       QUICK DISK LOAD COMMAND
;
;====================================
;
QL:
        CALL IOFRS
        CALL QDRCK                                                       ; Ready check
        JR C,LEBAC
        CALL FNINP                                                       ; Input filename
        CALL HDPCL                                                       ; Head point clear
;
;       Disp 'Loading...'
;
        LD DE,MSG?2                                                      ; 'LOADING '
        RST 018h
;
;       File search
;
FILESH:
        CALL FILSCH
        JR C,LEBAC
;
;       Atribute check
;
        LD A,(ATRB)
        CP OBJCD
        JR NZ,FILESH
;
;
;
DSFLNA:
        LD DE,NAME
        RST 018h

        LD HL,(EXADR)
        LD A,H
        OR L
        JR NZ,LEB8B
        LD HL,(COMNT)
        LD A,H
        OR L
LEB8B:
        JR NZ,LPARA0
        LD A,0FFh
        LD (0113Ah),A



;
;       Iocs parameter set
;
        LD HL,01200h
        JR LPARA1
LPARA0:
        LD HL,(EXADR)
LPARA1:
        LD (QDPC),HL                                                     ; Data adrs set
        LD HL,(DTADR)
        LD (QDPE),HL
        LD HL,00103h                                                     ; Read data block cmd.
        LD (QDPA),HL                                                     ; QDPA = 3 (read from headpoint)
                                                                         ; QDPB = 1 (data should be read)
;
;       Read data block
;
        CALL QDIOS                                                       ; QD iocs
LEBAC:
        JP C,QER04
        LD A,(0113Ah)
        CP 0FFh
        JR Z,LEBBD
;
;       Exec load file
;
        LD BC,00300h
        LD HL,(COMNT)
        JP (HL)

LEBBD:
        OUT (0E0h),A
        LD HL,01200h
        LD DE,00000h
        LD BC,(DTADR)
        LDIR
        LD BC,00300h
        JP 00000h

;
;       Iocs flag reset
;
IOFRS:
        XOR A
        LD (MTF),A                                                       ; Motor Flag = 0 (OFF)
        LD (FNUPS),A                                                     ; File number flag = 0
        LD (FNUPF),A                                                     ; File number up flag = 0
        RET

;
;
;       File search sub.
;
;
FILSCH:
;
;       Iocs parameter set
;
        LD HL,00003h                                                     ; read from headpoint
        LD (QDPA),HL                                                     ; QDPA = 3 (read from head point)
                                                                         ; QDPB = 0 (header should be read)
        LD HL,ATRB                                                       ; Head adrs
        LD (QDPC),HL
        LD HL,00040h                                                     ; Read size
        LD (QDPE),HL

;
;       Read information block
;
QLINF:
        CALL QDIOS
        RET C
;
;       File name check
;
        LD A,(BUFER)
        CP 00Dh
        RET Z
        LD HL,BUFER
        LD DE,NAME
        LD B,NAMSIZ
LDFNCK:
        LD A,(DE)
        CP (HL)
        JR NZ,QLINF
        CP 00Dh
        RET Z
        INC DE
        INC HL
        DJNZ LDFNCK
        RET
;
;       Quick disk ready check
;
QDRCK:
        XOR A
        LD (QDPB),A                                                      ; QDPB = 0 -> only Ready check
        INC A
        LD (QDPA),A                                                      ; QDPA = 1
        CALL QDIOS
        RET
;
;======================================
;
;       Quick disk directory command
;
;======================================
;
QD:
        CALL IOFRS
        CALL QDRCK
        JR C,QER04
        CALL HDPCL
        LD B,000h
;
;       Disp 'Directory of QD:'
;
        LD DE,DIRMSG
        RST 018h
;
;       Iocs parameter set
;
        LD HL,QDIRBF
DIRIOP:
        LD (QDPC),HL
        LD HL,00003h
        LD (QDPA),HL                                                     ; QDPA = 3 (read from headpoint)
                                                                         ; QDPB = 0 (header should be read)
        LD HL,00040h
        LD (QDPE),HL                                                     ; QDPE = 64 (header length)
;
;       Read information block
;
        PUSH BC
        CALL QDIOS
        POP BC
        JR C,DIREFC
        INC B
;
;       Buffer adrs increment
;
        LD HL,(QDPC)
        LD DE,PRNT
        ADD HL,DE
        JR DIRIOP
;
;       End file check
;
DIREFC:
        CP NTFECD
        JR Z,DIRMTF
        SCF
QER04:
        JR C,QERTRT
;
;       Motor off
;
DIRMTF:
        LD A,006h                                                        ; Motor off command
        LD (QDPA),A
        PUSH BC
        CALL QDIOS
        POP BC
;
;       No file check
;
        XOR A
        CP B
        JR NC,QDOKM
;
;       Directory disp
;
        CALL NL
        LD HL,QDIRBF
;
;       Disp atribute
;
DSPATR:
        LD A,(HL)
        LD DE,MSGQ01
        DEC A
        JR Z,LECA4
        LD DE,MSGQ02
        DEC A
        JR Z,LECA4
        LD DE,MSGQ03
        DEC A
        JR Z,LECA4
        LD DE,MSGQ04
        DEC A
        JR Z,LECA4
        LD DE,MSGQ05
        DEC A
        JR Z,LECA4
        DEC A
        JR Z,LECA1
        LD DE,MSGQ07
        DEC A
        JR Z,LECA4
        DEC A
        JR Z,LECA1
        DEC A
        JR Z,LECA1
        LD DE,MSGQ10
        DEC A
        JR Z,LECA4
        LD DE,MSGQ11
        DEC A
        JR Z,LECA4
LECA1:
        LD DE,MSGQ??
LECA4:
        RST 018h
;
;       Disp file name
;
LECA5:
        LD A,'"'
        CALL PRNT
        INC HL
        PUSH HL
        POP DE
        RST 018h
        LD A,'"'
        CALL PRNT
        CALL NL
;
;       Counter decrement
;
LECB6:
        LD DE,00011h
        ADD HL,DE
LECBA:
        CALL ?KEY
        OR A
        JR Z,LECBA
        CALL ?BRK
        JP Z,ST1X
        DJNZ DSPATR

QDOKM:
        CALL NL
        LD DE,MSGQOK
        RST 018h
        JP ST1X

;
;======================================
;
;       Error treatment
;
;=====================================
;
QERTRT:
        LD DE,MGNFE                                                      ; 'Not Found err'
        CP NTFECD                                                        ; Not found err
        JR Z,QERMF
        LD DE,MGNRE                                                      ; 'Not ready'
        CP QNTRCD                                                        ; Not ready
        JR Z,QERMF
        LD DE,MGUFE                                                      ; 'Unformat'
        CP UNFMCD                                                        ; Unformat err
        JR Z,QERMF
        LD DE,MSGTRM
        CP BRKCD                                                         ; Break
        JR Z,QERMF
        LD DE,MGHDE                                                      ; 'Hard error'
;
;       Motor off
;
QERMF:
        LD A,006h                                                        ; Motor off cmd.
        LD (QDPA),A
        CALL QDIOS
        CALL HDPCL
;
LECFC:
        LD A,(QDCPA)
        RRA
        RET C                                                            ; Boot err
        CALL NL
        RST 018h
        JP ST1X
;
;       Header point clear
;
HDPCL:
        LD A,005h                                                        ; Head point clear cmd.
        LD (QDPA),A
        CALL QDIOS
        RET

;
;======================================
;
;       Message table
;
;======================================
;
MSGQOK: DB      "OK!"
MSGTRM: DB      00Dh
MGNFE:  DB      "QD:FILE NOT FOUND",00Dh
MGHDE:  DB      "QD:HARD ERR",00Dh
MGNRE:  DB      "QD:NOT READY",00Dh
MGUFE:  DB      "QD:UNFORMAT",00Dh
LED4C:  DB      "QD:FILE MODE ERR",00Dh
DIRMSG: DB      "DIRECTORY OF QD:",00Dh
MSGQ01: DB      "    OBJ   ",00Dh
MSGQ02: DB      "    BTX   ",00Dh
MSGQ03: DB      "    BSD   ",00Dh
MSGQ04: DB      "    BRD   ",00Dh
MSGQ05: DB      "    RB    ",00Dh
MSGQ07: DB      "    LIB   ",00Dh
MSGQ10: DB      "    SYS   ",00Dh
MSGQ11: DB      "    GR    ",00Dh
MSGQ??: DB      "    ???   ",00Dh


QDIOS1:
        LD A,005h                                                        ; Retry 4
        LD (RTYF),A
;
RTY:
        DI
        CALL QMEIN
        EI
        RET NC
        PUSH AF
        CP 028h
        JR Z,RTY4
        CALL MTOF
        POP AF
        PUSH AF
        CP 029h
        JR NZ,RTY4
        LD HL,RTYF
        DEC (HL)
        JR Z,LEDF3
        POP AF
        JR RTY
LEDF3:
        CALL QDHPC
RTY4:
        POP AF
        RET

QMEIN:
        LD (RETSP),SP
        LD A,(QDPA)
        DEC A                                                            ; ready check           (1)
        JR Z,QDRC
        DEC A                                                            ; format                (2)
                                                                         ; not implemented
        DEC A                                                            ; read from headpoint   (3)
        JR Z,QDRD
        DEC A                                                            ; save from headpoint   (4)
                                                                         ; not implemented
        DEC A                                                            ; headpoint clear       (5)
        JR Z,QDHPC
        JP MTOF                                                          ; else motor off
;
;======================================
;
;       Head Point Clear
;
;======================================
;
QDHPC:
        PUSH AF
        XOR A
        LD (HDPT),A
        POP AF
        RET
;
;=================================
;
;       Ready Check
;
;=================================
;
QDRC:
        LD A,(QDPB)                                                      ; QDPB = 0 -> only Ready check
        JP QREDY
;
;=================================
;
;       Read
;
;=================================
;
QDRD:
        LD A,(MTF)                                                       ; A = Motor Flag
        OR A                                                             ; test Motor Flag
        CALL Z,MTON                                                      ; if Motor Flag = 0 then Motor On and go to home position
        CALL HPS                                                         ; head point search
        RET C
        CALL BRKC                                                        ; check break key
;
        CALL RDATANRCK                                                   ; read low-byte blocksize
        LD C,A
        CALL RDATANRCK                                                   ; read high-byte blocksize
        LD B,A
        LD HL,(QDPE)
        SBC HL,BC                                                        ;
        JP C,IOE41
        LD HL,(QDPC)
;
; Block Data Read
;
BDR:
        CALL RDATANRCK                                                   ; read data
        LD (HL),A                                                        ; save it
        INC HL                                                           ; inc address
        DEC BC                                                           ; dec counter
        LD A,B
        OR C
        JR NZ,BDR                                                        ; counter not zero than read again
        CALL RDCRC                                                       ; read checksum (3 bytes)
        LD A,(QDPB)
        BIT 0,A
        JP NZ,MTOF
        RET
;
; Head Point Search
;
HPS:
        LD HL,FNB                                                        ; HL = next file number
        DEC (HL)
        JR Z,HPNFE                                                       ; Not found
        CALL SYNCL2                                                      ; read 2 bytes last is in A
        LD C,A                                                           ; BLocKFLaG => C reg
        LD A,(HDPT)                                                      ; A = destination head point position
        LD HL,HDPT0                                                      ; HL = address of the actual head point position
        CP (HL)                                                          ; Search ok ?
        JR NZ,HPS1                                                       ; no, than make dummy block read
        INC A                                                            ; HDPT count up
        LD (HDPT),A
        LD (HL),A                                                        ; HDPT0 count up
        LD A,(QDPB)                                                      ; A = filetype to load
        XOR C                                                            ; xor with BLocKFLaG which
        RRA
        RET NC                                                           ; same, than ret else ...
;
; Dummy read
;
DMR:
        CALL RDATANRCK                                                   ; read size low byte
        LD C,A
        CALL RDATANRCK                                                   ; read size high byte
        LD B,A
;
DMR1:                                                                    ; read size bytes
        CALL RDATANRCK
        DEC BC
        LD A,B
        OR C
        JR NZ,DMR1
        CALL RDCRC                                                       ; read checksum (3 bytes)
        JR HPS                                                           ; next
;
HPS1:
        INC (HL)                                                         ; increment actual head point position
        JR DMR
;
HPNFE:
        LD A,NTFECD                                                      ; Not Found
        SCF
        RET



;
; Ready & Write protect
;       ACC = 0 : Ready check
;       ACC = 1 : & Write Protect
;
QREDY:
        LD B,A                                                           ; save command
        LD A,002h
        OUT (SIOBC),A                                                    ; select register 2 (IV)
        LD A,081h
        OUT (SIOBC),A                                                    ; write 81h in register 2
        LD A,002h
        OUT (SIOBC),A                                                    ; select register 2 (IV)
        IN A,(SIOBC)                                                     ; read back register 2
        AND 081h
        CP 081h
        JP NZ,IOE50                                                      ; Not ready
        LD A,010h
        OUT (SIOAC),A                                                    ; NULL CODE, RESET EXT/STATUS INT, REGISTER 0
        IN A,(SIOAC)
        LD C,A                                                           ; save Read Register 0
        AND 008h                                                         ; test DCD (HeadSet)
        JP Z,IOE50                                                       ; Not ready
        LD A,B                                                           ; restore command
        OR A                                                             ; if command = 0 then
        RET Z                                                            ; return
        LD A,C                                                           ; else restore Read Register 0
        AND 020h                                                         ; test CTS (WriteProtect)
        RET NZ                                                           ; if CTS then not protected, return
        JP IOE46                                                         ; else Write protect

;
;
; MTON -- QD MOTOR ON
;         READ FILE NUMBER
;         READ & CHECK CRC,FLAG
;
MTON:
        LD HL,SIOLD                                                      ; SIO Load Data
        LD B,00Bh
        CALL LSINT                                                       ; load SIO init and motor on and go to home position

        CALL SYNCL1                                                      ; search for sync and read first 2 bytes, last is in A
        LD (FNA),A                                                       ; save actual file no in File Number A
        INC A
        LD (FNB),A                                                       ; save next file no in File Number B
        CALL RDCRC                                                       ; read checksum (3 bytes)
FNEND:
        LD HL,SYNCF
        SET 3,(HL)                                                       ; set bit3 of SyncFlags
        XOR A                                                            ; A = 0
        LD (HDPT0),A                                                     ; actual head point position = 0
        RET
;
;       sio initial
;
LSINT:
        LD C,SIOAC
        OTIR
        LD A,005h                                                        ; 00000101
        LD (MTF),A                                                       ; MoTor Flag = 5
        OUT (SIOBC),A                                                    ; ch B select register 5
        LD A,080h                                                        ; 10000000
        OUT (SIOBC),A                                                    ; set DTR_B (Motor On), clear RTS_B

LREDY:                                                                   ; check for ready and if so, than goto home position
        LD A,010h                                                        ; 00010000
        OUT (SIOAC),A                                                    ; reset ext/status interrupts, set register 0
        IN A,(SIOAC)                                                     ; read register 0
        AND 008h                                                         ; test DCD_A (disk inside ?)
        JP Z,IOE50                                                       ; Not ready
        CALL BRKC                                                        ; BReak Key Check
        LD A,010h                                                        ; 00010000
        OUT (SIOBC),A                                                    ; reset ext/status interrupts, set register 0
        IN A,(SIOBC)                                                     ; read register 0
        AND 008h                                                         ; test DCD_B (Home)
        JR Z,LREDY
        LD BC,000E9h                                                     ; wait 160ms
        JP TIMW

;
; Motor off
;
QDOFF:                                                                   ; basic call
MTOF:
        PUSH AF
        LD A,005h
        OUT (SIOAC),A                                                    ; select Write Register 5
        LD A,060h                                                        ; 01100000
        OUT (SIOAC),A                                                    ; DTR OFF (Motor Off), Tx DISABLE, RTS OFF (WRGA)
        LD A,005h
        OUT (SIOBC),A                                                    ; select Write Register 5
        XOR A                                                            ; 00000000
        LD (MTF),A                                                       ; Motor Flag = 0
        OUT (SIOBC),A                                                    ; DTR OFF (Motor Off), clear  RTS_B
        POP AF
        RET

;
; SYNCL1 -- LOAD F.N SYNC ONLY
;                (SEND BREAK 110ms)
; SYNCL2 -- LOAD FIRST FILE SYNC
;                (SEND BREAK 110ms)
;
SYNCL2:
        LD A,058h                                                        ; 01011000
                                                                         ; RESET Rx CRC CHECKER, CHANNEL RESET, REGISTER 0
        LD B,00Bh                                                        ; 11 values to load
        LD HL,SIOLD
        CALL SYNCA
        LD HL,SYNCF
        BIT 3,(HL)                                                       ; test bit3 of SyncFlags
        LD BC,00003h                                                     ; WAIT 2ms
        JR Z,TMLPL
        RES 3,(HL)                                                       ; reset bit3 of SyncFlags
SYNCL1:
        ld bc,000a0h                                                     ; WAIT 110ms
;
TMLPL:                                                                   ; the motor is switched on
                                                                         ; and a hunt phase is initiated,
                                                                         ; that means the incoming datastream
                                                                         ; is inspected for the programmed 
                                                                         ; sync characters
        CALL TIMW
        LD A,005h
        OUT (SIOBC),A                                                    ; select Write Register 5
        LD A,082h                                                        ; 10000010
        OUT (SIOBC),A                                                    ; DTR ON (Motor On), RTS ON ()
        LD A,003h
        OUT (SIOAC),A                                                    ; select Write Register 3
        LD A,0D3h                                                        ; 11010011
        OUT (SIOAC),A                                                    ; RX 8 BIT, ENTER HUNT PHASE, SYNC, Rx ENABLE
        LD BC,02CC0h                                                     ; 220ms timeout
;
SYNCW0:                                                                  ; now the datastream is inspected
                                                                         ; also a timeout is checked
        LD A,010h
        OUT (SIOAC),A                                                    ; RESET EXT/STATUS INT, select Register 0
        IN A,(SIOAC)
        AND 010h                                                         ; test SYNC/HUNT
        JR Z,SYNCW1                                                      ; first 2 syncbytes found
        DEC BC
        LD A,B
        OR C
        JR NZ,SYNCW0
        JP IOE54                                                         ; unformatted
;
SYNCW1:                                                                  ; now we should ignore further sync characters
        LD A,003h
        OUT (SIOAC),A                                                    ; select Write Register 3
        LD A,0C3h                                                        ; 11000011
        OUT (SIOAC),A                                                    ; Rx 8 BIT, SYNC CHAR LOAD INHIBIT, Rx ENABLE
        LD B,09Fh                                                        ; timeout
;
SYNCW2:
                                                                         ; loop for find the end of syncbytes:
                                                                         ; rx available is only set if the first
                                                                         ; byte is found which is not a syncbyte
        LD A,010h
        OUT (SIOAC),A                                                    ; NULL CODE, RESET EXT/STATUS INT, REGISTER 0
        IN A,(SIOAC)
        AND 001h                                                         ; test Rx CHARACTER AVAILABLE
        JR NZ,SYNCW3
        DEC B
        JR NZ,SYNCW2
SYNCW01:
        JP IOE54                                                         ; unformated
;
SYNCW3:                                                                  ; now the datastream is in sync and the
                                                                         ; first real data is ready to read
        LD A,003h
        OUT (SIOAC),A                                                    ; select Write Register 3
        LD A,0C9h                                                        ; 11001001
        OUT (SIOAC),A                                                    ; Rx 8 BIT, Rx CRC ENABLE, Rx ENABLE
        CALL RDATANRCK
        JP RDATANRCK

;
;
;
SYNCA:
        LD C,SIOAC
        OUT (C),A
        LD A,005h
        OUT (SIOBC),A                                                    ; select Write Register 5
        LD A,080h
        OUT (SIOBC),A                                                    ; set DTR_B (Motor On), clear RTS_B
        OTIR
        RET

;
;       RDCRC -- READ CRC & CHECK
;
RDCRC:
        LD B,003h                                                        ; 3 retries
RDCR1:
        CALL RDATANRCK                                                   ; read 3 bytes
        DJNZ RDCR1
RDCR2:                                                                   ; read REGISTER 0
        IN A,(SIOAC)
        RRCA                                                             ; test Rx CHARACTER AVAILABLE
        JR NC,RDCR2                                                      ; Rx Available
        LD A,001h                
        OUT (SIOAC),A                                                    ; select REGISTER 1
        IN A,(SIOAC)                                                     ; read REGISTER 1
        AND 040h                                                         ; test CRC ERROR
        JR NZ,IOE41                                                      ; Hard err
        OR A
        RET

RDATANRCK:
NRCK:
        LD A,010h
        OUT (SIOAC),A                                                    ; reset ext/status interrupts, set register 0
        IN A,(SIOAC)                                                     ; read register 0
        AND 008h                                                         ; test DCD (HeadSet)
        JP Z,IOE50                                                       ; Not Ready
;
;       Read data (1 chr)
;
RDATA:
        IN A,(SIOAC)                                                     ; read REGISTER 0
        RLCA
        JR C,IOE41                                                       ; test BREAK/ABORT (Hard Err)
        RRCA
        RRCA
        JR NC,NRCK                                                       ; test Rx AVAILABLE
        IN A,(SIOAD)                                                     ; read data
        OR A
        RET
               
;
;       i/o err
;
IOE41:
        LD A,HDERCD                                                      ; Hard err
        DB 021h
IOE46:
        LD A,WPRTCD                                                      ; Write protect
        DB 021h
IOE50:
        LD A,QNTRCD                                                      ; Not ready
        DB 021h
IOE53:
        LD A,NFSECD                                                      ; No file space
        DB 021h
IOE54:
        LD A,UNFMCD                                                      ; Unformat
        LD SP,(RETSP)
        SCF
        RET
               

;
;       wait timer
;
;
;       BC = 0001H =   0.7ms (  0.704ms)
;            0003H =   2.0ms (  2.107ms)
;            001DH =  20.0ms ( 19.938ms)
;            00A0H = 110.0ms (110.050ms)
;            00E9H = 160.0ms (160.140ms)
;            0140H = 220.0ms (219.940ms)
;
;
TIMW:
        PUSH AF
TIMW1:
        LD A,086h
TIMW2:
        DEC A
        JR NZ,TIMW2
        DEC BC
        LD A,B
        OR C
        JR NZ,TIMW1
        POP AF
        RET

;
;
;
; SIO CH A COMMAND CHAIN
;
; SIOLD -- LOAD INIT. DATA
;
;
;
; BiSync mode, uses 16h and 16h as sync characters
; the SIO works also in polling mode, no interrupt is generated
;
SIOLD:
        DB      058h                                                     ; RESET Rx CRC CHECKER, CHANNEL RESET
        DB      004h                                                     ; select Write Register 4
        DB      010h                                                     ; X1 CLOCK mode, 16 bit sync char, sync mode, no parity
        DB      005h                                                     ; select Write Register 5
        DB      004h                                                     ; CRC-16
        DB      003h                                                     ; select Write Register 3
        DB      0D0h                                                     ; RX 8 BITS, AUTO ENABLES, ENTER HUNT PHASE
        DB      006h                                                     ; select Write Register 6
        DB      016h                                                     ; set SYNC CHR(1)
        DB      007h                                                     ; select Write Register 7
        DB      016h                                                     ; set SYNC CHR(2)


;
;
; BREAK CHECK
;
BRKC:
        LD A,0E8h
        LD (0E000h),A
        NOP
        LD A,(0E001h)
        AND 081h
        RET NZ
        LD SP,(RETSP)
        SCF
        RET
               
        ld l,#41

; the following is only to get the original length of 4096 bytes
ALIGN:  MACRO ?boundary
        DS    ?boundary - 1 - ($ + ?boundary - 1) % ?boundary, 0FFh
        ENDM

        ALIGN 0F7FFh
        DB      0FFh
