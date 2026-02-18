
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

    input logic select_prog,
    input logic auth_init,
    input logic auth,
    input logic get_id,
    input logic [127: 0] chip_challenge,

    input logic response_valid,
    input logic [127: 0] response,

    output logic prog_selected,
    output logic auth_initialized,
    output logic [127: 0] card_challenge,
    output logic authed,
    output logic id_retrieved,
    output logic [127: 0] id_cipher,

    output logic [168: 0] command, // 1b cla + 1b ins + 2b instructions (always empty) + 1b lc + 16b daten
    output logic command_valid
);

parameter CLA = 8'h80;

enum {SELECT_PROG, AUTH_INIT, AUTH, GET_ID} active_transmission, next_active_transmission;
enum {READY, EXECUTING, DONE} state, next_state;


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
            if (auth_init || auth || get_id || select_prog)begin
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

// updating the command
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        command <= '0;
        command_valid <= 0;
    end else begin
        command_valid <= next_state != READY;
        if(state == READY & next_state != READY)begin
            case (next_active_transmission)
                SELECT_PROG:
                    command <= {
                        8'h00, 8'hA4, 8'h04, 8'h00, 8'h06,
                        8'hF0, 8'h00, 8'h00, 8'h0C, 8'hDC, 8'h00
                    };
                AUTH_INIT:
                    command <= cmd(8'h10, 0);
                AUTH:
                    command = cmd(8'h11, chip_challenge);
                GET_ID:
                    command = cmd(8'h12, 0);
            endcase;
        end;
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
        prog_selected <= 0;

        authed <= 0;

        id_retrieved <= 0;
        id_cipher <= 0;
    end else begin

        state <= next_state;
        active_transmission <= next_active_transmission;
        if(response_valid) begin
            case(active_transmission)
                SELECT_PROG:
                    prog_selected <= 1;
                AUTH_INIT: begin
                    card_challenge <= response;
                    auth_initialized <= 1;
                end
                AUTH:
                    authed <= 1;
                GET_ID: begin
                    id_retrieved <= 1;
                    id_cipher <= response;
                end
            endcase
        end
    end
end
endmodule
