# clkdiv
A clock divider module with enable input

## Parameters
### DIV
The amount to divide clk_i by, the default is 8
### IDLE_HIGH
When 1, clk_o will idle high, and idles low otherwise. The default is 1.
### COVER
For testing use only. Set to 1 to include cover properties during formal verification

## Ports
### clk_i
The system clock
### enable_i
When high, enables clk_o
### clk_o
The output clock, with a frequency that is the frequency of clk_i divided by DIV

## Description
This module is intended to be used for generating low-speed clock outputs for protocols such as SPI and I2C. To
simplify compliance with these standards, the module uses a state machine to ensure that clk_o never pulses high or
low for a time shorter than the output period divided by two. This state machine is in one of three states; idle,
running, or cooldown.

In the idle state, clk_o is the value specified by the IDLE_HIGH parameter. As soon as enable_i goes high, the clk_o
signal toggles, and the module transitions to the running state.

In the running state, clk_o toggles at the frequency specified by clk_i and DIV. The enable_i signal is sampled on
every transition of clk_o back to the idle value. If enable_i is low at this time, the state machine transitions to
the cooldown state.

The cooldown state merely waits for a half period before transitioning to the idle state. It does not sample
enable_i, and clk_o will always be the value specified by IDLE_HIGH.

If you require a clock for digital logic within the FPGA, I recommend looking into the clocking, buffer, and PLL
primitives provided by your FPGA vendor instead. 

## FuseSoC
Use [FuseSoc](https://github.com/olofk/fusesoc) to simplify integrating this core into your project. If you're
interested in more cores by me, take a peek at my [FuseSoC core library](https://github.com/adwranovsky/CoreOrchard).

## License
This project is licensed under the [OHDL](http://juliusbaxter.net/ohdl/ohdl.txt), which is a weak, copyleft license for HDL.
