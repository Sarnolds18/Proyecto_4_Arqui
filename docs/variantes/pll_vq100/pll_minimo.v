module t(input i_Clk, output o_LED_1);
  wire c, l; reg [23:0] n;
  SB_PLL40_CORE #(.FEEDBACK_PATH("SIMPLE"),.DIVR(4'b0000),.DIVF(7'b0010111),.DIVQ(3'b100),.FILTER_RANGE(3'b010))
    u(.REFERENCECLK(i_Clk),.PLLOUTGLOBAL(c),.LOCK(l),.RESETB(1'b1),.BYPASS(1'b0));
  always @(posedge c) n <= n + 1;
  assign o_LED_1 = n[23];
endmodule
