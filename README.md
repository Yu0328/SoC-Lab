# SoC-Lab

國立高雄科技大學 115-1「系統晶片設計實習」作業。

## 作業

| 作業 | 內容 
|---|---|
| [HW1](HW1/README.md) | AHB／AXI Master、Slave wrapper FSM；CPU、Mem Ctrl、UART（內含 DMA）的 Message Sequence Chart；Bonus：FSM 的 RTL 與模擬 
| [HW2](HW2/README.md) | Zynq-7020 手冊中的 BSP／ISR 章節；GIC 中斷暫存器（IRQ #、pending、mask）；EGO-XZ7 上用 AXI GPIO + 按鈕中斷寫 Driver 和 ISR（跑馬燈暫停／繼續） 

## 目錄

```
SoC-Lab/
├── HW1/
│   ├── README.md        作業說明：FSM、MSC、Bonus 摘要
│   ├── fsm/             六張 wrapper FSM
│   ├── msc/             AHB、AXI 兩張 Message Sequence Chart
│   └── bonus/           RTL、testbench、模擬波形
│       ├── rtl/         ahb_master／ahb_slave／axi_master_rd／axi_master_wr／axi_slave
│       ├── tb/          tb_ahb.v、tb_axi.v
│       ├── sim/         模擬輸出的 VCD
│       └── wave/        從 VCD 畫出的波形圖
└── HW2/
    ├── README.md        作業報告：手冊章節、中斷暫存器、實作
    ├── images/          block design、UG585 截圖
    ├── vivado/pins.xdc  EGO-XZ7 的 LED、按鈕腳位
    └── sdk/main.c       Driver + ISR
```


## 參考資料

- AMBA AHB Protocol Specification（ARM IHI 0033）
- AMBA AXI Protocol Specification（ARM IHI 0022）
- Zynq-7000 Technical Reference Manual（UG585）
