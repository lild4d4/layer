module eeprom_ctrl (
    input wire clk,
    input wire rst,

    // interface with auth
    input wire start,
    output reg busy,
    output reg done,
    input wire get_key,  // get_key = 1, get_id = 0
    output reg [127:0] buffer,

    // spi_ctrl wiring
    output reg spi_start,
    input reg spi_done,
    input reg spi_busy,
    input reg [255:0] spi_rx_data,
    output reg [255:0] spi_tx_data,
    output reg [5:0] spi_w_len,
    output reg [5:0] spi_r_len
);
  // eeprom spi interface
  reg eeprom_start;
  reg [6:0] eeprom_addr;  // read / write address in eeprom
  reg [127:0] eeprom_rdata;  // data read from an address
  reg eeprom_done;

  eeprom_spi u_eeprom_spi (
      .clk(clk),
      .rst(rst),

      .eeprom_start(eeprom_start),
      .eeprom_addr (eeprom_addr),
      .eeprom_rdata(eeprom_rdata),
      /* verilator lint_off PINCONNECTEMPTY */
      .eeprom_busy (),
      /* verilator lint_on PINCONNECTEMPTY */
      .eeprom_done (eeprom_done),

      .spi_start(spi_start),
      .spi_done(spi_done),
      .spi_busy(spi_busy),
      .spi_rx_data(spi_rx_data),
      .spi_tx_data(spi_tx_data),
      .spi_w_len(spi_w_len),
      .spi_r_len(spi_r_len)
  );

  typedef enum logic [5:0] {
    S_IDLE,
    S_GET_KEY,
    S_GET_ID,
    S_WAIT_EEPROM
  } state_t;

  reg [5:0] state;

  assign busy = (state != S_IDLE);

  /* verilator lint_off UNUSEDPARAM */
  localparam logic [6:0] AddrKeyA = 7'h00;
  localparam logic [6:0] AddrKeyB = 7'h10;
  localparam logic [6:0] AddrKeyC = 7'h20;
  localparam logic [6:0] AddrKeyD = 7'h30;

  localparam logic [6:0] AddrIdA = 7'h40;
  localparam logic [6:0] AddrIdB = 7'h50;
  localparam logic [6:0] AddrIdC = 7'h60;
  localparam logic [6:0] AddrIdD = 7'h70;
  /* verilator lint_on UNUSEDPARAM */

  always @(posedge clk) begin
    if (rst) begin
      state <= S_IDLE;
      done <= 1'b0;
      buffer <= 128'b0;
      eeprom_start <= 1'b0;
      eeprom_addr <= 7'h00;
    end else begin
      // auto clear
      done <= 1'b0;
      eeprom_start <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            state <= get_key ? S_GET_KEY : S_GET_ID;
          end
        end

        S_GET_KEY: begin
          // hard coded to key B for now
          eeprom_addr <= AddrKeyB;
          eeprom_start <= 1'b1;

          state <= S_WAIT_EEPROM;
        end


        S_GET_ID: begin
          // hard coded to id B for now
          eeprom_addr <= AddrIdB;
          eeprom_start <= 1'b1;

          state <= S_WAIT_EEPROM;
        end


        S_WAIT_EEPROM: begin
          if (eeprom_done) begin
            buffer <= eeprom_rdata;
            done   <= 1'b1;
            state  <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
