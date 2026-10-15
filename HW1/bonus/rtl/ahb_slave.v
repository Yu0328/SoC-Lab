// AHB Slave wrapper（對應 README 1.2）
// UART 暫存器：NREG=6、RO=1（STATUS 唯讀）
// Mem Ctrl 共用：NREG 調大、RO=-1、WAIT 設成 DDR 的等待拍數
module ahb_slave #(
    parameter NREG = 6,
    parameter RO   = 1,      // 唯讀暫存器的 index，-1 表示沒有
    parameter WAIT = 0       // 每筆 data phase 插幾拍 HREADYOUT=0
)(
    input             HCLK, HRESETn,
    input             HSEL,
    input      [31:0] HADDR,
    input      [1:0]  HTRANS,
    input             HWRITE,
    input      [31:0] HWDATA,
    input             HREADY,      // 匯流排上的 HREADY（上一筆是否結束）
    output reg [31:0] HRDATA,
    output reg        HREADYOUT,
    output reg        HRESP        // 0=OKAY 1=ERROR
);
    localparam IDLE = 2'd0, DATA = 2'd1, ERR1 = 2'd2, ERR2 = 2'd3;
    reg [1:0]  state;
    reg [31:0] regs [0:NREG-1];
    reg [31:0] addr_q;
    reg        write_q;
    reg [3:0]  wcnt;

    // address phase：被選到且是 NONSEQ/SEQ
    wire       valid = HSEL && HREADY && HTRANS[1];
    wire [31:0] idx  = HADDR >> 2;
    wire       legal = (idx < NREG) && !(HWRITE && idx == RO);
    wire       done  = (wcnt == WAIT);   // 這筆 data phase 是否結束

    always @(posedge HCLK or negedge HRESETn)
        if (!HRESETn) begin
            state <= IDLE; wcnt <= 0;
        end else case (state)
            IDLE: if (valid) begin state <= legal ? DATA : ERR1; wcnt <= 0; end  // ② ⑤；否則 ① 留在 IDLE
            DATA: if (!done)       wcnt  <= wcnt + 1;                 // ③ 等待
                  else if (valid)  begin state <= legal ? DATA : ERR1; wcnt <= 0; end // ③ burst 下一拍 / ⑥
                  else             state <= IDLE;                     // ④ 傳輸結束
            ERR1: state <= ERR2;                                      // ⑦
            ERR2: state <= IDLE;                                      // ⑧
        endcase

    // 記下 address phase，data phase 用
    always @(posedge HCLK)
        if (valid && (state == IDLE || (state == DATA && done))) begin
            addr_q  <= idx;
            write_q <= HWRITE;
        end

    // data phase 結束那拍寫入
    always @(posedge HCLK)
        if (state == DATA && done && write_q) regs[addr_q] <= HWDATA;

    always @* begin
        HREADYOUT = 1'b1; HRESP = 1'b0; HRDATA = 32'h0;
        case (state)
            DATA: begin HREADYOUT = done; HRDATA = regs[addr_q]; end
            ERR1: begin HREADYOUT = 1'b0; HRESP = 1'b1; end
            ERR2: begin HREADYOUT = 1'b1; HRESP = 1'b1; end
        endcase
    end
endmodule
