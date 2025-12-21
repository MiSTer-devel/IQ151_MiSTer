`default_nettype none

module basic6(
   input  wire        osc,
   input  wire [15:0] A,
   output wire  [7:0] D,
   input  wire        memr_n,
   input  wire        memw_n,
   input  wire        INIT,
   output wire        NDRY_n,
   output wire        RAM_n
);

wire [7:0] data_EPROM_out;

wire cs0     = (A[15:11] == 5'b1100_1); // C800
wire cs1     = (A[15:11] == 5'b1101_0); // D000
wire cs2     = (A[15:11] == 5'b1101_1); // D800
wire cs3     = (A[15:11] == 5'b1110_0); // E000
wire cs_C800 = cs0 | cs1 | cs2 | cs3;
wire cs      = cs_C800 & memw_n & ~memr_n;

assign NDRY_n = 1'b1;
assign RAM_n  = ~cs;  // 0 = request served by basic6 module, 1 = should be served by computer RAM
assign D = data_EPROM_out;

wire [1:0]  addrePrefix = cs0 ? 2'b00 :
                          cs1 ? 2'b01 :
                          cs2 ? 2'b10 :
                          cs3 ? 2'b11 : 2'b00 ;

dpram #(.ADDRWIDTH(13), .MEM_INIT_FILE("./rom/Basic6.mif")) myEPPROM
(
   .clock(osc),
   .address_a({addrePrefix, A[10:0]}),
   .wren_a(0),
   .q_a(data_EPROM_out)
);

endmodule //basic6
