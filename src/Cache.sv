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

endmodule