// Testbench autoverificable del reset por boton de rtl/pochoco_soc.v (C6).
//
// Corre sw/trade.hex. Revisa que:
//   1. el reset de encendido se libera a los 4096 ciclos;
//   2. el programa corre (escribe los LEDs/7-seg o lee STATUS del SPI);
//   3. al apretar i_Switch[0], rst_ni baja en <= 3 ciclos y el PC vuelve a 0;
//   4. al soltarlo, rst_ni sigue en 0 4096 ciclos y despues el programa vuelve
//      a correr desde _start (el PC pasa por 0 y vuelve a leer STATUS);
//   5. los otros botones no resetean.
//
// Run (desde la raiz del repo):
//   iverilog -g2012 -o /tmp/tb_rst.vvp $(yosys-config --datdir)/ice40/cells_sim.v \
//     rtl/*.v rtl/espino_core/*.v sim/tb_reset_boton.v && vvp /tmp/tb_rst.vvp

`timescale 1ns/1ps

module tb_reset_boton;

  reg clk = 0;
  reg [3:0] sw = 4'b0000;
  always #20 clk = ~clk;

  pochoco_soc #(.MemFile("sw/trade.hex")) dut (
    .i_Clk(clk), .o_LED(), .i_Switch(sw),
    .o_Segment1_A(), .o_Segment1_B(), .o_Segment1_C(), .o_Segment1_D(),
    .o_Segment1_E(), .o_Segment1_F(), .o_Segment1_G(),
    .o_Segment2_A(), .o_Segment2_B(), .o_Segment2_C(), .o_Segment2_D(),
    .o_Segment2_E(), .o_Segment2_F(), .o_Segment2_G(),
    .i_SPI_SCLK(1'b0), .i_SPI_MOSI(1'b0), .i_SPI_CS_n(1'b1), .o_SPI_MISO());

  wire rst_ni = dut.rst_ni;
  wire [31:0] pc = dut.u_core.instr_addr_o;
  wire lee_status = dut.u_spi.rd && dut.u_spi.off == 0;

  integer ciclos = 0, errores = 0, t0, lecturas;
  always @(posedge clk) ciclos = ciclos + 1;

  task fallo(input [8*60-1:0] msg);
    begin errores = errores + 1; $display("FAIL %0s (ciclo %0d)", msg, ciclos); end
  endtask

  task esperar_status;
    begin
      lecturas = 0;
      repeat (2000) @(posedge clk) if (lee_status) lecturas = lecturas + 1;
      if (lecturas == 0) fallo("el programa no llega al bucle de espera");
    end
  endtask

  initial begin
    // 1. POR
    wait (rst_ni === 1'b1);
    if (ciclos < 4090 || ciclos > 4100) fallo("el POR no dura 4096 ciclos");
    // 2. corre
    esperar_status;

    // 5. otro boton no resetea
    @(negedge clk) sw = 4'b0010;
    repeat (50) @(posedge clk) if (rst_ni !== 1'b1) fallo("i_Switch[1] resetea");
    @(negedge clk) sw = 4'b0000;

    // 3. apretar el boton de reset 100 ciclos
    @(negedge clk) sw = 4'b0001; t0 = ciclos;
    wait (rst_ni === 1'b0);
    if (ciclos - t0 > 3) fallo("rst_ni tarda mas de 3 ciclos en bajar");
    repeat (5) @(posedge clk);
    if (pc !== 32'h0) fallo("el PC no vuelve a 0 en reset");
    repeat (95) @(posedge clk);
    if (rst_ni !== 1'b0) fallo("rst_ni subio con el boton apretado");

    // 4. soltar: 4096 ciclos mas de reset y vuelve a correr desde 0
    @(negedge clk) sw = 4'b0000; t0 = ciclos;
    wait (rst_ni === 1'b1);
    if (ciclos - t0 < 4090 || ciclos - t0 > 4100) fallo("el reset tras soltar no dura 4096 ciclos");
    if (pc !== 32'h0) fallo("no arranca en _start");
    esperar_status;

    // rebotes: pulsos cortos repetidos tambien resetean y luego se libera
    repeat (5) begin @(negedge clk) sw = 4'b0001; repeat (3) @(negedge clk); sw = 4'b0000; repeat (7) @(negedge clk); end
    if (rst_ni !== 1'b0) fallo("los rebotes no resetean");
    wait (rst_ni === 1'b1);
    esperar_status;

    if (errores == 0) $display("PASS reset por boton: POR, boton, rebotes y re-arranque");
    else              $display("FAIL reset por boton: %0d errores", errores);
    $finish;
  end

  initial begin #5_000_000; $display("FAIL timeout"); $finish; end

endmodule
