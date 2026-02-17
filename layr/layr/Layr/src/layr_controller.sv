/*
This module is responsible for tracking the overall protocol.
Including the handshakes with the nfc card and the local computations required for the authentication.
*/
module layr_controller(
    input logic clk,
    input logic rst,

    input logic start,

    input logic prog_selected,
    input logic auth_initialized,
    input logic challenge_generated,
    input logic authed,
    input logic id_retrieved,
    input logic id_verified,
    input logic id_valid,

    output logic select_prog,
    output logic auth_init,
    output logic generate_challenge,
    output logic auth,
    output logic get_id,
    output logic verify_id,

    output logic status,
    output logic status_valid
);

enum {READY, SELECT_PROG, AUTH_INIT, GENERATE_CHALLENGE, AUTH, GET_ID, VERIFY_ID, REQUEST_VALIDATED, REQUEST_DENIED} state, next_state;

// Driving the state
always_comb begin
    next_state = state;

    case (state)
        READY: begin
            if(start)
                next_state = SELECT_PROG;
        end
        SELECT_PROG: begin
            if(prog_selected)
                next_state = AUTH_INIT;
        end
        AUTH_INIT: begin
            if(auth_initialized)
                next_state = GENERATE_CHALLENGE;
        end
        GENERATE_CHALLENGE: begin
            if(challenge_generated)
                next_state = AUTH;
        end
        AUTH: begin
            if(authed)
                next_state = GET_ID;
        end
        GET_ID: begin
            if(id_retrieved)
                next_state = VERIFY_ID;
        end
        VERIFY_ID: begin
            if(id_verified) begin
                if(id_valid)
                    next_state = REQUEST_VALIDATED;
                else
                    next_state = REQUEST_DENIED;
            end
        end
    endcase
end

// Advancing the state
always_ff @(posedge clk) begin
    select_prog <= 0;
    auth_init <= 0;
    generate_challenge <= 0;
    auth <= 0;
    get_id <= 0;
    verify_id <= 0;
    status <= 0;
    status_valid <= 0;

    if (rst) begin
        state <= READY;
    end else begin
        state <= next_state;

        case (next_state)
            READY: begin
            end
            SELECT_PROG:
                select_prog <= (state != SELECT_PROG);
            AUTH_INIT:
                auth_init <= (state != AUTH_INIT);
            GENERATE_CHALLENGE:
                generate_challenge <= (state != GENERATE_CHALLENGE);
            AUTH:
                auth <= (state != AUTH);
            GET_ID:
                get_id <= (state != GET_ID);
            VERIFY_ID:
                verify_id <= (state != VERIFY_ID);
            REQUEST_VALIDATED: begin
                status <= 1;
                status_valid <= (state != REQUEST_VALIDATED);
            end
            REQUEST_DENIED: begin
                status <= 0;
                status_valid <= (state != REQUEST_DENIED);
            end
        endcase
    end
end

endmodule
