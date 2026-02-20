module layr(
    input logic clk,
    input logic rst,
    input logic card_present_i,


    // mfrc TX interface (to card)
    output  wire         mfrc_tx_valid,
    input wire         mfrc_tx_ready,
    output  wire [  4:0] mfrc_tx_len,
    output  wire [255:0] mfrc_tx_data,
    output  wire [  2:0] mfrc_tx_last_bits,
    output  wire [  1:0] mfrc_tx_kind,

    // mfrc RX interface (from card)
    input wire         mfrc_rx_valid,
    input wire [  4:0] mfrc_rx_len,
    input wire [255:0] mfrc_rx_data,
    input wire [  2:0] mfrc_rx_last_bits,

    output logic status,                // 1 if the request has been successfully authorized.
    output logic status_valid,          // 1 if the status is valid.
    output logic busy,
    input  logic soft_rst,              // synchronous reset: clears busy/state without disturbing async rst tree

    input logic eeprom_busy,
    input logic eeprom_done,
    input logic [127:0] eeprom_buffer,
    output logic eeprom_start,
    output logic eeprom_get_key
);

(* MARK_DEBUG = "TRUE" *) logic anti_coll, select_card, do_rats, select_prog, auth_init, generate_challenge, auth, get_id, verify_id, authed;
(* MARK_DEBUG = "TRUE" *) logic anti_coll_done, card_selected, rats_done, prog_selected, auth_initialized, challenge_generated, id_retrieved;

(* MARK_DEBUG = "TRUE" *) logic id_verified, id_valid;

(* MARK_DEBUG = "TRUE" *) logic [127:0] id_cipher;
logic [127:0] card_cipher;
logic [127:0] chip_cypher, chip_cypher_new;

// DEBUG: last 2 bytes of id_cipher visible in ILA
(* MARK_DEBUG = "TRUE" *) wire [15:0] dbg_id_tail = id_cipher[15:0];
(* MARK_DEBUG = "TRUE" *) wire [15:0] dbg_eeprom_tail = eeprom_buffer[15:0];

// Use a synchronous (clocked) idle clear to reset one-shot flags/state machines
// while idle, without introducing a derived async reset.
logic idle_clear;
assign idle_clear = (~busy & ~card_present_i) | soft_rst;

layr_controller controller(
    .clk(clk),
    .rst(rst),
    .idle_clear(idle_clear),

    .start(card_present_i),
    .anti_coll_done(anti_coll_done),
    .card_selected(card_selected),
    .rats_done(rats_done),
    .select_prog(select_prog),
    .auth_initialized(auth_initialized),
    .challenge_generated(challenge_generated),
    .authed(authed),
    .id_retrieved(id_retrieved),
    .id_verified(id_verified),
    .id_valid(id_valid),

    .anti_coll(anti_coll),
    .select_card(select_card),
    .do_rats(do_rats),
    .prog_selected(prog_selected),
    .auth_init(auth_init),
    .generate_challenge(generate_challenge),
    .auth(auth),
    .get_id(get_id),
    .verify_id(verify_id),

    .status(status),
    .status_valid(status_valid)
);

command_mux mux(
    .clk(clk),
    .rst(rst),
    .idle_clear(idle_clear),

    .select_prog(select_prog),
    .anti_coll(anti_coll),
    .select_card(select_card),
    .do_rats(do_rats),
    .auth_init(auth_init),
    .auth(auth),
    .get_id(get_id),

    .chip_challenge(chip_cypher),

    .mfrc_tx_valid(mfrc_tx_valid),
    .mfrc_tx_ready(mfrc_tx_ready),
    .mfrc_tx_len(mfrc_tx_len),
    .mfrc_tx_data(mfrc_tx_data),
    .mfrc_tx_last_bits(mfrc_tx_last_bits),
    .mfrc_tx_kind(mfrc_tx_kind),

    .mfrc_rx_valid(mfrc_rx_valid),
    .mfrc_rx_len(mfrc_rx_len),
    .mfrc_rx_data(mfrc_rx_data),
    .mfrc_rx_last_bits(mfrc_rx_last_bits),

    .anti_coll_done(anti_coll_done),
    .card_selected(card_selected),
    .rats_done(rats_done),
    .prog_selected(prog_selected),
    .auth_initialized(auth_initialized),
    .card_challenge(card_cipher),

    .authed(authed),

    .id_retrieved(id_retrieved),
    .id_cipher(id_cipher)
);

logic auth_eeprom_start, auth_eeprom_get_key;

layr_auth auth_i(
    .clk(clk),
    .rst(rst),
    .idle_clear(idle_clear),

    .generate_challenge(generate_challenge),
    .verify_id(verify_id),

    .card_cipher(card_cipher),
    .id_cipher(id_cipher),

    .chip_challenge_generated(challenge_generated),
    .chip_challenge(chip_cypher_new),

    .id_verified(id_verified),
    .id_valid(id_valid),

    .eeprom_busy(eeprom_busy),
    .eeprom_done(eeprom_done),
    .eeprom_buffer(eeprom_buffer),
    .eeprom_start(auth_eeprom_start),
    .eeprom_get_key(auth_eeprom_get_key)
);

assign eeprom_start   = auth_eeprom_start;
assign eeprom_get_key = auth_eeprom_get_key;

always_ff @(posedge clk) begin
    if (rst) begin
        busy <= 1'b0;
        chip_cypher <= '0;
    end else if (soft_rst) begin
        busy <= 1'b0;
        chip_cypher <= '0;
    end else begin
        // Synchronous clear while idle (keeps internal state clean between cards)
        if (idle_clear) begin
            chip_cypher <= '0;
        end else if (challenge_generated) begin
            chip_cypher <= chip_cypher_new;
        end

        if (card_present_i) busy <= 1'b1;
        else if (status_valid) busy <= 1'b0;
    end
end


endmodule
