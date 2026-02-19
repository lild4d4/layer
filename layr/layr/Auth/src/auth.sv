module auth (
    //--------------------------------------
    // = Required =
    //--------------------------------------
    input wire clk,
    input wire rst,

    //--------------------------------------
    // = Control =
    //
    // operation_i:
    //   0 = Generate challenge response
    //   1 = Verify ID
    //
    // start_i:
    //   0 = Do nothing
    //   1 = Run selected operation with
    //       data_i as input. Has to stay set
    //       until valid_o becomes true.
    //--------------------------------------
    input logic operation_i,
    input logic start_i,

    //--------------------------------------
    // = Data bus =
    //
    // data_i:
    //   Input data for any selected operation.
    //
    // data_o:
    //   Output data for any selected operation.
    //
    // valid_o:
    //   0 = the operation is still running
    //   1 = the operation is done, data
    //       can be read from data_o
    //--------------------------------------
    input reg [127:0] data_i,
    output logic [127:0] data_o,
    output logic valid_o,

    //--------------------------------------
    // = EEPROM interface =
    //
    // This section should not be touched.
    //--------------------------------------
    input logic eeprom_busy,
    input logic eeprom_done,
    input logic [127:0] eeprom_buffer,
    output logic eeprom_start,
    output logic eeprom_get_key
);


  typedef enum logic [5:0] {
    GET_KEY,
    WAIT_FOR_KEY,
    IDLE,
    GENERATE_CHALLENGE,
    VERIFY_ID
  } state_t;

  state_t state, next_state;

  wire encdec;
  wire verify_encdec;
  wire chal_encdec;
  wire aes_core_ready;
  wire aes_core_init;
  wire aes_core_next;
  wire chal_aes_core_init;
  wire chal_aes_core_next;
  wire verify_aes_core_init;
  wire verify_aes_core_next;
  wire result_valid;
  wire auth_challenge_valid;
  wire auth_challenge_encdec;
  wire auth_verify_id_valid;
  wire verify_eeprom_start;
  wire verify_eeprom_get_key;
  wire [127:0] key;
  wire [127:0] block, chal_block, verify_block;
  wire [127:0] result;
  wire [127:0] challenge_o;
  wire [127:0] session_key_o;

  logic auth_eeprom_start;
  logic auth_eeprom_get_key;
  logic generate_challenge_ready;
  logic verify_id_ready;

  reg id_valid;
  reg valid, next_valid;
  reg [127:0] output_data, next_output_data;
  reg [127:0] input_key, next_input_key;
  reg [127:0] session_key, next_session_key;

  aes_core u_aes_core (
      .clk(clk),
      .reset_n(!rst),
      .encdec(encdec),
      .init(aes_core_init),
      .next(aes_core_next),
      .key({key, 128'h0}),
      .keylen(1'b0),
      .block(block),

      .result(result),
      .ready(aes_core_ready),
      .result_valid(result_valid)
  );

  auth_challenge u_auth_challenge (
      .clk(clk),
      .rst(rst),
      .ready(generate_challenge_ready),
      .result_valid(result_valid),
      .input_cipher(data_i),
      .aes_core_result(result),

      .block_o(chal_block),
      .encdec(chal_encdec),
      .aes_core_init(chal_aes_core_init),
      .aes_core_next(chal_aes_core_next),
      .aes_core_ready(aes_core_ready),
      .valid_o(auth_challenge_valid),
      .challenge_o(challenge_o),
      .session_key_o(session_key_o)
  );

  auth_verify_id u_auth_verify_id (
      .clk(clk),
      .rst(rst),
      .ready(verify_id_ready),
      .result_valid(result_valid),
      .aes_core_ready(aes_core_ready),
      .input_cipher(data_i),
      .aes_core_result(result),

      .valid(auth_verify_id_valid),
      .encdec(verify_encdec),
      .aes_core_init(verify_aes_core_init),
      .aes_core_next(verify_aes_core_next),
      .block_o(verify_block),
      .id_valid(id_valid),

      .eeprom_busy(eeprom_busy),
      .eeprom_done(eeprom_done),
      .eeprom_buffer(eeprom_buffer),
      .eeprom_start(verify_eeprom_start),
      .eeprom_get_key(verify_eeprom_get_key)
  );

  assign valid_o = valid;
  assign data_o = output_data;

  // Demux for AES core.
  assign aes_core_init = (state == VERIFY_ID) ? verify_aes_core_init : chal_aes_core_init;
  assign aes_core_next = (state == VERIFY_ID) ? verify_aes_core_next : chal_aes_core_next;
  assign encdec = (state == VERIFY_ID) ? verify_encdec : chal_encdec;
  assign key = (state == VERIFY_ID) ? session_key : input_key;
  assign block = (state == VERIFY_ID) ? verify_block : chal_block;

  // Demux for EEPROM
  assign eeprom_start = (state == VERIFY_ID) ? verify_eeprom_start : auth_eeprom_start;
  assign eeprom_get_key = (state == VERIFY_ID) ? verify_eeprom_get_key : auth_eeprom_get_key;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      input_key <= 128'h0;
      session_key <= 128'h0;
      valid <= 1'b0;
      output_data <= 128'h0;
      input_key <= 128'h0;
      session_key <= 128'h0;
      state <= GET_KEY;
    end else begin
      state <= next_state;
      valid <= next_valid;
      output_data <= next_output_data;
      input_key <= next_input_key;
      session_key <= next_session_key;
    end
  end

  always_comb begin
    next_state = state;
    auth_eeprom_start = 1'b0;
    auth_eeprom_get_key = 1'b0;
    next_valid = 1'b0;
    next_state = state;
    generate_challenge_ready = 1'b0;
    verify_id_ready = 1'b0;
    next_output_data = output_data;
    next_input_key = input_key;
    next_session_key = session_key;

    case (state)
      GET_KEY: begin
        if (!eeprom_busy) begin
          auth_eeprom_get_key = 1'b1;
          auth_eeprom_start = 1'b1;
          next_state = WAIT_FOR_KEY;
        end
      end

      WAIT_FOR_KEY: begin
        if (eeprom_done) begin
          next_input_key = eeprom_buffer;
          next_state = IDLE;
        end
      end

      IDLE: begin
        if (start_i) begin
          case (operation_i)
            1'b0: next_state = GENERATE_CHALLENGE;
            1'b1: next_state = VERIFY_ID;
            default: next_state = IDLE;
          endcase
        end
      end

      GENERATE_CHALLENGE: begin

        if (!auth_challenge_valid) begin
          generate_challenge_ready = 1'b1;
        end else if (auth_challenge_valid) begin
          next_session_key = session_key_o;
          next_output_data = challenge_o;
          next_valid = 1'b1;
          next_state = IDLE;
        end
      end

      VERIFY_ID: begin
        if (!auth_verify_id_valid) begin
          verify_id_ready = 1'b1;
        end else if (auth_verify_id_valid) begin
          next_output_data = {127'h0, id_valid};
          next_valid = 1'b1;
          next_state = IDLE;
        end
      end

      default: next_state = IDLE;
    endcase
  end

endmodule
