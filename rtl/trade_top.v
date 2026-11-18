// Copyright 2026 Universidad de los Andes.
// Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: SHL-0.51
//
// Course: Arquitectura de Computadores (2026)
// Proyecto 4 - Pochoco Trader
//
// trade_top: FPGA top-level for the trading agent. It wires the Go Board
// pins (goboard.pcf) straight into pochoco_soc, which boots sw/trade.hex.
// The price arrives and the decision leaves through the SPI slave (PMOD
// pins); the algorithm lives in sw/trade.s.

module trade_top #(
  parameter MemFile = "sw/trade.hex"   // make TRADE_HEX=... lo cambia con chparam
) (
  input  wire       i_Clk,

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

  // Alternativa de hardware A (macro SOC_PLL): el SoC corre con el PLL a
  // 37,5 MHz (25 MHz * 24 / 16, parametros de `icepll -i 25 -o 37.5`). Sin
  // SOC_PLL corre directo del oscilador de 25 MHz.
  wire clk_soc;
`ifdef SOC_PLL
  wire pll_lock;
  SB_PLL40_CORE #(
    .FEEDBACK_PATH ("SIMPLE"),
    .DIVR          (4'b0000),
    .DIVF          (7'b0010111),
    .DIVQ          (3'b100),
    .FILTER_RANGE  (3'b010)
  ) u_pll (
    .REFERENCECLK  (i_Clk),
    .PLLOUTGLOBAL  (clk_soc),
    .LOCK          (pll_lock),
    .RESETB        (1'b1),
    .BYPASS        (1'b0)
  );
`else
  assign clk_soc = i_Clk;
`endif

  pochoco_soc #(
    .NumWords (512),
    .MemFile  (MemFile)
  ) u_pochoco (
    .i_Clk        (clk_soc),
`ifdef SOC_PLL
    .i_PLL_Lock   (pll_lock),
`endif

    .o_LED        (o_LED),
    .i_Switch     (i_Switch),

    .o_Segment1_A (o_Segment1_A), .o_Segment1_B (o_Segment1_B),
    .o_Segment1_C (o_Segment1_C), .o_Segment1_D (o_Segment1_D),
    .o_Segment1_E (o_Segment1_E), .o_Segment1_F (o_Segment1_F),
    .o_Segment1_G (o_Segment1_G),
    .o_Segment2_A (o_Segment2_A), .o_Segment2_B (o_Segment2_B),
    .o_Segment2_C (o_Segment2_C), .o_Segment2_D (o_Segment2_D),
    .o_Segment2_E (o_Segment2_E), .o_Segment2_F (o_Segment2_F),
    .o_Segment2_G (o_Segment2_G),

    .i_SPI_SCLK   (i_SPI_SCLK),
    .i_SPI_MOSI   (i_SPI_MOSI),
    .i_SPI_CS_n   (i_SPI_CS_n),
    .o_SPI_MISO   (o_SPI_MISO)
  );

endmodule
