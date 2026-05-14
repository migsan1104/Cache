// ============================================================
// Parameterized set-associative cache skeleton
// One data/tag/flag array per way
// Address format: [tag ID][set ID][word ID]
// ============================================================

module Cache #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 32,
    parameter int CACHE_BYTES  = 1024,
    parameter int LINE_BYTES   = 16,
    parameter int ASSOC        = 4,
)(
    input  logic clk,
    input  logic rst,

    input  logic                  cpu_valid,
    input  logic                  cpu_write,
    input  logic [ADDR_WIDTH-1:0] cpu_addr,
    input  logic [DATA_WIDTH-1:0] cpu_wdata,

    output logic                  cpu_ready,
    output logic                  cpu_hit,
    output logic [DATA_WIDTH-1:0] cpu_rdata,

    output logic                  mem_valid,
    output logic                  mem_write,
    output logic [ADDR_WIDTH-1:0] mem_addr,
    output logic [DATA_WIDTH-1:0] mem_wdata,

    input  logic                  mem_ready,
    input  logic [DATA_WIDTH-1:0] mem_rdata
);

    localparam int WORD_BYTES      = DATA_WIDTH / 8;
    localparam int WORDS_PER_LINE  = LINE_BYTES / WORD_BYTES;
    localparam int LINE_WIDTH      = LINE_BYTES * 8;
    localparam int NUM_LINES       = CACHE_BYTES / LINE_BYTES;
    localparam int NUM_SETS        = NUM_LINES / ASSOC;

    localparam int WORD_OFFSET_W   = $clog2(WORDS_PER_LINE);
    localparam int SET_INDEX_BITS  = (NUM_SETS <= 1) ? 0 : $clog2(NUM_SETS);
    localparam int SET_INDEX_W     = (SET_INDEX_BITS == 0) ? 1 : SET_INDEX_BITS;

    localparam int WORD_ADDR_W     = ADDR_WIDTH - $clog2(WORD_BYTES);
    localparam int TAG_WIDTH       = WORD_ADDR_W - WORD_OFFSET_W - SET_INDEX_BITS;
    localparam int LINE_ADDR_WIDTH = WORD_ADDR_W - WORD_OFFSET_W;

    localparam int WAY_INDEX_W     = (ASSOC <= 1) ? 1 : $clog2(ASSOC);

    // Flag bits: [0] valid, [1] dirty, [2] lock/reserved, [3] replacement/debug
    localparam int FLAG_BITS = 4;

    logic [TAG_WIDTH-1:0]       addr_tag;
    logic [SET_INDEX_W-1:0]     addr_set_id;
    logic [WORD_OFFSET_W-1:0]   addr_word_id;
    logic [LINE_ADDR_WIDTH-1:0] addr_line_addr;

    localparam int READ_LATENCY = 1;

    Address_Decode #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .CACHE_BYTES(CACHE_BYTES),
        .LINE_BYTES (LINE_BYTES),
        .ASSOC      (ASSOC)
    ) ADDR_DECODE (
        .addr     (cpu_addr),
        .tag      (addr_tag),
        .set_id   (addr_set_id),
        .word_id  (addr_word_id),
        .line_addr(addr_line_addr)
    );

    logic [ASSOC-1:0] data_wen;
    logic [ASSOC-1:0] tag_wen;
    logic [ASSOC-1:0] flag_wen;

    logic [SET_INDEX_W-1:0] array_rindex;
    logic [SET_INDEX_W-1:0] array_windex;

    logic [LINE_WIDTH-1:0] data_wline [ASSOC];
    logic [TAG_WIDTH-1:0]  tag_wdata  [ASSOC];
    logic [FLAG_BITS-1:0]  flag_wdata [ASSOC];

    logic [LINE_WIDTH-1:0] data_rline [ASSOC];
    logic [TAG_WIDTH-1:0]  tag_rdata  [ASSOC];
    logic [FLAG_BITS-1:0]  flag_rdata [ASSOC];

    logic [ASSOC-1:0]         way_hit;
    logic [DATA_WIDTH-1:0]    way_word [ASSOC];
    logic [WAY_INDEX_W-1:0]   hit_way;
    logic [DATA_WIDTH-1:0]    selected_word;

    assign array_rindex = addr_set_id;
    assign array_windex = addr_set_id;

    genvar way;

    generate
        for (way = 0; way < ASSOC; way++) begin : GEN_WAYS

            RAM #(
                .D_WIDTH     (LINE_WIDTH),
                .DEPTH       (NUM_SETS),
                .READ_LATENCY(READ_LATENCY)
            ) DATA_ARRAY (
                .clk  (clk),
                .wen  (data_wen[way]),
                .waddr(array_windex),
                .wdata(data_wline[way]),
                .raddr(array_rindex),
                .rdata(data_rline[way])
            );

            RAM #(
                .D_WIDTH     (TAG_WIDTH),
                .DEPTH       (NUM_SETS),
                .READ_LATENCY(READ_LATENCY)
            ) TAG_ARRAY (
                .clk  (clk),
                .wen  (tag_wen[way]),
                .waddr(array_windex),
                .wdata(tag_wdata[way]),
                .raddr(array_rindex),
                .rdata(tag_rdata[way])
            );

            RAM #(
                .D_WIDTH     (FLAG_BITS),
                .DEPTH       (NUM_SETS),
                .READ_LATENCY(READ_LATENCY)
            ) FLAG_ARRAY (
                .clk  (clk),
                .wen  (flag_wen[way]),
                .waddr(array_windex),
                .wdata(flag_wdata[way]),
                .raddr(array_rindex),
                .rdata(flag_rdata[way])
            );

            Tag #(
                .TAG_BITS(TAG_WIDTH)
            ) TAG_COMPARE (
                .req_tag   (addr_tag),
                .stored_tag(tag_rdata[way]),
                .valid     (flag_rdata[way][0]),
                .hit       (way_hit[way])
            );

            assign way_word[way] = data_rline[way][addr_word_id * DATA_WIDTH +: DATA_WIDTH];

        end
    endgenerate

    assign cpu_hit = |way_hit;

    always_comb begin
        hit_way       = '0;
        selected_word = '0;

        for (int i = 0; i < ASSOC; i++) begin
            if (way_hit[i]) begin
                hit_way       = i[WAY_INDEX_W-1:0];
                selected_word = way_word[i];
            end
        end
    end

    assign cpu_ready = cpu_valid && cpu_hit;
    assign cpu_rdata = selected_word;

    assign mem_valid = 1'b0;
    assign mem_write = 1'b0;
    assign mem_addr  = '0;
    assign mem_wdata = '0;

    always_comb begin
        data_wen  = '0;
        tag_wen   = '0;
        flag_wen  = '0;

        for (int i = 0; i < ASSOC; i++) begin
            data_wline[i] = '0;
            tag_wdata[i]  = addr_tag;
            flag_wdata[i] = 4'b0001;
        end
    end

endmodule