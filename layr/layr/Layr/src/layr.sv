module layr(
    input logic clk,
    input logic rst,
    input logic card_present_i,

    input logic response_valid,
    input logic [127: 0] response,

    output logic command_valid,
    output logic [168: 0] command,

    output logic status,                // 1 if the request has been successfully authorized.
    output logic status_valid,          // 1 if the status is valid.

    input logic eeprom_busy,
    input logic eeprom_done,
    input logic [127:0] eeprom_buffer,
    output logic eeprom_start,
    output logic eeprom_get_key
);

logic busy;
logic select_prog, auth_init, generate_challenge, auth, get_id, verify_id, authed;
logic prog_selected, auth_initialized, challenge_generated, authenticated, id_retrieved, id_verified, id_valid;

logic [127:0] id_cipher;
logic [127:0] card_cipher;
logic [127:0] chip_cypher, chip_cypher_new;

logic rst_;
assign rst_ = rst | (~busy & ~card_present_i);

layr_controller controller(
    .clk(clk),
    .rst(rst_),

    .start(card_present_i),
    .select_prog(select_prog),
    .auth_initialized(auth_initialized),
    .challenge_generated(challenge_generated),
    .authed(authed),
    .id_retrieved(id_retrieved),
    .id_verified(id_verified),
    .id_valid(id_valid),

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
    .rst(rst_),

    .select_prog(select_prog),
    .auth_init(auth_init),
    .auth(auth),
    .get_id(get_id),

    .chip_challenge(chip_cypher),

    .response_valid(response_valid),
    .response(response),

    .prog_selected(prog_selected),
    .auth_initialized(auth_initialized),
    .card_challenge(card_cipher),

    .authed(authed),

    .id_retrieved(id_retrieved),
    .id_cipher(id_cipher),

    .command(command),
    .command_valid(command_valid)
);

layr_auth auth_i(
    .clk(clk),
    .rst(rst_),

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
    .eeprom_start(eeprom_start),
    .eeprom_get_key(eeprom_get_key)
);

always_ff @(posedge clk) begin
    if(rst) busy <= 0;
    else begin
        if (card_present_i) busy <= 1;
        else if (status_valid) busy <= 0;
    end;

    if(rst_) chip_cypher <= 0;
    else if (challenge_generated) chip_cypher <= chip_cypher_new;
end


endmodule