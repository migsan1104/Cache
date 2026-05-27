// ============================================================
// Read miss queue for downstream refill requests
// Stores {MSHR ID, line address}
// Assumption: mem_req_ready means downstream accepts next cycle
// ============================================================

module Read_Miss_Queue #(
    parameter int ADDR_WIDTH      = 32,
    parameter int LINE_ADDR_WIDTH = 28,
    parameter int LINE_BYTES      = 16,
    parameter int ID_WIDTH        = 2,
    parameter int DEPTH           = 8
)(
    input  logic                         clk,
    input  logic                         rst,

    input  logic                         miss_valid,
    output logic                         miss_ready,
    input  logic [LINE_ADDR_WIDTH-1:0]   miss_line_addr,
    input  logic [ID_WIDTH-1:0]          miss_id,

    output logic                         mem_req_valid,
    input  logic                         mem_req_ready,
    output logic                         mem_req_write,
    output logic [ADDR_WIDTH-1:0]        mem_req_addr,
    output logic [ID_WIDTH-1:0]          mem_req_id
);

    localparam int LINE_OFFSET_W = $clog2(LINE_BYTES);
    localparam int FIFO_WIDTH    = ID_WIDTH + LINE_ADDR_WIDTH;

    logic                  fifo_full;
    logic                  fifo_empty;
    logic                  fifo_rd_valid;

    logic                  fifo_wr_en;
    logic                  fifo_rd_en;

    logic [FIFO_WIDTH-1:0] fifo_wr_data;
    logic [FIFO_WIDTH-1:0] fifo_rd_data;

    logic [LINE_ADDR_WIDTH-1:0] rd_line_addr;
    logic [ID_WIDTH-1:0]        rd_id;

    assign miss_ready   = !fifo_full;
    assign fifo_wr_en   = miss_valid && miss_ready;
    assign fifo_wr_data = {miss_id, miss_line_addr};

    // mem_req_ready is treated as a 1-cycle lookahead ready.
    assign fifo_rd_en = mem_req_ready && !fifo_empty;

    FIFO #(
        .WIDTH(FIFO_WIDTH),
        .DEPTH(DEPTH)
    ) MISS_FIFO (
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

    assign {rd_id, rd_line_addr} = fifo_rd_data;

    assign mem_req_valid = fifo_rd_valid;
    assign mem_req_write = 1'b0;
    assign mem_req_addr  = {{(ADDR_WIDTH-LINE_ADDR_WIDTH-LINE_OFFSET_W){1'b0}},
                            rd_line_addr,
                            {LINE_OFFSET_W{1'b0}}};
    assign mem_req_id    = rd_id;

endmodule