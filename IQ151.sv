//============================================================================
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
//
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

//assign ADC_BUS  = 'Z;
//assign USER_OUT = '1;

wire RXD = USER_IN[0];
wire TXD;
assign USER_OUT[1:0] = {TXD, 1'b1};

assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 0;
assign AUDIO_MIX = 3;

wire LED_YELLOW;
wire LED_RED;

assign LED_POWER = 2'b00;
assign LED_USER = LED_RED;
assign LED_DISK = { 1'b1, LED_YELLOW };
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

// IQ151 videoresolution is 512 column pixels x 256 row pixels

assign VIDEO_ARX = 8'd4;
assign VIDEO_ARY = 8'd3; 



`include "build_id.v" 
localparam CONF_STR = {
   "IQ151;;",
   "-;",
   "O1,RAM,32kB,64kB;",
   "-;",
   "O2,Video Module,Video32,Video64;",
   
   "O3,Graphics Module,On,Off;",
   "-;",
   "O45,Language Module,None,Basic G,Basic 6,Amos ASM+PAS+PAS1;",
   "-;",
   "O6,SD-Rom (Staper) Module,On,Off;",
   "O7,RS232 Module,Sestyk (8251),None;",
   "-;",
//   "O78,RS232 Module,None,Sestyk (8251),SERI (Z80-SIO);",
//   "O9,Floppy Module,Disc2 (8272),None;",
//   "S0,IQD,Mount A:;",
//	"S1,IQD,Mount B:;",

//H{Index} - Prefix to 'O' option which hides the option if menumask[Index] is set.
//h{Index} - Same as 'H', but hides the option if menumask[Index] is NOT set.
//D{Index} - Prefix to 'O' option which disables the option if menumask[Index] is set.
//d{Index} - Same as 'D', but disables the option if menumask[Index] is NOT set.	
   
   "R0,Reset IQ151;",
   "V,v",`BUILD_DATE 
};


wire  [1:0] buttons;
wire [31:0] status;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;
wire        ioctl_download;
wire  [7:0] ioctl_index;
wire ioctl_wait;

wire [31:0] sd_lba;
wire  [1:0] sd_rd;
wire  [1:0] sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire  [1:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;

hps_io #(.CONF_STR(CONF_STR), .STRLEN($size(CONF_STR)>>3)) hps_io
(
   .clk_sys(clk_sys),
   .HPS_BUS(HPS_BUS),

   .buttons(buttons),
   .status(status),
   .status_menumask({status[5]}),
   
   .ps2_key(ps2_key),
   .ps2_mouse(ps2_mouse),
      
   .ioctl_wr(ioctl_wr),
   .ioctl_addr(ioctl_addr),
   .ioctl_dout(ioctl_data),
   .ioctl_download(ioctl_download),
   .ioctl_index(ioctl_index),
   .ioctl_wait(ioctl_wait),

//   .sd_lba(sd_lba),
//   .sd_rd(sd_rd),
//   .sd_wr(sd_wr),
//   .sd_ack(sd_ack),
//   .sd_buff_addr(sd_buff_addr),
//   .sd_buff_dout(sd_buff_dout),
//   .sd_buff_din(sd_buff_din),
//   .sd_buff_wr(sd_buff_wr),

   .img_mounted(img_mounted),
   .img_readonly(img_readonly),
   .img_size(img_size)
);



///////////////////////   CLOCKS   ///////////////////////////////

wire locked;
reg  clk_sys;        // IQ151 system clock (for 8224) is 18.432MHz
wire clk_sysDouble;  // double osc freq for grafik module
wire clk_disc2;      // 8MHz clock
wire clk_sysX; 

pll pll
(
   .refclk(CLK_50M),
   .rst(0),
   .locked(locked),
   .outclk_0(clk_sysDouble),
   .outclk_1(clk_sysX),
   .outclk_2(clk_disc2)
   
//.outclk_1(clk_sysDouble)	
);

wire reset = RESET | status[0] | buttons[1] | ~(status_reset == 5'd0);
reg [5:2] last_status;
reg [4:0] status_reset = 0;

always @(posedge clk_sysDouble)
   clk_sys <= ~clk_sys;


//-------------------------------------------------------------------------------
//  Cassette audio in 
//
(* keep *) wire lineIn;

ltc2308_tape ltc2308_tape
(
   .clk(CLK_50M),
   .ADC_BUS(ADC_BUS),
   .dout(lineIn)
);


//////////////////////////////////////////////////////////////////

wire clk_video;
wire SS_n;
wire SR_n;
wire ZS_n;
wire ZR_n;
wire Zat_n;
wire pixel;
wire beeper;

IQ151_core IQ151_core
(
   .clk_50M(CLK_50M),
   .clk_sysDouble(clk_sysDouble),
   .clk_sys(clk_sys),
   .clk_disc2(clk_disc2),
   
   .reset_main(reset),
   .ps2_key(ps2_key),
   
   .clk_video(clk_video),
   .pixel(pixel),
   .SS_n(SS_n),
   .SR_n(SR_n),
   .ZS_n(ZS_n),
   .ZR_n(ZR_n),
   .Zat_n(Zat_n),
   
   .lineIn(lineIn),
   .RXD(RXD),
   .TXD(TXD),
   .beeper(beeper),
   
   .RAMSize(status[1]),
   .video(status[2]),
   .graphicsModuleOn(~status[3]),
   .basicModule(status[5:4]),
   .staperModuleOn(~status[6]),
   .sestykModuleOn(~status[7]),

   .LED_YELLOW(LED_YELLOW),
   .STAPE_LED(LED_RED),
   
   // SPI signals
   .SD_SCK(SD_SCK),
   .SD_MOSI(SD_MOSI),
   .SD_MISO(SD_MISO),
   .SD_CS(SD_CS)
   
   
//   sd_lba(sd_lba),
//   sd_rd(sd_rd),
//   sd_wr(sd_wr),
//   sd_ack(sd_ack),
//   sd_buff_addr(sd_buff_addr),
//   sd_buff_dout(sd_buff_dout),
//   sd_buff_din(sd_buff_din),
//   sd_dout_strobe(sd_buff_wr),
//   
//   img_mounted(img_mounted),
//   img_readonly(img_readonly),
//   img_size(img_size),
//   
//   .ForceMGFOff(status[10])
);


assign AUDIO_L = (beeper ? 16'h0FFF : 16'h00);
assign AUDIO_R = (beeper ? 16'h0FFF : 16'h00);


reg clk_video_sample;
always @(negedge clk_sysDouble)
   clk_video_sample <= ~clk_video_sample;

assign CLK_VIDEO = clk_sysDouble;
assign CE_PIXEL = ~clk_video;

assign VGA_R  = pixel  ? 8'hFF : 8'h00;
assign VGA_G  = pixel  ? 8'hFF : 8'h00;
assign VGA_B  = pixel  ? 8'hFF : 8'h00;
assign VGA_HS = ~SR_n;
assign VGA_VS = ~SS_n;
assign VGA_DE = Zat_n ;


endmodule
