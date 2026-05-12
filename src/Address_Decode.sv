module Address_Decode #(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter int CACHE_BYTES = 1024,
    parameter int LINE_BYTES  = 16,
    parameter int ASSOC       = 1
)(
    input  logic [ADDR_WIDTH-1:0] addr,

    output logic [TAG_WIDTH-1:0]        tag,
    output logic [SET_INDEX_W-1:0]      index,
    output logic [WORD_OFFSET_W-1:0]    word_offset,
    output logic [BYTE_OFFSET_W-1:0]    byte_offset,
    output logic [LINE_ADDR_WIDTH-1:0]  line_addr
);

    localparam int WORD_BYTES     = DATA_WIDTH / 8;
    localparam int WORDS_PER_LINE = LINE_BYTES / WORD_BYTES;
    localparam int NUM_LINES      = CACHE_BYTES / LINE_BYTES;
    localparam int NUM_SETS       = NUM_LINES / ASSOC;

    localparam int BYTE_OFFSET_W  = $clog2(WORD_BYTES);
    localparam int WORD_OFFSET_W  = $clog2(WORDS_PER_LINE);
    localparam int SET_INDEX_BITS = (NUM_SETS <= 1) ? 0 : $clog2(NUM_SETS);
    localparam int SET_INDEX_W    = (SET_INDEX_BITS == 0) ? 1 : SET_INDEX_BITS;

    localparam int LINE_OFFSET_W  = BYTE_OFFSET_W + WORD_OFFSET_W;
    localparam int TAG_WIDTH      = ADDR_WIDTH - LINE_OFFSET_W - SET_INDEX_BITS;
    localparam int LINE_ADDR_WIDTH = ADDR_WIDTH - LINE_OFFSET_W;

    assign byte_offset = addr[BYTE_OFFSET_W-1:0];

    assign word_offset = addr[BYTE_OFFSET_W +: WORD_OFFSET_W];

    generate
        if (SET_INDEX_BITS == 0) begin : GEN_FULLY_ASSOC
            assign index = '0;
            assign tag   = addr[ADDR_WIDTH-1:LINE_OFFSET_W];
        end
        else begin : GEN_INDEXED
            assign index = addr[LINE_OFFSET_W +: SET_INDEX_BITS];
            assign tag   = addr[ADDR_WIDTH-1 -: TAG_WIDTH];
        end
    endgenerate

    assign line_addr = addr[ADDR_WIDTH-1:LINE_OFFSET_W];

endmodule