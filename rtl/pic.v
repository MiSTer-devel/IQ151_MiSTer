

/*
 * Copyright (c) 2014, Aleksander Osman
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * 
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


module pic(
    input               clk,
    input               rst_n,
    
    //master pic
    input               master_address,
    input               master_read,
    output reg  [7:0]   master_readdata,
    input               master_write,
    input       [7:0]   master_writedata,
    
    //interrupt input
    input       [7:0]  interrupt_input_pins,
    
    //interrupt output
    output reg          interrupt_do,
    output reg  [7:0]   interrupt_vector,
    //input               interrupt_done,
	 input 					interrupt_ack,
	 
	 output reg [1:0] mas_ack_count,
	 output reg mas_uPM,
	 output mas_irq, 
	 output reg mas_current_irq,
	 output reg [10:0] mas_interrupt_offset,
	 output  mas_init_icw1 ,
	 output  mas_init_icw2 ,
	 output  mas_init_icw3 ,
	 output  mas_init_icw4 ,
	 output reg [2:0] mas_init_byte_expected
	 
);

//------------------------------------------------------------------------------


reg master_read_last= 0;
reg [15:0] interrupt_last= 0;


reg mas_read_reg_select= 0;
reg mas_special_mask= 0;
reg mas_in_init= 0;
reg mas_init_requires_4= 0;
reg mas_polled= 0;
reg mas_ltim= 0;
reg mas_adi= 0; // CALL address interval 0 = of 8= 0; 1= of 4
reg mas_sngl = 0;
//reg [2:0] mas_init_byte_expected= 0;
reg [2:0] mas_lowest_priority= 0;
reg [7:0] mas_imr= 0;
reg [7:0] mas_irr= 0;
reg [7:0] mas_isr= 0;
//reg [10:0] mas_interrupt_offset= 0;
reg mas_auto_eoi= 0;
reg mas_rotate_on_aeoi= 0;
//reg mas_uPM= 0;  // 0 = MCS-80/85 mode= 0; 1 = 8086/8088 mode
//reg mas_current_irq= 0;    
reg mas_spurious= 0;
reg mas_sla_active= 0;
reg interrupt_ack_last= 0;
//reg [1:0] mas_ack_count= 0;

wire interrupt_input_freeze;
reg [7:0] interrupt_input_reg;
wire [7:0] interrupt_input;

//wire mas_irq;
wire [2:0] mas_irq_value;
wire mas_acknowledge_not_spurious ;
wire mas_acknowledge             ;
wire [7:0] mas_interrupt_vector_bits ;
wire slave_read_valid ;
wire master_read_valid;

wire [7:0] mas_readdata_prepared ;
//wire mas_init_icw1 ;
//wire mas_init_icw2 ;
//wire mas_init_icw3 ;
//wire mas_init_icw4 ;
//wire mas_ocw1 ;
//wire mas_ocw2 ;
//wire mas_ocw3 ;

//reg mas_init_icw1 ;
//reg mas_init_icw2 ;
//reg mas_init_icw3 ;
//reg mas_init_icw4 ;
reg mas_ocw1 ;
reg mas_ocw2 ;
reg mas_ocw3 ;


wire [7:0] mas_interrupt_input ;
wire [7:0] mas_edge_detect ;
wire [7:0] mas_writedata_mask;
wire mas_isr_clear ;
wire [7:0] mas_selected_prepare ;
wire [7:0] mas_selected_shifted ;
wire [7:0] mas_selected_shifted_isr ;
wire [2:0] mas_selected_shifted_isr_first ;
wire [2:0] mas_selected_shifted_isr_first_norm ;
wire [7:0] mas_selected_shifted_isr_first_bits ;
wire [2:0] mas_selected_index ;
wire mas_spurious_start ;
wire interrupt_done;
wire [7:0] interrupt_vector_bits ;


//-----------------------------------------------
reg [2:0] mas_irq_value_reg;
//assign interrupt_input_freeze = ~(mas_ack_count == 0);
assign interrupt_input_freeze = interrupt_do;
assign interrupt_input = interrupt_input_freeze ? interrupt_input_reg : interrupt_input_pins;

always @(posedge interrupt_input_freeze)
begin
	interrupt_input_reg <= interrupt_input_pins;
	mas_irq_value_reg <= mas_irq_value;
end



assign mas_irq = mas_selected_prepare != 8'd0 && (mas_special_mask || mas_selected_index < mas_selected_shifted_isr_first);

assign mas_irq_value = (mas_irq)? mas_lowest_priority + mas_selected_index + 3'd1 : 3'd7;

assign mas_acknowledge_not_spurious = (mas_polled && master_read_valid) || (interrupt_done && ~(mas_spurious));
assign mas_acknowledge              = (mas_polled && master_read_valid) || interrupt_done;

//assign mas_interrupt_vector_bits = (mas_sla_active)? 8'b00000100 : interrupt_vector_bits;
assign mas_interrupt_vector_bits = interrupt_vector_bits;

//-------------------------------------------------------------------------------------------


always @(posedge clk or negedge rst_n) begin if(rst_n == 1'b0) master_read_last <= 1'b0; else if(master_read_last) master_read_last <= 1'b0; else master_read_last <= master_read; end 
assign master_read_valid = master_read && master_read_last == 1'b0;

//------------------------------------------------------------------------------


always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)   interrupt_last <= 16'd0;
    else                interrupt_last <= interrupt_input;
end

//------------------------------------------------------------------------------
 

assign mas_readdata_prepared =
    (mas_polled)?                                               { mas_current_irq, 4'd0, mas_irq_value } :
    (master_address == 1'b0 && mas_read_reg_select == 1'b0)?    mas_irr :
    (master_address == 1'b0 && mas_read_reg_select == 1'b1)?    mas_isr :
                                                                mas_imr;

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)   master_readdata <= 8'd0;
    else                master_readdata <= mas_readdata_prepared;
end

//------------------------------------------------------------------------------


//------------------------------------------------------------------------------
//
//assign	mas_init_icw1 = master_write && master_address == 1'b0 && master_writedata[4] == 1'b1;
//assign	mas_init_icw2 = master_write && master_address == 1'b1 && mas_in_init && mas_init_byte_expected == 3'd2;
//assign	mas_init_icw3 = master_write && master_address == 1'b1 && mas_in_init && mas_init_byte_expected == 3'd3;
//assign	mas_init_icw4 = master_write && master_address == 1'b1 && mas_in_init && mas_init_byte_expected == 3'd4;

assign	mas_init_icw1 = master_write && master_address == 1'b0 && master_writedata[4] == 1'b1;
assign	mas_init_icw2 = master_write && master_address == 1'b1 && mas_init_byte_expected == 3'd2;
assign	mas_init_icw3 = master_write && master_address == 1'b1 && mas_init_byte_expected == 3'd3;
assign	mas_init_icw4 = master_write && master_address == 1'b1 && mas_init_byte_expected == 3'd4;



wire [2:0] icw = (mas_init_icw1) ? 3'd1 : (mas_init_icw2) ? 3'd2 : (mas_init_icw3) ? 3'd3 : (mas_init_icw4) ? 3'd4 : 3'd0; 
reg [2:0] last_icw = 0;

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)   last_icw <= 3'd0;
    else                last_icw <= icw;
end
 

//
//always @(master_write or rst_n) begin
//
//	mas_init_icw1 <= master_write && master_address == 1'b0 && master_writedata[4] == 1'b1;
////	mas_init_icw2 <= master_write && master_address == 1'b1 && mas_in_init && mas_init_byte_expected == 3'd2;
////	mas_init_icw3 <= master_write && master_address == 1'b1 && mas_in_init && mas_init_byte_expected == 3'd3;
////	mas_init_icw4 <= master_write && master_address == 1'b1 && mas_in_init && mas_init_byte_expected == 3'd4;
//		
//	mas_init_icw2 <= master_write && master_address == 1'b1 && mas_init_byte_expected == 3'd2;
//	mas_init_icw3 <= master_write && master_address == 1'b1 && mas_init_byte_expected == 3'd3;
//	mas_init_icw4 <= master_write && master_address == 1'b1 && mas_init_byte_expected == 3'd4;		
//	  
//		
//end


//assign mas_ocw1 = mas_in_init == 1'b0 && master_write && master_address == 1'b1;
//assign mas_ocw2 = master_write && master_address == 1'b0 && master_writedata[4:3] == 2'b00;
//assign mas_ocw3 = master_write && master_address == 1'b0 && master_writedata[4:3] == 2'b01;


always @(master_write) begin
  mas_ocw1 <= mas_in_init == 1'b0 && master_write && master_address == 1'b1;
  mas_ocw2 <= master_write && master_address == 1'b0 && master_writedata[4:3] == 2'b00;
  mas_ocw3 <= master_write && master_address == 1'b0 && master_writedata[4:3] == 2'b01;
end


always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                           mas_polled <= 1'b0;
    else if(mas_polled && master_read_valid)    mas_polled <= 1'b0;
    else if(mas_ocw3)                           mas_polled <= master_writedata[2];
end


always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                                       mas_read_reg_select <= 1'b0;
    else if(mas_init_icw1)                                                  mas_read_reg_select <= 1'b0;
    else if(mas_ocw3 && master_writedata[2] == 1'b0 && master_writedata[1]) mas_read_reg_select <= master_writedata[0];
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                                       mas_special_mask <= 1'd0;
    else if(mas_init_icw1)                                                  mas_special_mask <= 1'd0;
    else if(mas_ocw3 && master_writedata[2] == 1'b0 && master_writedata[6]) mas_special_mask <= master_writedata[5];
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                   mas_in_init <= 1'b0;
    else if(mas_init_icw1)                              mas_in_init <= 1'b1;
    else if(mas_init_icw3 && ~(mas_init_requires_4))    mas_in_init <= 1'b0;
    else if(mas_init_icw4)                              mas_in_init <= 1'b0;
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)       mas_init_requires_4 <= 1'b0;
    else if(mas_init_icw1) mas_init_requires_4 <= master_writedata[0];
end
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)      	mas_ltim <= 1'b0;
    else if(mas_init_icw1) 	mas_ltim <= master_writedata[3];
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)      	mas_adi <= 1'b0;
    else if(mas_init_icw1) 	mas_adi <= master_writedata[2];
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)      	mas_sngl <= 1'b0;
    else if(mas_init_icw1) 	mas_sngl <= master_writedata[1];
end

//
//always @(posedge clk or negedge rst_n) begin
//    if(rst_n == 1'b0)                               						mas_init_byte_expected <= 3'd0;
//    else if(~master_write && mas_init_icw1) 					            mas_init_byte_expected <= 3'd2;
//    else if(~master_write && mas_init_icw2 && ~mas_sngl)             mas_init_byte_expected <= 3'd3;
//    else if(~master_write && mas_init_icw2 && mas_init_requires_4)   mas_init_byte_expected <= 3'd4;
//    else if(~master_write && mas_init_icw2)   			    				mas_init_byte_expected <= 3'd0;
//    else if(~master_write && mas_init_icw3 && mas_init_requires_4)   mas_init_byte_expected <= 3'd4;
//	 else if(~master_write && mas_init_icw4)   								mas_init_byte_expected <= 3'd0;
//end



always @(negedge master_write or negedge rst_n) begin
    if(rst_n == 1'b0)            					mas_init_byte_expected <= 3'd0;
	 
	 	 
    else if(last_icw == 3'd1) 					            mas_init_byte_expected <= 3'd2;
    else if(last_icw == 3'd2 && ~mas_sngl)             mas_init_byte_expected <= 3'd3;
    else if(last_icw == 3'd2 && mas_init_requires_4)   mas_init_byte_expected <= 3'd4;
    else if(last_icw == 3'd2)   			    				mas_init_byte_expected <= 3'd0;
    else if(last_icw == 3'd3 && mas_init_requires_4)   mas_init_byte_expected <= 3'd4;
	 else if(last_icw == 3'd4)   								mas_init_byte_expected <= 3'd0;
	  
end



 
	
	
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                                               mas_lowest_priority <= 3'd7;
    else if(mas_init_icw1)                                                          mas_lowest_priority <= 3'd7;
    else if(mas_ocw2 && master_writedata == 8'hA0)                                  mas_lowest_priority <= mas_lowest_priority + 3'd1;  //rotate on non-specific EOI
    else if(mas_ocw2 && { master_writedata[7:3], 3'b000 } == 8'hC0)                 mas_lowest_priority <= master_writedata[2:0];       //set priority
    else if(mas_ocw2 && { master_writedata[7:3], 3'b000 } == 8'hE0)                 mas_lowest_priority <= master_writedata[2:0];       //rotate on specific EOI
    else if(mas_acknowledge_not_spurious && mas_auto_eoi && mas_rotate_on_aeoi)     mas_lowest_priority <= mas_lowest_priority + 3'd1;  //rotate on AEOI
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)           mas_imr <= 8'hFF;
    else if(mas_init_icw1)      mas_imr <= 8'h00;
    else if(mas_ocw1)           mas_imr <= master_writedata;
end

//assign mas_interrupt_input = { interrupt_input[7:3], sla_current_irq, interrupt_input[1:0] };
assign mas_interrupt_input = interrupt_input;

assign mas_edge_detect = {
    interrupt_input[7] == 1'b1    && interrupt_last[7] == 1'b0,
    interrupt_input[6] == 1'b1    && interrupt_last[6] == 1'b0,
    interrupt_input[5] == 1'b1    && interrupt_last[5] == 1'b0,
    interrupt_input[4] == 1'b1    && interrupt_last[4] == 1'b0,
    interrupt_input[3] == 1'b1    && interrupt_last[3] == 1'b0,
    interrupt_input[2] == 1'b1    && interrupt_last[2] == 1'b0,
    interrupt_input[1] == 1'b1    && interrupt_last[1] == 1'b0,
    interrupt_input[0] == 1'b1    && interrupt_last[0] == 1'b0
};

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                       mas_irr <= 8'h00;
    else if(mas_init_icw1)                  mas_irr <= 8'h00;
    else if(mas_acknowledge_not_spurious)   mas_irr <= (mas_irr & mas_interrupt_input & ~(mas_interrupt_vector_bits)) | ((~(mas_ltim))? mas_edge_detect : mas_interrupt_input);
    else                                    mas_irr <= (mas_irr & mas_interrupt_input)                                | ((~(mas_ltim))? mas_edge_detect : mas_interrupt_input);
end

assign mas_writedata_mask =
    (master_writedata[2:0] == 3'd0)?    8'b00000001 :
    (master_writedata[2:0] == 3'd1)?    8'b00000010 :
    (master_writedata[2:0] == 3'd2)?    8'b00000100 :
    (master_writedata[2:0] == 3'd3)?    8'b00001000 :
    (master_writedata[2:0] == 3'd4)?    8'b00010000 :
    (master_writedata[2:0] == 3'd5)?    8'b00100000 :
    (master_writedata[2:0] == 3'd6)?    8'b01000000 :
                                        8'b10000000;

assign mas_isr_clear = 
    (mas_polled && master_read_valid) || //polling
    (mas_ocw2 && (master_writedata == 8'h20 || master_writedata == 8'hA0)); //non-specific EOI or rotate on non-specific EOF
                                        

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                                   mas_isr <= 8'h00;
    else if(mas_init_icw1)                                              mas_isr <= 8'h00;
    else if(mas_ocw2 && { master_writedata[7:3], 3'b000 } == 8'h60)     mas_isr <= mas_isr & ~(mas_writedata_mask);                     //clear on specific EOI
    else if(mas_ocw2 && { master_writedata[7:3], 3'b000 } == 8'hE0)     mas_isr <= mas_isr & ~(mas_writedata_mask);                     //clear on rotate on specific EOI
    else if(mas_isr_clear)                                              mas_isr <= mas_isr & ~(mas_selected_shifted_isr_first_bits);    //clear on polling or non-specific EOI (with or without rotate)
    else if(mas_acknowledge_not_spurious && ~(mas_auto_eoi))            mas_isr <= mas_isr | mas_interrupt_vector_bits;                 //set
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)       mas_interrupt_offset <= 11'd1;
    else if(mas_init_icw1)  mas_interrupt_offset[2:0] <= master_writedata[7:5];
	 else if(mas_init_icw2)  mas_interrupt_offset[10:3] <= master_writedata[7:0];
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)       mas_auto_eoi <= 1'b0;
    else if(mas_init_icw1)  mas_auto_eoi <= 1'b0;
    else if(mas_init_icw4)  mas_auto_eoi <= master_writedata[1];
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                   mas_rotate_on_aeoi <= 1'b0;
    else if(mas_init_icw1)                              mas_rotate_on_aeoi <= 1'b0;
    else if(mas_ocw2 && master_writedata[6:0] == 7'd0)  mas_rotate_on_aeoi <= master_writedata[7];
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)       mas_uPM <= 1'b0;
    else if(mas_init_icw1)  mas_uPM <= 1'b0;
    else if(mas_init_icw4)  mas_uPM <= master_writedata[0];
end

assign mas_selected_prepare = mas_irr & ~(mas_imr) & ~(mas_isr);

assign mas_selected_shifted =
    (mas_lowest_priority == 3'd7)?      mas_selected_prepare :
    (mas_lowest_priority == 3'd0)?      { mas_selected_prepare[0],   mas_selected_prepare[7:1] } :
    (mas_lowest_priority == 3'd1)?      { mas_selected_prepare[1:0], mas_selected_prepare[7:2] } :
    (mas_lowest_priority == 3'd2)?      { mas_selected_prepare[2:0], mas_selected_prepare[7:3] } :
    (mas_lowest_priority == 3'd3)?      { mas_selected_prepare[3:0], mas_selected_prepare[7:4] } :
    (mas_lowest_priority == 3'd4)?      { mas_selected_prepare[4:0], mas_selected_prepare[7:5] } :
    (mas_lowest_priority == 3'd5)?      { mas_selected_prepare[5:0], mas_selected_prepare[7:6] } :
                                        { mas_selected_prepare[6:0], mas_selected_prepare[7] };
    
assign mas_selected_shifted_isr =
    (mas_lowest_priority == 3'd7)?      mas_isr :
    (mas_lowest_priority == 3'd0)?      { mas_isr[0],   mas_isr[7:1] } :
    (mas_lowest_priority == 3'd1)?      { mas_isr[1:0], mas_isr[7:2] } :
    (mas_lowest_priority == 3'd2)?      { mas_isr[2:0], mas_isr[7:3] } :
    (mas_lowest_priority == 3'd3)?      { mas_isr[3:0], mas_isr[7:4] } :
    (mas_lowest_priority == 3'd4)?      { mas_isr[4:0], mas_isr[7:5] } :
    (mas_lowest_priority == 3'd5)?      { mas_isr[5:0], mas_isr[7:6] } :
                                        { mas_isr[6:0], mas_isr[7] };

assign mas_selected_shifted_isr_first =
    (mas_selected_shifted_isr[0])?  3'd0 :
    (mas_selected_shifted_isr[1])?  3'd1 :
    (mas_selected_shifted_isr[2])?  3'd2 :
    (mas_selected_shifted_isr[3])?  3'd3 :
    (mas_selected_shifted_isr[4])?  3'd4 :
    (mas_selected_shifted_isr[5])?  3'd5 :
    (mas_selected_shifted_isr[6])?  3'd6 :
                                    3'd7;
    
assign mas_selected_shifted_isr_first_norm = mas_lowest_priority + mas_selected_shifted_isr_first + 3'd1;

assign mas_selected_shifted_isr_first_bits =
    (mas_selected_shifted_isr_first_norm == 3'd0)?  8'b00000001 :
    (mas_selected_shifted_isr_first_norm == 3'd1)?  8'b00000010 :
    (mas_selected_shifted_isr_first_norm == 3'd2)?  8'b00000100 :
    (mas_selected_shifted_isr_first_norm == 3'd3)?  8'b00001000 :
    (mas_selected_shifted_isr_first_norm == 3'd4)?  8'b00010000 :
    (mas_selected_shifted_isr_first_norm == 3'd5)?  8'b00100000 :
    (mas_selected_shifted_isr_first_norm == 3'd6)?  8'b01000000 :
                                                    8'b10000000;

assign mas_selected_index =
    (mas_selected_shifted[0])?      3'd0 :
    (mas_selected_shifted[1])?      3'd1 :
    (mas_selected_shifted[2])?      3'd2 :
    (mas_selected_shifted[3])?      3'd3 :
    (mas_selected_shifted[4])?      3'd4 :
    (mas_selected_shifted[5])?      3'd5 :
    (mas_selected_shifted[6])?      3'd6 :
                                    3'd7;


always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)           mas_current_irq <= 1'b0;
    else if(mas_init_icw1)      mas_current_irq <= 1'b0;
    else if(mas_acknowledge)    mas_current_irq <= 1'b0;
    else if(mas_irq)            mas_current_irq <= 1'b1;
end


assign mas_spurious_start = mas_current_irq && ~(interrupt_done) && ~(mas_irq);

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                       mas_spurious <= 1'd0;
    else if(mas_init_icw1)                  mas_spurious <= 1'b0;
    else if(mas_spurious_start)             mas_spurious <= 1'b1;
    else if(mas_acknowledge || mas_irq)     mas_spurious <= 1'b0;
end

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                               mas_sla_active <= 1'b0;
    else if(mas_init_icw1)                                          mas_sla_active <= 1'b0;
    else if(mas_acknowledge)                                        mas_sla_active <= 1'b0;
    else if((mas_irq || mas_current_irq) && mas_irq_value != 3'd2)  mas_sla_active <= 1'b0;
    else if((mas_irq || mas_current_irq) && mas_irq_value == 3'd2)  mas_sla_active <= 1'b1;
end



always @(posedge clk or negedge rst_n) begin 
	if(rst_n == 1'b0) 			interrupt_ack_last <= 1'b0; 
	else 								interrupt_ack_last <= interrupt_ack; 
end 

always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                       			mas_ack_count <= 2'd0;
    else if(mas_init_icw1)                  			mas_ack_count <= 2'b0;
    else if(~interrupt_do)                  			mas_ack_count <= 2'b0;
    else if(interrupt_ack && ~interrupt_ack_last)  mas_ack_count <= mas_ack_count + 2'd1;
end


assign interrupt_done = (mas_uPM && mas_ack_count == 2'd2 && ~interrupt_ack) || (~mas_uPM && mas_ack_count == 2'd3 && ~interrupt_ack);


//------------------------------------------------------------------------------



always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)           interrupt_do <= 1'b0;
    else if(mas_init_icw1)      interrupt_do <= 1'b0;
    else if(mas_acknowledge)    interrupt_do <= 1'b0;
    else if(mas_irq)            interrupt_do <= 1'b1;
end

always @(posedge clk or negedge rst_n) begin
//always @(posedge interrupt_ack or posedge mas_init_icw1 or negedge rst_n) begin
    if(rst_n == 1'b0)                                               interrupt_vector <= 8'd0;
    else if(mas_init_icw1)                                          interrupt_vector <= 8'd0;
	 // uPM = 1 .... 8086/8088 mode
//*    else if(mas_uPM && (mas_irq || mas_current_irq))  interrupt_vector <= { mas_interrupt_offset[10:6], mas_irq_value };
//    else if(mas_uPM && (mas_irq || mas_current_irq) && mas_irq_value != 3'd2)  interrupt_vector <= { mas_interrupt_offset[10:6], mas_irq_value };
//    else if(mas_uPM && (mas_irq || mas_current_irq) && mas_irq_value == 3'd2)  interrupt_vector <= { sla_interrupt_offset, sla_irq_value };
	 // uPM = 0 .... MCS-80/85 mode
    else if(~mas_uPM && (mas_irq || mas_current_irq) && mas_ack_count == 2'd1)  			interrupt_vector <= 8'hCD; // CALL instruction
	else if(~mas_uPM && (mas_irq || mas_current_irq) && mas_ack_count == 2'd2 && mas_adi)  	interrupt_vector <= {mas_interrupt_offset[2:0], mas_irq_value_reg, 2'd0 } ; //  LO address, interval of 4
	else if(~mas_uPM && (mas_irq || mas_current_irq) && mas_ack_count == 2'd2 && ~mas_adi)  	interrupt_vector <= {mas_interrupt_offset[2:1], mas_irq_value_reg, 3'd0 } ; //  LO address, interval of 8	 
	 
	// else if(~mas_uPM && (mas_irq || mas_current_irq) && mas_ack_count == 2'd2)  	interrupt_vector <= {mas_interrupt_offset[2:0], 3'b110, 2'd0} ; //  LO address, interval of 4
	 else if(~mas_uPM && (mas_irq || mas_current_irq) && mas_ack_count == 2'd3)  			interrupt_vector <= {mas_interrupt_offset[10:3]} ; //  HI address

//	 else if(~mas_uPM && (mas_irq || mas_current_irq) && mas_ack_count == 2'd2) interrupt_vector <=  	8'h48  ; //  LO address, interval of 4	 
//	 else if(~mas_uPM && (mas_irq || mas_current_irq) && mas_ack_count == 2'd3) interrupt_vector <=  	8'hf7 ; //  HI address
//
//	 else if(~mas_uPM && (mas_irq || mas_current_irq) && mas_ack_count == 2'd2) interrupt_vector <=  	8'hf8  ; //  LO address, interval of 4	 
//	 else if(~mas_uPM && (mas_irq || mas_current_irq) && mas_ack_count == 2'd3) interrupt_vector <=  	8'h7f ; //  HI address

    
end

//assign interrupt_vector_bits =
//    (interrupt_vector[2:0] == 3'd0)?    8'b00000001 :
//    (interrupt_vector[2:0] == 3'd1)?    8'b00000010 :
//    (interrupt_vector[2:0] == 3'd2)?    8'b00000100 :
//    (interrupt_vector[2:0] == 3'd3)?    8'b00001000 :
//    (interrupt_vector[2:0] == 3'd4)?    8'b00010000 :
//    (interrupt_vector[2:0] == 3'd5)?    8'b00100000 :
//    (interrupt_vector[2:0] == 3'd6)?    8'b01000000 :
//                                        8'b10000000;
 
assign interrupt_vector_bits =
    (mas_irq_value == 3'd0)?    8'b00000001 :
    (mas_irq_value == 3'd1)?    8'b00000010 :
    (mas_irq_value == 3'd2)?    8'b00000100 :
    (mas_irq_value == 3'd3)?    8'b00001000 :
    (mas_irq_value == 3'd4)?    8'b00010000 :
    (mas_irq_value == 3'd5)?    8'b00100000 :
    (mas_irq_value == 3'd6)?    8'b01000000 :
                                        8'b10000000;


endmodule
