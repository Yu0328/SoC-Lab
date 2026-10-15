// AXI Master wrapper — Write（UART RX 寫回 DDR，對應 README 1.3）
module axi_master_wr #(parameter ID = 4'd1) (
    input             ACLK, ARESETn,
    // DMA 核心
    input             req,         // FIFO 累積到一個 burst
    input      [31:0] dst_addr,
    input      [7:0]  len,         // AWLEN（筆數-1）
    input      [31:0] fifo_data,   // FIFO 最前面那筆
    output            fifo_pop,
    output            done,
    output            err,
    // AW
    output reg        AWVALID,
    input             AWREADY,
    output reg [31:0] AWADDR,
    output reg [7:0]  AWLEN,
    output     [3:0]  AWID,
    output     [2:0]  AWSIZE,
    output     [1:0]  AWBURST,
    // W
    output            WVALID,
    input             WREADY,
    output     [31:0] WDATA,
    output     [3:0]  WSTRB,
    output            WLAST,
    // B
    input             BVALID,
    output            BREADY,
    input      [1:0]  BRESP,
    input      [3:0]  BID
);
    localparam IDLE = 3'd0, AW = 3'd1, W = 3'd2, B = 3'd3, ERR = 3'd4;
    reg [2:0] state;
    reg [7:0] cnt;

    assign AWID = ID, AWSIZE = 3'b010, AWBURST = 2'b01;
    assign WVALID   = (state == W);
    assign WDATA    = fifo_data;
    assign WSTRB    = 4'hF;
    assign WLAST    = (state == W) && cnt == AWLEN;
    assign fifo_pop = WVALID && WREADY;
    assign BREADY   = (state == B);
    assign done     = (state == B) && BVALID && BRESP == 2'b00;
    assign err      = (state == ERR);

    always @(posedge ACLK or negedge ARESETn)
        if (!ARESETn) begin
            state <= IDLE; AWVALID <= 0; cnt <= 0;
        end else case (state)
            IDLE: if (req) begin                                    // ①
                      state <= AW; AWVALID <= 1; AWADDR <= dst_addr; AWLEN <= len; cnt <= 0;
                  end
            AW:   if (AWREADY) begin AWVALID <= 0; state <= W; end  // ③；否則 ② 等 AWREADY
            W:    if (WREADY) begin                                 // ④ 一拍一筆
                      cnt <= cnt + 1;
                      if (WLAST) state <= B;                        // ⑤
                  end
            B:    if (BVALID) state <= (BRESP == 2'b00) ? IDLE : ERR;  // ⑦ / ⑧；否則 ⑥ 等 BVALID
            ERR:  state <= IDLE;                                    // ⑨
        endcase
endmodule
