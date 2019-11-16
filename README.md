# Sharp MZ Series Personal and Business Computer Emulation

Please consult my [GitHub](https://pdsmart.github.io) website for more upto date information, I will update this repository shortly.

Written by Philip Smart, 2018 for the Terasic DE10 Nano board under the MiSTer framework.

This project aims to provide full emulation (along with extensions) of the Sharp MZ Series Computers.

The following emulations have been written
  - MZ80K                                                              
  - MZ80C
  - MZ1200 
  - MZ80A
  - MZ700
  - MZ80B
  
 and the following are under development:
 - MZ800
 - MZ2000

The current version of the emulator provides:

  -	48K RAM for MZ80K,C,1200,A
  -	64K RAM for MZ700, MZ80B
  -	Hardware Tape Read/Write with selectable 1x - 32x Fast Mode
  -	Turbo Mode 1x - 32x (ie. 112MHz for MZ700)
  -	Programmable Character Generator (PCG-8000/PCG-1200)
  -	40x25, 80x25 Mono and Colour Display Modes
  -	320x200, 640x200 8 Colour Bit addressed Graphics
  -	Updateable Monitor Rom, CGRom, Keymap, User Rom, FDC Rom per Emulation type.
  -	i8253 mono audio

### Enhancements in test/under development:
-	Floppy Disk Drive/Controller 5.25"
-	Quick Disk Controller
-	Dual digital Joystick Input (MZ700)

### Known Issues
-	Tape Write isn’t working correctly, I made some structural changes resulting in it no longer working, so this needs to be resolved.
-	Keyboard mappings could be better, especially for the MZ1200 which is the Japanese version of the MZ80A.
-	HDMI needs to be re-enabled in the design.
- The Aspect Ratio/Scandoubler options aren’t working on the VGA output.


## Installation
1.	Follow the Setup Guide to create a new SD boot disk. https://github.com/MiSTer-devel/Main_MiSTer/wiki/Setup-Guide
2.	Copy across to the SD (via scp or mount the SD under Windows/Linux and use local copy commands) the latest RBF file from the releases folder, ie:-

    scp SharpMZ_MiSTer/releases/SharpMZ_\<date\>.rbf root@\<de10 ip address\>/media/fat/SharpMZ.rbf
    
    Target name can be anything you like ending with .rbf
3.	Make a SharpMZ directory on the SD card, ie:

    ssh root@\<de10 ip address\>
    
    mkdir /media/fat/SharpMZ
4.	Copy any Rom Files, MZF Tape Files, DSK files across to the new directory, ie:
  
    scp \*.mzf root@\<de10 ip address\>:/media/fat/SharpMZ/
5.	Start the MiSTer menu (ie. press the DE10 reset button if it is not showing).
6.	Select the SharpMZ core (or whatever name you called it).
7.	The emulator will boot into an MZ80K model with the SP-1002 monitor.
8.	Press F12 to change the configuration, select Save Config to store it.

## Detail

### Design Summary
The idea of this design is to keep the emulation as independent of the HPS as possible (so it works standalone), only needing the HPS to set control registers,
read/write tape/floppy cache ram with complete images and overlay the menu control system. The MiSTer/HPS system is an excellent base on which to host emulations, but there may be someone wanting to port this emulator to another target such as the Xilinx Zynq 7000 (which I have also been playing with). This in theory should allow easier porting if someone wants to port this emulator to another platform and control it with a PC (parallel port), HPS or instantiate another CPU as the menu control system.

As the Cyclone V SE on the Terasic DE10 has 5.5Mbits of memory, nearly all the RAM used by the emulation is on the FPGA. The Floppy Disk Controller may use HPS memory/external SDRAM depending on whether I decide to cache entire Floppy Disks as per the CMT unit or use the secondary SD card.

### Menu System
The MiSTer menu system is used extensively on this design as the Front End control. It allows for loading/saving of cassettes and floppy disks, setting the machine parameters, the display parameters, debugging and access to the MiSTer control menu.

### Tape Storage

In order to use the emulation seriously, you need to be able to load and save existing programs. Initially (on the original machines) this was via a CMT (tape) unit and later moved on to Floppy/Quick Disks.

This menu controls the hardware CMT unit and has the following choices:
- Load direct to RAM

  This option allows you to load an MZF format tape file (ie. 128 bytes header + code) directly into RAM. It uses the Load Address and Size stored in the header in order to correctly locate the code and also stores the header in the Cassette Work area at 10F0H. After load is completed and warm reset is made, the details of the tape are displayed on-screen. In order to run the loaded program, simply issue the correct monitor command, ie. J1200 (Jump to 1200H where 1200H is shown as the Execution Address in the tape summary).
- Queue Tape

  A real cassette has 1 or more programs stored on it sequentially. The emulation cache only stores 1 full program so this is a mechanism to line up multiple programs and they will be fed into the emulation cache as it becomes empty, thus simulating a real cassette.
  Selecting this option presents you with a directory listing of all MZF files. Choose one per selection and it will be added to the Queue. The programs queued will be displayed on the menu.
- Clear Queue

  This option allows you to purge all queue entries.
- Save Tape

  This option allows you to save a program to the MiSTer SD card which is in the emulation cache. Normally the emulation would have written a program/data to tape (ie. via the BASIC ‘SAVE’ command) which in reality is stored in the emulation cache.
  The tape is saved under the name given in the emulation save command (ie. in BASIC ‘SAVE “myfile”’ would result in a file called myfile.mzf being saved).
- Auto Save Tape

  This option allows you to auto save the emulation cache. Ie. when an emulation save completes, a flag is raised which is seen by the MiSTer program and the emulation cache is saved to SD under the name given in the emulation.
- Tape Buttons

  This option allows you to set the active Tape buttons, ie. Play, Record or Auto. Auto is a hardware mechanism to detect if the emulation is reading or writing to tape and process accordingly.
- Fast Tape Load

  This option allows you to set the speed of the tape drive. On the original machines, the tape runs at 1200baud which is quite slow, so use of this option is recommended.
  
  You can select one of: "Off", "2x", "4x", "8x", "16x", "32x"
  
  Selecting “Off” runs the tape drive at the original speed.


### Machine
The emulation emulates several Sharp MZ computers and this menu allows you to make selections accordingly.
- Machine Model

  This option allows you to choose which Sharp MZ computer is emulated. Currently the choices are:
  
  "MZ80K", "MZ80C", "MZ1200", "MZ80A", "MZ700" with "MZ800", "MZ80B", "MZ2000" in the pipeline.
- CPU Speed

  This option allows you to set the speed at which the emulation runs. Generally speaking, higher speeds can be beneficial in non-graphics based applications although some games benefit from a small speed boost. The choices are:
  
  - MZ80K/C/1200/A  => "2MHz",   "4MHz", "8MHz",  "16MHz", "32MHz", "64MHz"
  - MZ700           => "3.5MHz", "7MHz", "14MHz", "28MHz", "56MHz", "112MHz"
- Audio Source

  This option allows you to choose what is played through the audio output. The choices are:
  
  - Sound   => The mono audio generated by the emulation output on L/R channels.
  - Tape    => The CMT signals as sound, Playback on Right channel, Record on Left channel. In theory you should be able to connect the right channel to an external tape drive and record to physical tape.
- Audio Volume

  This option allows you to set the output volume. There are 16 possible steps from Min .. Max.
- Audio Mute

  This option allows you to Mute the output.
- Rom Management

  The emulation comes with the Monitor, Character Generator and Key Mapping Roms built-in for each machine emulated. This option selects a sub-menu which allows you to upload non-standard Roms when the emulation is started (ie. the Core is selected).

  - Machine Model

    This option allows you to select the emulated Sharp MZ computer to which the custom rom images will affect. The choices are:

    "MZ80K", "MZ80C", "MZ1200", "MZ80A", "MZ700" with "MZ800", "MZ80B", "MZ2000" in the pipeline.
  - User ROM

    On some machine models (ie. MZ80A) there exists a socket to place a User ROM, which will have control passed to it should the first byte be 0 and non-writeable. Although this option only exists on certain models, it is a nice to have feature it is available for all machine models.
    This option allows you to enable or disable the User ROM (NB. If you enable this option, it only enables hardware select, you still need to upload a ROM which has the first byte set to 0).
  -	Floppy Disk ROM

    A Floppy Disk drive was an expansion option for the Sharp MZ computers, and with the advent of the MZ700, a Quick Disk drive was also an option. These options typically held control software in a ROM at location F000H. This option allows you to enable this feature, albeit you still need to upload a ROM.

  -	Enable Custom Rom
    This section allows you to enable custom Roms and select the image which will be uploaded. For each Rom, you can enable or disable. If enabled, you can choose the required file. The Roms which can be customized are:
    - Monitor (40x25)
    - Monitor (80x25)
    -	Char Generator
    -	Key Mapping
    -	User Rom
    -	Floppy Disk
    
    The Monitor Rom is a special case. Most of the Personal Sharp MZ Computers were only able to display 40x25 characters so the Rom hardcodes these parameters. Some people required wider screens for use with CPM, so hardware modifications were made to create an 80x25 display. The emulation is capable of both modes but in order to run correctly, a different Monitor Rom for 80x25 display is needed.


### Display
The display on the Sharp MZ computers was originally quite simplistic. In order to cater for enhancements made in each model and by external vendors, the emulation has several configurable parameters which are grouped under this menu.

-	Display Type
  This option allows you to select the display used. Normally, when a machine model is chosen, it defaults to the original display, this option allows you to override the default. The choices are:
  
  "Mono 40x25", "Mono 80x25 ", "Colour 40x25", "Colour 80x25"
-	Video
  An extension to the original design was the addition of a graphics frame buffer. It is possible to blend the original display video with the graphics frame buffer. This option allows you to enable or disable the original display video (ie. if you only want graphics). 
-	Graphics
  There were various add-on boards made available in order to display bit addressable pixel graphics. This is my extension to the original design and as I gather information on other add-on boards, I will adapt the hardware interface so it accommodates these options. Please see the section below on the graphics frame buffer details if needed. This option allows you to enable or disable the display of the graphics frame buffer (which is blended with the original character based video output).
-	VRAM CPU Wait
  I deviated from the original design by adding a pixel based display buffer. During the Vertical Blanking period, I expand the character based VRAM and Attribute RAM into pixels and store them in the display buffer (a double buffer technique). This consequently means that no snow/tearing will occur if the CPU accesses the VRAM/Attribute RAM during the visible display period. The original design added software waits (MZ80K) and hardware CPU wait states (MZ80A/700) to eliminate snow/tearing and due to the addition of double buffering, this is no longer needed. You can thus disable the wait states with this option and gain some speed or enable them to keep compatibility.
-	PCG Mode
  All of the Sharp MZ computers used character generators which were hard coded in a ROM. External vendors offered add-ons to allow for a Programmable Character Generator based in RAM. This option enables the Programmable Character Generator which is compatible with the HAL PCG-8000/PCG-1200 add-ons.
-	Aspect Ratio
  This option is a MiSTer framework extension which converts the Aspect Ratio from 4:3 to 16:9. It doesn’t work at the moment with VGA output but should work on HDMI. Use this option to choose the desired format.
-	Scandoubler
  This option is a MiSTer framework extension which doubles the scan lines to widen/improve the image of older computer displays. It doesn’t work correctly with VGA output at the moment but should work on HDMI.
  
  The choices are: "None", "HQ2x", "CRT 25%", "CRT 50%", "CRT 75%"

### System
This is the MiSTer main control menu which allows you to select a core, map keys etc.

### Debugging
As you cannot easily get out a trusty Oscilloscope or write breakpoint/debug messages with an FPGA, I’ve added a debugging mode which can be used at any time without affecting the emulation (unless you choose a debug frequency in which case the emulation will run at the selected frequency).
Basically, the 8 LED’s on the main DE10 main board can display a selectable set of signals, either in auto mode (move from set to set after a fixed period) or a static set. The sample rate of the signals displayed on the LED’s is selectable from the Z80 CPU frequency down to 1Hz. You can also attach an oscilloscope onto the LED’s and thus see the waveform if a simple flicker is not sufficient. In addition, you can slow the CPU frequency down in steps from 1MHz to 1/10Hz so you have a good chance of seeing what is happening internally.
This debugging addition is also a great method of understanding the internals of a computer and seeing the Z80 in action.

To use the debug mode, press F12 to enter the MiSTer menu, then select Debug and you are offered the following choices:
-	Select Memory Bank

    This option allows you to select one of the memory banks so it can be written to a local (DE10 SD Card) file.
  
    - SysROM     = System ROM. This is the complete concatenated set of Monitor ROM’s for all the emulations.
    - SysRAM     = System RAM. This is the 64K Main RAM.
    - KeyMap     = Key Mapping ROM. This is the complete concatenated set of Key Mapping’s for all the emulations.
    - VRAM       = Video RAM. This is the 2K Video RAM concatenated with the 2K Attribute RAM.
    - CMTHDR     = Cassette Header. This is the 128 byte memory holding the last loaded or saved tape header.
    - CMTDATA    = Cassette Data. This is the 64K memory holding the last loaded or saved tape data.
    - CGROM      = Character Generator ROM. This is the complete concatenated set of CGROM’s for all the emulations.
    - CGRAM      = Character Generator RAM. This is the 2K contents of the Programmable Character Generator RAM.
    - All        = This is the complete memory set as one file.
  
-	Dump To <memory bank name>
    Dump the selected memory bank. The system will show the file name used for the dump.
  
-	Debug Mode
    Select to Enable or Disable
  
  -	CPU Frequency
    Select the CPU Frequency which can be one of:
    
    "CPU/CMT", "1MHz", "100KHz", "10KHz", "5KHz", "1KHz", "500Hz", "100Hz", "50Hz", "10Hz", "5Hz", "2Hz", "1Hz", "0.5Hz", "0.2Hz", "0.1Hz"
    
  -	Debug LEDS
    Select to Enable or Disable
    
  -	Sample Freq
    This is the sampling frequency used to sample the displayed signals. It can be one of:
    
    "CPU/CMT", "1MHz", "100KHz", "10KHz", "5KHz", "1KHz", "500Hz", "100Hz", "50Hz", "10Hz", "5Hz", "2Hz", "1Hz", "0.5Hz", "0.2Hz", "0.1Hz"
    
  -	Signal Block
    This is the signal block for display. It can be one of:
    
    - T80               => CPU Address/Data Bus and associated signals.
    - I/O               => Video, Keyboard and Select signals.
    - IOCTL             => External I/O Control. Address/Data and Select signals.
    - Config            => Register configuration signals.
    - MZ80C I           => 5 sets of signals relating to the MZ80K/C/1200/A/700/800.
    - MZ80C II          => An additional 5 sets of signals.
    - MZ80B I           => 5 sets of signals relating to the MZ80B/MZ2000.
    - MZ80B II          => An additional 5 sets of signals.
    
  -	Bank
    This is the Bank within the Block to be displayed on the LED’s. It can be one of:
    
    - T80               => "Auto",   "A7-0",     "A15-8",    "DI",       "Signals"
    - I/O               => "Auto",   "Video",    "PS2Key",   "Signals"
    - IOCTL             => "Auto",   "A23-16",   "A15-8",    "A7-0",     "Signals"
    - Config            => "Auto",   "Config 1", "Config 2", "Config 3", "Config 4", "Config 5"
    - MZ80C I           => "Auto",   "CS 1",     "CS 2",     "CS 3",     "INT/RE",   "Clk"
    - MZ80C II          => "Auto",   "CMT 1",    "CMT 2",    "CMT 3"
    - MZ80B I           => Not yet defined.
    - MZ80B II          => Not yet defined.


### Graphics Frame Buffer
An addition to the original design is a 640x200/320x200 8 colour Graphics frame buffer. There were many additions to the Sharp MZ series to allow graphics (ie. MZ80B comes with standard mono graphics) display and as I don’t have detailed information of these to date, I designed my own extension with the intention of adding hardware abstraction layers at a later date to add compatibility to external vendor add-ons.

This frame buffer is made up of 3x16K RAM blocks, 1 per colour with a resolution of 640x200 which matches the output display buffer bit for bit. If the display is working at 40x25 characters then the resolution is 320x200, otherwise for 80x25 it is 640x200.

The RAM for the Graphics frame buffer can be switched into the main CPU address range C000H – FFFFH by programmable registers, 1 bank at a time (ie. Red, Green, Blue banks). This allows for direct CPU addressable pixels to be read and/or written. Each pixel is stored in groups of 8 (1 byte in RAM) scanning from right to left per byte, left to right per row, top to bottom. Ie. if the Red bank is mapped into CPU address space, the byte at C000H represents pixels 7 - 0 of 320/640 (X) at pixel 0 of 200 (Y). Thus 01H written to C000H would set Pixel 7 (X) on Row 0 (Y). This applies for Green and Blue banks when mapped into CPU address space.

In order to speed up display, there is a Colour Write register, so that a write to the graphics RAM will update all 3 banks at the same time.

The programmable registers are as follows:

*Switching Graphics RAM Bank into ZPU CPU Address Range*

- Graphics Bank Switch Set Register: I/O Address: E8H (232 decimal)

  Switches in 1 of the 16Kb Graphics RAM pages (of the 3 pages) to C000 - FFFF. The bank which is switched in is set in the Control Register by bits 1/0 for Read operations and 3/2 for Write operations. This bank switch overrides all MZ80A/MZ700 page switching functions.
- Graphics Bank Switch Reset Register: I/O Address: E9H (233 decimal)

  Switches out the Graphics RAM and returns to previous state.

*Control Register: I/O Address: EAH (234 decimal)*

- Bit 1:0 
Read mode (00=Red Bank, 01=Green Bank, 10=Blue Bank, 11=Not used). Select which bank to be read when enabled in CPU address space.

- Bit 3:2
Write mode (00=Red Bank, 01=Green Bank, 10=Blue Bank, 11=Indirect). Select which bank to be written to when enabled in CPU address space.

- Bit 4
VRAM Output. 0=Enable, 1=Disable. Output Character RAM to the display.

- Bit 5
GRAM Output. 0=Enable, 1=Disable. Output Graphics RAM to the display.

- Bit 7:6
Blend Operator (00=OR ,01=AND, 10=NAND, 11=XOR). Operator to blend Character display with Graphics Display.

*Red Colour Writer Register: I/O Address: EBH (235 decimal)*

- Bit 0 Pixel 7 Set to Red during indirect write.
- Bit 1 Pixel 6
- Bit 2 Pixel 5
- Bit 3 Pixel 4
- Bit 4 Pixel 3
- Bit 5 Pixel 2
- Bit 6 Pixel 1
- Bit 7 Pixel 0 Set to Red during indirect write.

*Green Colour Writer Register: I/O Address: ECH (236 decimal)*
- Bit 0 Pixel 7 Set to Green during indirect write.
- Bit 1 Pixel 6
- Bit 2 Pixel 5
- Bit 3 Pixel 4
- Bit 4 Pixel 3
- Bit 5 Pixel 2
- Bit 6 Pixel 1
- Bit 7 Pixel 0 Set to Green during indirect write.

*Blue Colour Writer Register: I/O Address: EDH (237 decimal)*
- Bit 0 Pixel 7 Set to Blue during indirect write.
- Bit 1 Pixel 6
- Bit 2 Pixel 5
- Bit 3 Pixel 4
- Bit 4 Pixel 3
- Bit 5 Pixel 2
- Bit 6 Pixel 1
- Bit 7 Pixel 0 Set to Blue during indirect write.

For Indirect mode (Control Register bits 3/2 set to 11), a write to the Graphics RAM when mapped into CPU address space C000H – FFFFH will see the byte masked by the Red Colour Writer Register and written to the Red Bank with the same operation for Green and Blue. This allows rapid setting of a colour across the 3 banks.

## Credits
My original intention was to port the MZ80C Emulator written by Nibbles Lab https://github.com/NibblesLab/mz80c_de0 to the Terasic DE10 Nano. After spending some time analyzing it and trying to remove the NIOSII dependency, I discovered the MISTer project, at that point I decided upon writing my own emulation. Consequently some ideas in this code will have originated from Nibbles Lab and the i8253/Keymatrix modules were adapted to work in this implementation. Thus due credit to Nibbles Lab and his excellent work.

Also credit to Sorgelig for his hard work in creating the MiSTer framework and design of some excellent hardware add-ons. The MiSTer framework makes it significantly easier to design/port emulations.

## Links
The Sharp MZ Series Computers were not as wide spread as Commodore, Atari or Sinclair but they had a dedicated following. Given their open design it was very easy to modify and extend applications such as the BASIC interpreters and likewise easy to add hardware extension. As such, a look round the web finds some very comprehensive User Groups with invaluable resources. If you need manuals, programs, information then please look (for starters) at the following sites:

- https://original.sharpmz.org/
- https://www.sharpmz.no/
- https://mz-80a.com
- http://www.sharpusersclub.org/
- http://www.scav.cz/uvod.htm (use chrome to auto translate Czech)

