`default_nettype none

module grafik(
   input  wire        osc,
   input  wire        clk_sysDouble,
   input  wire [15:0] A,
   input  wire  [7:0] DIn,
   output wire  [7:0] DOut,
   input wire         video,     // video ... 0 = Video32, 1 = Video64 * for video32 timing fix

   input  wire        ZS_n,      // zatmění stránky = Vertical Blank
   input  wire        ZR_n,      // zatmění řádky = Horizontal Blank
   input  wire        INIT,
   input  wire        ior_n,
   input  wire        iow_n,
   input  wire        phi2,

   output wire        NRDY_n,
   output reg         VCLK,      // video clock - negedge
   output wire        VID_n
);


wire CS_n_8255 = ~(A[7:2] == 6'b1101_00);   // 0xD0 - 0xD3 ... CPU set 8255
wire S1_n      = ~(A == 16'hD4_D4);         // 0xD4        ... CPU read/write data from/to module grafik

reg         HCK;  // IC24A ..... derived clock signal
reg         Q0;   // IC23A ..... control signal
reg         Q1;   // IC35QA .... control signal
reg         Q2;   // IC35QBA ... control signal
reg   [5:0] cols; // column address 
reg   [7:0] rows; // row address
wire        MD        = ~(~(Q0 & Q1 & Q2 & gWR_n & ZS_n & ZR_n)); // IC31
wire [13:0] VideoAddr = {rows, cols};

reg ZR_n_last;
always @(posedge clk_sysDouble)
begin
   ZR_n_last <= ZR_n;

   if (~ZR_n_last & ZR_n)
   begin
      {cols, Q2, Q1, Q0} <= { 9'd0 };
      {HCK, VCLK} <= 2'b01;
   end      
   else 
   begin
      HCK  <= VCLK;
      VCLK <= (~VCLK) ? 1 : ~HCK;
      if (~HCK & VCLK) // = posedge HCK
         {cols, Q2, Q1, Q0} <= {cols, Q2, Q1, Q0} + 9'd1;
   end
end

always @(posedge ZR_n or negedge ZS_n)
begin
   if (~ZS_n)
      rows <= 8'b0;
   else
      rows <= rows - 8'b1;
end

reg    gWR_n; // CPU is writing to grafik module video RAM (=PROC)
reg    gRD_n; // CPU is reading from grafik module video RAM (=PROC_n)
reg    SEL_WR_n; 
wire   SYN     = ~(ZR_n & ZS_n & FAST_n); // IC11C time frame for grafik memory access from CPU
reg    NRDY_WR = 1'b0; // 1 = Write to VRam is pending
assign NRDY_n  = ~NRDY_WR;

// IC32B
//always @(negedge S1_n or negedge gWR_n) // S1 = MH74188 O4
reg S1_n_last;
always @(posedge osc)
begin
    S1_n_last <= S1_n;

   if (~gWR_n)
      NRDY_WR <= 1'b0;
   else if (~S1_n & S1_n_last)
      NRDY_WR <= SEL;
end

//IC9B
always @(negedge phi2)
   SEL_WR_n <= ~(SYN & NRDY_WR);

//IC32A
always @(negedge Q2)
begin
   gWR_n <=  SEL_WR_n;
   gRD_n <= ~SEL_WR_n;
end

reg  preRAS_PEN_n;
wire RAS_ALL = ~(gRD_n & ~ALL); // when readin from Video RAM we need all bits
wire RAS_PEN = ~(preRAS_PEN_n & ~Q2);
wire RAS     =  RAS_ALL | RAS_PEN; 

// IC9A
always @(posedge Q0 or posedge Q2)
begin
   if (Q2)
      preRAS_PEN_n <= 1'b1;
   else
      preRAS_PEN_n <= ~Q1;
end


//--------------------------------------------------------
//
wire [7:0] PA;     // column to write/read (bits 5:0 only ... 64d x 8 = 512 pixels)
wire [7:0] PB;     // row to write/read (bits 7:0 ... 256 pixel rows)
wire       ALL;    // PC0 - Bit Access (1= write whole byte to VRAM, 0=bit set/reset);
wire       PEN_n;  // PC1 - PEN set/reset bit (0=set, 1=reset); 0 = zapsat svitici bod
wire       FAST_n; // PC2 - FAST (0 = enable MEM write during screen redraw => screen may flickering during Video RAM R/W; );
wire       EV;     // PC3 - Show/hide pic (enable view) 1 = enable .. show picture from grafik
wire [2:0] COLOR;  // PC4-6 - ext. connector for color generator? Never manufactured.
wire       SEL;    // PC7 - SEL ... 1 = write to module
wire       EV8255;
wire       SEL8255;
wire       PCLisInput;               // PCLisInput as "pull-down" in case 8255 not setup yet
wire       PCHisInput;

assign EV  = ~PCLisInput & EV8255;      // PCLisInput as "pull-down" in case 8255 not setup yet
assign SEL = ~PCHisInput & SEL8255;     // PCLisInput as "pull-down" in case 8255 not setup yet

i8255 grafik8255
(
   .PA_Out(PA),
   .PB_Out(PB),
   .PC_Out({SEL8255, COLOR, EV8255, FAST_n, PEN_n, ALL}),
   .PCLisInput(PCLisInput),
   .PCHisInput(PCHisInput),
   .D_In(DIn),

    .clk(phi2),
   .RD_n(1'b1), // never read
   .WR_n(iow_n),
   .A(A[1:0]),
   .RESET(INIT),
   .CS_n(CS_n_8255)
);

//---------------------------------------------------------------
//
wire  [7:0] data_VRAM_out;
assign      DOut           = data_VRAM_out;
wire [13:0] CPUAddr        = {PB[7:0], PA[5:0]} ;
wire [13:0] memAddr        =  gWR_n ? VideoAddr : CPUAddr;
wire        WRx            = ~gWR_n & Q0 & ~Q1 & Q2; // & Q1 & ~Q0 pridano pro zkraceni delky intervalu zapisu!

// 16kB RAM
dpram #(.ADDRWIDTH(14)) videoRam 
(
//   .clock(clk_50M),
   .clock(clk_sysDouble),
   .address_a(memAddr),
   .wren_a(WRx),
   .data_a(RAMValueModified),
   .q_a(data_VRAM_out)
);

wire [7:0] bitToModify = (DIn_latch[7:5] == 3'b000) ? 8'b0000_0001 :
                         (DIn_latch[7:5] == 3'b001) ? 8'b0000_0010 :
                         (DIn_latch[7:5] == 3'b010) ? 8'b0000_0100 :
                         (DIn_latch[7:5] == 3'b011) ? 8'b0000_1000 :
                         (DIn_latch[7:5] == 3'b100) ? 8'b0001_0000 :
                         (DIn_latch[7:5] == 3'b101) ? 8'b0010_0000 :
                         (DIn_latch[7:5] == 3'b110) ? 8'b0100_0000 :
                         (DIn_latch[7:5] == 3'b111) ? 8'b1000_0000 : 8'b0000_0000;

wire       captureValue     = ~gWR_n & ~Q0 & ~Q1 & Q2;
reg  [7:0] data_VRAM_outD;
reg  [7:0] DIn_latch;
wire [7:0] RAMValueModified = (ALL)    ? DIn_latch  :
                              (~PEN_n) ? data_VRAM_outD | bitToModify   // PEN == 0 ==> set bit
                                       : data_VRAM_outD & ~bitToModify; // PEN == 1 ==> reset bit

always @(posedge captureValue)
begin
   DIn_latch      <= DIn;
   data_VRAM_outD <= data_VRAM_out;
end

//------------------------------------------------------------------
//
reg [7:0] VIDBuffer;
assign VID_n = VIDBuffer[0] & EV;

always @(negedge VCLK)
begin
   if (MD)
      VIDBuffer <= data_VRAM_out;
   else
      VIDBuffer  <= {1'b0, VIDBuffer[7:1]};
end

endmodule //grafik
