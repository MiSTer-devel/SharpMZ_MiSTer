--
-- mz80b_video.vhd
--
-- Video display signal generator
-- for MZ-80B on FPGA
--
-- Nibbles Lab. 2013-2014
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mz80b_video is
    Port (
        RST_n                : in  std_logic;                           -- Reset
        BOOTM                : in  std_logic;                           -- BOOT Mode
        -- Type of machine we are emulating.
        MODE_MZ80B           : in  std_logic;
        MODE_MZ2000          : in  std_logic;
        -- Type of display to emulate.
        DISPLAY_NORMAL       : in  std_logic;
        DISPLAY_NIDECOM      : in  std_logic;
        DISPLAY_GAL5         : in  std_logic;
        DISPLAY_COLOUR       : in  std_logic;
        -- Different operations modes.
        CONFIG_PCGRAM        : in  std_logic;                           -- PCG Mode Switch, 0 = CGROM, 1 = CGRAM.
        -- Clocks
        CK16M                : in  std_logic;                           -- 15.6kHz Dot Clock(16MHz)
        T80_CLK_n            : in  std_logic;                           -- Z80 Current Clock
        T80_CLK              : in  std_logic;                           -- Z80 Current Clock Inverted
        -- CPU Signals
        T80_A                : in  std_logic_vector(13 downto 0);       -- CPU Address Bus
        CSV_n                : in  std_logic;                           -- CPU Memory Request(VRAM)
        CSG_n                : in  std_logic;                           -- CPU Memory Request(GRAM)
        T80_RD_n             : in  std_logic;                           -- CPU Read Signal
        T80_WR_n             : in  std_logic;                           -- CPU Write Signal
        T80_MREQ_n           : in  std_logic;                           -- CPU Memory Request
        T80_BUSACK_n         : in  std_logic;                           -- CPU Bus Acknowledge
        T80_WAIT_n           : out std_logic;                           -- CPU Wait Request
        T80_DI               : in  std_logic_vector(7 downto 0);        -- CPU Data Bus(in)
        T80_DO               : out std_logic_vector(7 downto 0);        -- CPU Data Bus(out)
        -- Graphic VRAM Access
        GCS_n                : out std_logic;                           -- GRAM Request
        GADR                 : out std_logic_vector(20 downto 0);       -- GRAM Address
        GT80_WR_n            : out std_logic;                           -- GRAM Write Signal
        GBE_n                : out std_logic_vector(3 downto 0);        -- GRAM Byte Enable
        GDI                  : in  std_logic_vector(31 downto 0);       -- Data Bus Input from GRAM
        GDO                  : out std_logic_vector(31 downto 0);       -- Data Bus Output to GRAM
        -- Video Control from outside
        INV                  : in std_logic;                            -- Reverse mode(8255 PA4)
        VGATE                : in std_logic;                            -- Video Output Control(8255 PC0)
        CH80                 : in std_logic;                            -- Text Character Width(Z80PIO A5)
        -- Video Signals
        VGATE_n              : in  std_logic;                           -- Video Output Control
        HBLANK               : out std_logic;                           -- Horizontal Blanking
        VBLANK               : out std_logic;                           -- Vertical Blanking
        HSYNC_n              : out std_logic;                           -- Horizontal Sync
        VSYNC_n              : out std_logic;                           -- Vertical Sync
        ROUT                 : out std_logic;                           -- Red Output
        GOUT                 : out std_logic;                           -- Green Output
        BOUT                 : out std_logic;                           -- Green Output
        -- HPS Interface
        IOCTL_DOWNLOAD       : in  std_logic;                           -- HPS Downloading to FPGA.
        IOCTL_INDEX          : in  std_logic_vector(7 downto 0);        -- Menu index used to upload file.
        IOCTL_WR             : in  std_logic;                           -- HPS Write Enable to FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);       -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(15 downto 0)        -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(15 downto 0);       -- HPS Data to be read into HPS.
        IOCTL_INTERRUPT      : out std_logic                            -- HPS Interrupt.
    );
end mz80b_video;

architecture RTL of mz80b_video is

--
-- Registers
--
signal DIV                   : std_logic_vector(8 downto 0);             -- Clock Divider
signal HCOUNT                : std_logic_vector(9 downto 0);             -- Counter for Horizontal Signals
signal VCOUNT                : std_logic_vector(8 downto 0);             -- Counter for Vertical Signals
signal VADR                  : std_logic_vector(10 downto 0);            -- VRAM Address(selected)
signal VADRC                 : std_logic_vector(10 downto 0);            -- VRAM Address
signal GADRC                 : std_logic_vector(13 downto 0);            -- GRAM Address
signal GADRi                 : std_logic_vector(13 downto 0);            -- GRAM Address(for GRAM Access)
signal VADRL                 : std_logic_vector(10 downto 0);            -- VRAM Address(latched)
signal SDAT                  : std_logic_vector(7 downto 0);             -- Shift Register to Display
signal SDATB                 : std_logic_vector(7 downto 0);             -- Shift Register to Display
signal SDATR                 : std_logic_vector(7 downto 0);             -- Shift Register to Display
signal SDATG                 : std_logic_vector(7 downto 0);             -- Shift Register to Display
signal S2DAT                 : std_logic_vector(7 downto 0);             -- Shift Register to Display(for 40-char)
signal S2DAT0                : std_logic_vector(7 downto 0);             -- Shift Register to Display(for 80B)
signal S2DAT1                : std_logic_vector(7 downto 0);             -- Shift Register to Display(for 80B)
--
-- CPU Access
--
signal MA                    : std_logic_vector(11 downto 0);            -- Masked Address
signal CSB4_x                : std_logic;                                -- Chip Select (PIO-3039 Color Board)
signal CSF4_x                : std_logic;                                -- Chip Select (Background Color)
signal CSF5_x                : std_logic;                                -- Chip Select (Display Select for C-Monitor)
signal CSF6_x                : std_logic;                                -- Chip Select (Display Select for G-Monitor)
signal CSF7_x                : std_logic;                                -- Chip Select (GRAM Select)
signal GCSi_x                : std_logic;                                -- Chip Select (GRAM)
signal RCSV                  : std_logic;                                -- Chip Select (VRAM, NiosII)
signal RCSC                  : std_logic;                                -- Chip Select (CGROM, NiosII)
signal VWEN                  : std_logic;                                -- WR + MREQ (VRAM)
signal RVWEN                 : std_logic;                                -- WR + CS (VRAM, NiosII)
signal RCWEN                 : std_logic;                                -- WR + CS (CGROM, NiosII)
signal WAITi_n               : std_logic;                                -- Wait
signal WAITii_n              : std_logic;                                -- Wait(delayed)
signal ZGBE_n                : std_logic_vector(3 downto 0);             -- Byte Enable by Z80 access
--
-- Internal Signals
--
signal HDISPEN               : std_logic;                                -- Display Enable for Horizontal, almost same as HBLANK
signal HBLANKi               : std_logic;                                -- Horizontal Blanking
signal BLNK                  : std_logic;                                -- Horizontal Blanking (for wait)
signal XBLNK                 : std_logic;                                -- Horizontal Blanking (for wait)
signal VDISPEN               : std_logic;                                -- Display Enable for Vertical, same as VBLANK
signal MB                    : std_logic;                                -- Display Signal (Mono, Blue)
signal MG                    : std_logic;                                -- Display Signal (Mono, Green)
signal MR                    : std_logic;                                -- Display Signal (Mono, Red)
signal BB                    : std_logic;                                -- Display Signal (Color, Blue)
signal BG                    : std_logic;                                -- Display Signal (Color, Green)
signal BR                    : std_logic;                                -- Display Signal (Color, Red)
signal PBGR                  : std_logic_vector(2 downto 0);             -- Display Signal (Color)
signal POUT                  : std_logic_vector(2 downto 0);             -- Display Signal (Color)
signal VRAMDO                : std_logic_vector(7 downto 0);             -- Data Bus Output for VRAM
signal DCODE                 : std_logic_vector(7 downto 0);             -- Display Code, Read From VRAM
signal CGDAT                 : std_logic_vector(7 downto 0);             -- Font Data To Display
signal CGADR                 : std_logic_vector(10 downto 0);            -- Font Address To Display
signal CCOL                  : std_logic_vector(2 downto 0);             -- Character Color
signal BCOL                  : std_logic_vector(2 downto 0);             -- Background Color
signal CCOLi                 : std_logic_vector(2 downto 0);             -- Character Color(reg)
signal BCOLi                 : std_logic_vector(2 downto 0);             -- Background Color(reg)
signal GPRI                  : std_logic;
signal GPAGE                 : std_logic_vector(2 downto 0);
signal GPAGEi                : std_logic_vector(2 downto 0);
signal GDISPEN               : std_logic;
signal GDISPENi              : std_logic;
signal GBANK                 : std_logic_vector(1 downto 0);
signal INVi                  : std_logic;
signal VGATEi                : std_logic;
signal GRAMBDI               : std_logic_vector(7 downto 0);             -- Data from GRAM(Blue)
signal GRAMRDI               : std_logic_vector(7 downto 0);             -- Data from GRAM(Red)
signal GRAMGDI               : std_logic_vector(7 downto 0);             -- Data from GRAM(Green)
signal CH80i                 : std_logic;
signal CDISPEN               : std_logic;
signal PALET0                : std_logic_vector(2 downto 0);
signal PALET1                : std_logic_vector(2 downto 0);
signal PALET2                : std_logic_vector(2 downto 0);
signal PALET3                : std_logic_vector(2 downto 0);
signal PALET4                : std_logic_vector(2 downto 0);
signal PALET5                : std_logic_vector(2 downto 0);
signal PALET6                : std_logic_vector(2 downto 0);
signal PALET7                : std_logic_vector(2 downto 0);

--
-- Components
--
component dprom
    GENERIC (
          init_file          : string;
          widthad_a          : natural;
          width_a            : natural
    );
    PORT
    (
          address_a          : IN STD_LOGIC_VECTOR (widthad_a-1 DOWNTO 0);
          clock_a            : IN STD_LOGIC ;
          data_a             : IN STD_LOGIC_VECTOR (width_a-1 DOWNTO 0);
          wren_a             : IN STD_LOGIC;
          q_a                : OUT STD_LOGIC_VECTOR (width_a-1 DOWNTO 0);

          address_b          : IN STD_LOGIC_VECTOR (widthad_a-1 DOWNTO 0);
          clock_b            : IN STD_LOGIC ;
          data_b             : IN STD_LOGIC_VECTOR (width_a-1 DOWNTO 0);
          wren_b             : IN STD_LOGIC;
          q_b                : OUT STD_LOGIC_VECTOR (width_a-1 DOWNTO 0)
    );
end component;

component dpram
     generic (
          init_file          : string;
          widthad_a          : natural;
          width_a            : natural
      );
      Port (
          clock_a            : in  std_logic ;
          clocken_a          : in  std_logic := '1';
          address_a          : in  std_logic_vector (widthad_a-1 downto 0);
          data_a             : in  std_logic_vector (width_a-1 downto 0);
          wren_a             : in  std_logic;
          q_a                : out std_logic_vector (width_a-1 downto 0);

          clock_b            : in  std_logic ;
          clocken_b          : in  std_logic := '1';
          address_b          : in  std_logic_vector (widthad_a-1 downto 0);
          data_b             : in  std_logic_vector (width_a-1 downto 0);
          wren_b             : in  std_logic;
          q_b                : out std_logic_vector (width_a-1 downto 0)
    );
end component;

component cgrom
    PORT
    (
        data                 : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
        rdaddress            : IN STD_LOGIC_VECTOR (10 DOWNTO 0);
        rdclock              : IN STD_LOGIC ;
        wraddress            : IN STD_LOGIC_VECTOR (10 DOWNTO 0);
        wrclock              : IN STD_LOGIC  := '1';
        wren                 : IN STD_LOGIC  := '0';
        q                    : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
    );
end component;

component dpram2k
    PORT
    (
        address_a            : IN STD_LOGIC_VECTOR (10 DOWNTO 0);
        address_b            : IN STD_LOGIC_VECTOR (10 DOWNTO 0);
        clock_a              : IN STD_LOGIC  := '1';
        clock_b              : IN STD_LOGIC ;
        data_a               : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
        data_b               : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
        wren_a               : IN STD_LOGIC  := '0';
        wren_b               : IN STD_LOGIC  := '0';
        q_a                  : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
        q_b                  : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
    );
end component;

begin

    --
    -- Instantiation
    --
    VRAM0 : dpram
    GENERIC MAP (
        init_file            => "./roms/MZFONT.mif",
        widthad_a            => 11,
        width_a              => 8
    )
    PORT MAP (
        clock_a              => CK8M,
        clocken_a            => CK16M,
        address_a            => VADR,
        data_a               => T80_DI,
        wren_a               => VWEN,
        q_a                  => VRAMDO,

        clock_b              => CK16M,
        clocken_b            => IOCTL_CSVVRAM_n,
        address_b            => IOCTL_ADDR(10 DOWNTO 0),
        data_b               => IOCTL_DOUT(7 DOWNTO 0),
        wren_b               => RVWEN, --IOCTL_WR,
        q_b                  => open
    );

    CGROM0 : dprom
    GENERIC MAP (
        init_file            => "./roms/MZ80K_cgrom.mif",
        widthad_a            => 11,
        width_a              => 8
    ) 
    PORT MAP (
        address_a            => CGADR,
        clock_a              => CK16M,
        data_a               => IOCTL_DOUT(7 DOWNTO 0),
        wren_a               => '0',
        q_a                  => CGDAT,

        address_b            => IOCTL_ADDR(10 DOWNTO 0),
        clock_b              => IOCTL_CSCGROM_n,
        data_b               => IOCTL_DOUT(7 DOWNTO 0),
        wren_b               => ROWEN,--IOCTL_WR
        q_b                  => open
    );

    --
    -- Blank & Sync Generation
    --
    process( RST_n, CK16M ) begin

        if RST_n='0' then
            HCOUNT         <= "1111111000";
            HBLANKi        <= '0';
            HDISPEN        <= '0';
            BLNK           <= '0';
            HSYNC_n        <= '1';
            VDISPEN        <= '1';
            VSYNC_n        <= '1';
            GCSi_x         <= '1';
            VADRC          <= (others=>'0');
            GADRC          <= (others=>'0');
            VADRL          <= (others=>'0');
        elsif CK16M'event and CK16M='1' then

            -- Counters
            if HCOUNT=1015 then
                --HCOUNT<=(others=>'0');
                HCOUNT     <= "1111111000";
                VADRC      <= VADRL;                                     -- Return to Most-Left-Column Address
                if VCOUNT=259 then
                    VCOUNT <= (others=>'0');
                    VADRC  <= (others=>'0');                             -- Home Position
                    GADRC  <= (others=>'0');                             -- Home Position
                    VADRL  <= (others=>'0');
                else
                    VCOUNT <= VCOUNT+'1';
                end if;
            else
                HCOUNT     <= HCOUNT+'1';
            end if;

            -- Horizontal Signals Decode
            if HCOUNT=0 then
                HDISPEN    <= VDISPEN;                                   -- if V-DISP is Enable then H-DISP Start
            elsif HCOUNT=632 then
                HBLANKi    <= '1';                                       -- H-Blank Start
                BLNK       <= '1';
            elsif HCOUNT=640 then
                HDISPEN    <= '0';                                       -- H-DISP End
            elsif HCOUNT=768 then
                HSYNC_n    <= '0';                                       -- H-Sync Pulse Start
            elsif HCOUNT=774 and VCOUNT(2 downto 0)="111" then
                VADRL      <= VADRC;                                     -- Save Most-Left-Column Address
            elsif HCOUNT=859 then
                HSYNC_n    <= '1';                                       -- H-Sync Pulse End
            elsif HCOUNT=992 then
                BLNK       <= '0';
            elsif HCOUNT=1015 then
                HBLANKi    <= '0';                                       -- H-Blank End
            end if;

            -- VRAM Address counter(per 8dot)
            if HBLANKi='0' then
                if (HCOUNT(2 downto 0)="111" and CH80i='1') or (HCOUNT(3 downto 0)="1111" and CH80i='0') then
                    VADRC  <= VADRC+'1';
                end if;
                if (HCOUNT(2 downto 0)="111" and MODE_MZ2000='1') or (HCOUNT(3 downto 0)="1111" and MODE_MZ80B='1') then
                    GADRC  <= GADRC+'1';
                end if;
            end if;

            -- Graphics VRAM Access signal
            if HBLANKi='0' then
                if (HCOUNT(2 downto 0)="000" and MODE_MZ2000='1') or (HCOUNT(3 downto 0)="1000" and MODE_MZ80B='1') then
                  GCSi_x   <= '0';
                elsif (HCOUNT(2 downto 0)="111" and MODE_MZ2000='1') or (HCOUNT(3 downto 0)="1111" and MODE_MZ80B='1') then
                  GCSi_x   <= '1';
                end if;
            else
                GCSi_x     <= '1';
            end if;

            -- Get Font/Pattern data and Shift
            if HCOUNT(3 downto 0)="0000" then
                if CH80i='1' then
                    SDAT   <= CGDAT;
                else
                    SDAT   <= CGDAT(7)&CGDAT(7)&CGDAT(6)&CGDAT(6)&CGDAT(5)&CGDAT(5)&CGDAT(4)&CGDAT(4);
                    S2DAT  <= CGDAT(3)&CGDAT(3)&CGDAT(2)&CGDAT(2)&CGDAT(1)&CGDAT(1)&CGDAT(0)&CGDAT(0);
                end if;
                if MODE_MZ2000='1' then
                    SDATB  <= GRAMBDI;
                    SDATR  <= GRAMRDI;
                    SDATG  <= GRAMGDI;
                else
                    SDATB  <= GRAMBDI(3)&GRAMBDI(3)&GRAMBDI(2)&GRAMBDI(2)&GRAMBDI(1)&GRAMBDI(1)&GRAMBDI(0)&GRAMBDI(0);
                    S2DAT0 <= GRAMBDI(7)&GRAMBDI(7)&GRAMBDI(6)&GRAMBDI(6)&GRAMBDI(5)&GRAMBDI(5)&GRAMBDI(4)&GRAMBDI(4);
                    SDATR  <= GRAMRDI(3)&GRAMRDI(3)&GRAMRDI(2)&GRAMRDI(2)&GRAMRDI(1)&GRAMRDI(1)&GRAMRDI(0)&GRAMRDI(0);
                    S2DAT1 <= GRAMRDI(7)&GRAMRDI(7)&GRAMRDI(6)&GRAMRDI(6)&GRAMRDI(5)&GRAMRDI(5)&GRAMRDI(4)&GRAMRDI(4);
                end if;
            elsif HCOUNT(3 downto 0)="1000" then
                if CH80i='1' then
                    SDAT   <= CGDAT;
                else
                    SDAT   <= S2DAT;
                end if;
                if MODE_MZ2000='1' then
                    SDATB  <= GRAMBDI;
                    SDATR  <= GRAMRDI;
                    SDATG  <= GRAMGDI;
                else
                    SDATB  <= S2DAT0;
                    SDATR  <= S2DAT1;
                end if;
            else
                SDAT       <= SDAT(6 downto 0)&'0';
                SDATB      <= '0'&SDATB(7 downto 1);
                SDATR      <= '0'&SDATR(7 downto 1);
                SDATG      <= '0'&SDATG(7 downto 1);
            end if;

            -- Vertical Signals Decode
            if VCOUNT=0 then
                VDISPEN    <= '1';            -- V-DISP Start
            elsif VCOUNT=200 then
                VDISPEN    <= '0';            -- V-DISP End
            elsif VCOUNT=219 then
                VSYNC_n    <= '0';                -- V-Sync Pulse Start
            elsif VCOUNT=223 then
                VSYNC_n    <= '1';                -- V-Sync Pulse End
            end if;

        end if;

    end process;

    --
    -- Control Registers
    --
    process( RST_n, T80_CLK ) begin
        if RST_n='0' then
            BCOLi          <= (others=>'0');
            CCOLi          <= (others=>'1');
            GPRI           <= '0';
            GPAGEi         <= "000";
            GDISPENi       <= '0';
            CDISPEN        <= '1';
            GBANK          <= "00";
            PALET0         <= "000";
            PALET1         <= "111";
            PALET2         <= "111";
            PALET3         <= "111";
            PALET4         <= "111";
            PALET5         <= "111";
            PALET6         <= "111";
            PALET7         <= "111";
        elsif T80_CLK'event and T80_CLK='0' then
            if T80_WR_n='0' then
                if MODE_MZ2000='1' then        -- MZ-2000
                    -- Background Color
                    if CSF4_x='0' then
                        BCOLi    <= T80_DI(2 downto 0);
                    end if;
                    -- Character Color and Priority
                    if CSF5_x='0' then
                        CCOLi    <= T80_DI(2 downto 0);
                        GPRI     <= T80_DI(3);
                    end if;
                    -- Display Graphics and Pages
                    if CSF6_x='0' then
                        GPAGEi   <= T80_DI(2 downto 0);
                        GDISPENi <= not T80_DI(3);
                    end if;
                    -- Select Accessable Graphic Banks
                    if CSF7_x='0' then
                        GBANK    <= T80_DI(1 downto 0);
                    end if;
                else                            -- MZ-80B
                    -- Color Control(PIO-3039)
                    if CSB4_x='0' then
                        if T80_DI(6)='1' then
                            CDISPEN <= T80_DI(7);
                        else
                            case T80_DI(2 downto 0) is
                                when "000" => PALET0<=T80_DI(5 downto 3);
                                when "001" => PALET1<=T80_DI(5 downto 3);
                                when "010" => PALET2<=T80_DI(5 downto 3);
                                when "011" => PALET3<=T80_DI(5 downto 3);
                                when "100" => PALET4<=T80_DI(5 downto 3);
                                when "101" => PALET5<=T80_DI(5 downto 3);
                                when "110" => PALET6<=T80_DI(5 downto 3);
                                when "111" => PALET7<=T80_DI(5 downto 3);
                                when others => PALET0<=T80_DI(5 downto 3);
                            end case;
                        end if;
                    end if;
                    -- Select Accessable Graphic Banks and Outpu Pages
                    if CSF4_x='0' then
                        GBANK   <= T80_DI(0)&(not T80_DI(0));
                        GPAGEi(1 downto 0)<=T80_DI(2 downto 1);
                    end if;
                end if;
            end if;
        end if;
    end process;

    --
    -- Timing Conditioning and Wait
    --
    process( T80_MREQ_n ) begin
        if T80_MREQ_n'event and T80_MREQ_n='0' then
            XBLNK<=BLNK;
        end if;
    end process;

    process( T80_CLK ) begin
        if T80_CLK'event and T80_CLK='1' then
            WAITii_n<=WAITi_n;
        end if;
    end process;
    WAITi_n<='0' when (CSV_n='0' or CSG_n='0') and XBLNK='0' and BLNK='0' else '1';
    T80_WAIT_n<=WAITi_n and WAITii_n;

    --
    -- Mask by Mode
    --
    ZGBE_n       <= "1110"                 when GBANK="01" else
                    "1101"                 when GBANK="10" else
                    "1011"                 when GBANK="11" else "1111";
    GBE_n        <= ZGBE_n                 when BLNK='1' else "1000";
    GT80_WR_n    <= T80_WR_n               when BLNK='1' else '1';
    GCS_n        <= CSG_n                  when BLNK='1' else GCSi_x;
    RCSV         <= '0'                    when IOCTL_INDEX="01000000" and IOCTL_ADDR(15 downto 11)="11010" else '1';
    RCSC         <='0'                     when IOCTL_INDEX="01000000" and IOCTL_ADDR(15 downto 11)="11001" else '1';
    VWEN         <='1'                     when T80_WR_n='0' and CSV_n='0' and BLNK='1' else '0';
    RVWEN        <= not(IOCTL_WR='1' or RCSV);
    RCWEN        <= not(IOCTL_WR='1' or RCSC);
    CSB4_x       <= '0'                    when T80_A(7 downto 0)=X"B4" and T80_IORQ_n='0' else '1';
    CSF4_x       <= '0'                    when T80_A(7 downto 0)=X"F4" and T80_IORQ_n='0' else '1';
    CSF5_x       <= '0'                    when T80_A(7 downto 0)=X"F5" and T80_IORQ_n='0' else '1';
    CSF6_x       <= '0'                    when T80_A(7 downto 0)=X"F6" and T80_IORQ_n='0' else '1';
    CSF7_x       <= '0'                    when T80_A(7 downto 0)=X"F7" and T80_IORQ_n='0' else '1';
    CCOL         <= CCOLi                  when T80_BUSACK_n='1' else "111";
    BCOL         <= BCOLi                  when T80_BUSACK_n='1' else "000";
    INVi         <= INV                    when BOOTM='0' and T80_BUSACK_n='1' else '1';
    VGATEi       <= VGATE                  when BOOTM='0' and T80_BUSACK_n='1' else '0';
    GPAGE        <= GPAGEi                 when BOOTM='0' and T80_BUSACK_n='1' else "000";
    GDISPEN      <= '0'                    when BOOTM='1' or T80_BUSACK_n='0' else
                    '1'                    when MODE_MZ80B='1' else GDISPENi;
    CH80i        <= CH80                   when BOOTM='0' and T80_BUSACK_n='1' else '0';

    --
    -- Bus Select
    --
    VADR         <= T80_A(10 downto 0)     when CSV_n='0' and BLNK='1' else VADRC;
    GADRi        <= T80_A(13 downto 0)     when CSG_n='0' and BLNK='1' and MODE_MZ2000='1' else
                    '0'&T80_A(12 downto 0) when CSG_n='0' and BLNK='1' and MODE_MZ80B='1' else GADRC;
    GADR         <= "1111101"&GADRi;    -- 0x7D0000
    DCODE        <= T80_DI                 when CSV_n='0' and BLNK='1' and T80_WR_n='0' else VRAMDO;
    T80_DO       <= VRAMDO                 when T80_RD_n='0' and CSV_n='0' else
                    GDI(7 downto 0)        when T80_RD_n='0' and CSG_n='0' and GBANK="01" else
                    GDI(15 downto 8)       when T80_RD_n='0' and CSG_n='0' and GBANK="10" else
                    GDI(23 downto 16)      when T80_RD_n='0' and CSG_n='0' and GBANK="11" else (others=>'0');
    CGADR        <= DCODE&VCOUNT(2 downto 0);
    GRAMBDI      <= GDI(7 downto 0)        when GPAGE(0)='1' else (others=>'0');
    GRAMRDI      <= GDI(15 downto 8)       when GPAGE(1)='1' else (others=>'0');
    GRAMGDI      <= GDI(23 downto 16)      when GPAGE(2)='1' else (others=>'0');
    GDO          <= "00000000"&T80_DI&T80_DI&T80_DI;

    --
    -- Color Decode
    --
    -- Monoclome Monitor
--    MB<=SDAT(7) when HDISPEN='1' and VGATEi='0' else '0';
--    MR<=SDAT(7) when HDISPEN='1' and VGATEi='0' else '0';
    MB           <= '0';
    MR           <= '0';
    MG           <= not (SDAT(7) or (GDISPEN and (SDATB(0) or SDATR(0) or SDATG(0)))) when HDISPEN='1' and VGATEi='0' and INVi='0' else
                    SDAT(7) or (GDISPEN and (SDATB(0) or SDATR(0) or SDATG(0))) when HDISPEN='1' and VGATEi='0' and INVi='1' else '0';

    -- Color Monitor(MZ-2000)
    process( HDISPEN, VGATEi, GPRI, SDAT(7), SDATB(0), SDATR(0), SDATG(0), CCOL, BCOL ) begin
        if HDISPEN='1' and VGATEi='0' then
            if SDAT(7)='0' and SDATB(0)='0' then
                BB<=BCOL(0);
            else
                if GPRI='0' then
                    if SDAT(7)='1' then
                        BB<=CCOL(0);
                    else
                        BB<='1';    -- SDATB(0)='1'
                    end if;
                else     --GPRI='1'
                    if SDATB(0)='1' then
                        BB<='1';
                    else
                        BB<=CCOL(0);    -- SDAT(7)='1'
                    end if;
                end if;
            end if;
            if SDAT(7)='0' and SDATR(0)='0' then
                BR<=BCOL(1);
            else
                if GPRI='0' then
                    if SDAT(7)='1' then
                        BR<=CCOL(1);
                    else
                        BR<='1';    -- SDATR(0)='1'
                    end if;
                else    --GPRI='1' then
                    if SDATR(0)='1' then
                        BR<='1';
                    else
                        BR<=CCOL(1);    -- SDAT(7)='1'
                    end if;
                end if;
            end if;
            if SDAT(7)='0' and SDATG(0)='0' then
                BG<=BCOL(2);
            else
                if GPRI='0' then
                    if SDAT(7)='1' then
                        BG<=CCOL(2);
                    else
                        BG<='1';    -- SDATG(0)='1'
                    end if;
                else    --GPRI='1' then
                    if SDATG(0)='1' then
                        BG<='1';
                    else
                        BG<=CCOL(2);    -- SDAT(7)='1'
                    end if;
                end if;
            end if;
        else
            BB<='0';
            BR<='0';
            BG<='0';
        end if;
    end process;
    -- Color Monitor(PIO-3039)
    POUT<=(SDAT(7) and CDISPEN)&SDATR(0)&SDATB(0);
    process(POUT, PALET0, PALET1, PALET2, PALET3, PALET4, PALET5, PALET6, PALET7) begin
        case POUT is
            when "000" => PBGR<=PALET0;
            when "001" => PBGR<=PALET1;
            when "010" => PBGR<=PALET2;
            when "011" => PBGR<=PALET3;
            when "100" => PBGR<=PALET4;
            when "101" => PBGR<=PALET5;
            when "110" => PBGR<=PALET6;
            when "111" => PBGR<=PALET7;
            when others => PBGR<=PALET7;
        end case;
    end process;

    --
    -- Output
    --
    CK16M  <= CK16M;
    VBLANK <= VDISPEN;
    HBLANK <= HBLANKi;
    ROUT   <= MR when MODE_NORMAL='1' or BOOTM='1' or T80_BUSACK_n='0' else
              BR when MODE_COLOUR='1' and MODE_MZ2000='1'              else PBGR(0);
    GOUT   <= MG when MODE_NORMAL='1' or BOOTM='1' or T80_BUSACK_n='0' else
              BG when MODE_COLOUR='1' and MODE_MZ2000='1'              else PBGR(1);
    BOUT   <= MB when MODE_NORMAL='1' or BOOTM='1' or T80_BUSACK_n='0' else
              BB when MODE_COLOUR='1' and MODE_MZ2000='1'              else PBGR(2);

end RTL;
