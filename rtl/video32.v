`default_nettype none

module video32(
   input  wire        osc,
   input  wire [15:0] A,
   input  wire  [7:0] DIn,
   output wire  [7:0] DOut,
   input  wire        memr_n,
   input  wire        memw_n,
   output wire        NRDY_n,
   output wire        RAM_n,
   output wire        VID_n,
   output wire        SS_n,     // Vertical Sync (0 => sync pulse ... L between 272d and 287d)
   output wire        SR_n,     // Horizontal Sync (0 => sync pulse ... S between 24d and 27d)
   output wire        ZS_n,     // zatmění stránky = Vertical Blank (0 => blank screen ... L between 256d and 319d)
   output wire        ZR_n,     // zatmění řádky = Horizontal Blank (0 => blank screen ... S between 32d and 47d)
   output reg         ZAT_n
);

reg  [9:1] L; // video micro-line (8 micro-lines per character) runs from 0d to 319d
reg  [6:1] S; // video column ( = character ) run from 0d to 47d
wire       VCLK = ~d2; // VCLK is pixel clock
reg  [2:0] clkX;       // IC2QA + IC3 clkX[2] is character clock
reg        d1;         // = clk/3  IC15A
reg        d2;         // = clk/2  IC15B
assign     SS_n   = ~(L[5] & ~L[6] & L[9]); //  ==> micro-lines 272d - 287d
assign     SR_n   = ~(S[3] & ~S[4] & S[6]);
//wire       MOD    =  (clkX == 3'b111); // this is from real HW
wire       MOD    =  (clkX == 3'b011);
wire       VRAM   =  (A[15:10] == 6'b1110_11); // 0xEC00 - 0xEFFF
assign     RAM_n  = ~VRAM;
assign     NRDY_n = ~(~(~(S[4:1] == 4'b1111) & ~ZR_n) & ZS_n) | ~VRAM; // 1 = CPU can write to VRAM ... Je pristup do VRAM a je bud zatměni strankove nebo (zatmeni radkove a zaroven to neni posledni sloupec v ZR)


//*************** Blank signal for FPGA - not present in real HW ******************
always @(posedge VCLK)
begin
   if (MOD)
      ZAT_n <= ZS_n & ZR_n;
end
//*************** Blank signal for FPGA - not present in real HW ******************


always @(posedge osc)
begin
   d1 <= ~(d1 & d2);
   d2 <= d1;
end

always @(negedge d1)
   clkX <= clkX + 3'd1;

// IC5 + IC2 (BCD)
always @(posedge S[6]) // negedge ~S[6]
//   L <= L + 9'd1;
begin
   if (L == 9'd319)
      L <= 9'd0;
   else
      L <= L + 9'd1;
end

always @(negedge clkX[2])
begin
   if (S == 6'd47)
      S <= 6'd0;
   else
      S <= S + 6'd1;
end

assign ZR_n = ~S[6];
assign ZS_n = ~L[9];


//-------------------------------------- VIDEO RAM  -----------------------------------------------------------------
//
wire [7:0] data_VRAM_out;
wire [9:0] M    = ~(ZR_n & ZS_n) ? A[9:0] : { L[8:4], S[5:1] }; // address to video RAM
wire       WE   = ~(ZR_n & ZS_n) & ~memw_n & VRAM;
assign     DOut = data_VRAM_out;

// 1kB VRAM
dpram #(.ADDRWIDTH(10)) videoRAM
(
   .clock(osc),
   .address_a(M),
   .data_a(DIn),
   .wren_a(WE),
   .q_a(data_VRAM_out)
);


//-------------------------------------- EPROM ----------------------------------------------------------------------
//
wire [7:0] data_EPROM_out;
reg  [7:0] charMask;
reg        inverse;

// 1kB RAM
dpram #(.ADDRWIDTH(10), .MEM_INIT_FILE("./rom/znaky.mif")) charsEPPROM
(
   .clock(osc),
   .address_a({data_VRAM_out[6:0], L[3:1]}),
   .wren_a(0),
   .q_a(data_EPROM_out)
);


always @(negedge VCLK)
begin
   if (MOD)
   begin
      charMask <=  (ZR_n & ZS_n) ? data_EPROM_out : 8'h00;
      inverse  <= ~(ZR_n & ZS_n & data_VRAM_out[7]);
   end
   else
      charMask <= { charMask[6:0], 1'b0 };
end

assign VID_n = ~(charMask[7] ^ inverse);

endmodule //video32