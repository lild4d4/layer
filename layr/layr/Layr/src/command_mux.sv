
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

    input logic auth_init,
    input logic auth,
    input logic get_id,

    input logic [127: 0] chip_challenge,

    input logic response_valid,
    input logic [127: 0] response,

    output logic auth_initialized,
    output logic [127: 0] card_challenge,

    output logic authed,

    output logic id_retrieved,
    output logic [127: 0] id_cipher,

    output logic [168: 0] command, // 1b cla + 1b ins + 2b instructions (always empty) + 1b lc + 16b daten
    output logic command_valid
);

parameter CLA = 8'h80;

enum {AUTH_INIT, AUTH, GET_ID} active_transmission, next_active_transmission;
enum {READY, EXECUTING, DONE} state, next_state;


logic [127:0] payload;
logic [7:0] cla, ins;

always_comb begin
    next_state = state;
    next_active_transmission = active_transmission;
    case(state)
        READY: begin
            if(auth_init)
                next_active_transmission = AUTH_INIT;
            else if(auth)
                next_active_transmission = AUTH;
            else if(get_id)
                next_active_transmission = GET_ID;
            if (auth_init || auth || get_id)begin
                next_state = EXECUTING;
            end
        end
        EXECUTING:begin
            if(response_valid) begin
                next_state = READY;
            end
        end
    endcase
end

always_comb begin
    ins = 8'h00;
    payload = 0;

    case (next_active_transmission)
        AUTH_INIT: begin
            ins = 8'h10;
        end
        AUTH: begin
            ins = 8'h11;
            payload = chip_challenge;
        end
        GET_ID: begin
            ins = 8'h12;
        end
    endcase
end

// updating the command
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        command <= '0;
        command_valid <= 0;
    end else begin
        if(state == READY & next_state != READY)
            command <= {
                CLA,
                ins,
                16'h00, // instructions
                8'h10,  // payload size
                payload
            };
        command_valid <= next_state != READY;
    end
end


// update the state maching
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= READY;
        active_transmission <= AUTH_INIT;
    end else begin
        state <= next_state;
        active_transmission <= next_active_transmission;
    end
end

// assign the response to the corresponding output
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        auth_initialized <= 0;
        card_challenge <= 0;

        authed <= 0;

        id_retrieved <= 0;
        id_cipher <= 0;
    end else begin

        state <= next_state;
        active_transmission <= next_active_transmission;
        if(response_valid) begin
            case(active_transmission)
                AUTH_INIT: begin
                    card_challenge <= response;
                    auth_initialized <= 1;
                end
                AUTH: begin
                    authed <= 1;
                end
                GET_ID: begin
                    id_retrieved <= 1;
                    id_cipher <= response;
                end
            endcase
        end
    end
end
endmodule
