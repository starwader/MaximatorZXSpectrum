# MaximatorZXSpectrum
Quartus ZX Spectrum 16k project for KAMAMI Maximator (MAX10) evaluation board

The goal of the project was to run ZX Spectrum on affordable FPGA evaluation board "Maximator" made by Polish company KAMAMI, using as much of its capabilities as possible, and extend them with an expansion shield.

I started with Goran Devic's ZX Spectrum implementation from A-Z80 repository, and tweaked it to match Maximator board. 

Maximator-compatible shield made for that project that can be found on a different repository:

https://github.com/starwader/MaximatorZXSpectrumShield

## Technical details

- Altera MAX 10 10M08DAF256C8GES FPGA chip 
- 16k FPGA VRAM
- 16k MIST ROM
- HDMI audio (it might not be good idea to use audio on hi-end speakers - be careful with that)
- HDMI 640x480 video output
- VGA 640x480 8-color video output (Maximator VGA support only binary RGB)
- HDMI hotplug detection - automatic VGA/HDMI switching 
- PS/2 keyboard support
- alternative color palette switch for HDMI 
- various turbo modes on F1-F4 keys (up to 4x)
- external speaker connector 
- EAR connector - driven by LM393 comparator 
- tape loading sound on/off switch

## To be done

- extend memory to 48k/128+ with external SRAM
- fix turbo tape loading (for now loading programs works only for 1x tape speed)
- add joystick connector (maybe through USB/UART?)
- add SD card support (for ROM, and program selection - RAM snapshots?)
- use external multiplexer for switches 
- add settings screen overlay
- map switches to keyboard buttons to free up some pins
- add 16:9 ratio resolution mode
- add MIC connector (HDMI is better in most cases)

## Used modules and links

MIST Repository (ZX Spectrum ROM):

https://github.com/sorgelig/ZX_Spectrum-128K_MIST

A-Z80 processor implementation repository, along with ULA and ZX Spectrum de1 implementation:

https://github.com/gdevic/A-Z80

Shield designed specifically for Maximator board:

HDMI Module:

https://github.com/hdl-util/hdmi

Maximator website:

https://maximator-fpga.org/
