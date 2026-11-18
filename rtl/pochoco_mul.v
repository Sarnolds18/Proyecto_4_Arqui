// Proyecto 4 - Pochoco Trader, alternativa de hardware D.
//
// pochoco_mul: multiplicador secuencial mapeado en memoria (base
// 0x8002_0000, macro SOC_MUL). Hace en hardware la subrutina mul de
// trade.s: P = A * B sin signo, A de 32 bits, B de 16 bits, un bit de B por
// ciclo (suma y doble) y termina apenas B llega a 0, asi que tarda
// bits(B) ciclos (como mucho 16). Los productos de V2 son < 2^32.
//
//   +0x0  A       escritura
//   +0x4  B       escritura; arranca la multiplicacion (P = 0)
//   +0x8  P       lectura (valido cuando OCUPADO = 0)
//   +0xC  OCUPADO lectura, bit 0
//
// Una multiplicacion combinacional de 16x16 no cabe en la HX1K (sin DSP);
// esta usa ~100 LC. Testbench: sim/tb_pochoco_mul.v.

module pochoco_mul (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire        sel_i,
  input  wire        req_i,
  input  wire        we_i,
  input  wire [7:0]  addr_i,
  input  wire [31:0] wdata_i,
  output reg  [31:0] rdata_o
);

  wire [5:0] off    = addr_i[7:2];
  wire       access = sel_i & req_i;
  wire       wr     = access &  we_i;
  wire       rd     = access & ~we_i;

  reg [31:0] a_q, p_q;
  reg [15:0] b_q;
  wire       ocupado = (b_q != 16'd0);

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      a_q <= 32'd0;
      b_q <= 16'd0;
      p_q <= 32'd0;
    end else if (wr && off == 6'd0) begin
      a_q <= wdata_i;
    end else if (wr && off == 6'd1) begin
      b_q <= wdata_i[15:0];
      p_q <= 32'd0;
    end else if (ocupado) begin
      if (b_q[0]) p_q <= p_q + a_q;
      a_q <= {a_q[30:0], 1'b0};
      b_q <= {1'b0, b_q[15:1]};
    end
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rdata_o <= 32'd0;
    else if (rd) begin
      case (off)
        6'd2:    rdata_o <= p_q;
        6'd3:    rdata_o <= {31'd0, ocupado};
        default: rdata_o <= 32'd0;
      endcase
    end
  end

endmodule
