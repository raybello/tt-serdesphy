module spwm(
	input clk,
	input [5:0] sel1,
	output out
	);
	
	reg [6:0] counter = 1;
	reg [6:0] r_duty_cycle =0;
	
	always @ (posedge clk)
		begin
			case(sel1)
				0  : r_duty_cycle <= 0;
				1  : r_duty_cycle <= 9;
				2  : r_duty_cycle <= 17;
				3  : r_duty_cycle <= 26;
				4  : r_duty_cycle <= 35;
				5  : r_duty_cycle <= 42;
				6  : r_duty_cycle <= 50;
				7  : r_duty_cycle <= 57;
				8  : r_duty_cycle <= 64;
				9  : r_duty_cycle <= 71;
				10 : r_duty_cycle <= 77;
				11 : r_duty_cycle <= 82;
				12 : r_duty_cycle <= 87;
				13 : r_duty_cycle <= 90;
				14 : r_duty_cycle <= 93;
				15 : r_duty_cycle <= 96;
				16 : r_duty_cycle <= 97;
				17 : r_duty_cycle <= 98;
				18 : r_duty_cycle <= 99; //middle 
				19 : r_duty_cycle <= 98;
				20 : r_duty_cycle <= 97;
				21 : r_duty_cycle <= 96;
				22 : r_duty_cycle <= 93;
				23 : r_duty_cycle <= 90;
				24 : r_duty_cycle <= 87;
				25 : r_duty_cycle <= 82;
				26 : r_duty_cycle <= 77;
				27 : r_duty_cycle <= 71;
				28 : r_duty_cycle <= 64;
				29 : r_duty_cycle <= 57;
				30 : r_duty_cycle <= 50;
				31 : r_duty_cycle <= 42;
				32 : r_duty_cycle <= 35;
				33 : r_duty_cycle <= 26;
				34 : r_duty_cycle <= 17;
				35 : r_duty_cycle <= 9;
				36 : r_duty_cycle <= 0;
			endcase
		end
	
	always @ (posedge clk)
		begin
			if (counter <=100)
				counter <= counter +1;
			else 
				counter <=1;
		end
	
	assign out = (counter <= r_duty_cycle) ? 1:0;
	
endmodule 