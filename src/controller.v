module controller(
	input clk,
	output [5:0] sel1,
	output sel2
	);
	
	wire [5:0] sel1_to_sel2;
	
	sel1 sel1_i(
		.clk(clk),
		.sel1(sel1_to_sel2)
		);
		
	sel1 sel2_i(
		.clk(clk),
		.sel1(sel1)
		);
		
	sel2 sel3_i(
		.clk(clk),
		.sel1(sel1_to_sel2),
		.sel2(sel2)
		);
	
endmodule