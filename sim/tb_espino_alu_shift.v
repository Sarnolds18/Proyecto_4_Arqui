// Testbench autoverificable del shifter de rtl/espino_core/espino_alu.v
// (alternativa C). Compara SLL (y SRL/SRA con ESPINO_SHIFTER_FULL) contra
// los operadores de Verilog para todos los shamt y operandos aleatorios, y
// revisa que ADD/SUB sigan bien. Solo usa bits [4:0] de operand_b como shamt,
// igual que RV32 (SLLI y SLL).
//
// Run (solo SLL):
//   iverilog -DESPINO_SHIFTER -o /tmp/tb_alu.vvp sim/tb_espino_alu_shift.v rtl/espino_core/espino_alu.v
//   vvp /tmp/tb_alu.vvp
// Run (los tres): igual con -DESPINO_SHIFTER_FULL

`timescale 1ns/1ps

module tb_espino_alu_shift;

  reg  [3:0]  op;
  reg  [31:0] a, b;
  wire [31:0] r;
  wire        cmp;

  espino_alu dut (.operator_i(op), .operand_a_i(a), .operand_b_i(b),
                  .result_o(r), .cmp_result_o(cmp));

  integer n, s, errores = 0, seed = 11;
  reg [31:0] esperado;

  task revisar(input [3:0] o, input [31:0] e, input [8*4-1:0] nombre);
    begin
      op = o; #1;
      if (r !== e) begin
        errores = errores + 1;
        if (errores < 10) $display("FAIL %0s a=%h b=%h: %h, esperado %h", nombre, a, b, r, e);
      end
    end
  endtask

  initial begin
    for (n = 0; n < 2000; n = n + 1) begin
      a = (n < 32) ? 32'h8000_0001 : $random(seed);
      for (s = 0; s < 32; s = s + 1) begin
        b = {$random(seed)} & 32'hFFFF_FFE0 | s;        // bits altos de b no deben importar
        revisar(4'd5, a << s, "SLL ");
`ifdef ESPINO_SHIFTER_FULL
        revisar(4'd6, a >> s, "SRL ");
        revisar(4'd7, $signed(a) >>> s, "SRA ");
`endif
      end
      b = $random(seed);
      revisar(4'd0, a + b, "ADD ");
      revisar(4'd1, a - b, "SUB ");
    end
    if (errores == 0) $display("PASS espino_alu shifter: %0d operandos x 32 shamt", n);
    else              $display("FAIL espino_alu shifter: %0d errores", errores);
    $finish;
  end

endmodule
