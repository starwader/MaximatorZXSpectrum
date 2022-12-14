//============================================================================
// Sinclair ZX Spectrum ULA
//
// This module contains hdmi video support.
//
//  Copyright (C) 2022-2023  Jakub Budrewicz (HDMI)
//  Copyright (C) 2014-2016  Goran Devic (VGA)
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

module hdmi_video
(
    input wire clk_pix,         // Input pixel clock of 25.2 MHz
    input wire clk_pix_x5,         // Input pixel clock x5

    output wire VGA_R,    // Output VGA R component
    output wire VGA_G,    // Output VGA G component
    output wire VGA_B,    // Output VGA B component
    output reg VGA_HS,          // Output VGA horizontal sync
    output reg VGA_VS,          // Output VGA vertical sync
    output wire vs_nintr,       // Vertical retrace interrupt

    output wire [12:0] vram_address,// Address request to the video RAM
    input wire [7:0] vram_data, // Data read from the video RAM

    input wire [2:0] border,     // Border color index value

	 // HDMI output
	 output [2:0] HDMI_TX,
	 output HDMI_CLK,
	 inout HDMI_SDA,
	 inout HDMI_SCL,
	 input HDMI_HPD

);


logic [23:0] rgb = 24'd0;
logic [9:0] vga_hc, vga_vc, screen_start_x, screen_start_y, frame_width, frame_height, screen_width, screen_height;

//todo rename vga_hc and etc
reg [4:0] frame;                // Frame counter, used for the flash attribute


// Generate interrupt at around the time of the vertical retrace start
assign vs_nintr = (vga_vc=='0 && vga_hc[9:7]=='0)? '0 : '1;

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// VGA active display area 640x480
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire disp_enable;
assign disp_enable = vga_hc>=144 && vga_hc<784 && vga_vc>=35 && vga_vc<515;

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Fetch screen data from RAM based on the current video counters
// Spectrum resolution of 256x192 is line-doubled to 512x384 sub-frame
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire screen_en;
assign screen_en = vga_hc>=208 && vga_hc<720 && vga_vc>=83 && vga_vc<467;

reg [7:0] bits_prefetch;        // Line bitmap data prefetch register
reg [7:0] attr_prefetch;        // Attribute data prefetch register

// At the first clock of each new character, prefetch values are latched into these:
reg [7:0] bits;                 // Current line bitmap data register
reg [7:0] attr;                 // Current attribute data register

wire [4:0] pix_x;               // Column 0-31
wire [7:0] pix_y;               // Active display pixel Y coordinate
// We use 16 clocks for 1 byte of display; also prefetch 1 byte (+16)
wire [9:0] xd = vga_hc-10'd192; // =vga_hc-208+16
assign pix_x = xd[8:4];         // Effectively divide by 16
wire [9:0] yd = vga_vc-10'd83;  // Lines are (also) doubled vertically
assign pix_y = yd[8:1];         // Effectively divide by 2


always @(posedge clk_pix)
begin
    case (vga_hc[3:0])
                // Format the address into the bitmap which is a swizzle of coordinate parts
        10:     vram_address <= {pix_y[7:6], pix_y[2:0], pix_y[5:3], pix_x};
        12:     begin
                    bits_prefetch <= vram_data;
                    // Format the address into the attribute map
                    vram_address <= {3'b110, pix_y[7:3], pix_x};
                end
        14:     attr_prefetch <= vram_data;
        // Last tick before a new character: load working bitmap and attribute registers
        15:     begin
                    attr <= attr_prefetch;
                    bits <= bits_prefetch;
                end
    endcase
end

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Pixel data generator
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire [2:0] ink;                 // INK color (index into the palette)
wire [2:0] paper;               // PAPER color
wire bright;                    // BRIGHT attribute bit
wire flash;                     // FLASH attribute bit
wire pixbit;                    // Current pixel to render
wire inverted;                  // Are the pixel's attributes inverted?

// Output a pixel bit based on the VGA horizontal counter. This could have been
// a shift register but a mux works as well since we are writing out each pixel
// twice (required by this VGA clock rate)
always @(*) // always_comb
begin
    case (vga_hc[3:1])
        0:      pixbit = bits[7];
        1:      pixbit = bits[6];
        2:      pixbit = bits[5];
        3:      pixbit = bits[4];
        4:      pixbit = bits[3];
        5:      pixbit = bits[2];
        6:      pixbit = bits[1];
        7:      pixbit = bits[0];
    endcase
end

assign flash  = attr[7];
assign bright = attr[6];
assign inverted = flash & frame[4];
assign ink    = inverted? attr[5:3] : attr[2:0];
assign paper  = inverted? attr[2:0] : attr[5:3];

// The final color index depends on where we are (active display area, border) and
// whether we are rendering INK or PAPER color, including the brightness bit
assign cindex = screen_en? pixbit? {bright,ink} : {bright,paper} : {1'b0,border[2:0]};

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Color lookup table
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire [3:0] cindex;
wire [2:0] pix_rgb;



always @(*) // always_comb
begin
    case (cindex[3:0])
        // Normal color
        0:   rgb = 24'h000000; // BLACK
        1:   rgb = 24'h0000E0; // BLUE
        2:   rgb = 24'hE00000; // RED
        3:   rgb = 24'hE000E0; // MAGENTA
        4:   rgb = 24'h00E000; // GREEN
        5:   rgb = 24'h00E0E0; // CYAN
        6:   rgb = 24'hE0E000; // YELLOW
        7:   rgb = 24'hE0E0E0; // WHITE
        // "Bright" bit is set
        8:   rgb = 24'h000000; // BLACK remains black
        9:   rgb = 24'h0000FF;
        10:  rgb = 24'hFF0000;
        11:  rgb = 24'hFF00FF;
        12:  rgb = 24'h00FF00;
        13:  rgb = 24'h00FFFF;
        14:  rgb = 24'hFFFF00;
        15:  rgb = 24'hFFFFFF;
    endcase
end

hdmi #(
		.VIDEO_ID_CODE(1), 
		.VIDEO_REFRESH_RATE(60), 
		.AUDIO_RATE(48000), 
		.AUDIO_BIT_WIDTH(16), 
		.VENDOR_NAME("Max10"),
		.PRODUCT_DESCRIPTION("ZX Spectrum"),
		.SOURCE_DEVICE_INFORMATION(8)) hdmi_(	
	.clk_pixel_x5(clk_pix_x5), 
	.clk_pixel(clk_pix), 
	//.clk_audio(clk_audio), 
	.rgb(rgb), 
	//.audio_sample_word('{audio_sample_word_dampened, audio_sample_word_dampened}), 
	.tmds(HDMI_TX), 
	.tmds_clock(HDMI_CLK), 
	.cx(vga_hc), 
	.cy(vga_vc),
  .frame_width(frame_width),
  .frame_height(frame_height),
  .screen_width(screen_width),
  .screen_height(screen_height),
  .reset(0)
	);

endmodule
