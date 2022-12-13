//============================================================================
// Sinclair ZX Spectrum ULA
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
module ula
(
    //-------- Clocks and reset -----------------
    input wire CLOCK_10,
	 input wire cpu_turbo,               // CPU turbo speed (x2)
	 input wire ula_turbo,					// ULA Turbo speed (x2)
    output wire clk_vram,
    input wire nreset,              // Active low reset
    output wire locked,             // PLL is locked signal

    //-------- CPU control ----------------------
    output wire clk_cpu,            // Generates CPU clock of 3.5 MHz
    output wire vs_nintr,           // Generates a vertical retrace interrupt

    //-------- Address and data buses -----------
    input wire [15:0] A,            // Input address bus
    input wire [7:0] D,             // Input data bus
    output wire [7:0] ula_data,     // Output data
    input wire io_we,               // Write enable to data register through IO

    output wire [12:0] vram_address,// ULA video block requests a byte from the video RAM
    input wire [7:0] vram_data,     // ULA video block reads a byte from the video RAM

    //-------- PS/2 Keyboard --------------------
    input wire PS2_CLK,
    input wire PS2_DAT,
    output wire pressed,

    //-------- Audio (Tape player) --------------
  /*  inout wire I2C_SCLK,
    inout wire I2C_SDAT,
    output wire AUD_XCK,
    output wire AUD_ADCLRCK,
    output wire AUD_DACLRCK,
    output wire AUD_BCLK,
    output wire AUD_DACDAT,*/
	 output wire AUD_OUT,
    input wire AUD_IN,
    output reg beeper,
	 input wire tape_sound,
    //-------- VGA connector --------------------
    output wire VGA_R,
    output wire VGA_G,
    output wire VGA_B,
    output reg VGA_HS,
    output reg VGA_VS
);
`default_nettype none

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate PLL and clocks block
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire clk_pix;                       // VGA/HDMI pixel clock (25.2 MHz)
wire clk_pix_x5;							// pixel clock x5
wire clk_28;								
wire clk_ula;                       // ULA master clock (14 MHz)

assign clk_vram = clk_pix_x5;

ula_pll pll_( .locked(locked), .inclk0(CLOCK_10), .c0(clk_pix), .c1(clk_pix_x5), .c2(clk_28) );

clocks clocks_( .clk_main(clk_28), .ula_turbo(ula_turbo), .cpu_turbo(cpu_turbo), .clk_ula(clk_ula), .clk_cpu(clk_cpu) );

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// The border color index
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
reg [2:0] border;                   // Border color index value

always @(posedge clk_cpu)
begin
    if (A[0]==0 && io_we==1) begin
        border <= D[2:0];
		  // to_analog output
		  AUD_OUT <=  (tape_sound ? (~AUD_IN):0) ^ D[4];
        // EAR output (produces a louder sound)
        //pcm_outl[14] <= D[4];       // Why [14] and not [15]? Less loud.
        //pcm_outr[14] <= D[4];
        // MIC (echoes the input)
        //pcm_outl[13] <= D[3];
        //pcm_outr[13] <= D[3];
        // Let us hear the tape loading!
        //pcm_outl[12] <= pcm_inl[14] | pcm_inr[14];
        //pcm_outr[12] <= pcm_inl[14] | pcm_inr[14];
        // Let us see the tape loading!
        beep <= (AUD_IN) ^ D[4] ^ D[3];
    end
end
// Show the beeper visually by dividing the frequency with some factor to generate LED blinks
reg beep;                           // Beeper latch
reg [6:0] beepcnt;                  // Beeper counter
always @(posedge beep)
begin
    beepcnt <= beepcnt - '1;
    if (beepcnt==0) beeper <= ~beeper;
end

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate ULA's video subsystem
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
video video_( .* );

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate keyboard support
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire [7:0] scan_code;
wire scan_code_ready;
wire scan_code_error;

ps2_keyboard ps2_keyboard_( .*, .clk(clk_cpu) );

wire [4:0] key_row;
zx_keyboard zx_keyboard_( .*, .clk(clk_cpu) );

always_comb
begin
    ula_data = 8'hFF;
    // Regular IO at every odd address: line-in and keyboard
    if (A[0]==0) begin
        //ula_data = { 1'b1, pcm_inl[14] | pcm_inr[14], 1'b1, key_row[4:0] };
        ula_data = { 1'b1, AUD_IN , 1'b1, key_row[4:0] };
	 end
end

endmodule
