`default_nettype none

// Keyboard for IQ151

module keyboard (
      input  wire        reset,
      input  wire        clk,
      input  wire [10:0] ps2_key,
      input  wire  [7:0] X_in,  //  rows    => X = PA
      output wire  [7:0] X_out, //
      input  wire  [7:0] Y_in,  //  columns => Y = PB
      output wire  [7:0] Y_out, //
      output reg         FA,
      output reg         FB,
      output wire        SH, // shift
      output wire        CTRL,
      output reg         BREAK,
      output reg         RES
);

wire       pressed      = ps2_key[9];
wire       input_strobe = ps2_key[10];
wire       extended     = ps2_key[8];
wire [7:0] code         = ps2_key[7:0];
reg  [7:0] keys[7:0];
reg        capsLock;
reg        shiftL;
reg        shiftR;
reg        ctrlL;
reg        ctrlR;
reg        shiftExtra; // used when I need use shift to map extra PC key
assign     SH           = shiftExtra & ((shiftL & shiftR) ^ capsLock);
assign     CTRL         = ctrlL & ctrlR;

// columns => Y = PB
assign Y_out = ((~X_in[0]) ? {keys[7][0], keys[6][0], keys[5][0], keys[4][0], keys[3][0], keys[2][0], keys[1][0], keys[0][0]} : 8'hFF) &
               ((~X_in[1]) ? {keys[7][1], keys[6][1], keys[5][1], keys[4][1], keys[3][1], keys[2][1], keys[1][1], keys[0][1]} : 8'hFF) &
               ((~X_in[2]) ? {keys[7][2], keys[6][2], keys[5][2], keys[4][2], keys[3][2], keys[2][2], keys[1][2], keys[0][2]} : 8'hFF) &
               ((~X_in[3]) ? {keys[7][3], keys[6][3], keys[5][3], keys[4][3], keys[3][3], keys[2][3], keys[1][3], keys[0][3]} : 8'hFF) &
               ((~X_in[4]) ? {keys[7][4], keys[6][4], keys[5][4], keys[4][4], keys[3][4], keys[2][4], keys[1][4], keys[0][4]} : 8'hFF) &
               ((~X_in[5]) ? {keys[7][5], keys[6][5], keys[5][5], keys[4][5], keys[3][5], keys[2][5], keys[1][5], keys[0][5]} : 8'hFF) &
               ((~X_in[6]) ? {keys[7][6], keys[6][6], keys[5][6], keys[4][6], keys[3][6], keys[2][6], keys[1][6], keys[0][6]} : 8'hFF) &
               ((~X_in[7]) ? {keys[7][7], keys[6][7], keys[5][7], keys[4][7], keys[3][7], keys[2][7], keys[1][7], keys[0][7]} : 8'hFF);

// rows    => X = PA
assign X_out = ((~Y_in[0]) ? keys[0] : 8'hFF) &
               ((~Y_in[1]) ? keys[1] : 8'hFF) &
               ((~Y_in[2]) ? keys[2] : 8'hFF) &
               ((~Y_in[3]) ? keys[3] : 8'hFF) &
               ((~Y_in[4]) ? keys[4] : 8'hFF) &
               ((~Y_in[5]) ? keys[5] : 8'hFF) &
               ((~Y_in[6]) ? keys[6] : 8'hFF) &
               ((~Y_in[7]) ? keys[7] : 8'hFF);

reg old_stb;
reg old_reset = 1'b0;

always @(posedge clk)
begin
   old_stb   <= input_strobe;
   old_reset <= reset;

   if(~old_reset & reset)
   begin
      keys[0]    <= 8'b11111111;
      keys[1]    <= 8'b11111111;
      keys[2]    <= 8'b11111111;
      keys[3]    <= 8'b11111111;
      keys[4]    <= 8'b11111111;
      keys[5]    <= 8'b11111111;
      keys[6]    <= 8'b11111111;
      keys[7]    <= 8'b11111111;
      FA         <= 1'b1;
      FB         <= 1'b1;
      BREAK      <= 1'b1;
      RES        <= 1'b1;
      capsLock   <= 1'b0;
      ctrlL      <= 1'b1;
      ctrlR      <= 1'b1;
      shiftL     <= 1'b1;
      shiftR     <= 1'b1;
      shiftExtra <= 1'b1;
   end

   if(old_stb != input_strobe)
   begin
      if (extended)
      begin
         /* Extended keys */
         case(code)
            8'h4a : keys[4][3] <= ~pressed; // / = ?
            8'h5a : keys[4][4] <= ~pressed; // CR = ENTER NUMPAD
            8'h71 : keys[4][5] <= ~pressed; // DC = Delete
            8'h70 : keys[4][6] <= ~pressed; // INS (e070)
            8'h6b : keys[5][6] <= ~pressed; // <--- = sipka vlevo (E06b)
            8'h72 : keys[6][3] <= ~pressed; // down = sipka dolu (e072)
            8'h6c : keys[6][6] <= ~pressed; // Home (E06C)
            8'h75 : keys[7][5] <= ~pressed; // up = sipka nahoru (e075)
            8'h74 : keys[7][6] <= ~pressed; // right = sipka vpravo (e074)
            8'h14 : ctrlR      <= ~pressed; // Ctrl (right)
            8'h11 : FB         <= ~pressed; // FB = Alt (right)
         endcase
      end
      else
      begin
         /* character keys */
         case(code)
            8'h59 : shiftR     <= ~pressed; // right shift
            8'h12 : shiftL     <= ~pressed; // Left shift
            8'h14 : ctrlL      <= ~pressed; // Ctrl (left)
            8'h11 : FA         <= ~pressed; // FA = Alt (left)
            8'h76 : BREAK      <= ~pressed; // BREAK = ESC
            8'h58 : if (~pressed) capsLock <= ~capsLock ; //  toggle Caps Lock
            8'h66 : keys[5][6] <= ~pressed; // <--- = sipka vlevo  = jako backspace
         endcase

         case(code)
            // row 0
            8'h16 : keys[0][0] <= ~pressed; // 1
            8'h69 : keys[0][0] <= ~pressed; // 1 NUMPAD
            8'h1e : keys[0][1] <= ~pressed; // 2
            8'h72 : keys[0][1] <= ~pressed; // 2 NUMPAD
            8'h26 : keys[0][2] <= ~pressed; // 3
            8'h7a : keys[0][2] <= ~pressed; // 3 NUMPAD
            8'h25 : keys[0][3] <= ~pressed; // 4
            8'h6b : keys[0][3] <= ~pressed; // 4 NUMPAD
            8'h2e : keys[0][4] <= ~pressed; // 5
            8'h73 : keys[0][4] <= ~pressed; // 5 NUMPAD
            8'h36 : keys[0][5] <= ~pressed; // 6
            8'h74 : keys[0][5] <= ~pressed; // 6 NUMPAD
            8'h3d : keys[0][6] <= ~pressed; // 7
            8'h6c : keys[0][6] <= ~pressed; // 7 NUMPAD
            8'h3e : keys[0][7] <= ~pressed; // 8
            8'h75 : keys[0][7] <= ~pressed; // 8 NUMPAD
         endcase

         case(code)
            // row 1
            8'h15 : keys[1][0] <= ~pressed; // Q
            8'h1d : keys[1][1] <= ~pressed; // W
            8'h24 : keys[1][2] <= ~pressed; // E
            8'h2d : keys[1][3] <= ~pressed; // R
            8'h2c : keys[1][4] <= ~pressed; // T
            8'h35 : keys[1][5] <= ~pressed; // Y
            8'h3c : keys[1][6] <= ~pressed; // U
            8'h43 : keys[1][7] <= ~pressed; // I
         endcase

         case(code)
            // row 2
            8'h1c : keys[2][0] <= ~pressed; // A
            8'h1b : keys[2][1] <= ~pressed; // S
            8'h23 : keys[2][2] <= ~pressed; // D
            8'h2b : keys[2][3] <= ~pressed; // F
            8'h34 : keys[2][4] <= ~pressed; // G
            8'h33 : keys[2][5] <= ~pressed; // H
            8'h3b : keys[2][6] <= ~pressed; // J
            8'h42 : keys[2][7] <= ~pressed; // K
         endcase

         case(code)
            // row 3
            8'h1a : keys[3][0] <= ~pressed; // Z
            8'h22 : keys[3][1] <= ~pressed; // X
            8'h21 : keys[3][2] <= ~pressed; // C
            8'h2a : keys[3][3] <= ~pressed; // V
            8'h32 : keys[3][4] <= ~pressed; // B
            8'h31 : keys[3][5] <= ~pressed; // N
            8'h3a : keys[3][6] <= ~pressed; // M
            8'h41 : keys[3][7] <= ~pressed; // , <
            8'h71 : keys[3][7] <= ~pressed; // , NUMPAD
         endcase

         case(code)
            // row 4
            8'h46 : keys[4][0] <= ~pressed; // 9
            8'h7d : keys[4][0] <= ~pressed; // 9 NUMPAD
            8'h44 : keys[4][1] <= ~pressed; // O
            8'h4b : keys[4][2] <= ~pressed; // L
            8'h49 : keys[4][3] <= ~pressed; // . >
            8'h5a : keys[4][4] <= ~pressed; // CR = ENTER
            // [4][5] DC = Delete
            // [4][6] IC = INSERT = in special characters
            8'h05 : keys[4][7] <= ~pressed; // F1
         endcase

         case(code)
            // row 5
            8'h45 : keys[5][0] <= ~pressed; // 0
            8'h70 : keys[5][0] <= ~pressed; // 0 NUMPAD
            8'h4d : keys[5][1] <= ~pressed; // P
            8'h4c : keys[5][2] <= ~pressed; // ; +
            8'h79 : keys[5][2] <= ~pressed; // + NUMPAD
            8'h4A : keys[5][3] <= ~pressed; // ? 
            8'h5d : keys[5][4] <= ~pressed; // ! = '
            8'h83 : keys[5][5] <= ~pressed; // DL = F7
            // [5][6] left = in special characters
            8'h06 : keys[5][7] <= ~pressed; // F2
         endcase

         case(code)
            // row 6
            8'h0e : keys[6][0] <= ~pressed; // ~
            8'h54 : keys[6][1] <= ~pressed; // [
            8'h5b : keys[6][2] <= ~pressed; // ]
            // [6][3] down = in special characters
            8'h03 : keys[6][4] <= ~pressed; // K4 = F5
            8'h0b : keys[6][5] <= ~pressed; // IL= F6
            // [6][6] HOME = in special characters
            8'h0c : keys[6][7] <= ~pressed; // F4
         endcase

         case(code)
            // row 7
            8'h55 : keys[7][0] <= ~pressed; // =
            8'h54 : keys[7][1] <= ~pressed; // @ = [  !!!!!!
            8'h52 : keys[7][2] <= ~pressed; // : *
            8'h7c : keys[7][2] <= ~pressed; // * NUMPAD
            8'h29 : keys[7][3] <= ~pressed; // Space
            8'h4E : keys[7][4] <= ~pressed; // -
            8'h7B : keys[7][4] <= ~pressed; // - NUMPAD
            // [7][5] up = in special characters
            // [7][6] right = in special characters
            8'h04 : keys[7][7] <= ~pressed; // F3
         endcase

      end
   end
end

endmodule //keyboard