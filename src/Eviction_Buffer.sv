// ============================================================
// Eviction buffer for dirty cache line writebacks
// Assumption: mem_req_ready means downstream will accept next cycle
// ============================================================

module Eviction_Buffer #(
    parameter int ADDR_WIDTH = 32,
    parameter int LINE_WIDTH = 128,
    parameter int DEPTH      = 8
)(
    input  logic                  clk,
    input  logic                  rst,

    input  logic                  evict_valid,
    output logic                  evict_ready,
    input  logic [ADDR_WIDTH-1:0] evict_addr,
    input  logic [LINE_WIDTH-1:0] evict_line_data,

    output logic                  mem_req_valid,
    input  logic                  mem_req_ready,
    output logic                  mem_req_write,
    output logic [ADDR_WIDTH-1:0] mem_req_addr,
    output logic [LINE_WIDTH-1:0] mem_req_wdata
);

    localparam int FIFO_WIDTH = ADDR_WIDTH + LINE_WIDTH;

    logic                  fifo_full;
    logic                  fifo_empty;
    logic                  fifo_rd_valid;

    logic                  fifo_wr_en;
    logic                  fifo_rd_en;

    logic [FIFO_WIDTH-1:0] fifo_wr_data;
    logic [FIFO_WIDTH-1:0] fifo_rd_data;

    assign evict_ready  = !fifo_full;
    assign fifo_wr_en   = evict_valid && evict_ready;
    assign fifo_wr_data = {evict_addr, evict_line_data};

    // mem_req_ready is treated as a 1-cycle lookahead ready.
    assign fifo_rd_en = mem_req_ready && !fifo_empty;

    FIFO #(
        .WIDTH(FIFO_WIDTH),
        .DEPTH(DEPTH)
    ) WB_FIFO (
        .clk     (clk),
        .rst     (rst),

        .full    (fifo_full),
        .wr_en   (fifo_wr_en),
        .wr_data (fifo_wr_data),

        .empty   (fifo_empty),
        .rd_en   (fifo_rd_en),
        .rd_valid(fifo_rd_valid),
        .rd_data (fifo_rd_data)
    );

    assign mem_req_valid = fifo_rd_valid;
    assign mem_req_write = fifo_rd_valid;

    assign {mem_req_addr, mem_req_wdata} = fifo_rd_data;

endmodule