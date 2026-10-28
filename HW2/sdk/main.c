/*
 * HW2：跑馬燈 + 按鈕中斷（EGO-XZ7，Zynq-7020）
 *
 * 硬體：axi_gpio_0 → 8 顆 LED（0x41200000）
 *       axi_gpio_1 → 1 顆按鈕（0x41210000），ip2intc_irpt → IRQ_F2P[0] → GIC ID 61
 *
 * main 一直跑跑馬燈；按下按鈕 → 中斷 → btn_isr() 切換 paused，跑馬燈停住／繼續。
 * GIC 不用 BSP 的 XScuGic，直接照 UG585 查到的暫存器位址設定。
 */
#include "xparameters.h"
#include "xil_io.h"
#include "xil_exception.h"
#include "xtime_l.h"
#include "sleep.h"

#define LED     XPAR_AXI_GPIO_0_BASEADDR                    /* 0x41200000 */
#define BTN     XPAR_AXI_GPIO_1_BASEADDR                    /* 0x41210000 */
#define IRQ_ID  XPAR_FABRIC_AXI_GPIO_1_IP2INTC_IRPT_INTR    /* 61 */

static volatile int paused = 0;             /* main 和 ISR 共用，要 volatile */

/* ISR：按鈕按下、放開都會進來，不是 main 呼叫的 */
void btn_isr(void *unused)
{
    static XTime last;
    XTime now;
    u32 iar = Xil_In32(0xF8F0010C);         /* ICCIAR：讀出中斷編號 */

    if ((iar & 0x3FF) == IRQ_ID) {
        XTime_GetTime(&now);
        /* 只在按下時切換；按鈕會彈跳，200 ms 內重複的當同一次 */
        if (Xil_In32(BTN) && now - last > COUNTS_PER_SECOND / 5) {
            paused = !paused;
            last = now;
        }
        Xil_Out32(BTN + 0x120, 1);          /* IPISR：清掉按鈕的中斷 */
    }
    Xil_Out32(0xF8F00110, iar);             /* ICCEOIR：告訴 GIC 處理完了 */
}

int main(void)
{
    u32 led = 0x01;

    /* 1. 按鈕 GPIO 開中斷 */
    Xil_Out32(BTN + 0x128, 1);              /* IPIER：開 CH1 中斷 */
    Xil_Out32(BTN + 0x11C, 0x80000000);     /* GIER：總開關 */

    /* 2. GIC 設定 ID 61（位址都是 UG585 附錄 A 查的）*/
    Xil_Out8(0xF8F01400 + IRQ_ID, 0xA0);    /* ICDIPR：優先權 */
    Xil_Out8(0xF8F01800 + IRQ_ID, 0x01);    /* ICDIPTR：送給 CPU0 */
    Xil_Out32(0xF8F01C0C,                   /* ICDICFR3 bit[27:26] = 01：high level */
              (Xil_In32(0xF8F01C0C) & ~(3u << 26)) | (1u << 26));
    Xil_Out32(0xF8F01284, 1u << 29);        /* ICDICPR1 bit29：清掉 ID 61 殘留的 pending */
    Xil_Out32(0xF8F01104, 1u << 29);        /* ICDISER1 bit29：開啟 ID 61（mask 打開）*/
    Xil_Out32(0xF8F01000, 1);               /* ICDDCR：開 Distributor */
    Xil_Out32(0xF8F00104, 0xF0);            /* ICCPMR：優先權門檻 */
    Xil_Out32(0xF8F00100, 0x07);            /* ICCICR：開 CPU Interface */

    /* 3. CPU：IRQ 發生時跳到 btn_isr，打開 IRQ */
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_IRQ_INT, btn_isr, NULL);
    Xil_ExceptionEnable();

    /* 跑馬燈：main 自己一直跑，ISR 只負責改 paused */
    while (1) {
        Xil_Out32(LED, led);
        usleep(200000);                     /* 0.2 秒一格，要快就調小 */
        if (!paused)
            led = ((led << 1) | (led >> 7)) & 0xFF;   /* LED0→LED7 循環 */
    }
}
