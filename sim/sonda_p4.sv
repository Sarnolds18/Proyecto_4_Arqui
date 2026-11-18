// Proyecto 4 - sondas de medicion por tick (M3, L1).
//
// Modulo top aparte que se compila junto a tb/tb_proyecto_4.sv (sin
// modificarlo) y observa el SoC por referencias jerarquicas. No agrega
// hardware: solo mide en simulacion.
//
// Ventana de un tick: desde byte_done del esclavo SPI (el precio queda en
// PRICE) hasta la primera lectura de STATUS posterior a la lectura de PRICE
// (el programa termino y volvio a esperar). Incluye el tiempo que el bucle
// de espera tarda en ver el precio.
//
// Por tick escribe en +TICKS=<archivo>:
//   tick, ciclos, ic, ciclos_decision
//   ciclos          ciclos de la ventana
//   ic              instrucciones retiradas en la ventana
//   ciclos_decision ciclos hasta la ultima escritura de DECISION
// y al final en +PC=<archivo> el perfil acumulado por PC:
//   pc, ciclos, instrucciones
// (un ciclo se atribuye a la instruccion que esta en ID en ese ciclo).
//
// Retiro de una instruccion en Espino: instr_valid_id && !stall en un flanco.
//
// Uso: make medir (ver Makefile).

`timescale 1ns/1ps

module sonda_p4;

  localparam int MAXPC = 512;            // palabras de RAM

  wire clk        = tb_proyecto_4.clk;
  wire byte_done  = tb_proyecto_4.dut.u_spi.byte_done;
  wire spi_rd     = tb_proyecto_4.dut.u_spi.rd;
  wire spi_wr     = tb_proyecto_4.dut.u_spi.wr;
  wire [5:0] off  = tb_proyecto_4.dut.u_spi.off;
  wire valid_id   = tb_proyecto_4.dut.u_core.instr_valid_id;
  wire stall      = tb_proyecto_4.dut.u_core.stall;
  wire [31:0] pc  = tb_proyecto_4.dut.u_core.pc_id;

  int fd_ticks;
  string ruta_ticks, ruta_pc;

  int  tick = -1, ciclos = 0, ic = 0, ciclos_dec = 0;
  bit  activo = 0, leyo_precio = 0;

  longint pc_ciclos [MAXPC];
  longint pc_instr  [MAXPC];

  initial begin
    if (!$value$plusargs("TICKS=%s", ruta_ticks)) ruta_ticks = "sonda_ticks.csv";
    if (!$value$plusargs("PC=%s", ruta_pc))       ruta_pc    = "sonda_pc.csv";
    fd_ticks = $fopen(ruta_ticks, "w");
    $fdisplay(fd_ticks, "tick,ciclos,ic,ciclos_decision");
    for (int i = 0; i < MAXPC; i++) begin pc_ciclos[i] = 0; pc_instr[i] = 0; end
  end

  always @(posedge clk) begin
    if (byte_done) begin
      if (activo)          // el tick anterior no llego a terminar: se cierra aca
        $fdisplay(fd_ticks, "%0d,%0d,%0d,%0d", tick, ciclos, ic, ciclos_dec);
      tick++;
      activo = 1; leyo_precio = 0;
      ciclos = 0; ic = 0; ciclos_dec = 0;
    end

    if (activo) begin
      if (spi_rd && off == 0 && leyo_precio) begin
        $fdisplay(fd_ticks, "%0d,%0d,%0d,%0d", tick, ciclos, ic, ciclos_dec);
        activo = 0;
      end else begin
        ciclos++;
        if (valid_id && pc[31:2] < MAXPC) pc_ciclos[pc[31:2]]++;
        if (valid_id && !stall) begin
          ic++;
          if (pc[31:2] < MAXPC) pc_instr[pc[31:2]]++;
        end
        if (spi_rd && off == 1) leyo_precio = 1;
        if (spi_wr && off == 2) ciclos_dec = ciclos;
      end
    end
  end

  final begin
    int fd;
    $fclose(fd_ticks);
    fd = $fopen(ruta_pc, "w");
    $fdisplay(fd, "pc,ciclos,instrucciones");
    for (int i = 0; i < MAXPC; i++)
      if (pc_ciclos[i] != 0 || pc_instr[i] != 0)
        $fdisplay(fd, "0x%03h,%0d,%0d", 12'(i * 4), pc_ciclos[i], pc_instr[i]);
    $fclose(fd);
  end

endmodule
