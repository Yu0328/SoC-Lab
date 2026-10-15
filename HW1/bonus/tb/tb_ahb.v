// AHB 系統：CPU（master 0，tb task）+ UART DMA（master 1，ahb_master）
//          UART 暫存器（ahb_slave @0x4000_0000）+ Mem Ctrl（ahb_slave @0x0000_0000，每拍 1 個 wait）
`timescale 1ns/1ps
module tb_ahb;
    reg clk = 0, rstn = 0;
    always #5 clk = ~clk;

    // ---------- master 0：CPU ----------
    reg        c_busreq = 0, c_write = 0;
    reg [1:0]  c_trans = 0;
    reg [31:0] c_addr = 0, c_wdata = 0;

    // ---------- master 1：DMA ----------
    reg        d_req = 0;
    reg [31:0] d_src = 0;
    reg [4:0]  d_beats = 16;
    wire       d_busreq, d_push, d_done, d_err;
    wire [31:0] d_haddr, d_fdata;
    wire [1:0]  d_trans;
    wire [2:0]  d_burst, d_size;
    wire        d_write;

    // ---------- 匯流排 ----------
    wire [31:0] HADDR, HWDATA, HRDATA;
    wire [1:0]  HTRANS;
    wire        HWRITE, HREADY, HRESP;
    reg  [1:0]  grant = 2'b01;      // one-hot：bit0 CPU、bit1 DMA
    reg         hmaster = 0;        // address phase 的 owner
    reg         hmaster_d = 0;      // data phase 的 owner

    // Arbiter：owner 還在要就繼續給，否則給另一個在要的，都沒有就給 CPU（default master）
    // ponytail: 兩個 master 寫死，要更多 master 再改成 round-robin
    always @(posedge clk) if (HREADY) begin
        if (grant[1] ? d_busreq : c_busreq) grant <= grant;
        else if (d_busreq) grant <= 2'b10;
        else               grant <= 2'b01;
        hmaster   <= grant[1];
        hmaster_d <= hmaster;
    end

    assign HADDR  = hmaster ? d_haddr : c_addr;
    assign HTRANS = hmaster ? d_trans : c_trans;
    assign HWRITE = hmaster ? d_write : c_write;
    assign HWDATA = hmaster_d ? 32'h0 : c_wdata;   // DMA 只讀

    // Decoder：HADDR[30] 選 UART
    wire sel_uart = HADDR[30];
    reg  dsel_uart = 0;
    always @(posedge clk) if (HREADY) dsel_uart <= sel_uart;
    wire [31:0] u_rdata, m_rdata;
    wire u_ready, m_ready, u_resp, m_resp;
    assign HREADY = dsel_uart ? u_ready : m_ready;
    assign HRDATA = dsel_uart ? u_rdata : m_rdata;
    assign HRESP  = dsel_uart ? u_resp  : m_resp;

    ahb_master dma (
        .HCLK(clk), .HRESETn(rstn),
        .req(d_req), .src_addr(d_src), .beats(d_beats),
        .fifo_push(d_push), .fifo_data(d_fdata), .done(d_done), .err(d_err),
        .HBUSREQ(d_busreq), .HGRANT(grant[1]), .HADDR(d_haddr), .HTRANS(d_trans),
        .HBURST(d_burst), .HSIZE(d_size), .HWRITE(d_write),
        .HRDATA(HRDATA), .HREADY(HREADY), .HRESP(HRESP));

    ahb_slave #(.NREG(6), .RO(1), .WAIT(0)) uart (
        .HCLK(clk), .HRESETn(rstn), .HSEL(sel_uart), .HADDR({4'b0, HADDR[27:0]}),
        .HTRANS(HTRANS), .HWRITE(HWRITE), .HWDATA(HWDATA), .HREADY(HREADY),
        .HRDATA(u_rdata), .HREADYOUT(u_ready), .HRESP(u_resp));

    ahb_slave #(.NREG(64), .RO(-1), .WAIT(1)) mem (
        .HCLK(clk), .HRESETn(rstn), .HSEL(!sel_uart), .HADDR(HADDR),
        .HTRANS(HTRANS), .HWRITE(HWRITE), .HWDATA(HWDATA), .HREADY(HREADY),
        .HRDATA(m_rdata), .HREADYOUT(m_ready), .HRESP(m_resp));

    // ---------- TX FIFO（只拿來比對） ----------
    reg [31:0] fifo [0:31];
    integer    nfifo = 0, nerr = 0, nfail = 0, i;
    always @(posedge clk) begin
        if (d_push) begin fifo[nfifo] <= d_fdata; nfifo <= nfifo + 1; end
        if (d_err)  nerr <= nerr + 1;
    end

    // ---------- CPU：single transfer ----------
    reg [31:0] rdata;
    reg        resp;
    task cpu_xfer(input w, input [31:0] a, input [31:0] d);
        begin
            c_busreq <= 1;
            @(posedge clk); while (!(grant[0] && HREADY)) @(posedge clk);
            c_trans <= 2'b10; c_addr <= a; c_write <= w;               // address phase
            @(posedge clk); while (!HREADY) @(posedge clk);
            c_trans <= 2'b00; c_wdata <= d; c_busreq <= 0;             // data phase
            @(posedge clk); while (!HREADY) @(posedge clk);
            rdata = HRDATA; resp = HRESP;
        end
    endtask

    task check(input cond, input [8*96-1:0] msg);
        begin
            if (cond) $display("PASS  %0s", msg);
            else begin $display("FAIL  %0s", msg); nfail = nfail + 1; end
        end
    endtask

    initial begin
        $dumpfile("tb_ahb.vcd"); $dumpvars(0, tb_ahb);
        for (i = 0; i < 64; i = i + 1) mem.regs[i] = 32'hD000_0000 + i;
        repeat (3) @(posedge clk); rstn <= 1;

        // 段 1：驅動程式設定 UART；同時 DMA 也要匯流排 → 要等仲裁
        fork
            begin
                cpu_xfer(1, 32'h4000_0008, 32'd434);     // BAUD_DIV
                cpu_xfer(1, 32'h4000_000C, 32'h0000_0000); // TX_ADDR
                cpu_xfer(1, 32'h4000_0010, 32'd64);      // TX_LEN
                cpu_xfer(1, 32'h4000_0000, 32'h3);       // CTRL.EN|START
            end
            begin
                @(posedge clk); d_src <= 0; d_beats <= 16; d_req <= 1;
                @(posedge clk); d_req <= 0;
                @(posedge clk); while (!d_done) @(posedge clk);
            end
        join
        cpu_xfer(0, 32'h4000_0008, 0);
        check(rdata == 434 && !resp, "UART BAUD_DIV write then read back = 434");

        // 段 2：DMA INCR16 讀到的資料要等於 DDR 內容
        @(posedge clk);
        check(nfifo == 16, "DMA INCR16 got 16 beats");
        begin : cmp
            reg ok; ok = 1;
            for (i = 0; i < 16; i = i + 1) if (fifo[i] !== 32'hD000_0000 + i) ok = 0;
            check(ok, "FIFO data == DDR[0..15]");
        end

        // 寫唯讀 STATUS → 兩拍 ERROR
        cpu_xfer(1, 32'h4000_0004, 32'hFFFF);
        check(resp == 1, "write read-only STATUS -> HRESP=ERROR");
        cpu_xfer(1, 32'h4000_0040, 32'h1);
        check(resp == 1, "write undefined address -> HRESP=ERROR");

        // 單拍 burst（NONSEQ → LAST）
        nfifo = 0;
        d_src <= 32'h20; d_beats <= 1; d_req <= 1; @(posedge clk); d_req <= 0;
        @(posedge clk); while (!d_done) @(posedge clk); repeat (2) @(posedge clk);
        check(nfifo == 1 && fifo[0] == 32'hD000_0008, "DMA SINGLE read DDR[8]");

        // burst 跨出 DDR 範圍 → SEQ 收到 ERROR，中止 burst
        nfifo = 0;
        d_src <= 32'hF0; d_beats <= 16; d_req <= 1; @(posedge clk); d_req <= 0;
        repeat (40) @(posedge clk);
        check(nerr == 1, "DMA burst out of range -> ERR once");
        check(nfifo == 4, "4 beats before ERROR, rest cancelled");
        check(dma.state == 0, "DMA back to IDLE");

        if (nfail == 0) $display("ALL PASS"); else $display("%0d FAIL", nfail);
        $finish;
    end

    initial begin #20000 $display("TIMEOUT"); $finish; end
endmodule
