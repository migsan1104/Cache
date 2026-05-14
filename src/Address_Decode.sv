// ============================================================
// Address decode for aligned word-based cache accesses
// Address format: [tag ID][set ID][word ID]
// ============================================================

module Address_Decode #(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter int CACHE_BYTES = 1024,
    parameter int LINE_BYTES  = 16,
    parameter int ASSOC       = 1
)(
    input  logic [ADDR_WIDTH-1:0] addr,

    output logic [TAG_WIDTH-1:0]        tag,
    output logic [SET_INDEX_W-1:0]      set_id,
    output logic [WORD_OFFSET_W-1:0]    word_id,
    output logic [LINE_ADDR_WIDTH-1:0]  line_addr
);

    localparam int WORD_BYTES     = DATA_WIDTH / 8;
    localparam int WORDS_PER_LINE = LINE_BYTES / WORD_BYTES;
    localparam int NUM_LINES      = CACHE_BYTES / LINE_BYTES;
    localparam int NUM_SETS       = NUM_LINES / ASSOC;

    localparam int WORD_OFFSET_W  = $clog2(WORDS_PER_LINE);
    localparam int SET_INDEX_BITS = (NUM_SETS <= 1) ? 0 : $clog2(NUM_SETS);
    localparam int SET_INDEX_W    = (SET_INDEX_BITS == 0) ? 1 : SET_INDEX_BITS;

    localparam int WORD_ADDR_W    = ADDR_WIDTH - $clog2(WORD_BYTES);
    localparam int TAG_WIDTH      = WORD_ADDR_W - WORD_OFFSET_W - SET_INDEX_BITS;
    localparam int LINE_ADDR_WIDTH = WORD_ADDR_W - WORD_OFFSET_W;

    logic [WORD_ADDR_W-1:0] word_addr;

    assign word_addr = addr[ADDR_WIDTH-1:$clog2(WORD_BYTES)];

    assign word_id = word_addr[WORD_OFFSET_W-1:0];

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

    assign line_addr = word_addr[WORD_ADDR_W-1:WORD_OFFSET_W];

endmodule