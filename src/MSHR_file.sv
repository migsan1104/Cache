// ============================================================
// 4-entry MSHR file with internal absorption FIFO
// Frontend misses enqueue into FIFO, MSHR entries allocate from FIFO
// ============================================================

module MSHR_File #(
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

    // ============================================================
    // MISS ENQUEUE FROM CACHE FRONTEND
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
    input  logic [CPU_ID_WIDTH-1:0]    alloc_cpu_req_id,

    output logic [MSHR_ID_WIDTH-1:0]   alloc_mshr_id,

    input  logic                       issue_done_valid,
    input  logic [MSHR_ID_WIDTH-1:0]   issue_done_mshr_id,

    input  logic                       complete_valid,
    input  logic [MSHR_ID_WIDTH-1:0]   complete_mshr_id,
    input  logic [DATA_WIDTH-1:0]      complete_word_data,

    output logic                       resp_valid,
    input  logic                       resp_ready,

    output logic [CPU_ID_WIDTH-1:0]    resp_cpu_req_id,
    output logic [MSHR_ID_WIDTH-1:0]   resp_mshr_id,

    output logic [LINE_ADDR_WIDTH-1:0] resp_line_addr,
    output logic [SET_INDEX_W-1:0]     resp_set_id,
    output logic [WORD_OFFSET_W-1:0]   resp_word_id,
    output logic [TAG_WIDTH-1:0]       resp_tag,
    output logic [WAY_INDEX_W-1:0]     resp_way,

    output logic                       resp_write,
    output logic [DATA_WIDTH-1:0]      resp_wdata,
    output logic [LINE_WIDTH-1:0]      resp_fill_line,

    output logic [3:0]                 issue_pending,
    output logic [LINE_ADDR_WIDTH-1:0] issue_line_addr [4],
    output logic [WORD_OFFSET_W-1:0]   issue_word_id   [4],

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
    logic [MSHR_COUNT-1:0] entry_completed;

    logic [LINE_ADDR_WIDTH-1:0] entry_line_addr [MSHR_COUNT];
    logic [SET_INDEX_W-1:0]     entry_set_id    [MSHR_COUNT];
    logic [WORD_OFFSET_W-1:0]   entry_word_id   [MSHR_COUNT];
    logic [TAG_WIDTH-1:0]       entry_tag       [MSHR_COUNT];
    logic [WAY_INDEX_W-1:0]     entry_way       [MSHR_COUNT];

    logic [MSHR_COUNT-1:0]      entry_write;
    logic [DATA_WIDTH-1:0]      entry_wdata     [MSHR_COUNT];

    logic [CPU_ID_WIDTH-1:0]    entry_cpu_req_id[MSHR_COUNT];
    logic [MSHR_ID_WIDTH-1:0]   entry_mshr_id   [MSHR_COUNT];

    logic [LINE_WIDTH-1:0]      entry_fill_line [MSHR_COUNT];

    logic [MSHR_COUNT-1:0] entry_alloc_onehot;
    logic [MSHR_COUNT-1:0] issue_done_onehot;
    logic [MSHR_COUNT-1:0] complete_onehot;
    logic [MSHR_COUNT-1:0] free_onehot;

    logic [MSHR_ID_WIDTH-1:0] entry_alloc_idx;
    logic [MSHR_ID_WIDTH-1:0] resp_idx;

    logic entry_alloc_ready;
    logic entry_alloc_fire;
    logic resp_fire;

    // ============================================================
    // Miss absorption FIFO
    // ============================================================

    assign missq_wentry.line_addr  = alloc_line_addr;
    assign missq_wentry.set_id     = alloc_set_id;
    assign missq_wentry.word_id    = alloc_word_id;
    assign missq_wentry.tag        = alloc_tag;
    assign missq_wentry.way        = alloc_way;
    assign missq_wentry.write      = alloc_write;
    assign missq_wentry.wdata      = alloc_wdata;
    assign missq_wentry.cpu_req_id = alloc_cpu_req_id;

    assign missq_wdata = missq_wentry;
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

    assign missq_rd_en = !missq_empty && !dispatch_valid_r && !missq_read_pending;

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

    // ============================================================
    // FIFO output holding register
    // ============================================================

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

    // ============================================================
    // Find first free MSHR entry
    // ============================================================

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

    assign resp_fire = resp_valid && resp_ready;

    // ============================================================
    // Route scheduler issue-done pulse
    // ============================================================

    always_comb begin
        issue_done_onehot = '0;

        if (issue_done_valid) begin
            issue_done_onehot[issue_done_mshr_id] = 1'b1;
        end
    end

    // ============================================================
    // Route returned word beat
    // ============================================================

    always_comb begin
        complete_onehot = '0;

        if (complete_valid) begin
            complete_onehot[complete_mshr_id] = 1'b1;
        end
    end

    // ============================================================
    // Pick first completed MSHR for response/refill
    // ============================================================

    always_comb begin
        resp_valid = 1'b0;
        resp_idx   = '0;

        for (int i = 0; i < MSHR_COUNT; i++) begin
            if (entry_valid[i] && entry_completed[i] && !resp_valid) begin
                resp_valid = 1'b1;
                resp_idx   = i[MSHR_ID_WIDTH-1:0];
            end
        end
    end

    always_comb begin
        free_onehot = '0;

        if (resp_fire) begin
            free_onehot[resp_idx] = 1'b1;
        end
    end

    // ============================================================
    // Response output mux
    // ============================================================

    assign resp_cpu_req_id = entry_cpu_req_id[resp_idx];
    assign resp_mshr_id    = entry_mshr_id[resp_idx];

    assign resp_line_addr  = entry_line_addr[resp_idx];
    assign resp_set_id     = entry_set_id[resp_idx];
    assign resp_word_id    = entry_word_id[resp_idx];
    assign resp_tag        = entry_tag[resp_idx];
    assign resp_way        = entry_way[resp_idx];

    assign resp_write      = entry_write[resp_idx];
    assign resp_wdata      = entry_wdata[resp_idx];
    assign resp_fill_line  = entry_fill_line[resp_idx];

    // ============================================================
    // Scheduler outputs
    // ============================================================

    assign issue_pending = entry_issue_pending;

    always_comb begin
        for (int i = 0; i < MSHR_COUNT; i++) begin
            issue_line_addr[i] = entry_line_addr[i];
            issue_word_id[i]   = entry_word_id[i];
        end
    end

    assign full  = missq_almost_full;
    assign empty = missq_empty && !dispatch_valid_r && ~|entry_valid;

    // ============================================================
    // Entries
    // ============================================================

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

                .issue_done         (issue_done_onehot[i]),

                .complete           (complete_onehot[i]),
                .complete_word_data (complete_word_data),

                .free               (free_onehot[i]),

                .valid              (entry_valid[i]),
                .issue_pending      (entry_issue_pending[i]),

                .line_addr          (entry_line_addr[i]),
                .set_id             (entry_set_id[i]),
                .word_id            (entry_word_id[i]),
                .tag                (entry_tag[i]),
                .way                (entry_way[i]),

                .write              (entry_write[i]),
                .wdata              (entry_wdata[i]),

                .cpu_req_id         (entry_cpu_req_id[i]),
                .mshr_id            (entry_mshr_id[i]),

                .completed          (entry_completed[i]),
                .fill_line          (entry_fill_line[i])
            );

        end
    endgenerate

endmodule