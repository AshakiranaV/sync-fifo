// ============================================================
// Self-checking testbench for sync_fifo
// Tests:
//   1  Flag state after reset
//   2  Fill to full
//   3  Write-while-full is ignored
//   4  Drain in FIFO order, data integrity
//   5  Read-while-empty is ignored
//   6  Simultaneous read + write, steady occupancy
//   7  Pointer wraparound over 2.5*DEPTH transactions
//   8  Almost-full / almost-empty threshold flags
// ============================================================
`timescale 1ns/1ps

module tb_sync_fifo;

    localparam DATA_WIDTH = 8;
    localparam DEPTH      = 16;
    localparam ADDR_WIDTH = $clog2(DEPTH);

    reg                   clk;
    reg                   rst_n;
    reg                   wr_en;
    reg  [DATA_WIDTH-1:0] wr_data;
    reg                   rd_en;
    wire [DATA_WIDTH-1:0] rd_data;
    wire                  full;
    wire                  empty;
    wire                  almost_full;
    wire                  almost_empty;
    wire [ADDR_WIDTH:0]   count;

    localparam AF_LVL = DEPTH - 2;
    localparam AE_LVL = 2;

    integer errors = 0;
    integer i;

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_data(wr_data),
        .rd_en(rd_en), .rd_data(rd_data),
        .full(full), .empty(empty),
        .almost_full(almost_full), .almost_empty(almost_empty),
        .count(count)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Reference model: simple scoreboard queue
    reg [DATA_WIDTH-1:0] model [0:1023];
    integer model_wr = 0;
    integer model_rd = 0;

    task check(input condition, input [255:0] msg);
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("FAIL: %0s (time=%0t)", msg, $time);
            end
        end
    endtask

    // Drive one write (data pushed to scoreboard only if FIFO not full)
    task push(input [DATA_WIDTH-1:0] d);
        begin
            @(negedge clk);
            wr_en   = 1;
            wr_data = d;
            if (!full) begin
                model[model_wr] = d;
                model_wr = model_wr + 1;
            end
            @(negedge clk);
            wr_en = 0;
        end
    endtask

    // Drive one read and compare against scoreboard
    task pop;
        reg was_empty;
        begin
            @(negedge clk);
            was_empty = empty;
            rd_en = 1;
            @(negedge clk);
            rd_en = 0;
            if (!was_empty) begin
                check(rd_data === model[model_rd], "data mismatch on read");
                model_rd = model_rd + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("fifo.vcd");
        $dumpvars(0, tb_sync_fifo);

        wr_en = 0; rd_en = 0; wr_data = 0;

        // Async reset
        rst_n = 0;
        #17;                      // deassert away from a clock edge
        rst_n = 1;
        @(negedge clk);

        // ---- Test 1: flags after reset ----
        check(empty === 1'b1, "T1: empty not asserted after reset");
        check(full  === 1'b0, "T1: full asserted after reset");
        check(count === 0,    "T1: count not zero after reset");
        $display("Test 1 (reset flags)           : %0s", errors ? "FAIL" : "PASS");

        // ---- Test 2: fill to full ----
        for (i = 0; i < DEPTH; i = i + 1)
            push(i[7:0] + 8'hA0);
        check(full  === 1'b1,  "T2: full not asserted after DEPTH writes");
        check(empty === 1'b0,  "T2: empty asserted when full");
        check(count === DEPTH, "T2: count != DEPTH when full");
        $display("Test 2 (fill to full)          : %0s", errors ? "FAIL" : "PASS");

        // ---- Test 3: write while full ignored ----
        push(8'hFF);
        check(full  === 1'b1,  "T3: full deasserted by illegal write");
        check(count === DEPTH, "T3: count changed by illegal write");
        $display("Test 3 (write-while-full)      : %0s", errors ? "FAIL" : "PASS");

        // ---- Test 4: drain in order ----
        for (i = 0; i < DEPTH; i = i + 1)
            pop;
        check(empty === 1'b1, "T4: empty not asserted after full drain");
        check(count === 0,    "T4: count not zero after full drain");
        $display("Test 4 (drain, data integrity) : %0s", errors ? "FAIL" : "PASS");

        // ---- Test 5: read while empty ignored ----
        pop;
        check(empty === 1'b1, "T5: empty deasserted by illegal read");
        check(count === 0,    "T5: count changed by illegal read");
        $display("Test 5 (read-while-empty)      : %0s", errors ? "FAIL" : "PASS");

        // ---- Test 6: simultaneous read + write ----
        // Preload half full, then N cycles of concurrent rd+wr;
        // occupancy must stay constant throughout.
        for (i = 0; i < DEPTH/2; i = i + 1)
            push(i[7:0] + 8'h30);
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge clk);
            wr_en   = 1;
            wr_data = i[7:0] + 8'h60;
            rd_en   = 1;
            model[model_wr] = i[7:0] + 8'h60;
            model_wr = model_wr + 1;
            @(negedge clk);
            wr_en = 0;
            rd_en = 0;
            check(rd_data === model[model_rd], "T6: data mismatch during rd+wr");
            model_rd = model_rd + 1;
            check(count === DEPTH/2, "T6: occupancy drifted during rd+wr");
        end
        // drain the residue
        for (i = 0; i < DEPTH/2; i = i + 1)
            pop;
        check(empty === 1'b1, "T6: not empty after drain");
        $display("Test 6 (simultaneous rd+wr)    : %0s", errors ? "FAIL" : "PASS");

        // ---- Test 7: pointer wraparound, 2.5*DEPTH transactions ----
        for (i = 0; i < (5*DEPTH)/2; i = i + 1) begin
            push(i[7:0] ^ 8'h5A);
            pop;
        end
        check(empty === 1'b1, "T7: not empty after wraparound sweep");
        check(count === 0,    "T7: count nonzero after wraparound sweep");
        $display("Test 7 (pointer wraparound)    : %0s", errors ? "FAIL" : "PASS");

        // ---- Test 8: almost_full / almost_empty thresholds ----
        // empty: almost_empty set, almost_full clear
        check(almost_empty === 1'b1, "T8: almost_empty clear when empty");
        check(almost_full  === 1'b0, "T8: almost_full set when empty");
        // fill to AF_LVL-1: almost_full still clear
        for (i = 0; i < AF_LVL - 1; i = i + 1)
            push(i[7:0]);
        check(almost_full === 1'b0, "T8: almost_full set below threshold");
        // one more write crosses the threshold
        push(8'hEE);
        check(almost_full === 1'b1, "T8: almost_full clear at threshold");
        // almost_empty must be clear well above its threshold
        check(almost_empty === 1'b0, "T8: almost_empty set above threshold");
        // drain down to AE_LVL: almost_empty asserts exactly at the boundary
        while (count > AE_LVL + 1)
            pop;
        check(almost_empty === 1'b0, "T8: almost_empty set above AE_LVL");
        pop;
        check(almost_empty === 1'b1, "T8: almost_empty clear at AE_LVL");
        // drain the rest
        while (!empty)
            pop;
        $display("Test 8 (almost flags)          : %0s", errors ? "FAIL" : "PASS");

        // ---- Summary ----
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d ERROR(S)", errors);
        $finish;
    end

endmodule
