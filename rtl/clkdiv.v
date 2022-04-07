`default_nettype none

/*
 * clkdiv - A clock divider module with enable input
 *
 * Parameters:
 *  DIV - The amount to divide clk_i by, the default is 8
 *  IDLE_HIGH - When 1, clk_o will idle high, and idles low otherwise. The default is 1.
 *  COVER - For testing use only. Set to 1 to include cover properties during formal verification
 *
 * Ports:
 *  clk_i - The system clock
 *  enable_i - When high, enables clk_o
 *  idle_o - When high, clk_o is idle and setting enable_i will begin oscillation again
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
    parameter IDLE_HIGH = 1,
    parameter COVER = 0
) (
    input wire clk_i,
    input wire enable_i,
    output reg idle_o,
    output reg clk_o
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
    wire idle_value;
    generate
        if (IDLE_HIGH == 1) begin
            assign idle_value = 1'b1;
            assign transition_to_idle = clk_o==1'b1 && past_clk_o==1'b0;
        end else begin
            assign idle_value = 1'b0;
            assign transition_to_idle = clk_o==1'b0 && past_clk_o==1'b1;
        end
    endgenerate


    /*
     * Create a counter for dividing the clock
     */
    localparam COUNTER_LIMIT = DIV-1;
    localparam COUNTER_HALF  = DIV/2;
    localparam COUNTER_WIDTH = $clog2(DIV);
    reg [COUNTER_WIDTH-1:0] counter;
    reg restart_counter;
    wire counter_reached_end  = counter >= COUNTER_LIMIT[COUNTER_WIDTH-1:0];
    wire counter_reached_half = counter >= COUNTER_HALF[COUNTER_WIDTH-1:0];
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
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:
                if (enable_i)
                    next_state = RUNNING;
            RUNNING:
                if (!enable_i && transition_to_idle)
                    next_state = COOLDOWN;
            COOLDOWN:
                if (counter_reached_end)
                    next_state = IDLE;
            default:
                next_state = IDLE;
        endcase
    end

    // state machine io
    always @(*) begin
        restart_counter = 0;
        clk_o = idle_value;
        idle_o = 0;
        // verilator lint_off CASEINCOMPLETE
        case (state)
            IDLE: begin
                idle_o = 1;
                restart_counter = enable_i;
            end
            RUNNING: begin
                restart_counter = counter_reached_end;
                clk_o = ~(counter_reached_half ^ idle_value);
            end
            COOLDOWN: begin
            end
        endcase
        // verilator lint_on CASEINCOMPLETE
    end

`ifdef FORMAL
    /*
     * Supporting logic for the formal properties
     */

    // Keep track of whether or not $past() is valid
    reg f_past_valid = 0;
    always @(posedge clk_i)
        f_past_valid <= 1;

    // Keep track of the simulation time
    integer f_time = 0;
    always @(posedge clk_i)
        f_time <= f_time + 1;

    // Record the length of time that clk_o stays in any particular state
    integer f_period_counter = 1;
    always @(posedge clk_i) begin
        if (f_past_valid && $changed(clk_o))
            f_period_counter <= 1;
        else if (f_period_counter == {COUNTER_WIDTH{1'b1}})
            f_period_counter <= f_period_counter; // saturate the counter, don't rollover
        else
            f_period_counter <= f_period_counter + 1;
    end

    // Record the length of time that enable_i stays in the low state
    integer f_enable_counter = 1;
    always @(posedge clk_i)
        if (f_past_valid && $fell(enable_i))
            f_enable_counter <= 1;
        else
            f_enable_counter <= f_enable_counter + 1;

    // Record the longest time that enable_i has been low
    integer f_longest_enable_low = 0;
    always @(posedge clk_i)
        if (f_past_valid && $rose(enable_i) && f_enable_counter > f_longest_enable_low)
            f_longest_enable_low <= f_enable_counter;

    /*
     * Formal properties
     */

    // Verify that "state" is always valid
    always @(*)
        assert(
            state == IDLE ||
            state == RUNNING ||
            state == COOLDOWN
        );

    // Verify clk_o isn't doing anything in the IDLE and COOLDOWN states
    always @(*)
        if (state==IDLE || state==COOLDOWN)
            assert(clk_o == idle_value);

    // Verify that clk_o hasn't transitioned any faster than half of the clock period. We make an exception for the
    // beginning of the simulation, when clk_o may transition as soon as enable_i is brought high.
    always @(posedge clk_i)
        if (f_past_valid && $changed(clk_o) && f_time >= DIV/2)
            assert(f_period_counter >= DIV/2);

    // Ensure that f_period_counter itself always remains valid
    always @(*)
        assert(f_period_counter > 0 && f_period_counter <= {COUNTER_WIDTH{1'b1}});

    // Generate a testbench that has the output clock completing 10 periods, and has the enable signal toggling
    // 5 times. Ensure that the enable_i signal was low for at least 2 periods one time
    integer f_num_clks = 0;
    integer f_num_enable_toggles = 0;
    always @(posedge clk_i)
        if (f_past_valid) begin
            if ($rose(clk_o))
                f_num_clks <= f_num_clks + 1;
            if ($changed(enable_i))
                f_num_enable_toggles <= f_num_enable_toggles + 1;
        end
    generate if (COVER==1) begin
        always @(*)
            cover(f_num_enable_toggles == 5 && f_num_clks == 10 && f_longest_enable_low >= DIV*2);
    end endgenerate
`endif

endmodule

`default_nettype wire
