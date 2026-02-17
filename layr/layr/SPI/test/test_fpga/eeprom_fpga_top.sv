module eeprom_fpga_top (
    input         clk,
    (* MARK_DEBUG = "TRUE" *) input         rst,

    (* MARK_DEBUG = "TRUE" *) output logic [3:0] led,

    // SPI bus
    (* MARK_DEBUG = "TRUE" *) output wire       sclk,
    (* MARK_DEBUG = "TRUE" *) output wire       mosi,
    (* MARK_DEBUG = "TRUE" *) input  wire       miso,
    (* MARK_DEBUG = "TRUE" *) output wire       cs1,
    (* MARK_DEBUG = "TRUE" *) output wire       cs0
);

  // ── signals to / from the DUT ──
  logic        start;
  wire         done;
  wire         busy;
  logic        get_key;
  wire [127:0] buffer;

  test_eeprom_ctrl_tb u_dut (
      .clk     (clk),
      .rst     (rst),

      .start   (start),
      .done    (done),
      .busy    (busy),
      .get_key (get_key),
      .buffer  (buffer),

      .spi_sclk(sclk),
      .spi_mosi(mosi),
      .spi_miso(miso),
      .cs_1    (cs1),
      .cs_0    (cs0)
  );

  // ── Simple FSM: trigger a key read, wait for done, pause, repeat ──
  localparam [23:0] DELAY_CYCLES = 24'd2_000;

  typedef enum logic [2:0] {
    S_IDLE,
    S_START,
    S_WAIT,
    S_DELAY
  } state_t;

  (* MARK_DEBUG = "TRUE" *) state_t state;
  reg [23:0] ctr;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state   <= S_IDLE;
      ctr     <= DELAY_CYCLES;
      start   <= 1'b0;
      get_key <= 1'b1;        // always read key
      led     <= 4'b0000;
    end else begin
      start <= 1'b0;          // default: pulse only one cycle

      case (state)
        // wait after reset before first trigger
        S_IDLE: begin
          if (ctr == 0)
            state <= S_START;
          else
            ctr <= ctr - 1;
        end

        // pulse start for one cycle
        S_START: begin
          start <= 1'b1;
          state <= S_WAIT;
        end

        // wait for done
        S_WAIT: begin
          if (done) begin
            led[0] <= ~led[0];           // toggle heartbeat
            if (buffer[15:0] != 16'h0)   // crude check: got something
              led[1] <= 1'b1;
            else
              led[1] <= 1'b0;
            ctr   <= DELAY_CYCLES;
            state <= S_DELAY;
          end
        end

        // pause, then repeat
        S_DELAY: begin
          if (ctr == 0)
            state <= S_START;
          else
            ctr <= ctr - 1;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule