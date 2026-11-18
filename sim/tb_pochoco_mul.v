// Testbench autoverificable de rtl/pochoco_mul.v (alternativa D).
//
// Por el bus MMIO (como lo hace Espino): escribe A y B, espera OCUPADO = 0,
// lee P y lo compara con A * B (32 bits). Revisa ademas que tarde
// exactamente bits(B) ciclos y casos borde (B = 0, B = 1, 0xFFFF, A grande,
// los operandos de V2 con D^2 = 24025).
//
// Run: iverilog -o /tmp/tb_mul.vvp sim/tb_pochoco_mul.v rtl/pochoco_mul.v
//      vvp /tmp/tb_mul.vvp

`timescale 1ns/1ps

module tb_pochoco_mul;

  reg         clk = 0, rst_n = 0, req = 0, we = 0;
  reg  [7:0]  addr = 0;
  reg  [31:0] wdata = 0;
  wire [31:0] rdata;

  always #20 clk = ~clk;

  pochoco_mul dut (.clk_i(clk), .rst_ni(rst_n), .sel_i(1'b1), .req_i(req), .we_i(we),
                   .addr_i(addr), .wdata_i(wdata), .rdata_o(rdata));

  integer errores = 0, n, ciclos, bits, seed = 3;
  reg [31:0] a, p, ocup;
  reg [15:0] b;

  task escribir(input [7:0] ad, input [31:0] d);
    begin @(negedge clk); req = 1; we = 1; addr = ad; wdata = d; @(negedge clk); req = 0; we = 0; end
  endtask

  task leer(input [7:0] ad, output [31:0] d);
    begin @(negedge clk); req = 1; we = 0; addr = ad; @(negedge clk); req = 0; d = rdata; end
  endtask

  task probar(input [31:0] ta, input [15:0] tb_);
    begin
      escribir(8'h0, ta);
      escribir(8'h4, {16'hABCD, tb_});          // bits altos de B se ignoran
      ciclos = 0;
      ocup = 1;
      while (ocup[0]) begin leer(8'hC, ocup); ciclos = ciclos + 2; end
      leer(8'h8, p);
      if (p !== ta * tb_) begin
        errores = errores + 1;
        if (errores < 10) $display("FAIL %0d * %0d = %0d, esperado %0d", ta, tb_, p, ta * tb_);
      end
      bits = 0; while ((tb_ >> bits) != 0) bits = bits + 1;
      // cada lectura de OCUPADO toma 2 ciclos: el ultimo leido en 0 llega a lo mas 2 ciclos tarde
      if (ciclos > bits + 3) begin
        errores = errores + 1;
        if (errores < 10) $display("FAIL B=%0d: %0d ciclos, deberian ser ~%0d", tb_, ciclos, bits);
      end
    end
  endtask

  initial begin
    repeat (2) @(negedge clk); rst_n = 1;
    probar(32'd12345, 16'd0);
    probar(32'd12345, 16'd1);
    probar(32'hFFFF_FFFF, 16'd1);
    probar(32'd1, 16'hFFFF);
    probar(32'd65535, 16'hFFFF);
    probar(32'd122522, 16'd24025);     // D^2 * W de la serie de estres
    probar(32'd24025, 16'd155);
    for (n = 0; n < 3000; n = n + 1) begin
      a = $random(seed);
      b = $random(seed);
      if (n % 3 == 0) a = a & 32'h0003_FFFF;   // tamanos de V2
      if (n % 5 == 0) b = b & 16'h00FF;
      probar(a, b);
    end
    if (errores == 0) $display("PASS pochoco_mul: %0d productos y tiempos correctos", n + 7);
    else              $display("FAIL pochoco_mul: %0d errores", errores);
    $finish;
  end

endmodule
