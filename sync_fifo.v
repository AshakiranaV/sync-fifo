// ============================================================
// Parameterized Synchronous FIFO
// - Single clock, active-low async reset
// - DEPTH must be a power of 2
// - Registered read data (1-cycle read latency, not FWFT)
// - Extra-MSB pointer scheme for full/empty disambiguation
// ============================================================
module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    wr_en,
    input  wire [DATA_WIDTH-1:0]   wr_data,

    input  wire                    rd_en,
    output reg  [DATA_WIDTH-1:0]   rd_data,

    output wire                    full,
    output wire                    empty,
    output wire [$clog2(DEPTH):0]  count
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    // Pointers carry one extra MSB (wrap bit):
    //   all bits equal            -> empty
    //   low bits equal, MSB diff  -> full
    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]) &&
                   (wr_ptr[ADDR_WIDTH]     != rd_ptr[ADDR_WIDTH]);

    // Two's-complement subtraction handles pointer wrap with no conditionals
    assign count = wr_ptr - rd_ptr;

    // Guard illegal accesses internally
    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;

    // Write side
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (do_write) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // Read side (registered output — data valid the cycle after rd_en)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr  <= 0;
            rd_data <= {DATA_WIDTH{1'b0}};
        end else if (do_read) begin
            rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
            rd_ptr  <= rd_ptr + 1'b1;
        end
    end

endmodule
