/**
This module handles the interface to the auth module.
*/
module layr_auth (
    input logic clk,
    input logic rst,
    input logic idle_clear,

    input logic generate_challenge,
    input logic verify_id,

    input logic [127:0] card_cipher,
    input logic [127:0] id_cipher,

    output logic chip_challenge_generated,
    output logic [127:0] chip_challenge,

    output logic id_verified,
    output logic id_valid,

    input logic eeprom_busy,
    input logic eeprom_done,
    input logic [127:0] eeprom_buffer,
    output logic eeprom_start,
    output logic eeprom_get_key
);

  logic start;
  logic operation;
  logic auth_valid;
  logic [127:0] auth_data_in;
  logic [127:0] auth_data_out;

  typedef enum logic [5:0] {
    READY,
    RUNNING,
    DONE
  } state_t;

  (* MARK_DEBUG = "TRUE" *) state_t state, next_state;

  always_comb begin
    next_state = state;
    case (state)
      READY: begin
        if (generate_challenge | verify_id) next_state = RUNNING;
      end
      RUNNING: begin
        if (auth_valid) next_state = DONE;
      end
      DONE: begin
        if ((operation == 0 && ~generate_challenge) | (operation == 1 && ~verify_id))
          next_state = READY;
      end
      default: begin
        next_state = READY;
      end
    endcase
  end

  // update the input data for the auth
  always_ff @(posedge clk) begin
    if (rst || idle_clear) begin
      state <= READY;
      auth_data_in <= '0;
      operation <= '0;
      start <= 0;
      chip_challenge_generated <= 0;
      chip_challenge <= 0;
      id_verified <= 0;
      id_valid <= 0;
    end else begin
      state <= next_state;
      start <= 0;
      if (state == READY & next_state == RUNNING) begin
        if (generate_challenge) begin
          auth_data_in <= card_cipher;
          operation <= '0;
          start <= '1;
        end else if (verify_id) begin
          auth_data_in <= id_cipher;
          operation <= 1;
          start <= '1;
        end
      end
      // process output data from auth
      if (auth_valid) begin
        if (operation == 0) begin
          chip_challenge <= auth_data_out;
          chip_challenge_generated <= 1;
        end else begin
          id_valid <= auth_data_out[0];
          id_verified <= 1;
        end
      end
    end
  end

  auth auth_i (
      .clk(clk),
      .rst(rst),

      .operation_i(operation),

      .start_i(start),
      .data_i (auth_data_in),
      .data_o (auth_data_out),

      .valid_o(auth_valid),

      .eeprom_busy(eeprom_busy),
      .eeprom_done(eeprom_done),
      .eeprom_buffer(eeprom_buffer),
      .eeprom_start(eeprom_start),
      .eeprom_get_key(eeprom_get_key)
  );

endmodule

