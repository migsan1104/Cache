// ============================================================
// Parameterized cache skeleton
// Uses Address_Decode.sv and RAM.sv directly for arrays
// ============================================================

module Cache #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 32,
    parameter int CACHE_BYTES  = 1024,
    parameter int LINE_BYTES   = 16,
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

    // ============================================================
    // Cache geometry
    // ============================================================

    localparam int WORD_BYTES      = DATA_WIDTH / 8;
    localparam int WORDS_PER_LINE  = LINE_BYTES / WORD_BYTES;
    localparam int NUM_LINES       = CACHE_BYTES / LINE_BYTES;
    localparam int NUM_SETS        = NUM_LINES / ASSOC;

    localparam int BYTE_OFFSET_W   = $clog2(WORD_BYTES);
    localparam int WORD_OFFSET_W   = $clog2(WORDS_PER_LINE);
    localparam int SET_INDEX_BITS  = (NUM_SETS <= 1) ? 0 : $clog2(NUM_SETS);
    localparam int SET_INDEX_W     = (SET_INDEX_BITS == 0) ? 1 : SET_INDEX_BITS;

    localparam int LINE_OFFSET_W   = BYTE_OFFSET_W + WORD_OFFSET_W;
    localparam int TAG_WIDTH       = ADDR_WIDTH - LINE_OFFSET_W - SET_INDEX_BITS;
    localparam int LINE_ADDR_WIDTH = ADDR_WIDTH - LINE_OFFSET_W;

    // Flag bits: [0] valid, [1] dirty, [2] lock/reserved, [3] replacement/debug
    localparam int FLAG_BITS = 4;

    // ============================================================
    // Address decode
    // ============================================================

    logic [TAG_WIDTH-1:0]       addr_tag;
    logic [SET_INDEX_W-1:0]     addr_index;
    logic [WORD_OFFSET_W-1:0]   addr_word_offset;
    logic [BYTE_OFFSET_W-1:0]   addr_byte_offset;
    logic [LINE_ADDR_WIDTH-1:0] addr_line_addr;

    Address_Decode #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .CACHE_BYTES(CACHE_BYTES),
        .LINE_BYTES (LINE_BYTES),
        .ASSOC      (ASSOC)
    ) ADDR_DECODE (
        .addr       (cpu_addr),

        .tag        (addr_tag),
        .index      (addr_index),
        .word_offset(addr_word_offset),
        .byte_offset(addr_byte_offset),
        .line_addr  (addr_line_addr)
    );

    // ============================================================
    // Cache arrays
    // ============================================================

    logic                    data_wen;
    logic                    tag_wen;
    logic                    flag_wen;

    logic [SET_INDEX_W-1:0]  array_windex;
    logic [SET_INDEX_W-1:0]  array_rindex;

    logic [DATA_WIDTH-1:0]   data_wdata;
    logic [TAG_WIDTH-1:0]    tag_wdata;
    logic [FLAG_BITS-1:0]    flag_wdata;

    logic [DATA_WIDTH-1:0]   data_rdata;
    logic [TAG_WIDTH-1:0]    tag_rdata;
    logic [FLAG_BITS-1:0]    flag_rdata;

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
        .D_WIDTH     (TAG_WIDTH),
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
    // Tag compare
    // ============================================================

    Tag #(
        .TAG_BITS(TAG_WIDTH)
    ) TAG_COMPARE (
        .req_tag   (addr_tag),
        .stored_tag(tag_rdata),
        .valid     (flag_rdata[0]),

        .hit       (cpu_hit)
    );

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