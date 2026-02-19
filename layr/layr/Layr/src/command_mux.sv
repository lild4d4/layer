/**
  * This module multiplexes NFC protocol commands onto the MFRC TX stream.
  * It also demultiplexes card responses into protocol status flags and data.
  */
module command_mux (
    input logic clk,
    input logic rst,
    input logic idle_clear,

    input logic anti_coll,
    input logic select_card,
    input logic do_rats,
    input logic select_prog,
    input logic auth_init,
    input logic auth,
    input logic get_id,
    input logic [127:0] chip_challenge,

    // mfrc TX interface (to card)
    output logic         mfrc_tx_valid,
    input  logic         mfrc_tx_ready,
    output logic [  4:0] mfrc_tx_len,
    output logic [255:0] mfrc_tx_data,
    output logic [  2:0] mfrc_tx_last_bits,
    output logic [  1:0] mfrc_tx_kind,

    // mfrc RX interface (from card)
    input logic         mfrc_rx_valid,
    input logic [  4:0] mfrc_rx_len,
    input logic [255:0] mfrc_rx_data,
    input logic [  2:0] mfrc_rx_last_bits,

    output logic anti_coll_done,
    output logic card_selected,
    output logic rats_done,
    output logic prog_selected,
    output logic auth_initialized,
    output logic [127:0] card_challenge,
    output logic authed,
    output logic id_retrieved,
    output logic [127:0] id_cipher
);

  parameter CLA = 8'h80;

  localparam [1:0] TXK_NORMAL = 2'd0;
  localparam [1:0] TXK_RATS = 2'd1;

  typedef enum logic [5:0] {
    ANTI_COLL,
    SELECT_CARD,
    RATS,
    SELECT_PROG,
    AUTH_INIT,
    AUTH,
    GET_ID
  } active_transmission_t;

  (* MARK_DEBUG = "TRUE" *) active_transmission_t active_transmission, next_active_transmission;

  typedef enum logic [5:0] {
    READY,
    SEND,
    WAIT_RX
  } state_t;

  state_t state, next_state;

  logic [ 7:0] i_block_pcb;
  logic [39:0] uid_cl1;

  function logic [167:0] cmd;
    input logic [7:0] ins;
    input logic [127:0] payload;

    cmd = {CLA, ins, 16'h0000, 8'h10, payload};
  endfunction

  function automatic logic [15:0] crc_a_7;
    input logic [55:0] data_bytes;
    logic [15:0] crc;
    logic [7:0] byte_v;
    integer i;
    integer j;
    begin
      crc = 16'h6363;
      for (i = 0; i < 7; i = i + 1) begin
        byte_v = data_bytes[55-i*8-:8];
        crc = crc ^ byte_v;
        for (j = 0; j < 8; j = j + 1) begin
          if (crc[0]) crc = (crc >> 1) ^ 16'h8408;
          else crc = crc >> 1;
        end
      end
      // byte order matches Arduino: CRC_L then CRC_H
      crc_a_7 = {crc[7:0], crc[15:8]};
    end
  endfunction

  wire [55:0] select_payload_7 = {8'h93, 8'h70, uid_cl1};
  wire [15:0] select_crc = crc_a_7(select_payload_7);

  always_comb begin
    next_state = state;
    next_active_transmission = active_transmission;
    case (state)
      READY: begin
        if (anti_coll) next_active_transmission = ANTI_COLL;
        else if (select_card) next_active_transmission = SELECT_CARD;
        else if (do_rats) next_active_transmission = RATS;
        else if (select_prog) next_active_transmission = SELECT_PROG;
        else if (auth_init) next_active_transmission = AUTH_INIT;
        else if (auth) next_active_transmission = AUTH;
        else if (get_id) next_active_transmission = GET_ID;

        if (anti_coll || select_card || do_rats || select_prog || auth_init || auth || get_id)
          next_state = SEND;
      end
      SEND: begin
        if (mfrc_tx_valid && mfrc_tx_ready) next_state = WAIT_RX;
      end
      WAIT_RX: begin
        if (mfrc_rx_valid) next_state = READY;
      end
    endcase
  end

  // TX datapath
  always_ff @(posedge clk) begin
    if (rst || idle_clear) begin
      mfrc_tx_valid <= 1'b0;
      mfrc_tx_len <= '0;
      mfrc_tx_data <= '0;
      mfrc_tx_last_bits <= 3'd0;
      mfrc_tx_kind <= TXK_NORMAL;
      i_block_pcb <= 8'h02;
    end else begin
      if (state == READY && next_state == SEND) begin
        mfrc_tx_valid <= 1'b1;
        mfrc_tx_last_bits <= 3'd0;
        mfrc_tx_kind <= TXK_NORMAL;

        case (next_active_transmission)
          ANTI_COLL: begin
            mfrc_tx_len  <= 5'd1;
            mfrc_tx_data <= {8'h93, 8'h20, 240'd0};
            i_block_pcb  <= 8'h02;
          end
          SELECT_CARD: begin
            mfrc_tx_len <= 5'd8;
            mfrc_tx_data <= {
              8'h93,
              8'h70,
              uid_cl1[39:32],
              uid_cl1[31:24],
              uid_cl1[23:16],
              uid_cl1[15:8],
              uid_cl1[7:0],
              select_crc[15:8],
              select_crc[7:0],
              184'd0
            };
          end
          RATS: begin
            mfrc_tx_len  <= 5'd1;
            mfrc_tx_data <= {8'hE0, 8'h50, 240'd0};
            mfrc_tx_kind <= TXK_RATS;
          end
          SELECT_PROG: begin
            mfrc_tx_len <= 5'd11;
            mfrc_tx_data <= {
              i_block_pcb,
              8'h00,
              8'hA4,
              8'h04,
              8'h00,
              8'h06,
              8'hF0,
              8'h00,
              8'h00,
              8'h0C,
              8'hDC,
              8'h00,
              160'd0
            };
          end
          AUTH_INIT: begin
            mfrc_tx_len  <= 5'd21;
            mfrc_tx_data <= {i_block_pcb, cmd(8'h10, 128'd0), 80'd0};
          end
          AUTH: begin
            mfrc_tx_len  <= 5'd21;
            mfrc_tx_data <= {i_block_pcb, cmd(8'h11, chip_challenge), 80'd0};
          end
          GET_ID: begin
            mfrc_tx_len  <= 5'd5;
            mfrc_tx_data <= {i_block_pcb, CLA, 8'h12, 8'h00, 8'h00, 8'h00, 208'd0};
          end
          default: begin
          end
        endcase
      end

      if (state == SEND && mfrc_tx_valid && mfrc_tx_ready) mfrc_tx_valid <= 1'b0;

      if (state == READY && next_state == READY) mfrc_tx_valid <= 1'b0;

      if (state == WAIT_RX && mfrc_rx_valid) begin
        case (active_transmission)
          SELECT_PROG, AUTH_INIT, AUTH, GET_ID: begin
            i_block_pcb <= i_block_pcb ^ 8'h01;
          end
          default: begin
          end
        endcase
      end
    end
  end

  // update the state machine
  always_ff @(posedge clk) begin
    if (rst || idle_clear) begin
      state <= READY;
      active_transmission <= ANTI_COLL;
    end else begin
      state <= next_state;
      active_transmission <= next_active_transmission;
    end
  end

  // assign the response to the corresponding output
  always_ff @(posedge clk) begin
    if (rst || idle_clear) begin
      anti_coll_done <= 0;
      card_selected <= 0;
      rats_done <= 0;
      auth_initialized <= 0;
      card_challenge <= 0;
      prog_selected <= 0;
      authed <= 0;
      id_retrieved <= 0;
      id_cipher <= 0;
      uid_cl1 <= 0;
    end else begin
      if (state == WAIT_RX && mfrc_rx_valid) begin
        case (active_transmission)
          ANTI_COLL: begin
            if (mfrc_rx_len >= 5'd4) begin
              uid_cl1 <= mfrc_rx_data[255-:40];
              anti_coll_done <= 1;
            end
          end
          SELECT_CARD: begin
            card_selected <= 1;
          end
          RATS: begin
            rats_done <= 1;
          end
          SELECT_PROG: begin
            prog_selected <= 1;
          end
          AUTH_INIT: begin
            card_challenge   <= mfrc_rx_data[247-:128];
            auth_initialized <= 1;
          end
          AUTH: begin
            authed <= 1;
          end
          GET_ID: begin
            id_retrieved <= 1;
            id_cipher <= mfrc_rx_data[247-:128];
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule
