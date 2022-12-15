//============================================================================
// Sinclair ZX Spectrum host board
//
//  Copyright (C) 2014-2016  Goran Devic
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================
module MaximatorZXSpectrum
(
    //-------- Clocks and reset -----------------
    input wire CLOCK_10,            // Input clock 10 MHz
    input wire KEY_RESET,           // RESET button (pin nRES, R15)
	 input wire KEY_NMI,					// NMI button (pin D0, L16)
	 input wire ULA_TURBO_EN,			// switch 28/14 mHz ULA (pin D11, D16)
	 input wire CPU_TURBO_EN,			// turbo switch 2x CPU freq (pin D10, D15)
	 input wire INT_EN,					// interrupt switch (pin D12, C15) (temporary hdmi/vga)
	 input wire TAPE_SOUND_EN,			// mix tape sound switch (pin D13, C16)

    //-------- PS/2 Keyboard --------------------
    input wire PS2_CLK,					// PS2 CLK (pin D5, G15)
    input wire PS2_DAT,					// PS2 DAT (pin D1, J15)
	 input wire AUDIO_IN,				// AUDIO IN (pin D8, E15)
	 output wire AUDIO_OUT,				// AUDIO OUT (pin D9, E16)
    //-------- VGA connector --------------------
    output wire VGA_R,
    output wire VGA_G,
    output wire VGA_B,
    output reg VGA_HS,
    output reg VGA_VS,
	   // HDMI output
	 output logic [2:0] HDMI_TX_p,
	 output logic [2:0] HDMI_TX_n,
	 output logic HDMI_CLK_p,
	 output logic HDMI_CLK_n,

	 inout HDMI_SDA,
	 inout HDMI_SCL,
	 input HDMI_HPD,
	 
    //-------- Atari joystick mapped as Kempston
    //input wire [4:0] kempston,      // Input with weak pull-up
    //output wire kempston_gnd,       // Helps mapping to DB9 cable
    //output wire [4:0] LEDG,         // Show the joystick state

    output wire [3:0] LEDGTOP       // Show additional information visually
);
`default_nettype none

wire clk_vram;
	
wire reset;
wire locked;
//assign reset = locked & KEY0;
assign reset = locked & KEY_RESET;
// Export selected pins to the extension connector

//assign kempston_gnd = 0;

//assign PS2_CLK_OUT = PS2_CLK;

// Top 3 green LEDs show various states:
assign LEDGTOP[3] = ULA_TURBO_EN;
assign LEDGTOP[2] = CPU_TURBO_EN;              // Reserved for future use
assign LEDGTOP[1] = INT_EN;         // Show the beeper state
assign LEDGTOP[0] = beeper;        // Show when a key is being pressed

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Internal buses and address map selection logic
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire [15:0] A;                  // Global address bus
wire [7:0] D;                   // CPU data bus

wire [7:0] ram_data;            // Internal 16K RAM data
wire RamWE;
assign RamWE = A[15:14]==2'b01 && nIORQ==1 && nRD==1 && nWR==0;

//wire ExtRamWE;                  // Extended (and external) 32K RAM
//assign ExtRamWE = A[15]==1 && nIORQ==1 && nRD==1 && nWR==0;
//assign SRAM_DQ[15:0] = ExtRamWE? {8'b0,D[7:0]} : {16{1'bz}};


wire [7:0] ula_data;            // ULA
wire io_we;
assign io_we = nIORQ==0 && nRD==1 && nWR==0;

wire [7:0] sram_data;
wire [7:0] ROM_DQ;

rom16 rom_inst(
	.address(A[13:0]),
	.clock(clk_vram), // todo
	.q(ROM_DQ));

// Memory map:
//   0000 - 3FFF  16K ROM (mapped to the external Flash memory)
//   4000 - 7FFF  16K dual-port RAM
//   8000 - FFFF  32K RAM (mapped to the external SRAM memory)
always @(*) // always_comb
begin
    case ({nIORQ,nRD,nWR})
        // -------------------------------- Memory read --------------------------------
        3'b101: begin
                casez (A[15:14])
                    2'b00:  D[7:0] = ROM_DQ;
                    2'b01:  D[7:0] = ram_data;
                    2'b1?:  D[7:0] = 8'b11111111;//ram_data; // modified
					 //casez (A[14])
                //    '0:  D[7:0] = ROM_DQ;
                //    '1:  D[7:0] = ram_data;
                endcase
            end
        // ---------------------------------- IO read ----------------------------------
        3'b001: begin
                // Normally data supplied by the ULA
                D[7:0] = ula_data;

                // Kempston joystick at the IO address 0x1F; active bits are high:
                //                   FIRE         UP           DOWN         LEFT         RIGHT
                //if (A[7:0]==8'h1F) begin
                //    D[7:0] = { 3'b0, !kempston[4],!kempston[0],!kempston[1],!kempston[2],!kempston[3] };
                //end
            end
    default:
        D[7:0] = {8{1'bz}};
    endcase
end

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate 16K dual-port RAM
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// "A" port is the CPU side, "B" port is the VGA image generator in the ULA
ram16 ram16_(
    .clock      (clk_vram),     // RAM connects to the higher, pixel clock rate

    .address_a  (A[13:0]),      // Address in to the RAM from the CPU side
    .data_a     (D),            // Data in to the RAM from the CPU side
    .q_a        (ram_data),     // Data out from the RAM into the data bus selector
    .wren_a     (RamWE),

    .address_b  ({1'b0, vram_address}),
    .data_b     (8'b0),
    .q_b        (vram_data),
    .wren_b     ('0));

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// 32K of ZX Spectrum extended RAM is using the external SRAM memory
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//assign SRAM_ADDR[14:0] = A[14:0];
//assign SRAM_ADDR[17:15] = 0;
//assign SRAM_CE_N = 0;
//assign SRAM_OE_N = 0;
//assign SRAM_WE_N = !ExtRamWE;
//assign SRAM_UB_N = 1;
//assign SRAM_LB_N = 0;

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate ULA
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire clk_cpu;                   // Global CPU clock of 3.5 MHz
wire [12:0] vram_address;       // ULA video block requests a byte from the video RAM
wire [7:0] vram_data;           // ULA video block reads a byte from the video RAM
wire vs_nintr;                  // Generates a vertical retrace interrupt
wire pressed;                   // Show that a key is being pressed
wire beeper;                    // Show the beeper state


wire [2:0] HDMI_TX;
wire HDMI_CLK;

ula ula_(
    //-------- Clocks and reset -----------------
    .CLOCK_10 (CLOCK_10),
	 .cpu_turbo (~CPU_TURBO_EN),               // Turbo speed (3.5 MHz x 2 = 7.0 MHz)
	 .ula_turbo (~ULA_TURBO_EN),
	 .tape_sound(~TAPE_SOUND_EN),
	 .clk_vram (clk_vram),
    .nreset (reset),            // KEY0 is reset; on DE1, keys are active low!
    .locked (locked),           // PLL is locked signal
	 .vga_en(!HDMI_HPD),
	 .hdmi_en(HDMI_HPD),
    .alternate_colors(INT_EN),
	 
	 //-------- CPU control ----------------------
    .clk_cpu (clk_cpu),         // Generates CPU clock of 3.5 MHz
    .vs_nintr (vs_nintr),       // Generates a vertical retrace interrupt

    //-------- Address and data buses -----------
    .A (A),                     // Input address bus
    .D (D),                     // Input data bus
    .ula_data (ula_data),       // Output data
    .io_we (io_we),             // Write enable to data register through IO

    .vram_address (vram_address),// ULA video block requests a byte from the video RAM
    .vram_data (vram_data),     // ULA video block reads a byte from the video RAM

    //-------- PS/2 Keyboard --------------------
    .PS2_CLK (PS2_CLK),
    .PS2_DAT (PS2_DAT),
    .pressed (pressed),

    //-------- Audio (Tape player) --------------
	 .AUD_OUT (AUDIO_OUT),
	 .AUD_IN (!AUDIO_IN),
    .beeper (beeper),

    //-------- VGA connector --------------------
    .VGA_R (VGA_R),
    .VGA_G (VGA_G),
    .VGA_B (VGA_B),
    .VGA_HS (VGA_HS),
    .VGA_VS (VGA_VS),
	 
	 //-------- HDMI -----------------------------
	 .HDMI_TX(HDMI_TX),
	 .HDMI_CLK(HDMI_CLK),
	 .HDMI_SDA(HDMI_SDA),
	 .HDMI_SCL(HDMI_SCL),
	 .HDMI_HPD(HDMI_HPD),
);


DifferentialSignal diff1_(
	.in(HDMI_TX[0]),
	.p(HDMI_TX_p[0]),
	.n(HDMI_TX_n[0]),
);

DifferentialSignal diff2_(
	.in(HDMI_TX[1]),
	.p(HDMI_TX_p[1]),
	.n(HDMI_TX_n[1]),
);

DifferentialSignal diff3_(
	.in(HDMI_TX[2]),
	.p(HDMI_TX_p[2]),
	.n(HDMI_TX_n[2]),
);

DifferentialSignal diff4_(
	.in(HDMI_CLK),
	.p(HDMI_CLK_p),
	.n(HDMI_CLK_n),
);

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate A-Z80 CPU
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire nM1;
wire nMREQ;
wire nIORQ;
wire nRD;
wire nWR;
wire nRFSH;
wire nHALT;
wire nBUSACK;

wire nWAIT = 1;
wire nINT = vs_nintr;//(INT_EN==0)? vs_nintr : '1;// SW1 disables interrupts and, hence, keyboard
wire nNMI = KEY_NMI;                   // Pressing KEY1 issues a NMI
wire nBUSRQ = 1;

z80_top_direct_n z80_(
    .nM1 (nM1),
    .nMREQ (nMREQ),
    .nIORQ (nIORQ),
    .nRD (nRD),
    .nWR (nWR),
    .nRFSH (nRFSH),
    .nHALT (nHALT),
    .nBUSACK (nBUSACK),

    .nWAIT (nWAIT),
    .nINT (nINT),
    .nNMI (nNMI),
    .nRESET (reset),
    .nBUSRQ (nBUSRQ),

    .CLK (clk_cpu),
    .A (A),
    .D (D)
);

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Lit green LEDs to show activity on a Kempston compatible joystick
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//assign LEDG[0] = !kempston[0]; // UP
//assign LEDG[1] = !kempston[1]; // DOWN
//assign LEDG[2] = !kempston[2]; // LEFT
//assign LEDG[3] = !kempston[3]; // RIGHT
//assign LEDG[4] = !kempston[4]; // FIRE

endmodule
