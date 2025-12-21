derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

#set clk_sys {emu:emu|clk_sys}


create_clock -name {emu:emu|clk_sys} -period 54.25
create_clock -name {emu:emu|IQ151_core:IQ151_core|i8224:i8224|phi2reg[0]} -period 54.25 -waveform {0 24.12} [get_registers {emu:emu|IQ151_core:IQ151_core|i8224:i8224|phi2reg[0]}]

#
#3Warning (332060): Node: emu:emu|IQ151G:IQ151core|i8224:i8224|phi2reg[0] was determined to be a clock but was found without an associated clock assignment.
#	Info (13166): Register emu:emu|IQ151G:IQ151core|i8224:i8224|reset is being clocked by emu:emu|IQ151G:IQ151core|i8224:i8224|phi2reg[0]

#
#create_generated_clock -name phi1 -source [get_nets {emu|pll|pll_inst|altera_pll_i|outclk_wire[1]}] -divide_by 9 -duty_cycle 22.23 [get_registers {emu:emu|IQ151G:IQ151core|i8224:i8224|phi1}]
#create_generated_clock -name phi2 -source [get_nets {emu|pll|pll_inst|altera_pll_i|outclk_wire[1]}] -divide_by 9 -duty_cycle 55.56 [get_registers {emu:emu|IQ151G:IQ151core|i8224:i8224|phi2}]
#
#create_generated_clock -name d1_video32 -source [get_nets {emu|pll|pll_inst|altera_pll_i|outclk_wire[1]}] -divide_by 3 -duty_cycle 50 {emu:emu|IQ151G:IQ151core|video32:video32|d1}
#create_generated_clock -name d2_video32 -source [get_nets {emu|pll|pll_inst|altera_pll_i|outclk_wire[1]}] -divide_by 2 -duty_cycle 50 {emu:emu|IQ151G:IQ151core|video32:video32|d2}
#
#
#create_generated_clock -name d1_video64 -source [get_nets {emu|pll|pll_inst|altera_pll_i|outclk_wire[1]}] -divide_by 2 -duty_cycle 50 {emu:emu|IQ151G:IQ151core|video64:video64|d1}


#|sys_top|emu:emu|IQ151_core:IQ151_core|vm80a:cpu|

set_multicycle_path -to {emu|IQ151_core|cpu|*} -setup 2
set_multicycle_path -to {emu|IQ151_core|cpu|*} -hold 1