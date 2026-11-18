// Proyecto 4 - Pochoco Trader, alternativa de hardware B.
//
// pochoco_sma: suma movil de los ultimos 16 precios recibidos por SPI.
// Hace en hardware la actualizacion de la ventana de trade.s
// (suma += p - buf[idx]; buf[idx] = p; idx = (idx + 1) & 15), con los 16
// precios en una memoria 16x8 que se infiere como BRAM. El core sigue
// calculando y escribiendo la decision; esto solo le entrega la suma.
//
// Se activa con la macro SOC_SMA: pochoco_spi_slave la instancia y la
// expone en el offset 0x0C del esclavo (SUMA, solo lectura, 12 bits).
//
// Tiempo: valid_i es byte_done retrasado un ciclo (price_i ya estable). La
// suma nueva queda lista 2 ciclos despues de valid_i. El programa no puede
// leerla antes: entre byte_done y la lectura de SUMA tiene que leer STATUS
// y PRICE (al menos 6 ciclos). Testbench: sim/tb_pochoco_sma.v.

module pochoco_sma (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire        valid_i,     // precio nuevo en price_i (1 ciclo)
  input  wire [7:0]  price_i,
  output reg  [11:0] suma_o       // suma de los ultimos 16 precios (16 * 255 = 4080)
);

  // Ventana: parte en cero al configurar la FPGA, igual que buf[] en trade.s
  reg [7:0] mem [0:15];
  integer i;
  initial for (i = 0; i < 16; i = i + 1) mem[i] = 8'd0;

  reg [3:0] idx_q;
  reg [7:0] p_q, old_q;
  reg       fase_q;

  // Lectura sincrona del precio que sale (puerto de lectura de la BRAM)
  always @(posedge clk_i) old_q <= mem[idx_q];

  // Escritura del precio que entra
  always @(posedge clk_i) if (fase_q) mem[idx_q] <= p_q;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      idx_q  <= 4'd0;
      p_q    <= 8'd0;
      fase_q <= 1'b0;
      suma_o <= 12'd0;
    end else begin
      fase_q <= valid_i;
      if (valid_i) p_q <= price_i;
      if (fase_q) begin
        suma_o <= suma_o + {4'd0, p_q} - {4'd0, old_q};
        idx_q  <= idx_q + 4'd1;
      end
    end
  end

endmodule
