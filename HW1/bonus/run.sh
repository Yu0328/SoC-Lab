#!/bin/sh
# 跑兩個 testbench，波形在 sim/*.vcd（用 gtkwave 開）
set -e
cd "$(dirname "$0")"
mkdir -p sim && cd sim
iverilog -g2005 -o tb_ahb.vvp ../tb/tb_ahb.v ../rtl/ahb_master.v ../rtl/ahb_slave.v
vvp -n tb_ahb.vvp
iverilog -g2005 -o tb_axi.vvp ../tb/tb_axi.v ../rtl/axi_master_rd.v ../rtl/axi_master_wr.v ../rtl/axi_slave.v
vvp -n tb_axi.vvp
