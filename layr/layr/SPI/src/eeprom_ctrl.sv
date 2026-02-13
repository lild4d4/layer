module eeprom_ctrl (
    input wire clk,
    input wire rst,

    // interface with auth
    input  wire start,
    output wire busy,
    output wire done,

    input wire get_key,  // get_key = 1, get_id = 0
    output wire [127:0] buffer,

    // eeprom spi interface
    output wire eeprom_start,
    output wire [6:0] eeprom_addr,  // read / write address in eeprom
    input reg [127:0] eeprom_rdata,  // data read from an address
    input reg eeprom_busy,
    input reg eeprom_done
);
  typedef enum logic [5:0] {
    S_IDLE,
    S_GET_KEY,
    S_GET_ID,
    S_WAIT_EEPROM
  } state_t;

  assign busy = (state != S_IDLE);

  localparam logic [6:0] AddrKeyA = 7'h00;
  localparam logic [6:0] AddrKeyB = 7'h10;
  localparam logic [6:0] AddrKeyC = 7'h20;
  localparam logic [6:0] AddrKeyD = 7'h30;

  localparam logic [6:0] AddrIdA = 7'h40;
  localparam logic [6:0] AddrIdB = 7'h50;
  localparam logic [6:0] AddrIdC = 7'h60;
  localparam logic [6:0] AddrIdD = 7'h70;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_IDLE;
      busy <= 1'b0;
      done <= 1'b0;
      buffer <= 128'b0;
      eeprom_start <= 1'b0;
      eeprom_addr <= 7'h00;
    end else begin
      // auto clear
      done <= 1'b0;
      eeprom_start <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            state <= get_key ? S_GET_KEY : S_GET_ID;
          end
        end

        S_GET_KEY: begin
          // hard coded to key A for now
          eeprom_addr <= AddrKeyA;
          eeprom_start <= 1'b1;

          state <= S_WAIT_EEPROM;
        end


        S_GET_ID: begin
          // hard coded to id A for now
          eeprom_addr <= AddrIdA;
          eeprom_start <= 1'b1;

          state <= S_WAIT_EEPROM;
        end


        S_WAIT_EEPROM: begin
          if (eeprom_done) begin
            buffer <= eeprom_rdata;

            done   <= 1'b1;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
