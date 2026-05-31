// ============================================================
// Single MSHR entry
// Owns miss metadata, optional dirty-victim writeback,
// refill request issue, response collection, critical-word pulse,
// and full-line refill write pulse.
// ============================================================

module MSHR_Entry #(
    parameter int ADDR_WIDTH      = 32,
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int TAG_WIDTH       = 16,
    parameter int WAY_INDEX_W     = 2,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int MSHR_ID_WIDTH   = 2
)(
    input  logic clk,
    input  logic rst,

    input  logic alloc,

    input  logic [LINE_ADDR_WIDTH-1:0] alloc_line_addr,
    input  logic [SET_INDEX_W-1:0]     alloc_set_id,
    input  logic [WORD_OFFSET_W-1:0]   alloc_word_id,
    input  logic [TAG_WIDTH-1:0]       alloc_tag,
    input  logic [WAY_INDEX_W-1:0]     alloc_way,

    input  logic                       alloc_write,
    input  logic [DATA_WIDTH-1:0]      alloc_wdata,

    input  logic [CPU_ID_WIDTH-1:0]    alloc_cpu_req_id,
    input  logic [MSHR_ID_WIDTH-1:0]   alloc_mshr_id,

    input  logic                       alloc_victim_valid,
    input  logic                       alloc_victim_dirty,
    input  logic [TAG_WIDTH-1:0]       alloc_victim_tag,
    input  logic [LINE_WIDTH-1:0]      alloc_victim_line,

    input  logic                       issue_done,

    input  logic                       resp_valid,
    input  logic [DATA_WIDTH-1:0]      resp_data,

    output logic                       valid,
    output logic                       issue_pending,

    output logic                       req_valid,
    output logic                       req_write,
    output logic [ADDR_WIDTH-1:0]      req_addr,
    output logic [DATA_WIDTH-1:0]      req_wdata,
    output logic [MSHR_ID_WIDTH-1:0]   req_mshr_id,

    output logic [LINE_ADDR_WIDTH-1:0] line_addr,
    output logic [SET_INDEX_W-1:0]     set_id,
    output logic [WORD_OFFSET_W-1:0]   word_id,
    output logic [TAG_WIDTH-1:0]       tag,
    output logic [WAY_INDEX_W-1:0]     way,

    output logic                       dirty,

    output logic [CPU_ID_WIDTH-1:0]    cpu_req_id,
    output logic [MSHR_ID_WIDTH-1:0]   mshr_id,

    output logic                       miss_valid,
    output logic [CPU_ID_WIDTH-1:0]    miss_id,

    output logic                       refill_wen,
    output logic [LINE_WIDTH-1:0]      fill_line
);

    localparam int WORDS_PER_LINE = LINE_WIDTH / DATA_WIDTH;
    localparam int BEAT_COUNT_W   = (WORDS_PER_LINE <= 1) ? 1 : $clog2(WORDS_PER_LINE);

    typedef enum logic [2:0] {
        S_IDLE,
        S_ISSUE_W,
        S_ISSUE_R,
        S_WAIT_R,
        S_REFILL
    } state_t;

    state_t state;

    logic [BEAT_COUNT_W-1:0] wb_count;
    logic [BEAT_COUNT_W-1:0] issue_count;
    logic [BEAT_COUNT_W-1:0] recv_count;

    logic [WORD_OFFSET_W-1:0] miss_word_id_r;
    logic [WORD_OFFSET_W-1:0] wb_word_id;
    logic [WORD_OFFSET_W-1:0] issue_word_id;
    logic [WORD_OFFSET_W-1:0] recv_word_id;

    logic write_r;
    logic [DATA_WIDTH-1:0] wdata_r;

    logic victim_valid_r;
    logic victim_dirty_r;
    logic [TAG_WIDTH-1:0]  victim_tag_r;
    logic [LINE_WIDTH-1:0] victim_line_r;
    logic [LINE_ADDR_WIDTH-1:0] victim_line_addr;

    logic [DATA_WIDTH-1:0] beat_data;
    logic [LINE_WIDTH-1:0] fill_line_r;
    logic [LINE_WIDTH-1:0] fill_line_next;

    logic miss_valid_r;
    logic refill_wen_r;

    assign valid         = (state != S_IDLE);
    assign issue_pending = (state == S_ISSUE_W) || (state == S_ISSUE_R);

    assign wb_word_id    = wb_count[WORD_OFFSET_W-1:0];
    assign issue_word_id = miss_word_id_r + issue_count[WORD_OFFSET_W-1:0];
    assign recv_word_id  = miss_word_id_r + recv_count [WORD_OFFSET_W-1:0];

    assign victim_line_addr = {victim_tag_r, set_id};

    assign word_id    = issue_word_id;
    assign fill_line  = fill_line_r;
    assign miss_valid = miss_valid_r;
    assign miss_id    = cpu_req_id;
    assign refill_wen = refill_wen_r;

    assign dirty = write_r;

    assign req_valid   = (state == S_ISSUE_W) || (state == S_ISSUE_R);
    assign req_write   = (state == S_ISSUE_W);
    assign req_mshr_id = mshr_id;

    assign req_addr =
        (state == S_ISSUE_W)
        ? {{(ADDR_WIDTH-LINE_ADDR_WIDTH-WORD_OFFSET_W){1'b0}},
           victim_line_addr,
           wb_word_id}
        : {{(ADDR_WIDTH-LINE_ADDR_WIDTH-WORD_OFFSET_W){1'b0}},
           line_addr,
           issue_word_id};

    assign req_wdata =
        (state == S_ISSUE_W)
        ? victim_line_r[wb_word_id * DATA_WIDTH +: DATA_WIDTH]
        : '0;

    assign beat_data =
        (write_r && (recv_word_id == miss_word_id_r)) ? wdata_r : resp_data;

    always_comb begin
        fill_line_next = fill_line_r;
        fill_line_next[recv_word_id * DATA_WIDTH +: DATA_WIDTH] = beat_data;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= S_IDLE;
            wb_count     <= '0;
            issue_count  <= '0;
            recv_count   <= '0;
            miss_valid_r <= 1'b0;
            refill_wen_r <= 1'b0;
        end
        else begin
            miss_valid_r <= 1'b0;
            refill_wen_r <= 1'b0;

            case (state)

                S_IDLE: begin
                    if (alloc) begin
                        line_addr      <= alloc_line_addr;
                        set_id         <= alloc_set_id;
                        miss_word_id_r <= alloc_word_id;
                        tag            <= alloc_tag;
                        way            <= alloc_way;

                        write_r        <= alloc_write;
                        wdata_r        <= alloc_wdata;

                        cpu_req_id     <= alloc_cpu_req_id;
                        mshr_id        <= alloc_mshr_id;

                        victim_valid_r <= alloc_victim_valid;
                        victim_dirty_r <= alloc_victim_dirty;
                        victim_tag_r   <= alloc_victim_tag;
                        victim_line_r  <= alloc_victim_line;

                        wb_count       <= '0;
                        issue_count    <= '0;
                        recv_count     <= '0;
                        fill_line_r    <= '0;

                        if (alloc_victim_valid && alloc_victim_dirty) begin
                            state <= S_ISSUE_W;
                        end
                        else begin
                            state <= S_ISSUE_R;
                        end
                    end
                end

                S_ISSUE_W: begin
                    if (issue_done) begin
                        if (wb_count == WORDS_PER_LINE-1) begin
                            wb_count <= '0;
                            state    <= S_ISSUE_R;
                        end
                        else begin
                            wb_count <= wb_count + 1'b1;
                        end
                    end
                end

                S_ISSUE_R: begin
                    if (issue_done) begin
                        if (issue_count == WORDS_PER_LINE-1) begin
                            issue_count <= '0;
                            state       <= S_WAIT_R;
                        end
                        else begin
                            issue_count <= issue_count + 1'b1;
                        end
                    end
                end

                S_WAIT_R: begin
                    if (resp_valid) begin
                        fill_line_r <= fill_line_next;

                        if (recv_count == '0) begin
                            miss_valid_r <= 1'b1;
                        end

                        if (recv_count == WORDS_PER_LINE-1) begin
                            recv_count   <= '0;
                            refill_wen_r <= 1'b1;
                            state        <= S_REFILL;
                        end
                        else begin
                            recv_count <= recv_count + 1'b1;
                        end
                    end
                end

                S_REFILL: begin
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule