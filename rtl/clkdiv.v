`default_nettype none

/*
 * clkdiv - A clock divider module with enable input
 *
 * Parameters:
 *  DIV - The amount to divide clk_i by, the default is 8
 *  IDLE_HIGH - When 1, clk_o will idle high, and idles low otherwise. The default is 1.
 *
 * Ports:
 *  clk_i - The system clock
 *  enable_i - When high, enables clk_o
 *  clk_o - The output clock, with a frequency that is the frequency of clk_i divided by DIV
 *
 * Description:
 *  This module is intended to be used for generating low-speed clock outputs for protocols such as SPI and I2C. To
 *  simplify compliance with these standards, the module uses a state machine to ensure that clk_o never pulses high or
 *  low for a time shorter than the output period divided by two. This state machine is in one of three states; idle,
 *  running, or cooldown.
 *
 *  In the idle state, clk_o is the value specified by the IDLE_HIGH parameter. As soon as enable_i goes high, the clk_o
 *  signal toggles, and the module transitions to the running state.
 *
 *  In the running state, clk_o toggles at the frequency specified by clk_i and DIV. The enable_i signal is sampled on
 *  every transition of clk_o back to the idle value. If enable_i is low at this time, the state machine transitions to
 *  the cooldown state.
 *
 *  The cooldown state merely waits for a half period before transitioning to the idle state. It does not sample
 *  enable_i, and clk_o will always be the value specified by IDLE_HIGH.
 *
 *  If you require a clock for digital logic within the FPGA, I recommend looking into the clocking, buffer, and PLL
 *  primitives provided by your FPGA vendor instead. 
 */
module clkdiv #(
    parameter DIV = 8,
    parameter IDLE_HIGH = 1
) (
    input wire clk_i,
    input wire enable_i,
    output wire clk_o
);

    /*
     * Try to force an elaboration failure when invalid parameters are specified
     */
    generate if (DIV < 2)
        invalid_verilog_parameter DIV_must_be_greater_than_or_equal_to_2 ();
    endgenerate

    /*
     * Detect when clk_o transitions to the idle value
     */
    reg past_clk_o;
    always @(posedge clk_i)
        past_clk_o <= clk_o;

    wire transition_to_idle;
    generate
        if (IDLE_HIGH == 1)
            assign transition_to_idle = clk_o==1'b1 && past_clk_o==1'b0;
        else
            assign transition_to_idle = clk_o==1'b0 && past_clk_o==1'b1;
    endgenerate


    /*
     * Create a counter for dividing the clock
     */
    localparam COUNTER_LIMIT = DIV-1;
    localparam COUNTER_WIDTH = $clog2(DIV);
    reg [COUNTER_WIDTH-1:0] counter;
    reg restart_counter;
    wire counter_reached_div = counter == COUNTER_LIMIT[COUNTER_WIDTH-1:0];
    initial counter = 0;
    always @(posedge clk_i)
        if (restart_counter)
            counter <= 0;
        else
            counter <= counter + 1;


    /*
     * clkdiv state machine
     */

    // valid states
    localparam
        IDLE     = 3'b001,
        RUNNING  = 3'b010,
        COOLDOWN = 3'b100;

    // state register
    reg [2:0] state, next_state;
    initial state = IDLE;
    always @(posedge clk_i)
        state <= next_state;

    // state transition logic
    always @(posedge clk_i) begin
        next_state = state;
        case (state)
            IDLE:
                if (enable_i)
                    next_state = RUNNING;
            RUNNING:
                if (!enable_i && transition_to_idle)
                    next_state = COOLDOWN;
            COOLDOWN:
                if (counter_reached_div)
                    next_state = IDLE;
            default:
                next_state = state;
        endcase
    end

    // state machine io
    always @(posedge clk_i) begin
        case (state)
            IDLE: begin
            end
            RUNNING: begin
            end
            COOLDOWN: begin
            end
        endcase
    end

`ifdef FORMAL
    // Keep track of whether or not $past() is valid
    reg f_past_valid = 0;
    always @(posedge clk_i)
        f_past_valid <= 1;

    // Verify that "state" is always valid
    always @(*)
        assert(
            state == IDLE ||
            state == RUNNING ||
            state == COOLDOWN
        );

    // Verify that the clk_o doesn't change state any faster than half of the clock period
`endif

endmodule

`default_nettype wire
