// ============================================================
// 4-entry MSHR file
// Allocates, tracks, completes, and frees outstanding cache misses
// ============================================================

module MSHR_File #(
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int TAG_WIDTH       = 16,
    parameter int WAY_INDEX_W     = 2,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128
)(
    input  logic clk,
    input  logic rst,

    // ============================================================
    // ALLOCATE NEW MISS
    // ============================================================

    input  logic                       alloc_valid,
    output logic                       alloc_ready,

    input  logic [LINE_ADDR_WIDTH-1:0] alloc_line_addr,
    input  logic [SET_INDEX_W-1:0]     alloc_set_id,
    input  logic [WORD_OFFSET_W-1:0]   alloc_word_id,
    input  logic [TAG_WIDTH-1:0]       alloc_tag,
    input  logic [WAY_INDEX_W-1:0]     alloc_way,

    input  logic                       alloc_write,
    input  logic [DATA_WIDTH-1:0]      alloc_wdata,

    output logic [1:0]                 alloc_resp_id,

    // ============================================================
    // MEMORY FILL COMPLETION
    // ============================================================

    input  logic                       complete_valid,
    input  logic [1:0]                 complete_resp_id,
    input  logic [LINE_WIDTH-1:0]      complete_fill_line,

    // ============================================================
    // COMPLETED MISS RESPONSE OUTPUT
    // ============================================================

    output logic                       resp_valid,
    input  logic                       resp_ready,

    output logic [1:0]                 resp_id,
    output logic [LINE_ADDR_WIDTH-1:0] resp_line_addr,
    output logic [SET_INDEX_W-1:0]     resp_set_id,
    output logic [WORD_OFFSET_W-1:0]   resp_word_id,
    output logic [TAG_WIDTH-1:0]       resp_tag,
    output logic [WAY_INDEX_W-1:0]     resp_way,

    output logic                       resp_write,
    output logic [DATA_WIDTH-1:0]      resp_wdata,

    output logic [LINE_WIDTH-1:0]      resp_fill_line,

    // ============================================================
    // STATUS
    // ============================================================

    output logic                       full,
    output logic                       empty
);

    localparam int MSHR_COUNT = 4;

    logic [MSHR_COUNT-1:0] entry_valid;
    logic [MSHR_COUNT-1:0] entry_completed;

    logic [LINE_ADDR_WIDTH-1:0] entry_line_addr [MSHR_COUNT];
    logic [SET_INDEX_W-1:0]     entry_set_id    [MSHR_COUNT];
    logic [WORD_OFFSET_W-1:0]   entry_word_id   [MSHR_COUNT];
    logic [TAG_WIDTH-1:0]       entry_tag       [MSHR_COUNT];
    logic [WAY_INDEX_W-1:0]     entry_way       [MSHR_COUNT];

    logic [MSHR_COUNT-1:0]      entry_write;
    logic [DATA_WIDTH-1:0]      entry_wdata     [MSHR_COUNT];

    logic [1:0]                 entry_resp_id   [MSHR_COUNT];
    logic [LINE_WIDTH-1:0]      entry_fill_line [MSHR_COUNT];

    logic [MSHR_COUNT-1:0] alloc_onehot;
    logic [MSHR_COUNT-1:0] complete_onehot;
    logic [MSHR_COUNT-1:0] free_onehot;

    logic [1:0] alloc_idx;
    logic [1:0] resp_idx;

    logic alloc_fire;
    logic resp_fire;

    assign alloc_fire = alloc_valid && alloc_ready;
    assign resp_fire  = resp_valid  && resp_ready;

    // Find first free MSHR entry
    always_comb begin
        alloc_ready  = 1'b0;
        alloc_idx    = 2'b00;
        alloc_onehot = 4'b0000;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (!entry_valid[i] && !alloc_ready) begin
                alloc_ready       = 1'b1;
                alloc_idx         = i[1:0];
                alloc_onehot[i]   = 1'b1;
            end
        end
    end

    assign alloc_resp_id = alloc_idx;

    // Mark the selected MSHR complete when memory returns
    always_comb begin
        complete_onehot = 4'b0000;

        if (complete_valid) begin
            complete_onehot[complete_resp_id] = 1'b1;
        end
    end

    // Pick first completed MSHR to return to CPU
    always_comb begin
        resp_valid = 1'b0;
        resp_idx   = 2'b00;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (entry_valid[i] && entry_completed[i] && !resp_valid) begin
                resp_valid = 1'b1;
                resp_idx   = i[1:0];
            end
        end
    end

    always_comb begin
        free_onehot = 4'b0000;

        if (resp_fire) begin
            free_onehot[resp_idx] = 1'b1;
        end
    end

    assign resp_id        = entry_resp_id[resp_idx];
    assign resp_line_addr = entry_line_addr[resp_idx];
    assign resp_set_id    = entry_set_id[resp_idx];
    assign resp_word_id   = entry_word_id[resp_idx];
    assign resp_tag       = entry_tag[resp_idx];
    assign resp_way       = entry_way[resp_idx];

    assign resp_write     = entry_write[resp_idx];
    assign resp_wdata     = entry_wdata[resp_idx];

    assign resp_fill_line = entry_fill_line[resp_idx];

    assign full  = &entry_valid;
    assign empty = ~|entry_valid;

    genvar i;

    generate
        for (i = 0; i < MSHR_COUNT; i++) begin : GEN_MSHR_ENTRIES

            MSHR_Entry #(
                .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH),
                .SET_INDEX_W    (SET_INDEX_W),
                .WORD_OFFSET_W  (WORD_OFFSET_W),
                .TAG_WIDTH      (TAG_WIDTH),
                .WAY_INDEX_W    (WAY_INDEX_W),
                .DATA_WIDTH     (DATA_WIDTH),
                .LINE_WIDTH     (LINE_WIDTH)
            ) ENTRY (
                .clk               (clk),
                .rst               (rst),

                .alloc             (alloc_fire && alloc_onehot[i]),

                .alloc_line_addr   (alloc_line_addr),
                .alloc_set_id      (alloc_set_id),
                .alloc_word_id     (alloc_word_id),
                .alloc_tag         (alloc_tag),
                .alloc_way         (alloc_way),

                .alloc_write       (alloc_write),
                .alloc_wdata       (alloc_wdata),

                .alloc_resp_id     (i[1:0]),

                .complete          (complete_onehot[i]),
                .complete_fill_line(complete_fill_line),

                .free              (free_onehot[i]),

                .valid             (entry_valid[i]),

                .line_addr         (entry_line_addr[i]),
                .set_id            (entry_set_id[i]),
                .word_id           (entry_word_id[i]),
                .tag               (entry_tag[i]),
                .way               (entry_way[i]),

                .write             (entry_write[i]),
                .wdata             (entry_wdata[i]),

                .resp_id           (entry_resp_id[i]),

                .completed         (entry_completed[i]),
                .fill_line         (entry_fill_line[i])
            );

        end
    endgenerate

endmodule