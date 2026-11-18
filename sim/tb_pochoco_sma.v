// Testbench autoverificable de rtl/pochoco_sma.v (alternativa B).
//
// Manda precios con separacion aleatoria (desde 3 ciclos, mas rapido que lo
// que permite el SPI) y compara suma_o contra un modelo de la ventana de 16
// precios que parte en cero (igual que buf[] de trade.s). Incluye extremos:
// 0, 255 y 16 precios de 255 seguidos (suma maxima 4080, sin desborde).
//
// Run: iverilog -o /tmp/tb_sma.vvp sim/tb_pochoco_sma.v rtl/pochoco_sma.v
//      vvp /tmp/tb_sma.vvp

`timescale 1ns/1ps

module tb_pochoco_sma;

  reg        clk = 0, rst_n = 0, valid = 0;
  reg  [7:0] price = 0;
  wire [11:0] suma;

  always #20 clk = ~clk;

  pochoco_sma dut (.clk_i(clk), .rst_ni(rst_n), .valid_i(valid),
                   .price_i(price), .suma_o(suma));

  reg [7:0] ventana [0:15];
  integer idx = 0, esperado = 0, errores = 0, n, k, gap, seed = 7;

  task enviar(input [7:0] p);
    begin
      @(negedge clk); price = p; valid = 1;
      @(negedge clk); valid = 0; price = $random(seed);   // price_i cambia: no debe importar
      esperado = esperado + p - ventana[idx];
      ventana[idx] = p; idx = (idx + 1) % 16;
      repeat (2) @(negedge clk);                          // suma lista 2 ciclos despues
      if (suma !== esperado[11:0]) begin
        errores = errores + 1;
        if (errores < 10) $display("FAIL precio %0d: suma %0d, esperado %0d", n, suma, esperado);
      end
    end
  endtask

  initial begin
    for (k = 0; k < 16; k = k + 1) ventana[k] = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;

    // extremos
    n = 0; enviar(8'd0);
    for (n = 1; n <= 16; n = n + 1) enviar(8'd255);
    if (suma !== 12'd4080) begin errores = errores + 1; $display("FAIL suma maxima %0d", suma); end
    for (n = 17; n <= 33; n = n + 1) enviar(8'd1);

    // aleatorio, con separacion aleatoria
    for (n = 34; n < 3000; n = n + 1) begin
      gap = $random(seed) & 7;
      repeat (gap) @(negedge clk);
      enviar($random(seed));
    end

    if (errores == 0) $display("PASS pochoco_sma: %0d precios, suma igual al modelo", n);
    else              $display("FAIL pochoco_sma: %0d errores", errores);
    $finish;
  end

endmodule
