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
   `include "sys/emu_ports.vh"
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
   "OA,Monitor,Std,CPM;",

   "-;",
   "O2,Video Module,Video32,Video64;",
   "O3,Graphics Module,On,Off;",
   "-;",
   "O45,Language Module,None,Basic G,Basic 6,Amos ASM+PAS+PAS1;",
   "-;",
   "O6,SD-Rom (Staper) Module,On,Off;",
   "O7,RS232 Module,Sestyk (8251),None;",
//   "O78,RS232 Module,None,Sestyk (8251),SERI (Z80-SIO);",
   
   "-;",
   "O9,Floppy Module,Disc2 (8272),None;",
   "S1,DSK,Floppy 0 (A):;",
   "S0,DSK,Floppy 1 (B):;",

   "-;",
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

wire [31:0] sd_lba[2];
wire  [1:0] sd_rd;
wire  [1:0] sd_wr;
wire  [1:0] sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[2];
wire        sd_buff_wr;
wire  [1:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;

hps_io #(.CONF_STR(CONF_STR), .STRLEN($size(CONF_STR)>>3), .VDNUM(2)) hps_io
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

   .sd_lba(sd_lba),
   .sd_rd(sd_rd),
   .sd_wr(sd_wr),
   .sd_ack(sd_ack),
   .sd_buff_addr(sd_buff_addr),
   .sd_buff_dout(sd_buff_dout),
   .sd_buff_din(sd_buff_din),
   .sd_buff_wr(sd_buff_wr),

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

wire  [7:0] IQ_sd_buff_din;
wire [31:0] IQ_sd_lba;

assign sd_buff_din[0]=IQ_sd_buff_din;
assign sd_buff_din[1]=IQ_sd_buff_din;
assign sd_lba[0]=IQ_sd_lba;
assign sd_lba[1]=IQ_sd_lba;


IQ151_core IQ151_core
(
   .clk_50M(CLK_50M),
   .clk_sysDouble(clk_sysDouble),
   .clk_sys(clk_sys),
   
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
   .monitor(status[10]),
   .video(status[2]),
   .graphicsModuleOn(~status[3]),
   .basicModule(status[5:4]),
   .staperModuleOn(~status[6]),
   .sestykModuleOn(~status[7]),
   .floppyModule(~status[9]),

   .LED_FLOPPY(LED_YELLOW),
   .LED_STAPE(LED_RED),
   
   // SPI signals
   .SD_SCK(SD_SCK),
   .SD_MOSI(SD_MOSI),
   .SD_MISO(SD_MISO),
   .SD_CS(SD_CS),   
   
   .sd_lba(IQ_sd_lba),
   .sd_rd(sd_rd),
   .sd_wr(sd_wr),
   .sd_ack(sd_ack),
   .sd_buff_addr(sd_buff_addr),
   .sd_buff_dout(sd_buff_dout),
   .sd_buff_din(IQ_sd_buff_din),
   .sd_buff_wr(sd_buff_wr),
   
   .img_mounted(img_mounted),
   .img_readonly(img_readonly),
   .img_size(img_size[31:0])
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
