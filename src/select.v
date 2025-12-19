module sel1(
	input clk,
	output [5:0] sel1
	);
	
	reg [5:0] r_sel1 =0; 
	reg [6:0] r_count =0;
    reg r_sel_pulse =0;
	
	always @ (posedge clk)
		begin
			if (r_count <= 99)
				r_count <= r_count +1;
			else
				begin
					r_count <= 0;
					r_sel_pulse <= 1;
				end
	
			if (r_sel_pulse)
				begin
					r_sel_pulse <=0;
					r_sel1 <= r_sel1 +1;
					   if (r_sel1 >36)
				            begin
				               r_sel1 <=0;
				            end
					
				end
		end
	
	assign sel1 = r_sel1;
endmodule

module sel2(
	input clk,
	input [5:0] sel1,
	output sel2
	);
	
	reg r_sel2 = 0;
	
	always @ (posedge clk) 
		begin 
			if (sel1 <= 0)
				r_sel2 <= ~r_sel2;
		end
		
	assign sel2 = r_sel2;
	
endmodule 