"""把 sim/*.vcd 畫成波形圖 wave/*.png（先跑 run.sh）。"""
import pathlib
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = pathlib.Path(__file__).parent
CLK = 10  # ns

STATES = {
    "dma.state": ["IDLE", "REQ", "NONSEQ", "SEQ", "LAST", "ERR"],
    "mem.state": ["IDLE", "DATA", "ERR1", "ERR2"],
    "dma_rd.state": ["IDLE", "AR", "R", "ERR"],
    "dma_wr.state": ["IDLE", "AW", "W", "B", "ERR"],
    "mem.ws": ["IDLE", "DATA", "RESP"],
    "mem.rs": ["IDLE", "DATA"],
    "HTRANS": ["IDLE", "BUSY", "NONSEQ", "SEQ"],
}


def load(path):
    """回傳 ({訊號名: [(ns, 值字串), ...]}, {訊號名: 位元寬})，名稱是 tb 底下的相對路徑，如 dma.state。"""
    scope, ids, waves, width, t = [], {}, {}, {}, 0
    for line in path.read_text().splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] == "$scope":
            scope.append(p[2])
        elif p[0] == "$upscope":
            scope.pop()
        elif p[0] == "$var":
            name = ".".join(scope[1:] + [p[4]])
            ids.setdefault(p[3], []).append(name)
            width[name] = int(p[2])
        elif p[0].startswith("#"):
            t = int(p[0][1:]) // 1000
        elif p[0][0] in "b" and len(p) == 2:
            for n in ids.get(p[1], []):
                waves.setdefault(n, []).append((t, p[0][1:]))
        elif p[0][0] in "01xz" and p[0][1:] in ids:
            for n in ids[p[0][1:]]:
                waves.setdefault(n, []).append((t, p[0][0]))
    return waves, width


def fmt(name, v):
    if "x" in v or "z" in v:
        return "x"
    n = int(v, 2)
    if name in STATES:
        return STATES[name][n]
    return f"{n:X}" if n > 9 else str(n)


def plot(vcd, sigs, t0, t1, title, out):
    waves, width = vcd
    fig, ax = plt.subplots(figsize=(max(8, (t1 - t0) / CLK * 0.42), 0.55 * len(sigs) + 0.9))
    for row, (name, label) in enumerate(sigs):
        y = len(sigs) - 1 - row
        ev = waves[name]
        cur = [v for t, v in ev if t <= t0][-1:] or ["x"]
        pts = [(t0, cur[0])]
        for t, v in ev:
            if t0 < t < t1 and v != pts[-1][1]:
                pts.append((t, v))
        pts.append((t1, None))
        bus = width[name] > 1
        for (ta, va), (tb, _) in zip(pts, pts[1:]):
            if bus:
                ax.fill_between([ta, tb], y + 0.1, y + 0.75, color="#e9f6ef", ec="#2e9a6b", lw=1)
                if tb - ta >= CLK:
                    ax.text((ta + tb) / 2, y + 0.42, fmt(name, va), ha="center", va="center", fontsize=7)
            else:
                lvl = y + (0.75 if va == "1" else 0.1)
                ax.plot([ta, tb], [lvl, lvl], color="#23774f", lw=1.4)
        # 1-bit 的垂直邊
        if not bus:
            for tb, _ in pts[1:-1]:
                ax.plot([tb, tb], [y + 0.1, y + 0.75], color="#23774f", lw=1.4)
    for t in range(t0 - t0 % CLK + 5, t1, CLK):   # 上升緣（clk 在 5、15、25... 上升）
        ax.axvline(t, color="#dddddd", lw=0.6, zorder=0)
    ax.set_yticks([len(sigs) - 1 - i + 0.42 for i in range(len(sigs))])
    ax.set_yticklabels([lab for _, lab in sigs], fontsize=8)
    ax.set_xlim(t0, t1)
    ax.set_ylim(-0.2, len(sigs))
    ax.set_xlabel("ns", fontsize=8)
    ax.tick_params(axis="x", labelsize=7)
    ax.set_title(title, fontsize=10, loc="left")
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    fig.tight_layout()
    fig.savefig(out, dpi=130)
    plt.close(fig)
    print(out)


if __name__ == "__main__":
    out = HERE / "wave"
    out.mkdir(exist_ok=True)
    ahb = load(HERE / "sim/tb_ahb.vcd")
    axi = load(HERE / "sim/tb_axi.vcd")

    ahb_sigs = [("clk", "HCLK"), ("d_busreq", "HBUSREQ1 (DMA)"), ("grant", "HGRANT[1:0]"),
                ("dma.state", "DMA FSM"), ("HTRANS", "HTRANS"), ("HADDR", "HADDR"),
                ("HREADY", "HREADY"), ("HRESP", "HRESP"), ("HRDATA", "HRDATA"),
                ("mem.state", "Mem Ctrl FSM"), ("d_push", "fifo_push")]
    plot(ahb, ahb_sigs, 30, 420, "AHB: arbitration + INCR16 read, Mem Ctrl 1 wait state per beat",
         out / "ahb_incr16.png")
    plot(ahb, ahb_sigs + [("d_err", "err (IRQ)")], 660, 820,
         "AHB: burst crosses DDR end -> two-cycle ERROR, master cancels with HTRANS=IDLE",
         out / "ahb_error.png")

    plot(axi, [("clk", "ACLK"), ("dma_rd.state", "DMA read FSM"), ("ARVALID", "ARVALID"),
               ("ARREADY", "ARREADY"), ("ARADDR", "ARADDR"), ("ARLEN", "ARLEN"),
               ("mem.rs", "Mem Ctrl read FSM"), ("RVALID", "RVALID"), ("RREADY", "RREADY (FIFO)"),
               ("RDATA", "RDATA"), ("RLAST", "RLAST"), ("RRESP", "RRESP")],
         230, 480, "AXI: AR then 16-beat R burst, RREADY drops when FIFO is full", out / "axi_read.png")
    plot(axi, [("clk", "ACLK"), ("dma_wr.state", "DMA write FSM"), ("AWVALID", "AWVALID"),
               ("AWREADY", "AWREADY"), ("AWADDR", "AWADDR"), ("mem.ws", "Mem Ctrl write FSM"),
               ("WVALID", "WVALID"), ("WREADY", "WREADY"), ("WDATA", "WDATA"), ("WLAST", "WLAST"),
               ("BVALID", "BVALID"), ("BREADY", "BREADY"), ("BRESP", "BRESP")],
         480, 610, "AXI: AW -> 8-beat W burst -> B response", out / "axi_write.png")
