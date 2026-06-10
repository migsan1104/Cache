// ============================================================
// Single MSHR entry - two-process FSM
// Write miss fetches only other 3 words.
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
        S_ISSUE_R_R,
        S_ISSUE_R_W,
        S_WAIT_R_R,
        S_WAIT_R_W,
        S_REFILL
    } state_t;

    state_t state, state_n;

    logic [BEAT_COUNT_W-1:0] wb_count, wb_count_n;
    logic [BEAT_COUNT_W-1:0] issue_count, issue_count_n;
    logic [BEAT_COUNT_W-1:0] recv_count, recv_count_n;

    logic [WORD_OFFSET_W-1:0] miss_word_id_r, miss_word_id_n;
    logic [WORD_OFFSET_W-1:0] wb_word_id;
    logic [WORD_OFFSET_W-1:0] read_issue_word_id;
    logic [WORD_OFFSET_W-1:0] write_issue_word_id;
    logic [WORD_OFFSET_W-1:0] read_recv_word_id;
    logic [WORD_OFFSET_W-1:0] write_recv_word_id;
    logic [WORD_OFFSET_W-1:0] active_issue_word_id;
    logic [WORD_OFFSET_W-1:0] active_recv_word_id;

    logic write_r, write_n;
    logic [DATA_WIDTH-1:0] wdata_r, wdata_n;

    logic victim_valid_r, victim_valid_n;
    logic victim_dirty_r, victim_dirty_n;
    logic [TAG_WIDTH-1:0]  victim_tag_r, victim_tag_n;
    logic [LINE_WIDTH-1:0] victim_line_r, victim_line_n;
    logic [LINE_ADDR_WIDTH-1:0] victim_line_addr;

    logic [LINE_ADDR_WIDTH-1:0] line_addr_n;
    logic [SET_INDEX_W-1:0]     set_id_n;
    logic [TAG_WIDTH-1:0]       tag_n;
    logic [WAY_INDEX_W-1:0]     way_n;
    logic [CPU_ID_WIDTH-1:0]    cpu_req_id_n;
    logic [MSHR_ID_WIDTH-1:0]   mshr_id_n;

    logic [LINE_WIDTH-1:0] fill_line_r, fill_line_n;

    logic miss_valid_r, miss_valid_n;
    logic refill_wen_r, refill_wen_n;

    assign wb_word_id = wb_count[WORD_OFFSET_W-1:0];

    assign read_issue_word_id = issue_count[WORD_OFFSET_W-1:0];
    assign read_recv_word_id  = recv_count [WORD_OFFSET_W-1:0];

    assign write_issue_word_id =
        (issue_count[WORD_OFFSET_W-1:0] >= miss_word_id_r)
        ? issue_count[WORD_OFFSET_W-1:0] + 1'b1
        : issue_count[WORD_OFFSET_W-1:0];

    assign write_recv_word_id =
        (recv_count[WORD_OFFSET_W-1:0] >= miss_word_id_r)
        ? recv_count[WORD_OFFSET_W-1:0] + 1'b1
        : recv_count[WORD_OFFSET_W-1:0];

    assign active_issue_word_id =
        (state == S_ISSUE_R_W) ? write_issue_word_id : read_issue_word_id;

    assign active_recv_word_id =
        (state == S_WAIT_R_W) ? write_recv_word_id : read_recv_word_id;

    assign victim_line_addr = {victim_tag_r, set_id};

    assign valid = (state != S_IDLE);

    assign issue_pending =
        (state == S_ISSUE_W)   ||
        (state == S_ISSUE_R_R) ||
        (state == S_ISSUE_R_W);

    assign req_valid =
        (state == S_ISSUE_W)   ||
        (state == S_ISSUE_R_R) ||
        (state == S_ISSUE_R_W);

    assign req_write   = (state == S_ISSUE_W);
    assign req_mshr_id = mshr_id;

    assign req_addr =
        (state == S_ISSUE_W)
        ? {{(ADDR_WIDTH-LINE_ADDR_WIDTH-WORD_OFFSET_W){1'b0}},
           victim_line_addr,
           wb_word_id}
        : {{(ADDR_WIDTH-LINE_ADDR_WIDTH-WORD_OFFSET_W){1'b0}},
           line_addr,
           active_issue_word_id};

    assign req_wdata =
        (state == S_ISSUE_W)
        ? victim_line_r[wb_word_id * DATA_WIDTH +: DATA_WIDTH]
        : '0;

    assign word_id    = active_issue_word_id;
    assign dirty      = write_r;
    assign fill_line  = fill_line_r;
    assign miss_valid = miss_valid_r;
    assign miss_id    = cpu_req_id;
    assign refill_wen = refill_wen_r;

    always_comb begin
        state_n        = state;

        wb_count_n     = wb_count;
        issue_count_n  = issue_count;
        recv_count_n   = recv_count;

        line_addr_n    = line_addr;
        set_id_n       = set_id;
        miss_word_id_n = miss_word_id_r;
        tag_n          = tag;
        way_n          = way;

        write_n        = write_r;
        wdata_n        = wdata_r;

        cpu_req_id_n   = cpu_req_id;
        mshr_id_n      = mshr_id;

        victim_valid_n = victim_valid_r;
        victim_dirty_n = victim_dirty_r;
        victim_tag_n   = victim_tag_r;
        victim_line_n  = victim_line_r;

        fill_line_n    = fill_line_r;

        miss_valid_n   = 1'b0;
        refill_wen_n   = 1'b0;

        case (state)

            S_IDLE: begin
                if (alloc) begin
                    line_addr_n    = alloc_line_addr;
                    set_id_n       = alloc_set_id;
                    miss_word_id_n = alloc_word_id;
                    tag_n          = alloc_tag;
                    way_n          = alloc_way;

                    write_n        = alloc_write;
                    wdata_n        = alloc_wdata;

                    cpu_req_id_n   = alloc_cpu_req_id;
                    mshr_id_n      = alloc_mshr_id;

                    victim_valid_n = alloc_victim_valid;
                    victim_dirty_n = alloc_victim_dirty;
                    victim_tag_n   = alloc_victim_tag;
                    victim_line_n  = alloc_victim_line;

                    wb_count_n     = '0;
                    issue_count_n  = '0;
                    recv_count_n   = '0;
                    fill_line_n    = '0;

                    if (alloc_write) begin
                        fill_line_n[alloc_word_id * DATA_WIDTH +: DATA_WIDTH] = alloc_wdata;
                    end

                    if (alloc_victim_valid && alloc_victim_dirty)
                        state_n = S_ISSUE_W;
                    else if (alloc_write)
                        state_n = S_ISSUE_R_W;
                    else
                        state_n = S_ISSUE_R_R;
                end
            end

            S_ISSUE_W: begin
                if (issue_done) begin
                    if (wb_count == WORDS_PER_LINE-1) begin
                        wb_count_n = '0;
                        state_n    = write_r ? S_ISSUE_R_W : S_ISSUE_R_R;
                    end
                    else begin
                        wb_count_n = wb_count + 1'b1;
                    end
                end
            end

            S_ISSUE_R_R: begin
                if (issue_done) begin
                    if (issue_count == WORDS_PER_LINE-1) begin
                        issue_count_n = '0;
                        state_n       = S_WAIT_R_R;
                    end
                    else begin
                        issue_count_n = issue_count + 1'b1;
                    end
                end
            end

            S_ISSUE_R_W: begin
                if (issue_done) begin
                    if (issue_count == WORDS_PER_LINE-2) begin
                        issue_count_n = '0;
                        state_n       = S_WAIT_R_W;
                    end
                    else begin
                        issue_count_n = issue_count + 1'b1;
                    end
                end
            end

            S_WAIT_R_R: begin
                if (resp_valid) begin
                    fill_line_n[active_recv_word_id * DATA_WIDTH +: DATA_WIDTH] = resp_data;

                    if (recv_count == '0)
                        miss_valid_n = 1'b1;

                    if (recv_count == WORDS_PER_LINE-1) begin
                        recv_count_n = '0;
                        refill_wen_n = 1'b1;
                        state_n      = S_REFILL;
                    end
                    else begin
                        recv_count_n = recv_count + 1'b1;
                    end
                end
            end

            S_WAIT_R_W: begin
                if (resp_valid) begin
                    fill_line_n[active_recv_word_id * DATA_WIDTH +: DATA_WIDTH] = resp_data;

                    if (recv_count == '0)
                        miss_valid_n = 1'b1;

                    if (recv_count == WORDS_PER_LINE-2) begin
                        recv_count_n = '0;
                        refill_wen_n = 1'b1;
                        state_n      = S_REFILL;
                    end
                    else begin
                        recv_count_n = recv_count + 1'b1;
                    end
                end
            end

            S_REFILL: begin
                state_n = S_IDLE;
            end

            default: begin
                state_n = S_IDLE;
            end

        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= S_IDLE;

            wb_count       <= '0;
            issue_count    <= '0;
            recv_count     <= '0;

            line_addr      <= '0;
            set_id         <= '0;
            miss_word_id_r <= '0;
            tag            <= '0;
            way            <= '0;

            write_r        <= 1'b0;
            wdata_r        <= '0;

            cpu_req_id     <= '0;
            mshr_id        <= '0;

            victim_valid_r <= 1'b0;
            victim_dirty_r <= 1'b0;
            victim_tag_r   <= '0;
            victim_line_r  <= '0;

            fill_line_r    <= '0;

            miss_valid_r   <= 1'b0;
            refill_wen_r   <= 1'b0;
        end
        else begin
            state          <= state_n;

            wb_count       <= wb_count_n;
            issue_count    <= issue_count_n;
            recv_count     <= recv_count_n;

            line_addr      <= line_addr_n;
            set_id         <= set_id_n;
            miss_word_id_r <= miss_word_id_n;
            tag            <= tag_n;
            way            <= way_n;

            write_r        <= write_n;
            wdata_r        <= wdata_n;

            cpu_req_id     <= cpu_req_id_n;
            mshr_id        <= mshr_id_n;

            victim_valid_r <= victim_valid_n;
            victim_dirty_r <= victim_dirty_n;
            victim_tag_r   <= victim_tag_n;
            victim_line_r  <= victim_line_n;

            fill_line_r    <= fill_line_n;

            miss_valid_r   <= miss_valid_n;
            refill_wen_r   <= refill_wen_n;
        end
    end

endmodule