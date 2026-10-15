// AXI Master wrapper — Read（UART TX DMA，對應 README 1.4）
module axi_master_rd #(parameter ID = 4'd1) (
    input             ACLK, ARESETn,
    // DMA 核心
    input             req,         // FIFO 空間夠放一個 burst
    input      [31:0] src_addr,
    input      [7:0]  len,         // ARLEN（筆數-1）
    input             fifo_ready,  // FIFO 還沒滿
    output            fifo_push,
    output     [31:0] fifo_data,
    output            done,
    output            err,
    // AR
    output reg        ARVALID,
    input             ARREADY,
    output reg [31:0] ARADDR,
    output reg [7:0]  ARLEN,
    output     [3:0]  ARID,
    output     [2:0]  ARSIZE,
    output     [1:0]  ARBURST,
    // R
    input             RVALID,
    output            RREADY,
    input      [31:0] RDATA,
    input      [1:0]  RRESP,
    input             RLAST,
    input      [3:0]  RID
);
    localparam IDLE = 2'd0, AR = 2'd1, R = 2'd2, ERR = 2'd3;
    reg [1:0] state;
    reg       bad;   // 這個 burst 裡有沒有收過非 OKAY

    assign ARID = ID, ARSIZE = 3'b010, ARBURST = 2'b01;   // 32-bit、INCR
    assign RREADY    = (state == R) && fifo_ready;        // FIFO 滿就暫停
    wire   hs        = RVALID && RREADY;
    assign fifo_push = hs && RRESP == 2'b00;
    assign fifo_data = RDATA;
    assign done      = (state == R) && hs && RLAST && !bad && RRESP == 2'b00;
    assign err       = (state == ERR);

    always @(posedge ACLK or negedge ARESETn)
        if (!ARESETn) begin
            state <= IDLE; ARVALID <= 0; bad <= 0;
        end else case (state)
            IDLE: if (req) begin                                    // ①
                      state <= AR; ARVALID <= 1; ARADDR <= src_addr; ARLEN <= len; bad <= 0;
                  end
            AR:   if (ARREADY) begin ARVALID <= 0; state <= R; end  // ③；否則 ② 等 ARREADY
            R:    if (hs) begin                                     // ④ 收資料
                      if (RRESP != 2'b00) bad <= 1;
                      if (RLAST) state <= (bad || RRESP != 2'b00) ? ERR : IDLE;  // ⑥ / ⑤
                  end
            ERR:  state <= IDLE;                                    // ⑦ 發中斷
        endcase
endmodule
