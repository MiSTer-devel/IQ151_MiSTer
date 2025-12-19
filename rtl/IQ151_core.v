`default_nettype none

module IQ151_core
(
   input  wire        clk_50M,          // 50MHz main clock
   input  wire        clk_sysDouble,    // double osc freq for grafik module
   input  wire        clk_sys,          // IQ151 system clock (for 8224) is 18.432MHz
   input  wire        clk_disc2,        // 8MHz

   input  wire        reset_main,
   input  wire [10:0] ps2_key,

   output wire        clk_video,
   output wire        pixel,   
   output wire        SS_n,             // synchronizace snímků = Vertical sync
   output wire        SR_n,             // synchronizace řádků = Horizontal sync
   output wire        ZS_n,             // zatmeni snimku = Vertical blank
   output wire        ZR_n,             // zatmeni radku = Horizontal blank
   output wire        Zat_n,            // zatmeni ... 1 = display ON, 0 = display off)

   input  wire        lineIn,           // Cassette ine in for loading data
   input  wire        RXD,              // Serial line module RXD/TXD
   output wire        TXD,
   output wire        beeper,

   input  wire        RAMSize,          // 0 = 32Kb, 1 = 64kB
   input  wire        video,            // 0 = Video32, 1 = Video64
   input  wire        graphicsModuleOn,
   input  wire [1:0]  basicModule,      // 0 = None, 1 = Basic G, 2 = Basic 6, 3 = Amos ASM+PAS+PAS1
   input  wire        staperModuleOn,   // SD-Card interface
   input  wire        sestykModuleOn,   // serial interface

   output wire        LED_YELLOW,
   output wire        STAPE_LED,        // STAPER module activity LED

   //SD-SPI - for Stapper Module (SD-Card interface)
   output wire        SD_SCK,
   output wire        SD_MOSI,
   input  wire        SD_MISO,
   output wire        SD_CS

//    input wire   [1:0] img_mounted,
//    input wire         img_readonly,
//    input wire  [31:0] img_size,
//    input wire   [1:0] density,
//
//    output wire [31:0] sd_lba,
//    output wire  [1:0] sd_rd,
//    output wire  [1:0] sd_wr,
//    input  wire        sd_ack,
//    input  wire  [8:0] sd_buff_addr,
//    input  wire  [7:0] sd_buff_dout,
//    output wire  [7:0] sd_buff_din,
//    input  wire        sd_dout_strobe
);


//-------------------------------------- i8224 + i8080 + i8228 ------------------------------------------------------
//
wire        osc;
wire        phi1;
wire        phi2;
wire        sync;
wire        INIT;        // reset from i8224 to 8080
wire        ststb_n;     // strobe from 8224 to 8228
wire        hold = 1'b0; // 8080 hold pin
wire [15:0] AP;
wire [15:0] A = A_enable ? AP : 16'd0;
wire        A_enable;
wire  [7:0] DP;
wire        int8080;
wire        int8080Enable;
wire        wait8080;    // output from CPU
wire        dbin;
wire        wr_n;
wire        hlda;
wire        readyin = NRDY_n;
wire        ready;
wire        memr_n;
wire        memw_n;
wire        ior_n;
wire        iow_n;
wire        inta_n ;
wire        busen_n = hlda;
wire        sp_en;
wire  [7:0] databus_from_8228;
wire  [7:0] databus_to_8228;
wire  [7:0] databus_from_cpu;
wire  [7:0] databus_to_cpu;
wire  [7:0] PIC_D_out;
wire  [7:0] interrupt_vector;

i8224 i8224
(
   .osc(osc),
   .phi1(phi1),
   .phi2(phi2),
   .ststb_n(ststb_n),
   .reset(INIT),
   .ready(ready),
   .clk(clk_sys),
   .sync(sync),
   .resetin_n(~reset_main),
   .readyin(readyin)
);

i8228 i8228
(
   .memr_n(memr_n),
   .memw_n(memw_n),
   .ior_n(ior_n),
   .iow_n(iow_n),
   .inta_n(inta_n),
   .inta_12V(1'b0),
   .databus_from_cpu(databus_from_cpu),
   .databus_to_cpu(databus_to_cpu),
   .databus_from_8228(databus_from_8228),
   .databus_to_8228(databus_to_8228),
   .busen_n(busen_n),
   .ststb_n(ststb_n),
   .dbin(dbin),
   .wr_n(wr_n),
   .hlda(hlda)
);

vm80a_core cpu
(
   .pin_clk(~osc),
   .pin_f1(phi1),
   .pin_f2(phi2),
   .pin_reset(INIT),
   .pin_hold(hold),
   .pin_ready(ready),
   .pin_int(int8080),
   .pin_inte(int8080Enable),
   .pin_a(AP),
   .pin_aena(A_enable),
   .pin_din(databus_to_cpu),
   .pin_dout(databus_from_cpu),
   .pin_dbin(dbin),
   .pin_wr_n(wr_n),
   .pin_hlda(hlda),
   .pin_sync(sync)
);

pic i8259
(
   .clk(osc),
   .rst_n(~INIT),
   .master_address(A[8]),
   .master_read(~CS59_n & ~ior_n),
   .master_readdata(PIC_D_out),
   .master_write(~CS59_n & ~iow_n),
   .master_writedata(databus_from_8228),
   //.interrupt_input_pins({~SR_n, ~SS_n, BREAK, STAPE_INTRb, STAPE_INTRa, 3'h0}),
   //.interrupt_input_pins({~SR_n, ~SS_n, BREAK, STAPE_INTRb & staperModuleOn, STAPE_INTRa & staperModuleOn, TxD_INT & sestykModuleOn, RxD_INT & sestykModuleOn, 1'h0}),
   .interrupt_input_pins({~SR_n, ~SS_n, BREAK, 5'h0}),
   .interrupt_do(int8080),
   .interrupt_vector(interrupt_vector),
   .interrupt_ack(~inta_n)
);

//-------------------------------------- CS decoder -----------------------------------------------------------------
//
reg  BootStrap_n; // this cause ROM remap after start/reset
reg  FR;          // signal for MH102
reg  RN;          // signal for MH102
wire CSx     =  (A[15:10] == 6'b1000_00); // 0x80 - 0x83 ... access to registers with BootStrap_n, FR, RN
wire CS55_n  = ~(A[15:10] == 6'b1000_01); // 0x84 - 0x87 ... Keyboard 8255 chip
wire CS59_n  = ~(A[15:10] == 6'b1000_10); // 0x88 - 0x8B ... IRQ 8259 chip
wire CS102_n = ~(A[15:10] == 6'b1000_11); // 0x8C - 0x8F
wire CS101_n = ~(A[15:10] == 6'b1001_00); // 0x90 - 0x93

always @(posedge clk_sys)
begin
   if (INIT)
      {RN, FR, BootStrap_n} <= 3'b000;
   else if (~iow_n & CSx)
      {RN, FR, BootStrap_n} <= databus_from_8228[2:0];
end


assign databus_to_8228 =
            ~(CS51_n     | ior_n)                           ? DOut_Sestyk :      // Sestyk9 module (Serial interface)
            ~(CS55_n     | ior_n)                           ? DO_8255 :          // Keyboard 8255 chip
            ~(CS59_n     | ior_n)                           ? PIC_D_out :        // IRQ 8259 chip
            ~(STAPE_CS_n | ior_n)                           ? StapeDout :        // Stapper module (=SD ROM)

//             (DISC2_8272_CS      & ~ior_n)                  ? DISC2_DOut :       // Disc2 data from floppy
//             (DISC2_EPROM_CS     & ~memr_n)                 ? DISC2_EPROM_DOut : // Disc2 data from EPROM with firmware

            // video ... 0 = Video32, 1 = Video64  
            (~RAM_Video32_n & ~memr_n & ~video)             ? DOut32 :           // Video32 A=EC00
            (~RAM_Video64_n & ~memr_n &  video)             ? DOut64 :           // Video64 A=E800
            ((A[15:10] == 6'b1111_11) & ~ior_n & video)     ? DOut64 :           // Video64 module detection A=FF D=8'hFE
            (~RAM_BasicG_n & ~BasigG_Off & ~memr_n)         ? DOutBasicG :       // Basic G Eprom access
            (~RAM_Basic6_n & ~Basig6_Off & ~memr_n)         ? DOutBasic6 :       // Basic 6 Eprom access
            (~RAM_Amos_n   & ~Amos_Off   & ~memr_n)         ? DOutAmos   :       // Amos ASM+PAS+PAS1 Eprom access
            (CSEPROM     & ~memr_n)                         ? data_EPROM_out :   // EPROM 0xF000 - 0xFFFF
            (CSRAM & RAM & ~memr_n)                         ? data_RAM_out :     // RAM
            (~inta_n  )                                     ? interrupt_vector : // IRQ Vector ********************má tam být i to int8080????????
            //(~inta_n     & int8080)                      ? interrupt_vector :   // IRQ Vector            

            8'hFF; // data bus pull-up rezistors = 0xFF


//--------------------------------------  refresh address and MUX generator -----------------------------------------
//
reg [6:0] refreshAddress;
reg       rd;
reg       refresh_clk;

always @(INIT or ststb_n)
begin
   if (INIT)
      rd <= ~refresh_clk;
   else if (~ststb_n)
      rd <= DP[5];
end

always @(posedge phi2 or posedge ~memr_n)
begin
   if (~memr_n)
      refresh_clk <= 0;
   else if (phi2)
      refresh_clk <= ~rd;
end

always @(posedge refresh_clk)
begin
   refreshAddress <= refreshAddress + 1'b1;
end


//-------------------------------------- Keyboard + Beeper ----------------------------------------------------------
//
wire [7:0] DO_8255;
wire [7:0] PA_in;
wire [7:0] PA_out;
wire [7:0] PB_in;
wire [7:0] PB_out;
wire [7:0] PC_in;
wire [7:0] PC_out;
wire       PAisInput;
wire       PBisInput;
wire       FA;
wire       FB;
wire       SH;
wire       CTRL;
wire       BREAK;

i8255 Key8255
(
   .PA_In(PA_in),
   .PA_Out(PA_out),
   .PB_In(PB_in),
   .PB_Out(PB_out),
   .PC_In(PC_in),
   .PC_Out(PC_out),
   .PAisInput(PAisInput),
   .PBisInput(PBisInput),
   .D_In(databus_from_8228),
   .D_Out(DO_8255),
   .clk(osc),
   .RD_n(ior_n),
   .WR_n(iow_n),
   .A(A[9:8]),
   .RESET(INIT),
   .CS_n(CS55_n)
);

keyboard keyboard
(
   .reset(INIT),
   .clk(osc),
   .ps2_key(ps2_key),
   .X_in(PAisInput ? 8'hFF : PA_out),
   .X_out(PA_in),
   .Y_in(PBisInput ? 8'hFF : PB_out),
   .Y_out(PB_in),
   .FA(FA),
   .FB(FB),
   .SH(SH),
   .CTRL(CTRL),
   .BREAK(BREAK)
);

assign beeper     = PC_out[3];
assign PC_in[7:4] = (PC_out[2:1] == 2'b00) ? {FB, FA, CTRL, SH} : {lineIn, lineIn, SR_cnt[3], 1'b0};


//-------------------------------------- Modul STAPE + file "punch reader" ------------------------------------------
// Module STAPE = standartni periferie
//
//   PA - in - for punch reader
// PB - our - for puncher or printer
// PC - 8255 is in mode 1 and PC wires are used for hadshaking

// PC_out[0] --> INTRb
// PC_out[1] --> /output buffer B full
// PC_in[2] <--- / ACKb

// PC_out[3] --> INTRA
// PC_in[4]  <-- /strobe a
// PC_out[5] --> / input buffer A full

// PC_out[6] == 1 ---> puncher is selected
// PC_out[7] == 1 ---> printer is selected

wire [7:0] StapeDout;
wire [7:0] data_to_IQSDROM;
wire [7:0] data_from_IQSDROM;
wire [7:0] STAPE_PC_out;
wire       ack_din;          // data_in ready to be read by IQ_SDROM (300ns negative pulse)
wire       obf_din;          // data_in read - can be changed by IQ (OBF = output buffer full)
wire       stb_dout;         // data_out read by IQ - can be changed by IQ_SDROM (500ns negative pulse)
wire       ibf_dout;         // data_out ready to be read by IQ (IBF = input buffer full)
reg  [1:0] stb_dout_buf;
reg  [1:0] ack_din_buf;
wire       STAPE_CS_n = ~(A[7:2] == 6'b1111_10) | ~staperModuleOn; // 0xF8 - 0xFB
assign     STAPE_LED  = ~(STAPE_CS_n | (ior_n & iow_n));

always @(posedge osc)
begin
   stb_dout_buf <= { stb_dout_buf[0], stb_dout };
   ack_din_buf  <= { ack_din_buf[0], ack_din };
end

i8255 STAPE8255
(
   .PA_In(data_from_IQSDROM),
   .PA_Out(data_to_IQSDROM),
   //.PC_In({3'b000, stb_dout, 1'b0, ack_din, 2'b00}),
   .PC_In({3'b000, stb_dout_buf[1], 1'b0, ack_din_buf[1], 2'b00}),
   .PC_Out(STAPE_PC_out),

   .D_In(databus_from_8228),
   .D_Out(StapeDout),
   .clk(osc),

   .RD_n(ior_n),
   .WR_n(iow_n),
   .A(A[1:0]),
   .RESET(INIT),
   .CS_n(STAPE_CS_n)
);

// Port B = IQ => SD ROM
// PC_out[1] --> /output buffer B full   (obf_din) ... driven by IQ
// PC_in[2] <--- / ACKb                  (ack_din) ... driven by SD ROM

// Port A = SD ROM => IQ
// PC_in[4]  <-- /strobe a               (stb_dout) ... driven by SD ROM
// PC_out[5] --> / input buffer A full   (ibf_dout) ... driven by IQ

// PC_out[6] == 1 ---> puncher is selected

assign obf_din  = STAPE_PC_out[5];
assign ibf_dout = STAPE_PC_out[5];

IQ_SDROM IQ_SDROM
(
   .clk(clk_50M),
   .reset_in(~reset_main),

   // SPI signals
   .spi_miso(SD_MISO),
   .spi_mosi(SD_MOSI),
   .spi_clk(SD_SCK),
   .spi_cs(SD_CS),

   // communication
   .data_in(data_to_IQSDROM),     // data FROM IQ151 computer TO SDROM (8255 port PA)
   .stb_dout(stb_dout),           // data_out read by IQ - can be changed by IQ_SDROM (500ns negative pulse)
   .ibf_dout(ibf_dout),           // data_out ready to be read by IQ (IBF = input buffer full)

   .data_out(data_from_IQSDROM),  // data FROM SDROM TO IQ151 computer (8255 port PA)
   .ack_din(ack_din),             // data_in ready to be read by IQ_SDROM (300ns negative pulse)
   .obf_din(obf_din)              // data_in read - can be changed by IQ (OBF = output buffer full)
);


//-------------------------------------- EPROM ----------------------------------------------------------------------
//  4kB ... 0xF0FF - 0xFFFF
//
wire CSEPROM = (A[15:12] == 4'b1111) | ~BootStrap_n; // 0xF000 - 0xFFFF ... EPROM access
wire [7:0] data_EPROM_out;

dpram #(.ADDRWIDTH(12), .MEM_INIT_FILE("./rom/Monitor.mif")) myEPPROM
(
   .clock(clk_sys),
   .address_a(BootStrap_n ? A[11:0] : {1'b1, A[10:0]}),
   .wren_a(0),
   .q_a(data_EPROM_out)
);


//-------------------------------------- RAM 64kB -------------------------------------------------------------------
//
wire [7:0] data_RAM_out;
wire       CSRAM = RAMSize ? 1 : ~A[15]; // RAMSize ... 0 = 32Kb, 1 = 64kB
wire       RAM   = CSRAM;

reg        RAS_n;
reg        CAS_n;
reg  [4:0] RAS_CAS_cnt;
reg        phi2_last;

always @(posedge osc)
begin
   phi2_last <= phi2;

   if (phi2 & ~phi2_last)
      RAS_CAS_cnt <= 5'd6;
   else if (RAS_CAS_cnt != 5'd0)
     RAS_CAS_cnt <= RAS_CAS_cnt - 5'd1;
     
   if (RAS_CAS_cnt == 5'd6)
      RAS_n = 1'b0;
   if (RAS_CAS_cnt == 5'd1)
      RAS_n = 1'b1;
   if (RAS_CAS_cnt == 5'd4)
      CAS_n = 1'b0;
   if (RAS_CAS_cnt == 5'd0)
   begin
      RAS_n = 1'b1;
      CAS_n = 1'b1;
   end
end


// Zapis na C8000 je potreba pro rozbehnuti monitoru pri ram 64 bez basic 6 nebo basic G
// jinak se to zahryzne
dpram #(.ADDRWIDTH(16)) myRam
(
   .clock(clk_sys),
   .address_a(reset_main ? 16'hC800 : A),
   .data_a(reset_main ? 8'hFF : databus_from_8228),
   .wren_a(CSRAM & ~memw_n & ~RAS_n & ~CAS_n & RAM | reset_main),
   .q_a(data_RAM_out)
);


//-------------------------------------- Basic modules --------------------------------------------------------------
//
wire RAM_Basic6_n; // Basic 6 module is driving bus
wire RAM_BasicG_n; // Basic G module is driving bus
wire RAM_Amos_n;   // Amos ASM+PAS+PAS1 module is driving bus

wire [7:0] DOutBasicG;
wire [7:0] DOutBasic6;
wire [7:0] DOutAmos;

//   input [1:0] basicModule, // 0 = None, 1 = Basic G, 2 = Basic 6
wire BasigG_Off = ~(basicModule == 2'b01);
wire Basig6_Off = ~(basicModule == 2'b10);
wire Amos_Off   = ~(basicModule == 2'b11);

basicG basicG
(
   .osc(osc),
   .A(A),
   .D(DOutBasicG),
   .memr_n(memr_n | BasigG_Off),
   .memw_n(memw_n | BasigG_Off),
   .INIT(INIT),
   .RAM_n(RAM_BasicG_n)
);

basic6 basic6
(
   .osc(osc),
   .A(A),
   .D(DOutBasic6),
   .memr_n(memr_n | Basig6_Off),
   .memw_n(memw_n | Basig6_Off),
   .INIT(INIT),
   .RAM_n(RAM_Basic6_n)
);

amos amos
(
   .osc(osc),
   .A(A),
   .DIn(databus_from_8228),
   .DOut(DOutAmos),
   .memr_n(memr_n | Amos_Off),
   .iow_n(iow_n | Amos_Off),
   .INIT(INIT),
   .RAM_n(RAM_Amos_n)
);


//-------------------------------------- Video Modules --------------------------------------------------------------
//
reg [3:0] SR_cnt;   // SR_cnt[3] = 1 kHz
always @(posedge SR_n)
   SR_cnt <= SR_cnt + 1'b1;

wire        RAM_Video32_n; // Video 32 module is driving bus (when RAM_Video32_n = 0)
wire        RAM_Video64_n; // Video 64 module is driving bus
wire        RAM_Video_n;
wire        VID32_n;
wire        VID64_n;
wire        VIDgrafik_n;
//wire      SS_n;        // synchronizace snímků = Vertical sync
//wire      SR_n;        // synchronizace řádků = Horizontal sync
//wire      ZS_n;        // zatmeni snimku = Vertical blank
//wire      ZR_n;        // zatmeni radku = Horizontal blank

// video ... 0 = Video32, 1 = Vide64
wire       Video32_Off =  video;
wire       Video64_Off = ~video;
wire       ZAT32_n;
wire       ZAT64_n;
wire       SS32_n;
wire       SS64_n;
wire       SR32_n;
wire       SR64_n;
wire       ZS32_n;
wire       ZS64_n;
wire       ZR32_n;
wire       ZR64_n;
wire [7:0] DOut32;
wire [7:0] DOut64;
wire [7:0] DOutGrafik;

assign pixel       = (VID32_n & ~Video32_Off) | (VID64_n & ~Video64_Off) | (VIDgrafik_n & graphicsModuleOn);
assign RAM_Video_n = (RAM_Video32_n | Video32_Off) & (RAM_Video64_n | Video64_Off);

assign SS_n  = (SS32_n  | Video32_Off) & (SS64_n  | Video64_Off);
assign SR_n  = (SR32_n  | Video32_Off) & (SR64_n  | Video64_Off);

assign ZS_n  = (ZS32_n  | Video32_Off) & (ZS64_n  | Video64_Off);
assign ZR_n  = (ZR32_n  | Video32_Off) & (ZR64_n  | Video64_Off);

assign Zat_n = (ZAT32_n  | Video32_Off) & (ZAT64_n  | Video64_Off);
   
   
wire NRDY32_n;
wire NRDY64_n;
wire NRDY_grafik_n;
wire NRDY_n = (NRDY32_n | Video32_Off) & (NRDY64_n | Video64_Off) & (NRDY_grafik_n | ~graphicsModuleOn);


video32 video32
(
   .osc(osc),
   .A(A),
   .DIn(databus_from_8228),
   .DOut(DOut32),
   .memr_n(memr_n | Video32_Off),
   .memw_n(memw_n | Video32_Off),
   .RAM_n(RAM_Video32_n),
   .NRDY_n(NRDY32_n),
   .VID_n(VID32_n),
   .SS_n(SS32_n),
   .SR_n(SR32_n),
   .ZS_n(ZS32_n),
   .ZR_n(ZR32_n),
   .ZAT_n(ZAT32_n)
);

video64 video64
(
   .osc(osc),
   .INIT(INIT),
   .A(A),
   .DIn(databus_from_8228),
   .DOut(DOut64),
   .memr_n(memr_n | Video64_Off),
   .memw_n(memw_n | Video64_Off),
   .ior_n(ior_n | Video64_Off),
   .iow_n(iow_n | Video64_Off),
   .RAM_n(RAM_Video64_n),
   .NRDY_n(NRDY64_n),
   .VID_n(VID64_n),
   .SS_n(SS64_n),
   .SR_n(SR64_n),
   .ZS_n(ZS64_n),
   .ZR_n(ZR64_n),
   .ZAT_n(ZAT64_n)
);

grafik grafik
(
   .osc(osc),
   .clk_sysDouble(clk_sysDouble),
   .INIT(INIT),
   .A(A),
   .DIn(databus_from_cpu),
   .DOut(DOutGrafik),
   .video(video),
   .ior_n(ior_n | ~graphicsModuleOn),
   .iow_n(iow_n | ~graphicsModuleOn),
   .NRDY_n(NRDY_grafik_n),
   .VID_n(VIDgrafik_n),
   .ZS_n(ZS_n),
   .ZR_n(ZR_n),
   .VCLK(clk_video),
   .phi2(phi2)
);


//-------------------------------------- RS232 Modules --------------------------------------------------------------
//
assign TXD        = TxD_Sestyk | ~sestykModuleOn;
assign RxD_Sestyk = RXD        | ~sestykModuleOn;

// --- SESTYK (8251) ---
wire       CS51_n       = ~((A[7:1] == 7'b1110_010) & sestykModuleOn); // 0xE4 - 0xE5
wire [7:0] DOut_Sestyk;
wire       TxD_Sestyk; 
wire       RxD_Sestyk;
wire       TxD_INT;        // ~INT2
wire       RxD_INT;        // ~INT1
//reg  [3:0] baseDiv;        // phi / 13 = 2 048MHz / 13 = 157 538Hz
reg  [6:0] Clk_Sestyk_Div;
wire       Clk_Sestyk;

//always @(posedge phi2)
//begin
//   baseDiv <= baseDiv + 1'b1;
//   if (baseDiv == 4'd12)
//      begin
//         baseDiv <= 4'd0;
//         Clk_Sestyk_Div <= Clk_Sestyk_Div + 1'b1;
//      end
//end
//
//// Clk_Sestyk_Div[ ] //   2 = 78,769 baud (Hz) ???
//// Clk_Sestyk_Div[0] //   4 = 39,385 baud (Hz) 
//// Clk_Sestyk_Div[1] //   8 = 19,692 baud (Hz)
//// Clk_Sestyk_Div[2] //  16 =  9,846 baud (Hz)
//// Clk_Sestyk_Div[3] //  32 =  4,923 baud (Hz)
//// Clk_Sestyk_Div[4] //  64 =  2,462 baud (Hz)
//// Clk_Sestyk_Div[5] // 128 =  1,231 baud (Hz)
//
//assign Clk_Sestyk  = Clk_Sestyk_Div[2]; //  16 =  9,846 baud (Hz)

reg  [10:0] mainClkDiv;        // 50M / 1302 = 38402 Hz
always @(posedge clk_50M)
begin
   if (mainClkDiv == 0)
   begin
      mainClkDiv <= 1302;
      Clk_Sestyk_Div <= Clk_Sestyk_Div + 1'b1;
   end
   else
     mainClkDiv <= mainClkDiv - 1;
end

//                            38,402
// Clk_Sestyk_Div[0] //   2 = 19,201 baud (Hz) 
// Clk_Sestyk_Div[1] //   4 =  9,600 baud (Hz)
// Clk_Sestyk_Div[2] //   8 =  4,800 baud (Hz)
// Clk_Sestyk_Div[3] //  16 =  2,400 baud (Hz)
// Clk_Sestyk_Div[4] //  32 =  1,200 baud (Hz)

assign Clk_Sestyk  = Clk_Sestyk_Div[1]; //  4 =  9,600 baud (Hz)

i8251 Sestyk_8251
(
   .CLK(phi2),
   .RESET(INIT),
   .CS_n(CS51_n),
   .WR_n(iow_n),
   .RD_n(ior_n),
   .CD(A[0]),         // 1 = Control, 0 = Data
   .DIn(databus_from_8228),
   .DOut(DOut_Sestyk),
   .RxD(RxD_Sestyk),
   .RxRDY(RxD_INT),
   .RxC_n(Clk_Sestyk),
   .TxD(TxD_Sestyk),
   .TxRDY(TxD_INT), // = buffer is empty
//   .TxEMPTY(),
   .TxC_n(Clk_Sestyk)
//   .DSR_n(),
//   .DTR_n(),
//   .CTS_n(),
//   .RTS_n()
);


//-------------------------------------- DISC2 Module ---------------------------------------------------------------
//
wire DISC2_8272_CS  = A[15:9] == 7'b1010_101;   // 0xAA - 0xAB
wire DISC2_SET      = A[15:8] == 8'b1010_1100;  // 0xAC      ???????????????????????????????????????????????????????????????????????????
//wire DISC2_EPROM_CS = A[15:11] == 5'b1010_0;    // 0xA0 - 0xA7 ... location based on 74188 from sapi.cz
wire DISC2_EPROM_CS = A[15:11] == 5'b1110_0;    // 0xA0 - 0xA7 ... location based IQ151 java emulator from Omikron88


wire [7:0] DISC2_DOut;// = (fdc_sel & ~ior) ? u765_dout : 8'hFF;
wire [7:0] DISC2_EPROM_DOut;

//dpram #(.ADDRWIDTH(14), .MEM_INIT_FILE("./rom/Disc2.mif")) myEPPROM_Disc2
//(
//   .clock(clk_sys),
//   .address_a(A[13:0]),
//   .wren_a(0),
//   .q_a(DISC2_EPROM_DOut)
//); 
//
//wire motor = 1;
//    reg  [1:0] u765_ready = 0;
//    always @(posedge clk_sys) if(img_mounted[0]) u765_ready[0] <= |img_size;
//    always @(posedge clk_sys) if(img_mounted[1]) u765_ready[1] <= |img_size;
//
//    wire fdc_int;
//    u765 u765
//    (
//        .reset(INIT),
//
//        .clk_sys(clk_sys),
//        .ce(clk_disc2),
//        .a0(A[0]),
//        .ready(u765_ready),
//        .motor({motor,motor}),
//        .available(2'b11),
//        .nRD(~DISC2_8272_CS | ior_n), 
//        .nWR(~DISC2_8272_CS | iow_n),
//        .din(databus_from_8228),
//        .dout(DISC2_DOut),
//        //.int_out(fdc_int),
//        //.tc(tc),
//        //.density(density),
//        //.activity_led(LED),
//
//        .img_mounted(img_mounted),
//        .img_size(img_size[31:0]),
//        .img_wp(img_readonly),
//        .sd_lba(sd_lba),
//        .sd_rd(sd_rd),
//        .sd_wr(sd_wr),
//        .sd_ack(sd_ack),
//        .sd_buff_addr(sd_buff_addr),
//        .sd_buff_dout(sd_buff_dout),
//        .sd_buff_din(sd_buff_din),
//        .sd_buff_wr(sd_dout_strobe)
//    );


endmodule // IQ151G
