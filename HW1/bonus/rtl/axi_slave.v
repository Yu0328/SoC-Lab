// AXI Slave wrapper（UART 暫存器；Mem Ctrl 共用，對應 README 1.5、1.6）
// 寫、讀兩個 FSM 各自獨立，共用同一組暫存器
module axi_slave #(
    parameter NREG = 6,
    parameter RO   = 1       // 唯讀暫存器的 index（STATUS），-1 表示沒有
)(
    input             ACLK, ARESETn,
    // AW
    input             AWVALID,
    output            AWREADY,
    input      [31:0] AWADDR,
    input      [7:0]  AWLEN,
    input      [3:0]  AWID,
    // W
    input             WVALID,
    output            WREADY,
    input      [31:0] WDATA,
    input             WLAST,
    // B
    output            BVALID,
    input             BREADY,
    output     [1:0]  BRESP,
    output reg [3:0]  BID,
    // AR
    input             ARVALID,
    output            ARREADY,
    input      [31:0] ARADDR,
    input      [7:0]  ARLEN,
    input      [3:0]  ARID,
    // R
    output            RVALID,
    input             RREADY,
    output     [31:0] RDATA,
    output     [1:0]  RRESP,
    output            RLAST,
    output reg [3:0]  RID
);
    localparam OKAY = 2'b00, SLVERR = 2'b10;
    reg [31:0] regs [0:NREG-1];

    // ---------- Write：IDLE → DATA → RESP ----------
    localparam W_IDLE = 2'd0, W_DATA = 2'd1, W_RESP = 2'd2;
    reg [1:0]  ws;
    reg [31:0] waddr;    // word index
    reg        werr;

    assign AWREADY = (ws == W_IDLE);
    assign WREADY  = (ws == W_DATA);
    assign BVALID  = (ws == W_RESP);
    assign BRESP   = werr ? SLVERR : OKAY;

    always @(posedge ACLK or negedge ARESETn)
        if (!ARESETn) ws <= W_IDLE;
        else case (ws)
            W_IDLE: if (AWVALID) begin                              // ②；否則 ① 沒有寫請求
                        ws <= W_DATA; waddr <= AWADDR >> 2; BID <= AWID; werr <= 0;
                    end
            W_DATA: if (WVALID) begin                               // ③ 寫入一筆，位址 +4
                        if (waddr < NREG && waddr != RO) regs[waddr] <= WDATA;
                        else werr <= 1;                             // 寫唯讀 STATUS 或位址不存在
                        waddr <= waddr + 1;
                        if (WLAST) ws <= W_RESP;                    // ④
                    end
            W_RESP: if (BREADY) ws <= W_IDLE;                       // ⑥；否則 ⑤ 等 BREADY
        endcase

    // ---------- Read：IDLE → DATA ----------
    localparam R_IDLE = 1'b0, R_DATA = 1'b1;
    reg        rs;
    reg [31:0] raddr;
    reg [7:0]  rlen, rcnt;

    assign ARREADY = (rs == R_IDLE);
    assign RVALID  = (rs == R_DATA);
    assign RDATA   = (raddr < NREG) ? regs[raddr] : 32'h0;
    assign RRESP   = (raddr < NREG) ? OKAY : SLVERR;
    assign RLAST   = (rs == R_DATA) && rcnt == rlen;   // slave 自己數、自己產生 RLAST

    always @(posedge ACLK or negedge ARESETn)
        if (!ARESETn) rs <= R_IDLE;
        else case (rs)
            R_IDLE: if (ARVALID) begin                              // ②；否則 ① 沒有讀請求
                        rs <= R_DATA; raddr <= ARADDR >> 2; rlen <= ARLEN; rcnt <= 0; RID <= ARID;
                    end
            R_DATA: if (RREADY) begin                               // ③ 一筆被接受，位址 +4
                        raddr <= raddr + 1; rcnt <= rcnt + 1;
                        if (RLAST) rs <= R_IDLE;                    // ④
                    end
        endcase
endmodule
