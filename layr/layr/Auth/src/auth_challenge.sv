module auth_challenge (
    input logic clk,
    input logic rst,
    input logic ready,
    input logic result_valid,
    input logic aes_core_ready,
    input logic [127:0] input_cipher,
    input logic [127:0] aes_core_result,

    output logic valid_o,
    output logic encdec,
    output logic aes_core_init,
    output logic aes_core_next,
    output logic [127:0] block_o,
    output reg [127:0] challenge_o,
    output reg [127:0] session_key_o
);

 typedef enum logic [5:0] {
    IDLE,
    DECRYPT,
    GET_RANDOM,
    ENCRYPT_CHALLENGE
  } state_t;

 (* MARK_DEBUG = "TRUE" *) state_t state, next_state;

  wire random_valid;
  wire random_ready;
  wire aes_handler_valid;
  wire [63:0] random_value;

  logic random_load;
  logic aes_handler_ready;

  reg valid, next_valid;
  reg [63:0] rc, next_rc;
  reg [63:0] rt, next_rt;
  reg [127:0] block, next_block;
  reg [127:0] challenge, next_challenge;
  reg [127:0] session_key, next_session_key;

  assign valid_o = valid;
  assign block_o = next_block;
  assign challenge_o = challenge;
  assign session_key_o = session_key;

  auth_aes_handler u_aes_handler (
      .clk(clk),
      .rst(rst),
      .ready(aes_handler_ready),
      .aes_core_ready(aes_core_ready),
      .result_valid(result_valid),

      .valid_o(aes_handler_valid),
      .aes_core_init(aes_core_init),
      .aes_core_next(aes_core_next)
  );

  auth_random u_random (
      .clk (clk),
      .rst (rst),
      .load(random_load),
      .seed(rc),

      .rnd  (random_value),
      .valid(random_valid),
      .ready(random_ready)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      rc <= 64'd0;
      rt <= 64'd0;
      block <= 128'h0;
      valid <= 1'b0;
      challenge <= 128'h0;
      session_key <= 128'h0;
      state <= IDLE;
    end else begin
      state <= next_state;
      block <= next_block;
      valid <= next_valid;
      rc <= next_rc;
      rt <= next_rt;
      session_key <= next_session_key;
      challenge <= next_challenge;
    end
  end

  always_comb begin
    next_state = state;
    encdec = 1'b0;
    next_valid = 1'b0;
    aes_handler_ready = 1'b0;
    random_load = 1'b0;
    next_block = block;
    next_rc = rc;
    next_rt = rt;
    next_session_key = session_key;
    next_challenge = challenge;

    case (state)
      IDLE: begin
        if (ready) next_state = DECRYPT;
      end

      DECRYPT: begin
        encdec = 1'b0;
        next_block = input_cipher;

        if (!aes_handler_valid) begin
          aes_handler_ready = 1'b1;
        end else if (aes_handler_valid) begin
          next_rc = aes_core_result[127:64];
          next_state = GET_RANDOM;
        end
      end

      GET_RANDOM: begin
        if (random_ready && !random_valid) begin
          random_load = 1'b1;
        end else if (random_valid) begin
          next_rt = random_value;
          // k_eph = rc || rt (raw concatenation, matching Java Card)
          next_session_key = {rc, random_value};
          next_state = ENCRYPT_CHALLENGE;
        end
      end

      ENCRYPT_CHALLENGE: begin
        encdec = 1'b1;
        next_block = {rt, rc};

        if (!aes_handler_valid) begin
          aes_handler_ready = 1'b1;
        end else if (aes_handler_valid) begin
          next_valid = 1'b1;
          next_challenge = aes_core_result;
          next_state = IDLE;
        end
      end

      default: next_state = IDLE;

    endcase
  end

endmodule
