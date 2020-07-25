/*
    a Test circuit for simple SDRAM controller

    ------------+-----+-----------+------+------------
        wait    |WRITE|    wait   | READ |    wait
    ------------+-----+-----------+------+------------
        1 sec    16clk    1 sec     16clk    (loop)

*/
`include "sdram_con2.sv"
module sdram_test(
    input   logic           CLOCK_50,
    input   logic   [3:0]   KEY,
    inout           [31:0]  DRAM_DQ,
    output  logic           DRAM_CLK,
                            DRAM_CKE,
                            DRAM_WE_N,
                            DRAM_CAS_N,
                            DRAM_RAS_N,
                            DRAM_CS_N,
    output  logic   [1:0]   DRAM_BA,
    output  logic   [12:0]  DRAM_ADDR,
    output  logic   [3:0]   DRAM_DQM,
    output  logic   [17:0]  LEDR
);
    localparam TIMECONST = 'd50000000;
    logic  [22:0]    addr_count;
    logic  [15:0]    c2rdata, r2cdata;
    (*noprune*) logic  [15:0]    r2cdata_cache;
    // 0.. Controller => SDRAM
    // 1.. NOP
    // 2.. SDRAM => Controller
    // 3.. NOP
    (*noprune*) logic            is_read;
    logic  [1:0]     dataflow;
    logic  [1:0]     state;
    logic  [31:0]    timecount;
    
    // BUS <=> SDRAM Controller
    logic           wrreq, rereq;
    (*noprune*) logic           rwdone_w, rw_wait, rw_busy;
    // state( SDRAM Controller <=> SDRAM )
    // 0: bank set
    // 1: read / write
    // 2: done
    assign LEDR[0] = (dataflow == 'd2) ? 'b1 : 'b0;
    assign c2rdata = (dataflow==0) ? addr_count[15:0] : 16'hff00;
    assign DRAM_DQM[3:2] = 'b00;

    always_ff @(posedge CLOCK_50)begin
        if(!KEY[0]) begin
            addr_count <= 'd0;
            dataflow <= 'd0;
            state <= 'd0;
            r2cdata_cache <= 'd0;
            timecount <= 'd0;
        end else begin
            if(dataflow[0]) begin
                timecount <= (timecount == TIMECONST -'d1) ? 0 : timecount + 'd1;
                dataflow <= (timecount == TIMECONST -'d1) ? dataflow + 'd1 : dataflow;
            end else begin
                case(state)
                'd0: begin
                    if(rw_busy) state <= 'd0;
                    else begin
                        wrreq <= (dataflow==0) ? 'b1 : 'b0;
                        rereq <= (dataflow==2) ? 'b1 : 'b0;
                        state <= 'd1;
                    end
                end
                'd1: begin
                    if(rw_busy) {wrreq, rereq} <= 'b00;
                    if(rwdone_w) begin
                        if(dataflow==2) r2cdata_cache <= r2cdata;
                        else r2cdata_cache <= 16'h0000;
                        state <= 'd2; 
                    end
                end
                'd2: begin
                    addr_count <= (addr_count == 15) ? 0 : addr_count+'b1;
                    dataflow <= (addr_count == 15) ? dataflow + 'd1 : dataflow;
                    state <= 'd0;
                end
                endcase
            end    
        end
    end

    sdram_con2 sdram_con2(
        CLOCK_50, CLOCK_50, !KEY[0], 
        addr_count[22:0],
        wrreq, rereq,
        c2rdata, // CONTROLLER to RAM
        r2cdata, // RAM to CONTROLLER
        rwdone_w, rw_wait, rw_busy,
        // SDRAM PIN_ASSIGN
        DRAM_DQ[15:0],
        DRAM_DQM[1], DRAM_DQM[0],
        DRAM_CKE, DRAM_CLK,
        DRAM_WE_N,
        DRAM_CAS_N,
        DRAM_RAS_N,
        DRAM_CS_N,
        DRAM_BA,
        DRAM_ADDR
    );

endmodule    