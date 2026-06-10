// ============================================================
// Address decode for aligned word-based cache accesses
// Address format using byte address:
// [tag ID][set ID][word ID][byte offset]
// Internal cache fields ignore byte offset.
// ============================================================

module Address_Decode #(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter int CACHE_BYTES = 1024,
    parameter int LINE_BYTES  = 16,
    parameter int ASSOC       = 1,

    parameter int WORD_BYTES      = DATA_WIDTH / 8,
    parameter int WORDS_PER_LINE  = LINE_BYTES / WORD_BYTES,
    parameter int NUM_LINES       = CACHE_BYTES / LINE_BYTES,
    parameter int NUM_SETS        = NUM_LINES / ASSOC,

    parameter int BYTE_OFFSET_W   = $clog2(WORD_BYTES),
    parameter int WORD_OFFSET_W   = $clog2(WORDS_PER_LINE),

    parameter int SET_INDEX_BITS  = (NUM_SETS <= 1) ? 0 : $clog2(NUM_SETS),
    parameter int SET_INDEX_W     = (SET_INDEX_BITS == 0) ? 1 : SET_INDEX_BITS,

    parameter int WORD_ADDR_W     = ADDR_WIDTH - BYTE_OFFSET_W,
    parameter int TAG_WIDTH       = WORD_ADDR_W - WORD_OFFSET_W - SET_INDEX_BITS,
    parameter int LINE_ADDR_WIDTH = WORD_ADDR_W - WORD_OFFSET_W
)(
    input  logic [ADDR_WIDTH-1:0]       addr,

    output logic [TAG_WIDTH-1:0]        tag,
    output logic [SET_INDEX_W-1:0]      set_id,
    output logic [WORD_OFFSET_W-1:0]    word_id,
    output logic [LINE_ADDR_WIDTH-1:0]  line_addr
);

    logic [WORD_ADDR_W-1:0] word_addr;

    assign word_addr = addr[ADDR_WIDTH-1:BYTE_OFFSET_W];

    assign word_id   = word_addr[WORD_OFFSET_W-1:0];
    assign line_addr = word_addr[WORD_ADDR_W-1:WORD_OFFSET_W];

    generate
        if (SET_INDEX_BITS == 0) begin : GEN_FULLY_ASSOC
            assign set_id = '0;
            assign tag    = word_addr[WORD_ADDR_W-1:WORD_OFFSET_W];
        end
        else begin : GEN_INDEXED
            assign set_id = word_addr[WORD_OFFSET_W +: SET_INDEX_BITS];
            assign tag    = word_addr[WORD_ADDR_W-1 -: TAG_WIDTH];
        end
    endgenerate

endmodule