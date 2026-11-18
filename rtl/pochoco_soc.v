// Copyright 2026 Universidad de los Andes.
// Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: SHL-0.51
//
// Course: Arquitectura de Computadores (2026)
// 
// Authors:
// - Nicolás Villegas <navillegas@miuandes.cl>

module pochoco_soc #(
  parameter NumWords   = 512,
  parameter MemFile    = "../sw/blink.hex"
) (
  input  wire       i_Clk,
`ifdef SOC_PLL
  input  wire       i_PLL_Lock,      // trade_top con PLL: el POR espera el lock
`endif

  output wire [3:0] o_LED,
  input  wire [3:0] i_Switch,

  output wire       o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D,
  output wire       o_Segment1_E, o_Segment1_F, o_Segment1_G,
  output wire       o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D,
  output wire       o_Segment2_E, o_Segment2_F, o_Segment2_G,

  input  wire       i_SPI_SCLK,
  input  wire       i_SPI_MOSI,
  input  wire       i_SPI_CS_n,
  output wire       o_SPI_MISO
);

  wire clk;
  assign clk = i_Clk;

  // Power-on reset. Held for 2^12 cycles (~164 us at 25 MHz) instead of
  // just 15: right after configuration the iCE40 BRAMs (program RAM and
  // register file) need some time before reads are reliable. Only the MSB
  // is checked (no full-width compare) to save LUTs.
  reg  [12:0] por_cnt = 13'b0;
  wire        rst_ni;
`ifdef SOC_PLL
  wire por_en = i_PLL_Lock;
`else
  wire por_en = 1'b1;
`endif
  // Reset por boton (Proyecto 4): mientras i_Switch[0] este apretado el
  // contador vuelve a 0, asi que al soltarlo se repite el reset de encendido
  // completo (core, esclavo SPI con DECISION = 0 y perifericos). Sincronizado
  // con 2 FF; los rebotes solo alargan el reset. Testbench: sim/tb_reset_boton.v
  reg [1:0] btn_rst_sync = 2'b00;
  always @(posedge clk) btn_rst_sync <= {btn_rst_sync[0], i_Switch[0]};

  always @(posedge clk) begin
    if (btn_rst_sync[1])                por_cnt <= 13'd0;
    else if (!por_cnt[12] && por_en)    por_cnt <= por_cnt + 13'd1;
  end
  assign rst_ni = por_cnt[12];

  // Core-memory wiring
  wire        instr_req;
  wire [31:0] instr_addr, instr_rdata;

  wire        data_req, data_we;
  wire [3:0]  data_be;
  wire [31:0] data_addr, data_wdata, data_rdata;

  espino_core #(.BootAddr(32'h0000_0000)) u_core (
    .clk_i         (clk),
    .rst_ni        (rst_ni),
    .instr_req_o   (instr_req),
    .instr_addr_o  (instr_addr),
    .instr_rdata_i (instr_rdata),
    .data_req_o    (data_req),
    .data_we_o     (data_we),
    .data_be_o     (data_be),
    .data_addr_o   (data_addr),
    .data_wdata_o  (data_wdata),
    .data_rdata_i  (data_rdata)
  );

  wire is_mmio, spi_sel, per_sel, mul_sel;
  assign is_mmio = data_addr[31];
`ifdef SOC_MUL
  // Proyecto 4, alternativa D: multiplicador en 0x8002_0000 (addr[17])
  assign mul_sel = is_mmio &  data_addr[17];
`else
  assign mul_sel = 1'b0;
`endif
  assign per_sel = is_mmio & ~data_addr[16] & ~mul_sel;
  assign spi_sel = is_mmio &  data_addr[16] & ~mul_sel;

  wire ram_b_req, per_req, spi_req;
  assign ram_b_req = data_req & ~is_mmio;
  assign per_req   = data_req &  per_sel;
  assign spi_req   = data_req &  spi_sel;

  wire [31:0] ram_b_rdata, per_rdata, spi_rdata;

  reg rd_is_per, rd_is_spi, rd_is_mul;
  always @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_is_per <= 1'b0;
      rd_is_spi <= 1'b0;
      rd_is_mul <= 1'b0;
    end else if (data_req & ~data_we) begin
      rd_is_per <= per_sel;
      rd_is_spi <= spi_sel;
      rd_is_mul <= mul_sel;
    end
  end

  wire [31:0] mul_rdata;
`ifdef SOC_MUL
  pochoco_mul u_mul (
    .clk_i   (clk),
    .rst_ni  (rst_ni),
    .sel_i   (mul_sel),
    .req_i   (data_req & mul_sel),
    .we_i    (data_we),
    .addr_i  (data_addr[7:0]),
    .wdata_i (data_wdata),
    .rdata_o (mul_rdata)
  );
`else
  assign mul_rdata = 32'd0;
`endif

  assign data_rdata = rd_is_per ? per_rdata :
                      rd_is_spi ? spi_rdata :
                      rd_is_mul ? mul_rdata : ram_b_rdata;

  pochoco_ram #(.NumWords(NumWords), .MemFile(MemFile)) u_ram (
    .clk_i     (clk),
    .a_req_i   (instr_req),
    .a_addr_i  (instr_addr),
    .a_rdata_o (instr_rdata),
    .b_req_i   (ram_b_req),
    .b_we_i    (data_we),
    .b_be_i    (data_be),
    .b_addr_i  (data_addr),
    .b_wdata_i (data_wdata),
    .b_rdata_o (ram_b_rdata)
  );

  // Peripherals
  wire [6:0] seg1, seg2;

  pochoco_periph u_periph (
    .clk_i     (clk),
    .rst_ni    (rst_ni),
    .sel_i     (per_sel),
    .req_i     (per_req),
    .we_i      (data_we),
    .addr_i    (data_addr[7:0]),
    .wdata_i   (data_wdata),
    .rdata_o   (per_rdata),
    .leds_o    (o_LED),
    .btn_i     (i_Switch),
    .seg1_o    (seg1),
    .seg2_o    (seg2)
  );

  // SPI Slave
  pochoco_spi_slave u_spi (
    .clk_i      (clk),
    .rst_ni     (rst_ni),
    .sel_i      (spi_sel),
    .req_i      (spi_req),
    .we_i       (data_we),
    .addr_i     (data_addr[7:0]),
    .wdata_i    (data_wdata),
    .rdata_o    (spi_rdata),
    .spi_sclk_i (i_SPI_SCLK),
    .spi_mosi_i (i_SPI_MOSI),
    .spi_cs_n_i (i_SPI_CS_n),
    .spi_miso_o (o_SPI_MISO)
  );

  // 7-seg is active-low on the board
  assign {o_Segment1_G, o_Segment1_F, o_Segment1_E, o_Segment1_D,
          o_Segment1_C, o_Segment1_B, o_Segment1_A} = ~seg1;
  assign {o_Segment2_G, o_Segment2_F, o_Segment2_E, o_Segment2_D,
          o_Segment2_C, o_Segment2_B, o_Segment2_A} = ~seg2;

endmodule