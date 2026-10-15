// AXI 系統：CPU（tb task）→ UART 暫存器（axi_slave）
//          UART DMA（axi_master_rd / axi_master_wr）→ Mem Ctrl（axi_slave，當 DDR）
// ponytail: 沒有 Interconnect，每個 master 直接接一個 slave；要多對多再加 crossbar
`timescale 1ns/1ps
module tb_axi;
    reg clk = 0, rstn = 0;
    always #5 clk = ~clk;
    integer nfail = 0, i;

    task check(input cond, input [8*64-1:0] msg);
        begin
            if (cond) $display("PASS  %0s", msg);
            else begin $display("FAIL  %0s", msg); nfail = nfail + 1; end
        end
    endtask

    // ================= CPU → UART =================
    reg         c_awvalid = 0, c_wvalid = 0, c_wlast = 0, c_bready = 0, c_arvalid = 0, c_rready = 0;
    reg  [31:0] c_awaddr = 0, c_wdata = 0, c_araddr = 0;
    reg  [7:0]  c_arlen = 0;
    wire        u_awready, u_wready, u_bvalid, u_arready, u_rvalid, u_rlast;
    wire [1:0]  u_bresp, u_rresp;
    wire [3:0]  u_bid, u_rid;
    wire [31:0] u_rdata;

    axi_slave #(.NREG(6), .RO(1)) uart (
        .ACLK(clk), .ARESETn(rstn),
        .AWVALID(c_awvalid), .AWREADY(u_awready), .AWADDR(c_awaddr), .AWLEN(8'd0), .AWID(4'd0),
        .WVALID(c_wvalid), .WREADY(u_wready), .WDATA(c_wdata), .WLAST(c_wlast),
        .BVALID(u_bvalid), .BREADY(c_bready), .BRESP(u_bresp), .BID(u_bid),
        .ARVALID(c_arvalid), .ARREADY(u_arready), .ARADDR(c_araddr), .ARLEN(c_arlen), .ARID(4'd0),
        .RVALID(u_rvalid), .RREADY(c_rready), .RDATA(u_rdata), .RRESP(u_rresp), .RLAST(u_rlast), .RID(u_rid));

    // AW 和 W 同時送，等 B
    reg [1:0] bresp;
    task cpu_write(input [31:0] a, input [31:0] d);
        reg aw_done, w_done;
        begin
            c_awvalid <= 1; c_awaddr <= a; c_wvalid <= 1; c_wdata <= d; c_wlast <= 1;
            aw_done = 0; w_done = 0;
            while (!(aw_done && w_done)) begin
                @(posedge clk);
                if (c_awvalid && u_awready) begin c_awvalid <= 0; aw_done = 1; end
                if (c_wvalid && u_wready)   begin c_wvalid  <= 0; w_done  = 1; end
            end
            c_bready <= 1;
            @(posedge clk); while (!u_bvalid) @(posedge clk);
            bresp = u_bresp; c_bready <= 0;
        end
    endtask

    // burst 讀 n+1 筆，存進 rbuf
    reg [31:0] rbuf [0:15];
    integer    nr;
    reg        rlast_ok;
    task cpu_read(input [31:0] a, input [7:0] n);
        begin
            c_arvalid <= 1; c_araddr <= a; c_arlen <= n;
            @(posedge clk); while (!u_arready) @(posedge clk);
            c_arvalid <= 0; c_rready <= 1; nr = 0; rlast_ok = 1;
            forever begin
                @(posedge clk);
                if (u_rvalid) begin
                    rbuf[nr] = u_rdata;
                    if (u_rlast !== (nr == n)) rlast_ok = 0;
                    nr = nr + 1;
                    if (u_rlast) disable cpu_read;
                end
            end
        end
    endtask

    // ================= DMA → DDR =================
    // AR / R
    reg         rd_req = 0, fifo_ready = 1;
    reg  [31:0] rd_src = 0;
    reg  [7:0]  rd_len = 15;
    wire        rd_push, rd_done, rd_err;
    wire [31:0] rd_fdata;
    wire        ARVALID, ARREADY, RVALID, RREADY, RLAST;
    wire [31:0] ARADDR, RDATA;
    wire [7:0]  ARLEN;
    wire [3:0]  ARID, RID;
    wire [2:0]  ARSIZE;
    wire [1:0]  ARBURST, RRESP;
    // AW / W / B
    reg         wr_req = 0;
    reg  [31:0] wr_dst = 0, wr_fdata = 32'hA000_0000;
    reg  [7:0]  wr_len = 7;
    wire        wr_pop, wr_done, wr_err;
    wire        AWVALID, AWREADY, WVALID, WREADY, WLAST, BVALID, BREADY;
    wire [31:0] AWADDR, WDATA;
    wire [7:0]  AWLEN;
    wire [3:0]  AWID, BID, WSTRB;
    wire [2:0]  AWSIZE;
    wire [1:0]  AWBURST, BRESP;

    axi_master_rd dma_rd (
        .ACLK(clk), .ARESETn(rstn),
        .req(rd_req), .src_addr(rd_src), .len(rd_len), .fifo_ready(fifo_ready),
        .fifo_push(rd_push), .fifo_data(rd_fdata), .done(rd_done), .err(rd_err),
        .ARVALID(ARVALID), .ARREADY(ARREADY), .ARADDR(ARADDR), .ARLEN(ARLEN), .ARID(ARID),
        .ARSIZE(ARSIZE), .ARBURST(ARBURST),
        .RVALID(RVALID), .RREADY(RREADY), .RDATA(RDATA), .RRESP(RRESP), .RLAST(RLAST), .RID(RID));

    axi_master_wr dma_wr (
        .ACLK(clk), .ARESETn(rstn),
        .req(wr_req), .dst_addr(wr_dst), .len(wr_len), .fifo_data(wr_fdata),
        .fifo_pop(wr_pop), .done(wr_done), .err(wr_err),
        .AWVALID(AWVALID), .AWREADY(AWREADY), .AWADDR(AWADDR), .AWLEN(AWLEN), .AWID(AWID),
        .AWSIZE(AWSIZE), .AWBURST(AWBURST),
        .WVALID(WVALID), .WREADY(WREADY), .WDATA(WDATA), .WSTRB(WSTRB), .WLAST(WLAST),
        .BVALID(BVALID), .BREADY(BREADY), .BRESP(BRESP), .BID(BID));

    axi_slave #(.NREG(64), .RO(-1)) mem (
        .ACLK(clk), .ARESETn(rstn),
        .AWVALID(AWVALID), .AWREADY(AWREADY), .AWADDR(AWADDR), .AWLEN(AWLEN), .AWID(AWID),
        .WVALID(WVALID), .WREADY(WREADY), .WDATA(WDATA), .WLAST(WLAST),
        .BVALID(BVALID), .BREADY(BREADY), .BRESP(BRESP), .BID(BID),
        .ARVALID(ARVALID), .ARREADY(ARREADY), .ARADDR(ARADDR), .ARLEN(ARLEN), .ARID(ARID),
        .RVALID(RVALID), .RREADY(RREADY), .RDATA(RDATA), .RRESP(RRESP), .RLAST(RLAST), .RID(RID));

    // TX FIFO 比對、RX FIFO 產生資料
    reg [31:0] fifo [0:31];
    integer    nfifo = 0, nerr = 0;
    always @(posedge clk) begin
        if (rd_push) begin fifo[nfifo] <= rd_fdata; nfifo <= nfifo + 1; end
        if (wr_pop)  wr_fdata <= wr_fdata + 1;
        if (rd_err || wr_err) nerr <= nerr + 1;
    end
    // FIFO 每 4 拍滿一次 → RREADY 拉低，R 通道暫停
    always @(posedge clk) fifo_ready <= ($time / 10) % 4 != 3;

    initial begin
        $dumpfile("tb_axi.vcd"); $dumpvars(0, tb_axi);
        for (i = 0; i < 64; i = i + 1) mem.regs[i] = 32'hD000_0000 + i;
        uart.regs[1] = 32'h0000_0100;   // STATUS 初值
        repeat (3) @(posedge clk); rstn <= 1;

        // 段 1：驅動程式設定 UART（每個暫存器走 AW、W、B）
        cpu_write(32'h08, 32'd434);   check(bresp == 0, "write BAUD_DIV -> OKAY");
        cpu_write(32'h0C, 32'h0);     check(bresp == 0, "write TX_ADDR -> OKAY");
        cpu_write(32'h10, 32'd64);    check(bresp == 0, "write TX_LEN -> OKAY");
        cpu_write(32'h00, 32'h3);     check(bresp == 0, "write CTRL -> OKAY");
        cpu_write(32'h04, 32'hFFFF);  check(bresp == 2'b10, "write read-only STATUS -> SLVERR");
        check(uart.regs[1] == 32'h100, "STATUS not modified");

        cpu_read(32'h00, 8'd4);       // 一個 burst 讀 CTRL..TX_LEN
        check(nr == 5 && rlast_ok, "UART read burst ARLEN=4: 5 beats, RLAST on last");
        check(rbuf[0] == 3 && rbuf[1] == 32'h100 && rbuf[2] == 434 && rbuf[3] == 0 && rbuf[4] == 64,
              "UART read data == written values");

        // 段 2：DMA 讀 DDR 16 筆，FIFO 偶爾滿（RREADY=0）
        rd_src <= 0; rd_len <= 15; rd_req <= 1; @(posedge clk); rd_req <= 0;
        @(posedge clk); while (!rd_done) @(posedge clk); repeat (2) @(posedge clk);
        check(nfifo == 16, "DMA read burst ARLEN=15: 16 beats");
        begin : cmp
            reg ok; ok = 1;
            for (i = 0; i < 16; i = i + 1) if (fifo[i] !== 32'hD000_0000 + i) ok = 0;
            check(ok, "FIFO data == DDR[0..15] (with RREADY stalls)");
        end

        // RX 寫回 DDR：8 筆寫到 0x80
        wr_dst <= 32'h80; wr_len <= 7; wr_req <= 1; @(posedge clk); wr_req <= 0;
        @(posedge clk); while (!wr_done) @(posedge clk); repeat (2) @(posedge clk);
        begin : cmpw
            reg ok; ok = 1;
            for (i = 0; i < 8; i = i + 1) if (mem.regs[32 + i] !== 32'hA000_0000 + i) ok = 0;
            check(ok, "DMA write burst AWLEN=7: DDR[32..39] == RX data");
        end

        // 讀超出 DDR → RRESP=SLVERR → ERR
        rd_src <= 32'hF8; rd_len <= 3; rd_req <= 1; @(posedge clk); rd_req <= 0;
        repeat (20) @(posedge clk);
        check(nerr == 1, "DMA read out of range -> ERR once");
        check(dma_rd.state == 0, "DMA read back to IDLE");

        // 寫超出 DDR → BRESP=SLVERR → ERR
        wr_dst <= 32'hF8; wr_len <= 3; wr_req <= 1; @(posedge clk); wr_req <= 0;
        repeat (20) @(posedge clk);
        check(nerr == 2, "DMA write out of range -> ERR once");
        check(dma_wr.state == 0, "DMA write back to IDLE");

        if (nfail == 0) $display("ALL PASS"); else $display("%0d FAIL", nfail);
        $finish;
    end

    initial begin #20000 $display("TIMEOUT"); $finish; end
endmodule
