// ============================================================
// 4-entry MSHR file with internal absorption FIFO
// Includes victim metadata for dirty eviction/writeback
// ============================================================

module MSHR_File #(
    parameter int ADDR_WIDTH      = 32,
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int TAG_WIDTH       = 16,
    parameter int WAY_INDEX_W     = 2,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int MSHR_ID_WIDTH   = 2,
    parameter int MISSQ_DEPTH     = 16
)(
    input  logic clk,
    input  logic rst,

    input  logic                       alloc_valid,
    output logic                       alloc_ready,

    input  logic [LINE_ADDR_WIDTH-1:0] alloc_line_addr,
    input  logic [SET_INDEX_W-1:0]     alloc_set_id,
    input  logic [WORD_OFFSET_W-1:0]   alloc_word_id,
    input  logic [TAG_WIDTH-1:0]       alloc_tag,
    input  logic [WAY_INDEX_W-1:0]     alloc_way,

    input  logic                       alloc_write,
    input  logic [DATA_WIDTH-1:0]      alloc_wdata,
    input  logic [CPU_ID_WIDTH-1:0]    alloc_cpu_req_id,

    input  logic                       alloc_victim_valid,
    input  logic                       alloc_victim_dirty,
    input  logic [TAG_WIDTH-1:0]       alloc_victim_tag,
    input  logic [LINE_WIDTH-1:0]      alloc_victim_line,

    output logic [MSHR_ID_WIDTH-1:0]   alloc_mshr_id,

    input  logic [3:0]                 issue_done,

    input  logic                       mem_resp_valid,
    input  logic [MSHR_ID_WIDTH-1:0]   mem_resp_id,
    input  logic [DATA_WIDTH-1:0]      mem_resp_rdata,

    output logic                       miss_valid,
    output logic [CPU_ID_WIDTH-1:0]    miss_id,

    output logic                       refill_wen,
    output logic [SET_INDEX_W-1:0]     refill_set_id,
    output logic [TAG_WIDTH-1:0]       refill_tag,
    output logic [WAY_INDEX_W-1:0]     refill_way,
    output logic                       refill_dirty,
    output logic [LINE_WIDTH-1:0]      refill_line,

    output logic [3:0]                 issue_pending,
    output logic [LINE_ADDR_WIDTH-1:0] issue_line_addr [4],
    output logic [WORD_OFFSET_W-1:0]   issue_word_id   [4],

    output logic [3:0]                 req_valid,
    output logic [3:0]                 req_write,
    output logic [ADDR_WIDTH-1:0]      req_addr  [4],
    output logic [DATA_WIDTH-1:0]      req_wdata [4],
    output logic [MSHR_ID_WIDTH-1:0]   req_id    [4],

    output logic                       full,
    output logic                       empty
);

    localparam int MSHR_COUNT = 4;

    typedef struct packed {
        logic [LINE_ADDR_WIDTH-1:0] line_addr;
        logic [SET_INDEX_W-1:0]     set_id;
        logic [WORD_OFFSET_W-1:0]   word_id;
        logic [TAG_WIDTH-1:0]       tag;
        logic [WAY_INDEX_W-1:0]     way;
        logic                       write;
        logic [DATA_WIDTH-1:0]      wdata;
        logic [CPU_ID_WIDTH-1:0]    cpu_req_id;

        logic                       victim_valid;
        logic                       victim_dirty;
        logic [TAG_WIDTH-1:0]       victim_tag;
        logic [LINE_WIDTH-1:0]      victim_line;
    } missq_entry_t;

    localparam int MISSQ_WIDTH = $bits(missq_entry_t);

    missq_entry_t missq_wentry;
    missq_entry_t missq_rentry;
    missq_entry_t dispatch_entry_r;

    logic [MISSQ_WIDTH-1:0] missq_wdata;
    logic [MISSQ_WIDTH-1:0] missq_rdata;

    logic missq_full;
    logic missq_almost_full;
    logic missq_empty;
    logic missq_wr_en;
    logic missq_rd_en;
    logic missq_rd_valid;
    logic missq_read_pending;

    logic dispatch_valid_r;

    logic [MSHR_COUNT-1:0] entry_valid;
    logic [MSHR_COUNT-1:0] entry_issue_pending;
    logic [MSHR_COUNT-1:0] entry_refill_wen;
    logic [MSHR_COUNT-1:0] entry_miss_valid;

    logic [LINE_ADDR_WIDTH-1:0] entry_line_addr [MSHR_COUNT];
    logic [SET_INDEX_W-1:0]     entry_set_id    [MSHR_COUNT];
    logic [WORD_OFFSET_W-1:0]   entry_word_id   [MSHR_COUNT];
    logic [TAG_WIDTH-1:0]       entry_tag       [MSHR_COUNT];
    logic [WAY_INDEX_W-1:0]     entry_way       [MSHR_COUNT];

    logic [MSHR_COUNT-1:0]      entry_dirty;
    logic [CPU_ID_WIDTH-1:0]    entry_cpu_req_id [MSHR_COUNT];
    logic [CPU_ID_WIDTH-1:0]    entry_miss_id    [MSHR_COUNT];
    logic [MSHR_ID_WIDTH-1:0]   entry_mshr_id    [MSHR_COUNT];
    logic [LINE_WIDTH-1:0]      entry_fill_line  [MSHR_COUNT];

    logic [MSHR_COUNT-1:0]      entry_alloc_onehot;
    logic [MSHR_COUNT-1:0]      mshr_resp_valid;

    logic [DATA_WIDTH-1:0]      mshr_resp_data;
    logic [MSHR_ID_WIDTH-1:0]   entry_alloc_idx;

    logic entry_alloc_ready;
    logic entry_alloc_fire;

    logic miss_valid_raw;

    assign missq_wentry.line_addr     = alloc_line_addr;
    assign missq_wentry.set_id        = alloc_set_id;
    assign missq_wentry.word_id       = alloc_word_id;
    assign missq_wentry.tag           = alloc_tag;
    assign missq_wentry.way           = alloc_way;
    assign missq_wentry.write         = alloc_write;
    assign missq_wentry.wdata         = alloc_wdata;
    assign missq_wentry.cpu_req_id    = alloc_cpu_req_id;

    assign missq_wentry.victim_valid  = alloc_victim_valid;
    assign missq_wentry.victim_dirty  = alloc_victim_dirty;
    assign missq_wentry.victim_tag    = alloc_victim_tag;
    assign missq_wentry.victim_line   = alloc_victim_line;

    assign missq_wdata  = missq_wentry;
    assign missq_rentry = missq_rdata;

    assign alloc_ready = !missq_almost_full;
    assign missq_wr_en = alloc_valid && alloc_ready;

    FIFO_Almost #(
        .WIDTH          (MISSQ_WIDTH),
        .DEPTH          (MISSQ_DEPTH),
        .ALMOST_FULL_GAP(5)
    ) MISS_QUEUE (
        .clk        (clk),
        .rst        (rst),
        .full       (missq_full),
        .almost_full(missq_almost_full),
        .wr_en      (missq_wr_en),
        .wr_data    (missq_wdata),
        .empty      (missq_empty),
        .rd_en      (missq_rd_en),
        .rd_valid   (missq_rd_valid),
        .rd_data    (missq_rdata)
    );

    assign missq_rd_en = !missq_empty &&
                         !dispatch_valid_r &&
                         !missq_read_pending;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            missq_read_pending <= 1'b0;
        end
        else begin
            if (missq_rd_en) begin
                missq_read_pending <= 1'b1;
            end
            else if (missq_rd_valid) begin
                missq_read_pending <= 1'b0;
            end
        end
    end

    assign entry_alloc_fire = dispatch_valid_r && entry_alloc_ready;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dispatch_valid_r <= 1'b0;
            dispatch_entry_r <= '0;
        end
        else begin
            if (missq_rd_valid) begin
                dispatch_valid_r <= 1'b1;
                dispatch_entry_r <= missq_rentry;
            end
            else if (entry_alloc_fire) begin
                dispatch_valid_r <= 1'b0;
            end
        end
    end

    always_comb begin
        entry_alloc_ready  = 1'b0;
        entry_alloc_idx    = '0;
        entry_alloc_onehot = '0;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (!entry_valid[i] && !entry_alloc_ready) begin
                entry_alloc_ready     = 1'b1;
                entry_alloc_idx       = i[MSHR_ID_WIDTH-1:0];
                entry_alloc_onehot[i] = 1'b1;
            end
        end
    end

    assign alloc_mshr_id = entry_alloc_idx;

    MSHR_Response_DeMux #(
        .MSHR_COUNT   (MSHR_COUNT),
        .DATA_WIDTH   (DATA_WIDTH),
        .MSHR_ID_WIDTH(MSHR_ID_WIDTH)
    ) RESP_DEMUX (
        .clk            (clk),
        .rst            (rst),
        .mem_resp_valid (mem_resp_valid),
        .mem_resp_id    (mem_resp_id),
        .mem_resp_rdata (mem_resp_rdata),
        .mshr_resp_valid(mshr_resp_valid),
        .mshr_resp_data (mshr_resp_data)
    );

    assign miss_valid_raw = |entry_miss_valid;

    MSHR_Response_Mux #(
        .MSHR_COUNT  (MSHR_COUNT),
        .CPU_ID_WIDTH(CPU_ID_WIDTH)
    ) RESP_MUX (
        .clk             (clk),
        .entry_miss_valid(entry_miss_valid),
        .entry_miss_id   (entry_miss_id),
        .miss_id         (miss_id)
    );

    Delay_r #(
        .D_WIDTH(1),
        .DELAY  (1)
    ) MISS_VALID_DELAY (
        .clk (clk),
        .rst (rst),
        .din (miss_valid_raw),
        .dout(miss_valid)
    );

    MSHR_Mux #(
        .MSHR_COUNT (MSHR_COUNT),
        .SET_INDEX_W(SET_INDEX_W),
        .TAG_WIDTH  (TAG_WIDTH),
        .WAY_INDEX_W(WAY_INDEX_W),
        .LINE_WIDTH (LINE_WIDTH)
    ) REFILL_MUX (
        .clk             (clk),
        .rst             (rst),
        .entry_refill_wen(entry_refill_wen),
        .entry_set_id    (entry_set_id),
        .entry_tag       (entry_tag),
        .entry_way       (entry_way),
        .entry_dirty     (entry_dirty),
        .entry_fill_line (entry_fill_line),
        .refill_wen      (refill_wen),
        .refill_set_id   (refill_set_id),
        .refill_tag      (refill_tag),
        .refill_way      (refill_way),
        .refill_dirty    (refill_dirty),
        .refill_line     (refill_line)
    );

    assign issue_pending = entry_issue_pending;

    always_comb begin
        for (int i = 0; i < MSHR_COUNT; i++) begin
            issue_line_addr[i] = entry_line_addr[i];
            issue_word_id[i]   = entry_word_id[i];
        end
    end

    assign full  = missq_almost_full;
    assign empty = missq_empty && !dispatch_valid_r && ~|entry_valid;

    genvar i;

    generate
        for (i = 0; i < MSHR_COUNT; i++) begin : GEN_MSHR_ENTRIES

            MSHR_Entry #(
                .ADDR_WIDTH     (ADDR_WIDTH),
                .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH),
                .SET_INDEX_W    (SET_INDEX_W),
                .WORD_OFFSET_W  (WORD_OFFSET_W),
                .TAG_WIDTH      (TAG_WIDTH),
                .WAY_INDEX_W    (WAY_INDEX_W),
                .DATA_WIDTH     (DATA_WIDTH),
                .LINE_WIDTH     (LINE_WIDTH),
                .CPU_ID_WIDTH   (CPU_ID_WIDTH),
                .MSHR_ID_WIDTH  (MSHR_ID_WIDTH)
            ) ENTRY (
                .clk                (clk),
                .rst                (rst),

                .alloc              (entry_alloc_fire && entry_alloc_onehot[i]),

                .alloc_line_addr    (dispatch_entry_r.line_addr),
                .alloc_set_id       (dispatch_entry_r.set_id),
                .alloc_word_id      (dispatch_entry_r.word_id),
                .alloc_tag          (dispatch_entry_r.tag),
                .alloc_way          (dispatch_entry_r.way),

                .alloc_write        (dispatch_entry_r.write),
                .alloc_wdata        (dispatch_entry_r.wdata),

                .alloc_cpu_req_id   (dispatch_entry_r.cpu_req_id),
                .alloc_mshr_id      (i[MSHR_ID_WIDTH-1:0]),

                .alloc_victim_valid (dispatch_entry_r.victim_valid),
                .alloc_victim_dirty (dispatch_entry_r.victim_dirty),
                .alloc_victim_tag   (dispatch_entry_r.victim_tag),
                .alloc_victim_line  (dispatch_entry_r.victim_line),

                .issue_done         (issue_done[i]),

                .resp_valid         (mshr_resp_valid[i]),
                .resp_data          (mshr_resp_data),

                .valid              (entry_valid[i]),
                .issue_pending      (entry_issue_pending[i]),

                .req_valid          (req_valid[i]),
                .req_write          (req_write[i]),
                .req_addr           (req_addr[i]),
                .req_wdata          (req_wdata[i]),
                .req_mshr_id        (req_id[i]),

                .line_addr          (entry_line_addr[i]),
                .set_id             (entry_set_id[i]),
                .word_id            (entry_word_id[i]),
                .tag                (entry_tag[i]),
                .way                (entry_way[i]),

                .dirty              (entry_dirty[i]),

                .cpu_req_id         (entry_cpu_req_id[i]),
                .mshr_id            (entry_mshr_id[i]),

                .miss_valid         (entry_miss_valid[i]),
                .miss_id            (entry_miss_id[i]),

                .refill_wen         (entry_refill_wen[i]),
                .fill_line          (entry_fill_line[i])
            );

        end
    endgenerate

endmodule