`ifndef SPI_REG_DEFINES
`define SPI_REG_DEFINES
`define SPI_REG_STATUS 32'h0000_0000
`define SPI_REG_CLKDIV 32'h0000_0004
`define SPI_REG_SPICMD 32'h0000_0008
`define SPI_REG_SPIADR 32'h0000_000C
`define SPI_REG_SPILEN 32'h0000_0010
`define SPI_REG_SPIDUM 32'h0000_0014
`define SPI_REG_TXFIFO 32'h0000_0020
`define SPI_REG_RXFIFO 32'h0000_0040
`endif

module eeprom_spi #(
    parameter [7:0] SPI_CLK_DIV = 8'd2  // spi_clk = clk / (2*(SPI_CLK_DIV+1))
) (
    input wire clk,
    input wire rst_n,

    // ── Simple command interface ────────────────────────────────
    input  wire       cmd_valid,  // Pulse: start a transaction
    input  wire       cmd_write,  // 1 = write byte, 0 = read byte
    input  wire [6:0] cmd_addr,   // EEPROM byte address (7 bits -> 128 bytes)
    input  wire [7:0] cmd_wdata,  // Write data (ignored on read)
    output reg  [7:0] cmd_rdata,  // Read data (valid when cmd_done pulses)
    output reg        cmd_done,   // Pulse: transaction complete
    output wire       cmd_busy,   // High while a transaction is in progress

    // ── Interface to shared axi_lite_master ─────────────────────
    output reg  [31:0] axi_req_addr,
    output reg  [31:0] axi_req_wdata,
    output reg         axi_req_write,
    output reg         axi_req_valid,
    input  wire [31:0] axi_resp_rdata,
    input  wire        axi_resp_done,
    input  wire        axi_busy
);

  // ── FSM states ──────────────────────────────────────────────
  localparam [5:0] S_IDLE = 6'd0,

  // --- One-time SPI clock-divider initialisation -------------
  S_INIT_CLKDIV = 6'd1, S_INIT_WAIT_CLKDIV = 6'd2,

  // --- WREN sequence (write only) ----------------------------
  S_WREN_CMD = 6'd3,  // Write WREN opcode to SPICMD
  S_WREN_WAIT_CMD = 6'd4, S_WREN_LEN = 6'd5,  // Set SPILEN for WREN (cmd=8, no addr/data)
  S_WREN_WAIT_LEN = 6'd6, S_WREN_TRIGGER = 6'd7,  // Trigger WREN transaction
  S_WREN_WAIT_TRIG = 6'd8, S_WREN_POLL = 6'd9,  // Poll STATUS until WREN SPI xfer completes
  S_WREN_WAIT_POLL = 6'd10,

  // --- READ / WRITE sequence ---------------------------------
  S_SET_CMD = 6'd11,  // SPICMD  <- READ or WRITE opcode
  S_WAIT_CMD = 6'd12, S_SET_ADDR = 6'd13,  // SPIADR  <- 7-bit address
  S_WAIT_ADDR = 6'd14, S_SET_LEN = 6'd15,  // SPILEN  <- cmd/addr/data lengths
  S_WAIT_LEN = 6'd16, S_SET_TXDATA = 6'd17,  // TXFIFO  <- write data (writes only)
  S_WAIT_TXDAT = 6'd18, S_TRIGGER = 6'd19,  // STATUS  <- start SPI xfer
  S_WAIT_TRIG = 6'd20, S_POLL_STAT = 6'd21,  // Poll STATUS until SPI idle
  S_WAIT_POLL = 6'd22, S_READ_RX = 6'd23,  // Read RXFIFO (reads only)
  S_WAIT_RX = 6'd24,

  // --- Write-completion polling (RDSR for WIP bit) -----------
  S_WIP_CMD = 6'd25,  // SPICMD  <- RDSR opcode
  S_WIP_WAIT_CMD = 6'd26, S_WIP_LEN = 6'd27,  // SPILEN  <- cmd=8, data=8
  S_WIP_WAIT_LEN = 6'd28, S_WIP_TRIGGER = 6'd29,  // STATUS  <- start RDSR xfer
  S_WIP_WAIT_TRIG = 6'd30, S_WIP_POLL_SPI = 6'd31,  // Poll STATUS until RDSR SPI xfer completes
  S_WIP_WAIT_SPI = 6'd32, S_WIP_READ_RX = 6'd33,  // Read RXFIFO (EEPROM status byte)
  S_WIP_WAIT_RX = 6'd34,

  // --- Completion --------------------------------------------
  S_DONE = 6'd35;

  reg [5:0] state;
  reg       init_done;  // Set after clock divider has been written once

  // Latched command
  reg       lat_write;
  reg [6:0] lat_addr;
  reg [7:0] lat_wdata;

  assign cmd_busy = (state != S_IDLE);

  // AT25010B SPI opcodes
  localparam [7:0] OPCODE_WREN = 8'h06;  // Write Enable
  localparam [7:0] OPCODE_RDSR = 8'h05;  // Read Status Register
  localparam [7:0] OPCODE_READ = 8'h03;  // Read from Memory Array
  localparam [7:0] OPCODE_WRITE = 8'h02;  // Write to Memory Array

  // ────────────────────────────────────────────────────────────
  // Helper task-like pattern: "issue AXI request when bus is free"
  //   Every state that starts an AXI transaction follows:
  //     1. Wait for !axi_busy
  //     2. Drive addr/wdata/write/valid for one cycle
  //     3. Move to a WAIT state that watches axi_resp_done
  //
  //   Every WAIT state does ONLY:
  //     if (axi_resp_done) -> next state
  //   No nested axi_busy checks inside axi_resp_done branches.
  // ────────────────────────────────────────────────────────────

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= S_INIT_CLKDIV;
      init_done     <= 1'b0;
      lat_write     <= 1'b0;
      lat_addr      <= 7'h0;
      lat_wdata     <= 8'h0;
      cmd_done      <= 1'b0;
      cmd_rdata     <= 8'h0;
      axi_req_addr  <= 32'h0;
      axi_req_wdata <= 32'h0;
      axi_req_write <= 1'b0;
      axi_req_valid <= 1'b0;
    end else begin
      // Defaults: single-cycle pulses clear themselves
      cmd_done      <= 1'b0;
      axi_req_valid <= 1'b0;

      case (state)

        // ══════════════════════════════════════════════════════
        // One-time SPI clock divider initialisation
        // ══════════════════════════════════════════════════════
        S_INIT_CLKDIV: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_CLKDIV;
            axi_req_wdata <= {24'h0, SPI_CLK_DIV};
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_INIT_WAIT_CLKDIV;
          end
        end

        S_INIT_WAIT_CLKDIV: begin
          if (axi_resp_done) begin
            init_done <= 1'b1;
            state     <= S_IDLE;
          end
        end

        // ══════════════════════════════════════════════════════
        // IDLE — accept new commands
        // ══════════════════════════════════════════════════════
        S_IDLE: begin
          if (cmd_valid) begin
            lat_write <= cmd_write;
            lat_addr  <= cmd_addr;
            lat_wdata <= cmd_wdata;
            // Writes require WREN first; reads go straight to SET_CMD
            state     <= cmd_write ? S_WREN_CMD : S_SET_CMD;
          end
        end

        // ══════════════════════════════════════════════════════
        // WREN Sequence (required before every WRITE)
        // ══════════════════════════════════════════════════════

        // -- Step 1: Write WREN opcode into SPICMD register --
        S_WREN_CMD: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_SPICMD;
            axi_req_wdata <= {OPCODE_WREN, 24'h0};
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_WREN_WAIT_CMD;
          end
        end

        S_WREN_WAIT_CMD: begin
          if (axi_resp_done) state <= S_WREN_LEN;
        end

        // -- Step 2: Set SPILEN for WREN: cmd=8, addr=0, data=0 --
        S_WREN_LEN: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_SPILEN;
            axi_req_wdata <= {16'd0, 8'd0, 8'd8};  // data[15:0]=0, addr[7:0]=0, cmd[7:0]=8
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_WREN_WAIT_LEN;
          end
        end

        S_WREN_WAIT_LEN: begin
          if (axi_resp_done) state <= S_WREN_TRIGGER;
        end

        // -- Step 3: Trigger the WREN SPI transaction --
        //    Write to STATUS: wr=1, csreg=CS0
        S_WREN_TRIGGER: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_STATUS;
            axi_req_wdata <= {20'h0, 4'b0001, 6'h0, 1'b1, 1'b0};  // wr=1
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_WREN_WAIT_TRIG;
          end
        end

        S_WREN_WAIT_TRIG: begin
          if (axi_resp_done) state <= S_WREN_POLL;
        end

        // -- Step 4: Poll STATUS until SPI controller is idle --
        S_WREN_POLL: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_STATUS;
            axi_req_write <= 1'b0;
            axi_req_valid <= 1'b1;
            state         <= S_WREN_WAIT_POLL;
          end
        end

        S_WREN_WAIT_POLL: begin
          if (axi_resp_done) begin
            // spi_ctrl_status is in bits [6:0] of the status register.
            // Bit 0 of spi_ctrl_status = 1 means the controller is idle
            // (the PULP controller sets status[0] when it returns to IDLE).
            if (axi_resp_rdata[0]) state <= S_SET_CMD;  // WREN done → continue with WRITE
            else state <= S_WREN_POLL;  // not yet, poll again
          end
        end

        // ══════════════════════════════════════════════════════
        // READ or WRITE Sequence
        // ══════════════════════════════════════════════════════

        // -- SPICMD: opcode --
        S_SET_CMD: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_SPICMD;
            axi_req_wdata <= lat_write ? {OPCODE_WRITE, 24'h0} : {OPCODE_READ, 24'h0};
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_WAIT_CMD;
          end
        end

        S_WAIT_CMD: begin
          if (axi_resp_done) state <= S_SET_ADDR;
        end

        // -- SPIADR: 7-bit address, MSB-aligned --
        S_SET_ADDR: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_SPIADR;
            axi_req_wdata <= {1'b0, lat_addr, 24'h0};
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_WAIT_ADDR;
          end
        end

        S_WAIT_ADDR: begin
          if (axi_resp_done) state <= S_SET_LEN;
        end

        // -- SPILEN: cmd=8, addr=8, data=8 --
        S_SET_LEN: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_SPILEN;
            axi_req_wdata <= {16'd8, 8'd8, 8'd8};  // data=8, addr=8, cmd=8
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_WAIT_LEN;
          end
        end

        S_WAIT_LEN: begin
          if (axi_resp_done) state <= lat_write ? S_SET_TXDATA : S_TRIGGER;
        end

        // -- TXFIFO: write data (writes only) --
        S_SET_TXDATA: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_TXFIFO;
            axi_req_wdata <= {lat_wdata, 24'h0};
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_WAIT_TXDAT;
          end
        end

        S_WAIT_TXDAT: begin
          if (axi_resp_done) state <= S_TRIGGER;
        end

        // -- STATUS: trigger the SPI transaction --
        S_TRIGGER: begin
          if (!axi_busy) begin
            axi_req_addr <= `SPI_REG_STATUS;
            if (lat_write) axi_req_wdata <= {20'h0, 4'b0001, 6'h0, 1'b1, 1'b0};  // wr=1, csreg=CS0
            else axi_req_wdata <= {20'h0, 4'b0001, 7'h0, 1'b1};  // rd=1, csreg=CS0
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_WAIT_TRIG;
          end
        end

        S_WAIT_TRIG: begin
          if (axi_resp_done) state <= S_POLL_STAT;
        end

        // -- Poll STATUS until SPI controller is idle --
        S_POLL_STAT: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_STATUS;
            axi_req_write <= 1'b0;
            axi_req_valid <= 1'b1;
            state         <= S_WAIT_POLL;
          end
        end

        S_WAIT_POLL: begin
          if (axi_resp_done) begin
            if (axi_resp_rdata[0]) begin
              // SPI transaction complete
              if (lat_write) state <= S_WIP_CMD;  // poll EEPROM WIP bit
              else state <= S_READ_RX;  // read data from RXFIFO
            end else begin
              state <= S_POLL_STAT;  // not done, poll again
            end
          end
        end

        // -- RXFIFO: read received data (reads only) --
        S_READ_RX: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_RXFIFO;
            axi_req_write <= 1'b0;
            axi_req_valid <= 1'b1;
            state         <= S_WAIT_RX;
          end
        end

        S_WAIT_RX: begin
          if (axi_resp_done) begin
            cmd_rdata <= axi_resp_rdata[7:0];
            state     <= S_DONE;
          end
        end

        // ══════════════════════════════════════════════════════
        // Write-Completion Polling (RDSR → check WIP bit)
        //
        // This is a self-contained mini-sequence:
        //   1. Program SPICMD = RDSR
        //   2. Program SPILEN = cmd 8, data 8
        //   3. Trigger rd=1
        //   4. Poll SPI status until idle
        //   5. Read RXFIFO → if WIP set, loop back to step 1
        // ══════════════════════════════════════════════════════

        // -- Step 1: SPICMD <- RDSR --
        S_WIP_CMD: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_SPICMD;
            axi_req_wdata <= {OPCODE_RDSR, 24'h0};
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_WIP_WAIT_CMD;
          end
        end

        S_WIP_WAIT_CMD: begin
          if (axi_resp_done) state <= S_WIP_LEN;
        end

        // -- Step 2: SPILEN <- cmd=8, addr=0, data=8 --
        S_WIP_LEN: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_SPILEN;
            axi_req_wdata <= {16'd8, 8'd0, 8'd8};  // data=8, addr=0, cmd=8
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_WIP_WAIT_LEN;
          end
        end

        S_WIP_WAIT_LEN: begin
          if (axi_resp_done) state <= S_WIP_TRIGGER;
        end

        // -- Step 3: Trigger RDSR (rd=1) --
        S_WIP_TRIGGER: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_STATUS;
            axi_req_wdata <= {20'h0, 4'b0001, 7'h0, 1'b1};  // rd=1, csreg=CS0
            axi_req_write <= 1'b1;
            axi_req_valid <= 1'b1;
            state         <= S_WIP_WAIT_TRIG;
          end
        end

        S_WIP_WAIT_TRIG: begin
          if (axi_resp_done) state <= S_WIP_POLL_SPI;
        end

        // -- Step 4: Poll SPI status until idle --
        S_WIP_POLL_SPI: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_STATUS;
            axi_req_write <= 1'b0;
            axi_req_valid <= 1'b1;
            state         <= S_WIP_WAIT_SPI;
          end
        end

        S_WIP_WAIT_SPI: begin
          if (axi_resp_done) begin
            if (axi_resp_rdata[0]) state <= S_WIP_READ_RX;  // SPI done, go read the result
            else state <= S_WIP_POLL_SPI;  // not yet
          end
        end

        // -- Step 5: Read RXFIFO and check WIP --
        S_WIP_READ_RX: begin
          if (!axi_busy) begin
            axi_req_addr  <= `SPI_REG_RXFIFO;
            axi_req_write <= 1'b0;
            axi_req_valid <= 1'b1;
            state         <= S_WIP_WAIT_RX;
          end
        end

        S_WIP_WAIT_RX: begin
          if (axi_resp_done) begin
            // EEPROM status register bit 0 = WIP (Write In Progress)
            if (axi_resp_rdata[0]) state <= S_WIP_CMD;  // still writing, poll again
            else state <= S_DONE;  // write complete!
          end
        end

        // ══════════════════════════════════════════════════════
        // DONE — unconditionally pulse cmd_done and return
        // ══════════════════════════════════════════════════════
        S_DONE: begin
          cmd_done <= 1'b1;
          state    <= S_IDLE;
        end

        default: state <= S_IDLE;

      endcase
    end
  end

endmodule




