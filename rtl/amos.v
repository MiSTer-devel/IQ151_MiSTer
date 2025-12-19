`default_nettype none

module amos(
   input  wire        osc,
   input  wire [15:0] A,
   input  wire  [7:0] DIn,
   output wire  [7:0] DOut,
   input  wire        memr_n,
   input  wire        iow_n,
   input  wire        INIT,
   output wire        RAM_n
);

wire [7:0] data_ASM_out;
wire [7:0] data_PAS_out;
wire [7:0] data_PAS1_out;
reg  [1:0] cs_switch;                           // 00=Pascal, 01=Pascal1, 10=Assembler, 11=IQ151 RAM
wire       cs_control = A[15:10] == 6'b1110_11; // 0xEC - 0xEF
wire       cs_data    = A[15:14] == 2'b10;      // 0x8000 - 0xBFFF
assign RAM_n          = ~cs_data | memr_n;      // 0 = request served by basicG module, 1 = should be served by computer RAM

assign DOut = (cs_switch == 2'b00) ? data_PAS_out  :
              (cs_switch == 2'b01) ? data_PAS1_out :
              (cs_switch == 2'b10) ? data_ASM_out  : 8'hff;

always @(posedge INIT or negedge iow_n)
begin
   if (INIT)
      cs_switch <= 2'b10;
   else if (~iow_n & cs_control)
      cs_switch <= DIn[1:0];
end

dpram #(.ADDRWIDTH(14), .MEM_INIT_FILE("./rom/Assembler.mif")) myAssembler
(
   .clock(osc),
   .address_a({A[13:0]}),
   .wren_a(0),
   .q_a(data_ASM_out)
);

dpram #(.ADDRWIDTH(14), .MEM_INIT_FILE("./rom/Pascal.mif")) myPascal
(
   .clock(osc),
   .address_a(A[13:0]),
   .wren_a(0),
   .q_a(data_PAS_out)
);

dpram #(.ADDRWIDTH(14), .MEM_INIT_FILE("./rom/Pascal1.mif")) myPascal1
(
   .clock(osc),
   .address_a(A[13:0]),
   .wren_a(0),
   .q_a(data_PAS1_out)
);

endmodule //amos
