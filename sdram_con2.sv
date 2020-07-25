// a simple SDRAM Controller for DE2-115 (IS42S16320B)
// (No BANK & No burst transfer mode support)
module sdram_con2(
    input   logic           clk, clk_sdrami, rst,
    // BUS <=> SDRAM Controller
    input   logic   [22:0]  addrin,
    input   logic           wrreq, rereq,
    input   logic   [15:0]  datain, // CONTROLLER to RAM
    output  logic   [15:0]  dataout,// RAM to CONTROLLER
    output  logic           rwdone_w, rw_wait, rw_busy,
    // SDRAM Controller <=> SDRAM
    inout           [15:0]  sdram_dqo,
    output  logic           sdram_dqm1, sdram_dqm0,
    output  logic           sdram_cke,
                            sdram_clk,
                            sdram_wen,
                            sdram_casn,
                            sdram_rasn,
                            sdram_csn,
    output  logic   [1:0]   sdram_ba,
    output  logic   [12:0]  sdram_addr
);

    localparam CAS_Latency = 'd2;
    localparam WAITC_CONST = 'd1;
    localparam REFC_CONST  = 'd7;
    localparam REFRESH_COUNT = 'd3000;
    
    logic   [9:0]   rowaddr, coladdr;
    logic   [3:0]   command_wire;
    logic   [15:0]  waitcount, refcount;
    logic   [31:0]  reftimer;

    assign  {sdram_csn, sdram_rasn, sdram_casn, sdram_wen} = command_wire; 
    assign  sdram_dqm0 = 'b0;
    assign  sdram_dqm1 = 'b0;
    assign  sdram_cke  = 'b1;
    assign  sdram_clk  = clk_sdrami;

    //commands
    localparam  COM_ACT = 'b0011;
    localparam  COM_PRE = 'b0010;
    localparam  COM_RED = 'b0101;
    localparam  COM_WRI = 'b0100;
    localparam  COM_NOP = 'b0111;
    localparam  COM_REF = 'b0001;
    localparam  COM_BST = 'b0110;

    // {BA1, BA0, A12, A11, A10, A[9-0]} parameters
    localparam  BA_PALL = 'b00_00_1_0000000000;

    typedef enum logic  [4:0] { 
        prechargeS, idleS, refreshS, RowAS, write1S, write2S, write3S, read1S, read2S, read3S,
        waitNclk
    } state_def;

    state_def state, afstate;
    always_comb begin
            case(afstate)
                idleS:      sdram_dqo <= 16'h0000;
                RowAS:      sdram_dqo <= datain;
                read1S:     sdram_dqo <= (CAS_Latency == 'd2)? 16'hzzzz : 16'h0000;
                read2S:     sdram_dqo <= 16'hzzzz;
                read3S:     sdram_dqo <= 16'hzzzz;
                write1S:    sdram_dqo <= 16'h0000;
                write2S:    sdram_dqo <= 16'h0000;
                write3S:    sdram_dqo <= 16'h0000;
                waitNclk:   sdram_dqo <= 16'h0000;
                refreshS:   sdram_dqo <= 16'h0000;
                default :   sdram_dqo <= 16'h0000;
            endcase
    end

    always_comb begin
            case(afstate)
                idleS:      dataout <= 16'h0000;
                RowAS:      dataout <= datain;
                read1S:     dataout <= (CAS_Latency == 'd2)? sdram_dqo : 16'h0000;
                read2S:     dataout <= sdram_dqo;
                read3S:     dataout <= sdram_dqo;
                write1S:    dataout <= 16'h0000;
                write2S:    dataout <= 16'h0000;
                write3S:    dataout <= 16'h0000;
                waitNclk:   dataout <= 16'h0000;
                refreshS:   dataout <= 16'h0000;
                default :   dataout <= 16'h0000;
            endcase
    end


    always_ff @(posedge clk or posedge rst)begin
        if(rst)begin
            {sdram_ba, sdram_addr} <= BA_PALL;
        end else begin
            case(state)
                idleS:begin
                    if(wrreq | rereq) {sdram_ba, sdram_addr} <= {2'b00, addrin[22:10]};
                end
                RowAS:begin
                    if(wrreq | rereq)        {sdram_ba, sdram_addr} <= {2'b00, 3'b000, addrin[9:0]};
                    else if(reftimer <= 'd10){sdram_ba, sdram_addr} <= {2'b00, 3'b000, 10'b0};
                    else                     {sdram_ba, sdram_addr} <= {2'b00, 3'b000, 10'b0};
                end
                read1S: {sdram_ba, sdram_addr} <= {2'b00, 13'b0};
                read2S: {sdram_ba, sdram_addr} <= {2'b00, 13'b0};
                read3S: {sdram_ba, sdram_addr} <= {2'b00, 13'b0};
                write1S:{sdram_ba, sdram_addr} <= {2'b00, 13'b0};
                write2S:{sdram_ba, sdram_addr} <= {2'b00, 13'b0};
                write3S:{sdram_ba, sdram_addr} <= {2'b00, 13'b0};
                waitNclk:{sdram_ba, sdram_addr}<= (waitcount == WAITC_CONST) ? {2'b00, 3'b001, 10'b0} : {2'b00, 13'b0};
                refreshS:{sdram_ba, sdram_addr}<= {2'b00, 13'b0};
                default:{sdram_ba, sdram_addr} <= {2'b00, 13'b0};
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst)begin
        if(rst) begin
            waitcount <= WAITC_CONST;
            refcount  <= REFC_CONST;
            command_wire <= COM_PRE;
            state <= waitNclk;
            rw_busy <= 'b1;
        end else begin
            if(state == refreshS) reftimer <= REFRESH_COUNT;
            else reftimer <= reftimer - 'd1;
            afstate = state;
            case(state)
                prechargeS : begin
                    command_wire <= COM_NOP;
                    state <= idleS;
                    rw_busy <= 'b0;
                end
                idleS : begin
                    if(wrreq | rereq)begin
                        command_wire <= COM_ACT;
                        state <= RowAS;
                        rw_busy <= 'b1;
                    end else if(reftimer <= 'd10)begin
                        command_wire <= COM_REF;
                        state <= refreshS;
                        rw_busy <= 'b1;
                    end else begin
                        command_wire <= COM_PRE; // Action: nop
                        state <= idleS;
                        rw_busy <= 'b0;
                    end
                end
                RowAS:begin
                    if(wrreq) begin
                        command_wire <= COM_WRI;
                        rw_wait <= 'b1;
                        state <= write1S;
                    end else begin
                        command_wire <= COM_RED;
                        rw_wait <= 'b1;
                        state <= read1S;
                    //end else begin
                    //    command_wire <= COM_PRE;
                    //    state <= prechargeS;
                    end
                end
                read1S:begin
                    command_wire <= COM_BST;
                    //rw_wait <= 'b0;
                    state <= read2S;
                end
                read2S:begin
                    command_wire <= COM_NOP;
                    rw_wait <=  (CAS_Latency == 'd2)  ? 'b0 : 'b1;
                    rwdone_w <= (CAS_Latency == 'd2)  ? 'b1 : 'b0;
                    state <= (CAS_Latency == 'd2) ? waitNclk : read3S;
                end
                read3S:begin
                    command_wire <= COM_NOP;
                    rw_wait <= 'b0;
                    rwdone_w <= 'b1;
                    state <= waitNclk;
                end
                write1S:begin
                    command_wire <= COM_BST;
                    //rw_wait <= 'b0;
                    state <= write2S;
                end
                write2S:begin
                    command_wire <= COM_NOP;
                    rw_wait  <= (CAS_Latency == 'd2) ? 'b0 : 'b1;
                    rwdone_w <= (CAS_Latency == 'd2) ? 'b1 : 'b0;
                    state <= (CAS_Latency == 'd2) ? waitNclk : write3S;                    
                end
                write3S:begin
                    command_wire <= COM_NOP;
                    rw_wait <= 'b0;
                    rwdone_w <= 'b1;
                    state <= waitNclk;
                end
                waitNclk: begin
                    command_wire <= (waitcount == WAITC_CONST) ? COM_PRE : COM_NOP;
                    rwdone_w <= (waitcount == WAITC_CONST) ? 'b0 : rwdone_w;
                    waitcount <= (waitcount == 'd0) ? WAITC_CONST : waitcount - 'd1;
                    state <= (waitcount == 'd0) ?  prechargeS : waitNclk;
                    rw_busy <= (waitcount == 'd0) ? 'b0 : 'b1;
                end
                refreshS: begin
                    command_wire <= COM_NOP;
                    refcount <= (refcount == 'd0) ? REFC_CONST : refcount - 'd1;
                    state    <= (refcount == 'd0) ? idleS : refreshS;
                    rw_busy  <= (refcount == 'd0) ? 'b0 : 'b1;
                end
                default : state <= idleS;
            endcase
        end
    end
    
endmodule