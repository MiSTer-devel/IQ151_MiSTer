module MH102(
   input clk, //???

   input FR,
   input RN,
   input wr_n,
   input rd_n,
   input cs_n,
   input a0,
   
   inout [7:0] D
);


//;HW nasobicka MH102
//;FR   A0   /CS   /WR   /RD   RND   funkce
//; 1    X    X     X     X     X    7-mi bitove nasobeni D7=1 zaporne/D7=0 kladne
//; 0    X    X     X     X     X    8-mi bitove nasobeni
//; X    0    X     X     X     X    nizsi byte (cteni/zapis)
//; X    1    X     X     X     X    vyssi byte (cteni/zapis)
//; X    X    1     X     X     X    obvod nevybran, D0..D7=1
//; X    X    0     X     X     X    obvod vybran pro cteni/zapis
//; X    X    X     1     X     X    zapis blokovan
//; X    X    X     0     X     X    zapis do obvodu povolen
//; X    X    X     X     1     X    cteni blokovano D0..D7=1
//; X    X    X     X     0     X    cteni registru povoleno
//; 1    1    X     X     X     1    zaokrouhluje D01= D´9 + prenos (D´7+1)
//; 0    1    X     X     X     1    zaokrouhluje D01= D´9 + prenos (D´8+1)
//; X    X    X     X     X     0    nezaokrouhluje

reg [7:0] D1;
reg [7:0] D2;

wire result [15:0];
//assign result = D1 * D2;

endmodule // MH102