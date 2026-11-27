// tb_reinicio.sv: dos series seguidas con una pausa entre ellas, sin apretar SW1.
//
// Emula a la maestra igual que tb/tb_proyecto_4.sv (mismo SPI modo 0, misma
// contabilidad), pero manda NA precios de la serie A, espera PAUSA_NS sin
// transacciones y despues NB precios de la serie B. Al empezar B la maestra
// reinicia su contabilidad (caja 10.000, 0 acciones), como en la competencia.
// La placa no se reinicia: el programa tiene que darse cuenta solo.
//
// Escribe reinicio.csv (serie,tick,precio,decision,caja,acciones,patrimonio)
// para comparar con ref/reinicio.py y mide cuanto tarda el
// programa en reiniciarse (de la ultima transaccion de A a DECISION = 0).
//
// Uso (desde la raiz del repo, Icarus >= 13):
//   iverilog -g2012 -DPROG_HEX=\"sw/trade_v2r.hex\" -s tb_reinicio -o sim/build/tb_reinicio \
//     $(yosys-config --datdir)/ice40/cells_sim.v rtl/*.v rtl/espino_core/*.v sim/tb_reinicio.sv
//   vvp -n sim/build/tb_reinicio +PAUSA_NS=1300000000 +NB=600
//   python3 ref/reinicio.py reinicio.csv            # --sin-reinicio si la pausa es corta
// Sin -DPROG_HEX usa sim/build/trade_v2r_corto.hex (timeout de ~2 ms, para probar rapido).

`timescale 1ns/1ps

module tb_reinicio;
  localparam int PERIODO_NS = 100000;           // ronda 3
  localparam int SPI_NS     = 9500;
  localparam int CAJA0 = 10000, COMISION = 5;

  int NA = 1500, NB = 1500, INICIO_B = 6000, PAUSA_NS = 3000000;
  string SERIE = "tb/practica_meta.csv";

  logic clk = 0;
  always #20 clk = ~clk;

  logic sclk = 0, mosi = 0, cs_n = 1;
  wire  miso;

`ifndef PROG_HEX
  `define PROG_HEX "sim/build/trade_v2r_corto.hex"
`endif
  pochoco_soc #(.MemFile(`PROG_HEX)) dut (
    .i_Clk(clk), .o_LED(), .i_Switch(4'b0000),
    .o_Segment1_A(), .o_Segment1_B(), .o_Segment1_C(), .o_Segment1_D(),
    .o_Segment1_E(), .o_Segment1_F(), .o_Segment1_G(),
    .o_Segment2_A(), .o_Segment2_B(), .o_Segment2_C(), .o_Segment2_D(),
    .o_Segment2_E(), .o_Segment2_F(), .o_Segment2_G(),
    .i_SPI_SCLK(sclk), .i_SPI_MOSI(mosi), .i_SPI_CS_n(cs_n), .o_SPI_MISO(miso));

  int precio [20000];

  task automatic leer_serie;
    int fd, t, r;
    string encabezado;
    fd = $fopen(SERIE, "r");
    if (fd == 0) begin $display("ERROR: no se encontro %s", SERIE); $finish; end
    r = $fgets(encabezado, fd);
    for (int n = 0; n < 20000; n++) r = $fscanf(fd, "%d,%d\n", t, precio[n]);
    $fclose(fd);
  endtask

  int bits_x = 0;
  task automatic spi(input logic [7:0] enviar, output logic [7:0] recibido);
    cs_n = 0;
    #1000;
    for (int b = 7; b >= 0; b--) begin
      mosi = enviar[b];
      #500 sclk = 1;
      if (miso !== 1'b0 && miso !== 1'b1) bits_x++;
      recibido[b] = (miso === 1'b1);
      #500 sclk = 0;
    end
    #500 cs_n = 1;
  endtask

  int caja, acciones, w;
  task automatic ejecutar(input logic [7:0] decision, input int p);
    int q = decision[5:0];
    case (decision[7:6])
      2'b01: begin
        if (q > (caja - COMISION) / p) q = (caja - COMISION) / p;
        if (q > 0) begin caja -= q * p + COMISION; acciones += q; end
      end
      2'b10: begin
        if (q > acciones) q = acciones;
        if (q > 0 && caja + q * p >= COMISION) begin caja += q * p - COMISION; acciones -= q; end
      end
      default: ;
    endcase
    w = caja + acciones * p;
  endtask

  // Tiempo de reinicio: desde el fin de la ultima transaccion de A hasta que
  // el programa escribe DECISION durante la pausa.
  bit en_pausa = 0;
  realtime t_fin_a = 0, t_reinicio = -1;
  always @(posedge clk)
    if (en_pausa && t_reinicio < 0 && dut.u_spi.wr && dut.u_spi.off == 2)
      t_reinicio = $realtime;

  logic [7:0] decision;
  int fd;

  initial begin
    void'($value$plusargs("NA=%d", NA));
    void'($value$plusargs("NB=%d", NB));
    void'($value$plusargs("INICIO_B=%d", INICIO_B));
    void'($value$plusargs("PAUSA_NS=%d", PAUSA_NS));
    void'($value$plusargs("SERIE=%s", SERIE));
    leer_serie();
    fd = $fopen("reinicio.csv", "w");
    $fdisplay(fd, "serie,tick,precio,decision,caja,acciones,patrimonio");
    #4000;

    caja = CAJA0; acciones = 0; w = CAJA0;
    for (int n = 0; n < NA; n++) begin
      spi(precio[n], decision);
      ejecutar(decision, precio[n]);
      $fdisplay(fd, "A,%0d,%0d,%02h,%0d,%0d,%0d", n, precio[n], decision, caja, acciones, w);
      #(PERIODO_NS - SPI_NS);
    end
    t_fin_a = $realtime - (PERIODO_NS - SPI_NS);
    en_pausa = 1;
    #(PAUSA_NS);
    en_pausa = 0;

    caja = CAJA0; acciones = 0; w = CAJA0;               // la maestra empieza la serie B
    for (int n = 0; n < NB; n++) begin
      spi(precio[INICIO_B + n], decision);
      ejecutar(decision, precio[INICIO_B + n]);
      $fdisplay(fd, "B,%0d,%0d,%02h,%0d,%0d,%0d", n, precio[INICIO_B + n], decision, caja, acciones, w);
      #(PERIODO_NS - SPI_NS);
    end
    $fclose(fd);

    if (t_reinicio < 0) $display("Reinicio: no hubo (pausa de %0d ns)", PAUSA_NS);
    else $display("Reinicio: %0.0f ns despues del ultimo precio de A (%0.0f ciclos)",
                  t_reinicio - t_fin_a, (t_reinicio - t_fin_a) / 40.0);
    $display("Patrimonio final B: %0d", w);
    $display("%s MISO sin valores X", bits_x == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
