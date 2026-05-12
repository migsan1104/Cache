// ============================================================
// Direct-mapped parameterized cache skeleton
// Uses RAM.sv directly for data, tag, and flag arrays
// ============================================================

module Cache #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 32,
    parameter int CACHE_SIZE   = 1024,
    parameter int LINE_BYTES   = 4,
    parameter int ASSOC        = 1,
    parameter int READ_LATENCY = 1
)(
    input  logic clk,
    input  logic rst,

    // ============================================================
    // CPU INTERFACE
    // ============================================================

    input  logic                  cpu_valid,
    input  logic                  cpu_write,
    input  logic [ADDR_WIDTH-1:0] cpu_addr,
    input  logic [DATA_WIDTH-1:0] cpu_wdata,

    output logic                  cpu_ready,
    output logic                  cpu_hit,
    output logic [DATA_WIDTH-1:0] cpu_rdata,

    // ============================================================
    // DOWNSTREAM MEMORY INTERFACE
    // ============================================================

    output logic                  mem_valid,
    output logic                  mem_write,
    output logic [ADDR_WIDTH-1:0] mem_addr,
    output logic [DATA_WIDTH-1:0] mem_wdata,

    input  logic                  mem_ready,
    input  logic [DATA_WIDTH-1:0] mem_rdata
);

    // Total number of cache lines in the entire cache
    localparam int NUM_LINES = CACHE_SIZE / LINE_BYTES;

    // Total number of cache sets
    localparam int NUM_SETS = NUM_LINES / ASSOC;

    // Number of bits used for byte offset inside a cache line
    localparam int OFFSET_BITS = $clog2(LINE_BYTES);

    // Number of bits used to index into cache sets
    localparam int INDEX_BITS = $clog2(NUM_SETS);

    // Remaining upper address bits used for tag comparison
    localparam int TAG_BITS = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;

    // Flag bits: [0] valid, [1] dirty, [2] lock/reserved, [3] replacement/debug
    localparam int FLAG_BITS = 4;

    // ============================================================
    // Address decode
    // ============================================================

    logic [TAG_BITS-1:0]    addr_tag;
    logic [INDEX_BITS-1:0]  addr_index;
    logic [OFFSET_BITS-1:0] addr_offset;

    assign addr_offset = cpu_addr[OFFSET_BITS-1:0];
    assign addr_index  = cpu_addr[OFFSET_BITS +: INDEX_BITS];
    assign addr_tag    = cpu_addr[ADDR_WIDTH-1 -: TAG_BITS];

    // ============================================================
    // Cache arrays
    // ============================================================

    logic                  data_wen;
    logic                  tag_wen;
    logic                  flag_wen;

    logic [INDEX_BITS-1:0] array_windex;
    logic [INDEX_BITS-1:0] array_rindex;

    logic [DATA_WIDTH-1:0] data_wdata;
    logic [TAG_BITS-1:0]   tag_wdata;
    logic [FLAG_BITS-1:0]  flag_wdata;

    logic [DATA_WIDTH-1:0] data_rdata;
    logic [TAG_BITS-1:0]   tag_rdata;
    logic [FLAG_BITS-1:0]  flag_rdata;

    assign array_rindex = addr_index;

    RAM #(
        .D_WIDTH     (DATA_WIDTH),
        .DEPTH       (NUM_SETS),
        .READ_LATENCY(READ_LATENCY)
    ) DATA_ARRAY (
        .clk  (clk),

        .wen  (data_wen),
        .waddr(array_windex),
        .wdata(data_wdata),

        .raddr(array_rindex),
        .rdata(data_rdata)
    );

    RAM #(
        .D_WIDTH     (TAG_BITS),
        .DEPTH       (NUM_SETS),
        .READ_LATENCY(READ_LATENCY)
    ) TAG_ARRAY (
        .clk  (clk),

        .wen  (tag_wen),
        .waddr(array_windex),
        .wdata(tag_wdata),

        .raddr(array_rindex),
        .rdata(tag_rdata)
    );

    RAM #(
        .D_WIDTH     (FLAG_BITS),
        .DEPTH       (NUM_SETS),
        .READ_LATENCY(READ_LATENCY)
    ) FLAG_ARRAY (
        .clk  (clk),

        .wen  (flag_wen),
        .waddr(array_windex),
        .wdata(flag_wdata),

        .raddr(array_rindex),
        .rdata(flag_rdata)
    );

    // ============================================================
    // Basic hit logic
    // ============================================================

    assign cpu_hit = flag_rdata[0] && (tag_rdata == addr_tag);

    // ============================================================
    // Temporary skeleton outputs
    // Controller logic will replace this next
    // ============================================================

    assign cpu_ready = cpu_valid && cpu_hit;
    assign cpu_rdata = data_rdata;

    assign mem_valid = 1'b0;
    assign mem_write = 1'b0;
    assign mem_addr  = '0;
    assign mem_wdata = '0;

    assign data_wen  = 1'b0;
    assign tag_wen   = 1'b0;
    assign flag_wen  = 1'b0;

    assign array_windex = addr_index;
    assign data_wdata   = cpu_wdata;
    assign tag_wdata    = addr_tag;
    assign flag_wdata   = 4'b0001;

endmodule