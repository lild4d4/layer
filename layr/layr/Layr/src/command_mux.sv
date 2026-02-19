
/**
  * This module is used to multiplex the various commands onto the command register.
  * Once a command has been tiggered through one of the flags `auth_init` `auth` or `get_id`
  * No new command can be triggered until the a response has been recieved for the old one.
  *
  * Depending on what command has been triggered, the response will be demultiplexed into
  * `id_cipher` and `card_challenge`
  */
module command_mux(
    input logic clk,
    input logic rst,
    input logic idle_clear,

    input logic select_prog,
    input logic auth_init,
    input logic auth,
    input logic get_id,
    input logic [127: 0] chip_challenge,

    // mfrc TX interface (to card)
    output logic         mfrc_tx_valid,
    input  logic         mfrc_tx_ready,
    output logic [  4:0] mfrc_tx_len,
    output logic [255:0] mfrc_tx_data,
    output logic [  2:0] mfrc_tx_last_bits,

    // mfrc RX interface (from card)
    input  logic         mfrc_rx_valid,
    input  logic [  4:0] mfrc_rx_len,
    input  logic [255:0] mfrc_rx_data,
    input  logic [  2:0] mfrc_rx_last_bits,

    output logic prog_selected,
    output logic auth_initialized,
    output logic [127: 0] card_challenge,
    output logic authed,
    output logic id_retrieved,
    output logic [127: 0] id_cipher
);

parameter CLA = 8'h80;

enum {SELECT_PROG, AUTH_INIT, AUTH, GET_ID} active_transmission, next_active_transmission;
enum {READY, SEND, WAIT_RX} state, next_state;


function logic [167:0] cmd;
    input logic [7:0] ins;
    input logic [127:0] payload;

    cmd = {
        CLA,
        ins,
        16'h0000,
        8'h10,      // payload size
        payload
    };
endfunction

always_comb begin
    next_state = state;
    next_active_transmission = active_transmission;
    case(state)
        READY: begin
            if(select_prog)
                next_active_transmission = SELECT_PROG;
            if(auth_init)
                next_active_transmission = AUTH_INIT;
            else if(auth)
                next_active_transmission = AUTH;
            else if(get_id)
                next_active_transmission = GET_ID;
            if (auth_init || auth || get_id || select_prog) begin
                next_state = SEND;
            end
        end
        SEND: begin
            if (mfrc_tx_valid && mfrc_tx_ready) begin
                next_state = WAIT_RX;
            end
        end
        WAIT_RX: begin
            if (mfrc_rx_valid) begin
                next_state = READY;
            end
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
    end else begin
        // Default: hold tx_* stable while valid is asserted.
        if (state == READY && next_state == SEND) begin
            mfrc_tx_valid <= 1'b1;
            mfrc_tx_last_bits <= 3'd0;

            case (next_active_transmission)
                SELECT_PROG:
                    begin
                        // 11 bytes
                        mfrc_tx_len <= 5'd10;
                        mfrc_tx_data <= {
                            8'h00, 8'hA4, 8'h04, 8'h00, 8'h06,
                            8'hF0, 8'h00, 8'h00, 8'h0C, 8'hDC, 8'h00,
                            168'd0
                        };
                    end
                AUTH_INIT:
                    begin
                        // 21 bytes
                        mfrc_tx_len <= 5'd20;
                        mfrc_tx_data <= {cmd(8'h10, 128'd0), 88'd0};
                    end
                AUTH:
                    begin
                        // 21 bytes
                        mfrc_tx_len <= 5'd20;
                        mfrc_tx_data <= {cmd(8'h11, chip_challenge), 88'd0};
                    end
                GET_ID:
                    begin
                        // 21 bytes
                        mfrc_tx_len <= 5'd20;
                        mfrc_tx_data <= {cmd(8'h12, 128'd0), 88'd0};
                    end
                default: begin
                end
            endcase
        end

        if (state == SEND && mfrc_tx_valid && mfrc_tx_ready) begin
            mfrc_tx_valid <= 1'b0;
        end

        if (state == READY) begin
            // If a command is not being sent, keep tx_valid low.
            if (next_state == READY) begin
                mfrc_tx_valid <= 1'b0;
            end
        end
    end
end


// update the state maching
always_ff @(posedge clk) begin
    if (rst || idle_clear) begin
        state <= READY;
        active_transmission <= AUTH_INIT;
    end else begin
        state <= next_state;
        active_transmission <= next_active_transmission;
    end
end

// assign the response to the corresponding output
always_ff @(posedge clk) begin
    if (rst || idle_clear) begin
        auth_initialized <= 0;
        card_challenge <= 0;
        prog_selected <= 0;

        authed <= 0;

        id_retrieved <= 0;
        id_cipher <= 0;
    end else begin
        if (mfrc_rx_valid) begin
            case (active_transmission)
                SELECT_PROG: begin
                    prog_selected <= 1;
                end
                AUTH_INIT: begin
                    card_challenge <= mfrc_rx_data[255:128];
                    auth_initialized <= 1;
                end
                AUTH: begin
                    authed <= 1;
                end
                GET_ID: begin
                    id_retrieved <= 1;
                    id_cipher <= mfrc_rx_data[255:128];
                end
                default: begin
                end
            endcase
        end
    end
end
endmodule
