

## LED0~LED7（axi_gpio_0，外接 port 名稱 led）
set_property -dict { PACKAGE_PIN T22 IOSTANDARD LVCMOS33 } [get_ports { led_tri_o[0] }]
set_property -dict { PACKAGE_PIN T21 IOSTANDARD LVCMOS33 } [get_ports { led_tri_o[1] }]
set_property -dict { PACKAGE_PIN U22 IOSTANDARD LVCMOS33 } [get_ports { led_tri_o[2] }]
set_property -dict { PACKAGE_PIN U21 IOSTANDARD LVCMOS33 } [get_ports { led_tri_o[3] }]
set_property -dict { PACKAGE_PIN V22 IOSTANDARD LVCMOS33 } [get_ports { led_tri_o[4] }]
set_property -dict { PACKAGE_PIN W22 IOSTANDARD LVCMOS33 } [get_ports { led_tri_o[5] }]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports { led_tri_o[6] }]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { led_tri_o[7] }]

## 按鈕 btns[0]（axi_gpio_1，外接 port 名稱 btn）
set_property -dict { PACKAGE_PIN P16 IOSTANDARD LVCMOS25 } [get_ports { btn_tri_i[0] }]

## 改用開關 SW0 時，把上一行換成：
## set_property -dict { PACKAGE_PIN F22 IOSTANDARD LVCMOS25 } [get_ports { btn_tri_i[0] }]
