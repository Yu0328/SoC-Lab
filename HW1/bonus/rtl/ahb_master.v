// AHB Master wrapper（UART DMA，對應 README 1.1）
// 從 DDR 讀 beats 筆資料（INCR16 時 beats=16），每筆用 fifo_push 丟進 TX FIFO
module ahb_master (
    input             HCLK, HRESETn,
    // DMA 核心
    input             req,         // 有資料要搬、FIFO 有空間
    input      [31:0] src_addr,
    input      [4:0]  beats,       // 1~16
    output reg        fifo_push,
    output reg [31:0] fifo_data,
    output reg        done,        // 一個 burst 完成（pulse）
    output reg        err,         // STATUS.ERR（pulse，接中斷）
    // AHB
    output reg        HBUSREQ,
    input             HGRANT,
    output reg [31:0] HADDR,
    output reg [1:0]  HTRANS,
    output     [2:0]  HBURST,
    output     [2:0]  HSIZE,
    output            HWRITE,
    input      [31:0] HRDATA,
    input             HREADY,
    input             HRESP
);
    localparam IDLE = 3'd0, REQ = 3'd1, NONSEQ = 3'd2, SEQ = 3'd3, LAST = 3'd4, ERR = 3'd5;
    localparam T_IDLE = 2'b00, T_NONSEQ = 2'b10, T_SEQ = 2'b11;

    reg [2:0]  state;
    reg [31:0] addr;
    reg [4:0]  len, cnt;   // cnt：已被接受的位址數

    assign HBURST = (len == 16) ? 3'b111 : (len == 1) ? 3'b000 : 3'b001;  // INCR16 / SINGLE / INCR
    assign HSIZE  = 3'b010;  // 32-bit
    assign HWRITE = 1'b0;    // UART TX 的 DMA 只讀 DDR

    always @(posedge HCLK or negedge HRESETn)
        if (!HRESETn) begin
            state <= IDLE; cnt <= 0; addr <= 0; len <= 0;
        end else case (state)
            IDLE:   if (req) begin                                  // ①
                        state <= REQ; addr <= src_addr; len <= beats; cnt <= 0;
                    end
            REQ:    if (HGRANT && HREADY) state <= NONSEQ;          // ③；否則 ② 等仲裁
            NONSEQ: if (HREADY) begin
                        addr <= addr + 4; cnt <= 1;
                        state <= (len == 1) ? LAST : SEQ;           // ⑥ / ④
                    end
            SEQ:    if (HRESP) state <= ERR;                        // ⑨ ERROR 第 1 拍
                    else if (HREADY) begin
                        addr <= addr + 4; cnt <= cnt + 1;
                        if (cnt == len - 1) state <= LAST;          // ⑦；否則 ⑤
                    end
            LAST:   if (HRESP) state <= ERR;
                    else if (HREADY) state <= IDLE;                 // ⑧
            ERR:    state <= IDLE;                                  // ERROR 第 2 拍結束
        endcase

    always @* begin
        HTRANS = T_IDLE; HADDR = addr;
        // 送到倒數第二個位址時放掉 HBUSREQ
        HBUSREQ = (state == REQ) || ((state == NONSEQ || state == SEQ) && cnt + 2 < len);
        case (state)
            NONSEQ: HTRANS = T_NONSEQ;
            SEQ:    HTRANS = T_SEQ;
        endcase
        // SEQ／LAST 那拍的 data phase 是上一個位址的資料
        fifo_push = (state == SEQ || state == LAST) && HREADY && !HRESP;
        fifo_data = HRDATA;
        done      = (state == LAST) && HREADY && !HRESP;
        err       = (state == ERR);
    end
endmodule
