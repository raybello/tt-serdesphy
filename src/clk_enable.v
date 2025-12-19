module clk_enable(
  input clk,
  output CE  //clock enable 
);
  
  reg [9:0] r_count = 0;
  reg r_CE;
  
  always @ (posedge clk)
    begin 
      if (r_count <= 250 )
        begin 
          r_count <= r_count +1;
          r_CE <= 0;
        end
      
      else 
        begin 
          r_count <= 0;
          r_CE <=1;
        end

    end
  
  assign CE = r_CE;
  
endmodule 