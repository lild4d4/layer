module auth_aes_handler (
    input logic clk,
    input logic rst,
    input logic ready,
    input logic aes_core_ready,
    input logic result_valid,

    output logic valid_o,
    output logic aes_core_init,
    output logic aes_core_next
);

  typedef enum logic [5:0] {
    IDLE,
    WRITE_INIT,
    READ_READY,
    WRITE_BLOCK,
    READ_VALID
  } state_t;
  state_t state, next_state;

  logic valid;

  assign valid_o = valid;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  always_comb begin
    next_state = state;
    aes_core_init = 1'b0;
    aes_core_next = 1'b0;
    valid = 1'b0;

    case (state)
      IDLE: begin
        if (ready) begin
          next_state = WRITE_INIT;
        end
      end

      WRITE_INIT: begin
        aes_core_init = 1'b1;
        next_state = READ_READY;
      end

      READ_READY: begin
        if (aes_core_ready) begin
          next_state = WRITE_BLOCK;
        end
      end

      WRITE_BLOCK: begin
        aes_core_next = 1'b1;
        next_state = READ_VALID;
      end

      READ_VALID: begin
        if (result_valid) begin
          valid = 1'b1;
          next_state = IDLE;
        end
      end

      default: next_state = IDLE;
    endcase
  end

endmodule
