`default_nettype none

module video64(
   input  wire        osc,
   input  wire        INIT,
   input  wire [15:0] A,
   input  wire  [7:0] DIn,
   output wire  [7:0] DOut,
   input  wire        memr_n,
   input  wire        memw_n,
   input  wire        ior_n,
   input  wire        iow_n,
   output wire        NRDY_n,
   output wire        RAM_n,
   output wire        VID_n,  // pixel
   output wire        SS_n,   // Synchronizace Stránková = Vertical Sync pulse
   output wire        SR_n,   // Synchronizace Řádková  = Horizontal Sync pulse
   output wire        ZS_n,   // Zatmění Stránky = Vertical Blank ... 1=visible
   output wire        ZR_n,   // Zatmění Řádky = Horizontal Blank ... 1=visible
   output reg         ZAT_n
);

reg   [2:0] R;          // pixel (micro)rows in a char ... IC4 + IC21
reg   [6:0] Xa;         // char columns (0-63 visible, 64-95 invisible) ... IC4 + IC22
reg  [11:6] Xb;         // char rows    (0-31 visible, 32-39 invisible) ... IC21 + IC5
reg   [2:0] clk;        // IC6
reg         d1;         // OSC / 2 ... IC16A
reg         d2;         // (micro)row clock ... IC16B
reg         fontWideEnabled; //IC26B
wire [10:0] X = {Xb[10:6], Xa[5:0]};

assign ZS_n     = ~Xb[11];
assign ZR_n     = ~Xa[6];
assign SS_n     = ~(Xb[7] & ~Xb[8] & Xb[11]); // lines 34d - 35d
assign SR_n     = ~(Xa[3] & ~Xa[4] & Xa[6]);
wire   MUX      = ~(ZR_n & ZS_n);            // 0 = Video64, 1 = CPU ... access to VideoRAM
assign RAM_n    = ~(A[15:11] == 5'b1110_1);  // 0xE800-0xEFFF = address inside RAM space of video64 module
wire   IO       =  (A[15:10] == 6'b1111_11); // 0xFC-0xFF     = address inside IO space of video64 module (for detection of video64 module (read) & enable/disable wide characters)
assign NRDY_n   = ~(~RAM_n & ~d2 & ZS_n);    // wait to CPU when needs to access Video64 in not suitable time
wire   d2_CLR_n = ~(Xa[2] & Xa[3] & Xa[4]); // IC13B
wire   io_wr    = ~iow_n & IO;
wire   MOD      = clk[0] & clk[2] & ~(X[0] & fontWide);  // triggers (together with VCLK) new char (micro line) load from eprom
wire   VCLK     = ~(~(~clk[0] & fontWide) & d1);         // pixel video clock IC24C


//*************** Blank signal for FPGA - not present in real HW ******************
reg [10:0] ZAT_clk;
reg  [2:0] ZAT_status;
wire ZAT_internal_n = ZS_n & ZR_n;

//always @(posedge VCLK)


always @(negedge VCLK)
begin
   if (ZAT_internal_n & (ZAT_status == 0))
   begin
      ZAT_clk    <= 3;
      ZAT_status <= 1;
   end

   if (ZAT_status == 1)
   begin
      if (ZAT_clk == 0)
      begin
        ZAT_status <= 2;
        ZAT_clk <= 386;
        ZAT_n <= 1;
      end
      else
         ZAT_clk <= ZAT_clk - 1;
   end

   if (ZAT_status == 2)
   begin
      if (ZAT_clk == 0)
      begin
        ZAT_status <= 0;
        ZAT_n      <= 0;
      end
      else
         ZAT_clk <= ZAT_clk - 1;
   end
end
//*************** Blank signal for FPGA - not present in real HW ******************


// IC16A
always @(posedge osc)
   d1 <= ~d1;

// IC6
always @(negedge d1) // = negedge d1_n 

////////////////////////////always @(posedge d1) // = negedge d1_n 
begin
   if (clk == 3'b101)
      clk <= 3'd0;
   else
      clk <= clk + 3'd1;
end

// IC16B
always @(posedge clk[0] or negedge d2_CLR_n)
begin
   if (~d2_CLR_n)
      d2 <= 1'b0;
   else
      d2 <= Xa[6];
end

// IC4 + IC22
always @(negedge clk[2])
begin
   if (Xa == 7'd95)
      Xa <= 7'd0;
   else
      Xa <= Xa + 7'd1;
end

// IC4 + IC21
always @(negedge d2)
   R <= R + 3'd1;

// IC21 + IC5 (BCD)
always @(negedge R[2])
begin
   if (Xb == 6'd39)
      Xb <= 6'd0;
   else
      Xb <= Xb + 6'd1;
end

// IC26B
always @(posedge INIT or posedge io_wr)
begin
   if (INIT)
      fontWideEnabled <= 1'b0;
   else
      fontWideEnabled <= DIn[0];
end

assign DOut = (~ior_n  & IO) ? 8'hFE : // this is for detection of video64 module by firmware
              data_VRAM_out;           // data from Video64 memory

reg       fontWide;
reg [2:0] functionMask;
wire      fontWideSET   = functionMask[1];
wire      fontWideRESET = fontWideEnabled & functionMask[2] & SR_n;

// IC32A + IC32B SET/RESET
always @(negedge fontWideSET or negedge fontWideRESET)
begin
   if (~fontWideRESET)
      fontWide <= 1'b0;
   else if (~fontWideSET)
      fontWide <= 1'b1;
end


//-------------------------------- video RAM -------------------------------------------------
//
wire        VRAM  = ~RAM_n;
wire [10:0] M     = MUX ? A[10:0] : X;      // address to video RAM
wire        WE    = MUX & ~memw_n & ~RAM_n; // write to video RAM 
wire  [7:0] data_VRAM_out;

// 2 kB video RAM
dpram #(.ADDRWIDTH(11)) videoRAM
(
   .clock(osc),
   .address_a(M),
   .data_a(DIn),
   .wren_a(WE),
   .q_a(data_VRAM_out)
);

//-------------------------------------- Chars EPROM ----------------------------------------------------------------------
//
wire [7:0] data_EPROM_out;
reg  [5:0] charMask;

dpram #(.ADDRWIDTH(11), .MEM_INIT_FILE("./rom/Video64.mif")) charsEPPROM
(
   .clock(osc),
   .address_a({data_VRAM_out[7:0], R[2:0]}),
   .wren_a(0),
   .q_a(data_EPROM_out)
);

always @(negedge VCLK)
begin
   if (MOD)
   begin
      charMask     <= MUX ? 6'b11_1111 : data_EPROM_out[5:0];
      functionMask <= {data_EPROM_out[7:6], MUX};
   end
   else  
      charMask <= { charMask[4:0], 1'b1 };
end

assign VID_n = ~charMask[5];

endmodule //video64
