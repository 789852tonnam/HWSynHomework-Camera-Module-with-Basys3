
## ------------------------------------------------------------------------
## 1. Clock Signal (สัญญาณนาฬิกา 100 MHz จากบอร์ด)
## ------------------------------------------------------------------------
set_property PACKAGE_PIN W5 [get_ports clk_100mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100mhz]

## ------------------------------------------------------------------------
## 2. Reset Button (ใช้ปุ่มตรงกลาง BTNC)
## ------------------------------------------------------------------------
set_property PACKAGE_PIN U18 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports reset]

## ------------------------------------------------------------------------
## 3. Switches (สวิตช์สำหรับเปลี่ยน State/Filter)
## ใช้สวิตช์ 4 ตัวขวาสุด (SW0 - SW3)
## ------------------------------------------------------------------------
set_property PACKAGE_PIN V17 [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[0]}]
set_property PACKAGE_PIN V16 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[1]}]
set_property PACKAGE_PIN W16 [get_ports {sw[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[2]}]
set_property PACKAGE_PIN W17 [get_ports {sw[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[3]}]
set_property PACKAGE_PIN W16 [get_ports {sw[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[2]}]
set_property PACKAGE_PIN W17 [get_ports {sw[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[3]}]

## ------------------------------------------------------------------------
## 4. VGA Display Ports (พอร์ตจอภาพ VGA มาตรฐานของ Basys 3)
## ------------------------------------------------------------------------
# VGA Red
set_property PACKAGE_PIN G19 [get_ports {vga_r[0]}]
set_property PACKAGE_PIN H19 [get_ports {vga_r[1]}]
set_property PACKAGE_PIN J19 [get_ports {vga_r[2]}]
set_property PACKAGE_PIN N19 [get_ports {vga_r[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]

# VGA Green
set_property PACKAGE_PIN J17 [get_ports {vga_g[0]}]
set_property PACKAGE_PIN H17 [get_ports {vga_g[1]}]
set_property PACKAGE_PIN G17 [get_ports {vga_g[2]}]
set_property PACKAGE_PIN D17 [get_ports {vga_g[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]

# VGA Blue
set_property PACKAGE_PIN N18 [get_ports {vga_b[0]}]
set_property PACKAGE_PIN L18 [get_ports {vga_b[1]}]
set_property PACKAGE_PIN K18 [get_ports {vga_b[2]}]
set_property PACKAGE_PIN J18 [get_ports {vga_b[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]

# VGA Sync
set_property PACKAGE_PIN P19 [get_ports vga_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hsync]
set_property PACKAGE_PIN R19 [get_ports vga_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vsync]

## ------------------------------------------------------------------------
## 5. OV7670 Camera Ports (อ้างอิงพินตามตารางโจทย์ของอาจารย์)
## ------------------------------------------------------------------------
# Data Pins [7:0]
set_property PACKAGE_PIN P17 [get_ports {ov7670_data[0]}]
set_property PACKAGE_PIN N17 [get_ports {ov7670_data[1]}]
set_property PACKAGE_PIN M19 [get_ports {ov7670_data[2]}]
set_property PACKAGE_PIN M18 [get_ports {ov7670_data[3]}]
set_property PACKAGE_PIN L17 [get_ports {ov7670_data[4]}]
set_property PACKAGE_PIN K17 [get_ports {ov7670_data[5]}]
set_property PACKAGE_PIN C16 [get_ports {ov7670_data[6]}]
set_property PACKAGE_PIN B16 [get_ports {ov7670_data[7]}]

# Control Signals
set_property PACKAGE_PIN A17 [get_ports ov7670_href]
set_property PACKAGE_PIN A16 [get_ports ov7670_pclk]
set_property PACKAGE_PIN R18 [get_ports ov7670_pwdn] 
set_property PACKAGE_PIN P18 [get_ports ov7670_rst]  
set_property PACKAGE_PIN A14 [get_ports ov7670_sioc] 
set_property PACKAGE_PIN A15 [get_ports ov7670_siod] 
set_property PACKAGE_PIN B15 [get_ports ov7670_vsync]
set_property PACKAGE_PIN C15 [get_ports ov7670_xclk]

# ตั้งค่ากระแสไฟให้ขากล้องทั้งหมดเป็น 3.3V
set_property IOSTANDARD LVCMOS33 [get_ports -filter { NAME =~  "*ov7670*" }]

# ใส่ Pull-up ให้สาย I2C/SCCB (สำคัญมาก ถ้าไม่ใส่กล้องจะไม่รับคำสั่งตั้งค่า)
set_property PULLUP true [get_ports ov7670_sioc]
set_property PULLUP true [get_ports ov7670_siod]
## Create Clock Constraints
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk_100mhz]
create_clock -period 40.000 -name cam_clk_pin -waveform {0.000 20.000} -add [get_ports ov7670_pclk]
## ------------------------------------------------------------------------
## 6. แก้ปัญหา Routing ของ PCLK
## ------------------------------------------------------------------------
# อนุญาตให้ Vivado เดินสายสัญญาณ Clock ผ่านพิน I/O ธรรมดาได้
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets ov7670_pclk_IBUF]