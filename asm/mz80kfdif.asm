;
; MZ-80K FDC ROM
;
		ORG	F000H
F000  00        NOP     
F001  F3        DI      
F002  AF        XOR     A
F003  329C11    LD      (#119C),A	;clock off
F006  3EC3      LD      A,#C3		;JP code for error trap
F008  320B10    LD      (#100B),A
F00B  215AF0    LD      HL,#F05A	;error can't boot
F00E  220C10    LD      (#100C),HL	;error trap
F011  11F09F    LD      DE,#9FF0	;transfer 9 bytes from
F014  2187F0    LD      HL,#F087	;ROM to RAM for use
;
;IBT1
;
F017  010900    IBT1:	LD      BC,#0009 ;by (IX+D) in reader
F01A  EDB0      LDIR    
F01C  CD0900    CALL    CRLF		;NL
F01F  117AF0    LD      DE,MESS1
F022  CD1500    CALL    MESSAGE		;msg "BOOT DRIVE ?"
F025  11009F    LD      DE,BUFF2
F028  CD0300    CALL    USER		;get line
F02B  210C00    LD      HL,#000C
F02E  19        ADD     HL,DE		;skip around msg
F02F  7E        LD      A,(HL)		;pickup answer to prompt
F030  FE0D      CP      #0D		;CR ?
F032  2002      JR      NZ,#F036        ;Z=CR assume drive 1
F034  3E31      LD      A,#31		;ASCII for 1
;
;IBT2
;
F036  47        IBT2:	LD      B,A	;save driveno
F037  E6F0      AND     #F0		;take ASCII and convert
F039  FE30      CP      #30		;to numeric having
F03B  20DF      JR      NZ,IBT1		;checked >1 & <=4
F03D  78        LD      A,B		;get driveno
F03E  E60F      AND     #0F		;mask
F040  3D        DEC     A		;-1 00-03
F041  FE04      CP      #04
F043  30D7      JR      NC,IBT1		;dud key, >=4, try again
F045  32F09F    LD      (#9FF0),A	;save drive no
F048  321110    LD      (#1011),A	;save drive no
F04B  DD21F09F  LD      IX,#9FF0	;IX pointer to fdc parameters at 9FF0
					;ready for disk read
F04F  CD3BF1    CALL    READER		;get boot records
F052  3A0098    LD      A,(#9800)	;1st byte of input buffer of boot records
F055  FEC3      CP      #C3		;jump cmd?
F057  CA0098    JP      Z,#9800		;yes, execute to 9800
;
;IBT3
;
F05A  31F010 	IBT3:   LD      SP,#10F0 ;no, reset stack
F05D  CD0900    CALL    CRLF		;NL
F060  116CF0    LD      DE,MESS2	;msg can't boot
F063  CD1500    CALL    MESSAGE
F066  CDA7F0    CALL    MOTOFF		;motor off
F069  C38200    JP      MAINLP		;warm start, ret to monitor
;
;MESS2
;
F06C  45523A43	MESS2:	DB	"ER:CAN'T BOOT"
F070  414E2754
F074  20424F4F
F078  54
F079  0D	DB	0DH
;
;MESS1
;
F07A  424F4F54	DB	"BOOT DRIVE ?"
F07E  20445249
F082  5645203F
F086  0D	DB	0DH
;
;DDATA
;fdc parameters
;
F087  00	DB	00H		;drive no-1
F088  00	DB	00H		;trk*2 remainder = head
F089  01	DB	01H		;sector no (range: 01 - 10)
F08A  00	DB	00H		;$80 = add 1 record to read to (F08B)
F08B  0700	DB	07H		;07H = 07*2 = 14 sectors to read, add 1 if (F08A = $80)
F08D  0098	DB	00H,98H		;9800H = load addr.
F08F  00	DB	00H		;no meaning
;
;MOTON
;
F090  C5        MOTON:	PUSH    BC	;starts motors
F091  01F808    LD      BC,#08F8
F094  ED78      IN      A,(C)		;start motor
F096  010000    LD      BC,#0000
;
;WAIT1
;
F099  0B        WAIT1:	DEC     BC	;wait for motor to
F09A  00        NOP     		;get up to speed
F09B  00        NOP     
F09C  78        LD      A,B
F09D  B1        OR      C
F09E  20F9      JR      NZ,WAIT1
F0A0  3E01      LD      A,#01
F0A2  320210    LD      (MOTFLG),A	;01=on 00=off
F0A5  C1        POP     BC
F0A6  C9        RET     
;
;MOTOFF
;
F0A7  C5        MOTOFF:	PUSH    BC	;stop motors
F0A8  CDAEF1    CALL    LNGDEL		;timed wait
F0AB  01F800    LD      BC,#00F8
F0AE  ED78      IN      A,(C)
F0B0  C1        POP     BC
F0B1  C9        RET     
;
;SKZERO
;
F0B2  CDBDF0    SKZERO:	CALL    DREADY	;seek track 0
F0B5  AF        XOR     A
F0B6  D3F9      OUT     (#F9),A		;clear track reg
F0B8  320010    LD      (#1000),A
F0BB  D3FA      OUT     (#FA),A		;send seek zero code
;
;DREADY
;
F0BD  C5        DREADY:	PUSH    BC
F0BE  010000    LD      BC,#0000
;
;DRY1
;
F0C1  DBF9      DRY1:	IN      A,(#F9)	;get DRDY, CRDY, RQM
F0C3  E603      AND     #03		;leave DRDY, CRDY
;
;DRY2
;
F0C5  FE02      DRY2:	CP      #02	;wait for DRDY & CRDY
F0C7  2002      JR      NZ,WAIT2        ;no, =03
F0C9  C1        POP     BC		;yes, =02
F0CA  C9        RET     
;
;WAIT2
;
F0CB  0B        WAIT2:	DEC     BC
F0CC  78        LD      A,B
F0CD  B1        OR      C
F0CE  20F1      JR      NZ,DRY1
F0D0  C1        POP     BC
F0D1  3E32      LD      A,#32
F0D3  320810    LD      (#1008),A	;error 40 (not found)
F0D6  C30B10    JP      #100B		;error can't boot
;
;STATUS
;
F0D9  DBFA      STATUS:	IN      A,(#FA)	;read status
F0DB  E6F0      AND     #F0
F0DD  07        RLCA    
F0DE  30F9      JR      NC,STATUS	;wait for CRDY
F0E0  E6F0      AND     #F0		;mask leave CRDY, S1, S2, S3
F0E2  0F        RRCA    		;move right until S§
F0E3  0F        RRCA    		;is in B0
F0E4  0F        RRCA    
F0E5  0F        RRCA    
F0E6  B7        OR      A		;clear flags
F0E7  C8        RET     Z		;Z=ok
F0E8  FE0C      CP      #0C		;0C=drive not ready etc.
F0EA  2004      JR      NZ,STS1
F0EC  3E32      LD      A,#32		;error code 40 (not found)
F0EE  180A      JR      STS3
;
STS1
;
F0F0  FE04      STS1:	CP      #04	;04=ID not found
F0F2  2004      JR      NZ,STS2
F0F4  3E36      LD      A,#36		;error code 54 (unformat error)
F0F6  1802      JR      STS3
;
;STS2
;
F0F8  3E29      STS2:	LD      A,#29	
F0FA  320810    LD      (#1008),A	;error code 41 disk hw error
F0FD  37        SCF     
F0FE  C9        RET     
;
;PRMDRV
;
F0FF  C5        PRMDRV:	PUSH    BC	;prime drive
F100  E5        PUSH    HL
F101  CD90F0    CALL    MOTON
F104  DD7E00    LD      A,(IX+#00)	;get drive no-1
F107  E603      AND     #03		;form drive code
F109  F61C      OR      #1C		;set TND, MOTOR, SELECT BIT
F10B  320110    LD      (#1001),A	;keep drive code
F10E  E60F      AND     #0F		;mask out TND
F110  47        LD      B,A
F111  0EF8      LD      C,#F8
F113  ED60      IN      H,(C)		;select drive
F115  3E32      LD      A,#32
;
;PRM1
;
F117  CDAEF1    PRM1:	CALL    LNGDEL	;wait for head
F11A  3D        DEC     A		:to load
F11B  20FA      JR      NZ,PRM1
F11D  010000    LD      BC,#0000
;
;PRM2
;
F120  DBF9      PRM2:	IN      A,(#F9)	;get DRDY, CRDY, RQM
F122  E607      AND     #07		;mask out RUBBISH
F124  FE06      CP      #06		;DRDY & CRDY ?
F126  2006      JR      NZ,PRM3		;NZ=no, keep trying
F128  CDB2F0    CALL    SKZERO
F12B  E1        POP     HL
F12C  C1        POP     BC
F12D  C9        RET     		;correct exit
;
;PRM3
;
F12E  0B        PRM3:	DEC     BC
F12F  78        LD      A,B
F130  B1        OR      C
F131  20ED      JR      NZ,PRM2
F133  3E32      LD      A,#32
F135  320810    LD      (#1008),A	;error 40 (not found)
F138  C30B10    JP      #100B		;abort; error can't boot
;
;READER
;
F13B  3E0A      READER:	LD      A,#0A	;no. of tries
F13D  320710    LD      (#1007),A
;
;RDR1
;
F140  CDFFF0    RDR1:	CALL    PRMDRV
F143  3A0110    LD      A,(#1001)	;keep drive in use
F146  47        LD      B,A
F147  0EF8      LD      C,#F8
F149  D9        EXX     		;save all regs
F14A  0EFB      LD      C,#FB		;port fb??
F14C  DD5E03    LD      E,(IX+#03)	;no meaning
F14F  DD5604    LD      D,(IX+#04)	;get half of numbers to read (7)
F152  CB13      RL      E		;B7 to carry
F154  CB12      RL      D		;double number of sectors (14), add carry
F156  1E03      LD      E,#03		;no meaning
F158  DD6E05    LD      L,(IX+#05)	;get loading address lo
F15B  DD6606    LD      H,(IX+#06)	;hi into HL
F15E  CDBDF0    CALL    DREADY
F161  AF        XOR     A		;no meaning
F162  DD7E01    LD      A,(IX+#01)	;get track to read
F165  1F        RRA     		;divide by 2, remainder to carry = head no.
F166  D3F9      OUT     (#F9),A		;send track to FDC
F168  DD7E02    LD      A,(IX+#02)	;sector number
F16B  3002      JR      NC,RDR2
F16D  F680      OR      #80		;odds/evens for side code
;
;RDR2
;
F16F  D3F8      RDR2:	OUT     (#F8),A	;send sect+side
F171  CDA6F1    CALL    SHTDEL		;short delay
F174  3E70      LD      A,#70		;seek & read code
F176  320010    LD      (#1000),A	;keep it
F179  F3        DI      
F17A  D3FA      OUT     (#FA),A		;send seek & read code to FDC
;
;RDR3
;
F17C  0680      RDR3:	LD      B,#80	;128 bytes/sector
;
;RDR4
;
F17E  DBF9      RDR4:	IN      A,(#F9)	;get DRDY, CRDY, RQM
F180  A3        AND     E		;mask with 03
F181  28FB      JR      Z,RDR4		;wait for either CRDY/RQM
F183  0F        RRCA    		;RQM into carry
F184  300C      JR      NC,RDR5		;NC=no RQM
F186  EDA2      INI 			;get data. port FB to (HL), B=B-1   
F188  C27EF1    JP      NZ,RDR4		;do whole sector
F18B  15        DEC     D		;dec sector counter
F18C  C27CF1    JP      NZ,RDR3		;NZ=more to do
F18F  D9        EXX     		;restore all regs
F190  ED78      IN      A,(C)		;send TND high
;
;RDR5
;
F192  CDD9F0    RDR5:	CALL    STATUS
F195  D0        RET     NC		;NC=good read
F196  3A0710    LD      A,(#1007)
F199  3D        DEC     A		;A try gone
F19A  320710    LD      (#1007),A	;counter 10times
F19D  CA0B10    JP      Z,#100B		;can't read at all abort
F1A0  CDB2F0    CALL    SKZERO
F1A3  C340F1    JP      RDR1
;
;SHTDEL
;
F1A6  F5        SHTDEL:	PUSH    AF
F1A7  3E0A      LD      A,#0A
;
;SDY1
;
F1A9  3D        SDY1:	DEC     A
F1AA  20FD      JR      NZ,SDY1
F1AC  F1        POP     AF
F1AD  C9        RET     
;
;LNGDEL
;
F1AE  F5        LNGDEL:	PUSH    AF	;long delay
F1AF  3E0A      LD      A,#0A
;
;LDY1
;
F1B1  CDA6F1    LDY1:	CALL    SHTDEL
F1B4  3D        DEC     A
F1B5  20FA      JR      NZ,LDY1
F1B7  F1        POP     AF
F1B8  C9        RET 

CRLF:		EQU	00009H
MESSAGE:	EQU	00015H
BUFF2:		EQU	9F00H
USER:		EQU	00003H
MAINLP:		EQU	00082H
MOTFLG:		EQU	1002H
		END
    
;
;no meaning !!
;
F1B9  13        INC     DE
F1BA  1B        DEC     DE
F1BB  72        LD      (HL),D
F1BC  DE42      SBC     A,#42
F1BE  FB        EI      
F1BF  2F        CPL     
F1C0  58        LD      E,B
F1C1  43        LD      B,E
F1C2  7C        LD      A,H
F1C3  52        LD      D,D
F1C4  3023      JR      NC,#F1E9        ; (35)
F1C6  71        LD      (HL),C
F1C7  42        LD      B,D
F1C8  1020      DJNZ    #F1EA           ; (32)
F1CA  74        LD      (HL),H
F1CB  40        LD      B,B
F1CC  43        LD      B,E
F1CD  03        INC     BC
F1CE  51        LD      D,C
F1CF  00        NOP     
F1D0  3C        INC     A
F1D1  42        LD      B,D
F1D2  D8        RET     C
F1D3  60        LD      H,B
F1D4  FB        EI      
F1D5  09        ADD     HL,BC
F1D6  FC402C    CALL    M,#2C40
F1D9  80        ADD     A,B
F1DA  79        LD      A,C
F1DB  2A4940    LD      HL,(#4049)
F1DE  4D        LD      C,L
F1DF  EE3E      XOR     #3E
F1E1  B2        OR      D
F1E2  1EA2      LD      E,#A2
F1E4  58        LD      E,B
F1E5  02        LD      (BC),A
F1E6  58        LD      E,B
F1E7  12        LD      (DE),A
F1E8  02        LD      (BC),A
F1E9  43        LD      B,E
F1EA  02        LD      (BC),A
F1EB  220002    LD      (#0200),HL
F1EE  2D        DEC     L
F1EF  4B        LD      C,E
F1F0  5A        LD      E,D
F1F1  0A        LD      A,(BC)
F1F2  40        LD      B,B
F1F3  4A        LD      C,D
F1F4  13        INC     DE
F1F5  42        LD      B,D
F1F6  45        LD      B,L
F1F7  0A        LD      A,(BC)
F1F8  5B        LD      E,E
F1F9  6E        LD      L,(HL)
F1FA  6A        LD      L,D
F1FB  4E        LD      C,(HL)
F1FC  4E        LD      C,(HL)
F1FD  4E        LD      C,(HL)
F1FE  5D        LD      E,L
F1FF  7E        LD      A,(HL)
F200  3011      JR      NC,#F213        ; (17)
F202  DD300E    JR      NC,#F213        ; (14)
F205  067E      LD      B,#7E
F207  FE3A      CP      #3A
F209  CAC221    JP      Z,#21C2
F20C  12        LD      (DE),A
F20D  23        INC     HL
F20E  13        INC     DE
F20F  0D        DEC     C
F210  C20622    JP      NZ,#2206
F213  C3C221    JP      #21C2

F216  3AB830    LD      A,(#30B8)
F219  FEB1      CP      #B1
F21B  CA4522    JP      Z,#2245
F21E  2A5030    LD      HL,(#3050)
F221  CD1E20    CALL    #201E
F224  7E        LD      A,(HL)
F225  FE27      CP      #27
F227  CA5722    JP      Z,#2257
F22A  3E84      LD      A,#84
F22C  327630    LD      (#3076),A
F22F  3E02      LD      A,#02
F231  327730    LD      (#3077),A
F234  CDCA13    CALL    #13CA
F237  D24A22    JP      NC,#224A
F23A  2E00      LD      L,#00
F23C  3EB2      LD      A,#B2
F23E  32C830    LD      (#30C8),A
F241  7D        LD      A,L
F242  326F30    LD      (#306F),A
F245  3E01      LD      A,#01
F247  C3C321    JP      #21C3

F24A  3ABE30    LD      A,(#30BE)
F24D  FEC5      CP      #C5
F24F  C23C22    JP      NZ,#223C
F252  3EB0      LD      A,#B0
F254  C33E22    JP      #223E

F257  23        INC     HL
F258  7E        LD      A,(HL)
F259  E67F      AND     #7F
F25B  6F        LD      L,A
F25C  C33C22    JP      #223C

F25F  3AB830    LD      A,(#30B8)
F262  FEB1      CP      #B1
F264  CA9022    JP      Z,#2290
F267  2A5030    LD      HL,(#3050)
F26A  CD1E20    CALL    #201E
F26D  3E80      LD      A,#80
F26F  327630    LD      (#3076),A
F272  3E01      LD      A,#01
F274  327730    LD      (#3077),A
F277  CDCA13    CALL    #13CA
F27A  D29522    JP      NC,#2295
F27D  210000    LD      HL,#0000
F280  3E82      LD      A,#82
F282  32C830    LD      (#30C8),A
F285  226330    LD      (#3063),HL
F288  116F30    LD      DE,#306F
F28B  7C        LD      A,H
F28C  12        LD      (DE),A
F28D  13        INC     DE
F28E  7D        LD      A,L
F28F  12        LD      (DE),A
F290  3E02      LD      A,#02
F292  C3C321    JP      #21C3

F295  3ABE30    LD      A,(#30BE)
F298  FEC5      CP      #C5
F29A  C2A222    JP      NZ,#22A2
F29D  3EB1      LD      A,#B1
F29F  C38222    JP      #2282

F2A2  CDEA1A    CALL    #1AEA
F2A5  C38222    JP      #2282

F2A8  2A5030    LD      HL,(#3050)
F2AB  CD1E20    CALL    #201E
F2AE  116F30    LD      DE,#306F
F2B1  0600      LD      B,#00
F2B3  0E04      LD      C,#04
F2B5  7E        LD      A,(HL)
F2B6  23        INC     HL
F2B7  FE27      CP      #27
F2B9  C2F822    JP      NZ,#22F8
F2BC  7E        LD      A,(HL)
F2BD  FE27      CP      #27
F2BF  C2DE22    JP      NZ,#22DE
F2C2  3AB830    LD      A,(#30B8)
F2C5  FEB1      CP      #B1
F2C7  CAD522    JP      Z,#22D5
F2CA  AF        XOR     A
F2CB  21C830    LD      HL,#30C8
F2CE  B8        CP      B
F2CF  CAD922    JP      Z,#22D9
F2D2  3EB3      LD      A,#B3
F2D4  77        LD      (HL),A
F2D5  78        LD      A,B
F2D6  C3C321    JP      #21C3

F2D9  3EB4      LD      A,#B4
F2DB  C3D422    JP      #22D4

F2DE  FE8D      CP      #8D
F2E0  CAF822    JP      Z,#22F8
F2E3  FE0A      CP      #0A
F2E5  CAF822    JP      Z,#22F8
F2E8  E67F      AND     #7F
F2EA  12        LD      (DE),A
F2EB  23        INC     HL
F2EC  13        INC     DE
F2ED  04        INC     B
F2EE  0D        DEC     C
F2EF  C2BC22    JP      NZ,#22BC
F2F2  117A30    LD      DE,#307A
F2F5  C3BC22    JP      #22BC

F2F8  3E53      LD      A,#53
F2FA  CD111C    CALL    #1C11
F2FD  C3C222    JP      #22C2

F300  CDE511    CALL    #11E5
F303  CD0C20    CALL    #200C
F306  FE3A      CP      #3A
F308  C26423    JP      NZ,#2364
F30B  2A5030    LD      HL,(#3050)
F30E  CD1E20    CALL    #201E
F311  3E80      LD      A,#80
F313  327630    LD      (#3076),A
F316  3E02      LD      A,#02
F318  327730    LD      (#3077),A
F31B  CDCA13    CALL    #13CA
F31E  DA2E23    JP      C,#232E
F321  3ACC30    LD      A,(#30CC)
F324  FE01      CP      #01
F326  C23123    JP      NZ,#2331
F329  3ECC      LD      A,#CC
F32B  CD111C    CALL    #1C11
F32E  210000    LD      HL,#0000
F331  3AB830    LD      A,(#30B8)
F334  FEB1      CP      #B1
F336  CA6E23    JP      Z,#236E
F339  FEB2      CP      #B2
F33B  CAC221    JP      Z,#21C2
F33E  226330    LD      (#3063),HL
F341  3EA2      LD      A,#A2
F343  32C830    LD      (#30C8),A
F346  CDB51D    CALL    #1DB5
F349  06DD      LD      B,#DD
F34B  30CD      JR      NC,#F31A        ; (-51)
F34D  E5        PUSH    HL
F34E  1111DD    LD      DE,#DD11
F351  300E      JR      NC,#F361        ; (14)
F353  067E      LD      B,#7E
F355  FE3A      CP      #3A
F357  CAC221    JP      Z,#21C2
F35A  12        LD      (DE),A
F35B  23        INC     HL
F35C  13        INC     DE
F35D  0D        DEC     C
F35E  C25423    JP      NZ,#2354
F361  C3C221    JP      #21C2

F364  3E4E      LD      A,#4E
F366  CD111C    CALL    #1C11
F369  3EB4      LD      A,#B4
F36B  C3BF21    JP      #21BF

F36E  EB        EX      DE,HL
F36F  2A4D31    LD      HL,(#314D)
F372  2B        DEC     HL
F373  2B        DEC     HL
F374  2B        DEC     HL
F375  72        LD      (HL),D
F376  23        INC     HL
F377  73        LD      (HL),E
F378  23        INC     HL
F379  3680      LD      (HL),#80
F37B  C3C221    JP      #21C2

F37E  CC44A0    CALL    Z,#A044
F381  41        LD      B,C
F382  AC        XOR     H
F383  2842      JR      Z,#F3C7         ; (66)
F385  C3A9F1    JP      #F1A9

F388  0A        LD      A,(BC)
F389  CC44A0    CALL    Z,#A044
F38C  41        LD      B,C
F38D  AC        XOR     H
F38E  2844      JR      Z,#F3D4         ; (68)
F390  C5        PUSH    BC
F391  A9        XOR     C
F392  F1        POP     AF
F393  1A        LD      A,(DE)
F394  CC44A0    CALL    Z,#A044
F397  2842      JR      Z,#F3DB         ; (66)
F399  C3A9AC    JP      #ACA9

F39C  41        LD      B,C
F39D  F1        POP     AF
F39E  02        LD      (BC),A
F39F  CC44A0    CALL    Z,#A044
F3A2  2844      JR      Z,#F3E8         ; (68)
F3A4  C5        PUSH    BC
F3A5  A9        XOR     C
F3A6  AC        XOR     H
F3A7  41        LD      B,C
F3A8  F1        POP     AF
F3A9  12        LD      (DE),A
F3AA  CC44A0    CALL    Z,#A044
F3AD  41        LD      B,C
F3AE  AC        XOR     H
F3AF  C9        RET     

F3B0  F2ED57    JP      P,#57ED
F3B3  CC44A0    CALL    Z,#A044
F3B6  41        LD      B,C
F3B7  AC        XOR     H
F3B8  D2F2ED    JP      NC,#EDF2
F3BB  5F        LD      E,A
F3BC  CC44A0    CALL    Z,#A044
F3BF  C9        RET     

F3C0  AC        XOR     H
F3C1  41        LD      B,C
F3C2  F2ED47    JP      P,#47ED
F3C5  CC44A0    CALL    Z,#A044
F3C8  D2AC41    JP      NC,#41AC
F3CB  F2ED4F    JP      P,#4FED
F3CE  CC44A0    CALL    Z,#A044
F3D1  53        LD      D,E
F3D2  50        LD      D,B
F3D3  AC        XOR     H
F3D4  48        LD      C,B
F3D5  CCF1F9    CALL    Z,#F9F1
F3D8  CC44A0    CALL    Z,#A044
F3DB  53        LD      D,E
F3DC  50        LD      D,B
F3DD  AC        XOR     H
F3DE  C9        RET     

F3DF  D8        RET     C
F3E0  F2DDF9    JP      P,#F9DD
F3E3  CC44A0    CALL    Z,#A044
F3E6  53        LD      D,E
F3E7  50        LD      D,B
F3E8  AC        XOR     H
F3E9  C9        RET     

F3EA  59        LD      E,C
F3EB  F2FDF9    JP      P,#F9FD
F3EE  50        LD      D,B
F3EF  55        LD      D,L
F3F0  53        LD      D,E
F3F1  48        LD      C,B
F3F2  A0        AND     B
F3F3  42        LD      B,D
F3F4  C3F1C5    JP      #C5F1

F3F7  50        LD      D,B
F3F8  55        LD      D,L
F3F9  53        LD      D,E
F3FA  48        LD      C,B
F3FB  A0        AND     B
F3FC  44        LD      B,H
F3FD  C5        PUSH    BC
F3FE  F1        POP     AF
F3FF  D5        PUSH    DE