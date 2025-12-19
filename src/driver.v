module H_driver(
	input clk,
	input sel2,
	input in1,
	input in2,
	output out1,
	output out2
	);
	
	reg r_out1, r_out2;
	
	always @ (*) 
		begin
			case(sel2)
				0 : r_out1 <= in1; 
                1 : r_out1 <= 0;
            endcase
           	case(sel2)
				0 : r_out2 <= 0;
				1 : r_out2 <= in2;
			endcase
		end
	assign out1 = r_out1;
	assign out2 = r_out2;
	
endmodule 