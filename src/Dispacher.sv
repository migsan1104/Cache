// ============================================================
// Reservation_Station
//
// One RS entry per cache line.
// Same-line misses merge into cpu_ids / word_ids.
// Issues one memory transaction per line to MSHR.
// On completed line, sends one bundle to Dispacher.
// ============================================================

module Reservation_Station #(
    parameter int LINE_ADDR_WIDTH = 16,
    parameter int SET_INDEX_W     = 4,
    parameter int WORD_OFFSET_W   = 2,
    parameter int TAG_WIDTH       = 16,
    parameter int WAY_INDEX_W     = 2,
    parameter int DATA_WIDTH      = 32,
    parameter int LINE_WIDTH      = 128,
    parameter int CPU_ID_WIDTH    = 4,
    parameter int MSHR_ID_WIDTH   = 2,
    parameter int RS_DEPTH        = 64,
    parameter int RS_AF_GAP       = 7,
    parameter int MAX_WAITERS     = 8,

    localparam int RS_ID_WIDTH    = (RS_DEPTH <= 1) ? 1 : $clog2(RS_DEPTH),
    localparam int COUNT_W        = $clog2(RS_DEPTH + 1),
    localparam int WAITER_COUNT_W = $clog2(MAX_WAITERS + 1)
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

    output logic                       issue_valid,
    input  logic                       issue_accept,
    input  logic [MSHR_ID_WIDTH-1:0]   issue_mshr_id,

    output logic [RS_ID_WIDTH-1:0]     issue_rs_id,
    output logic [LINE_ADDR_WIDTH-1:0] issue_line_addr,
    output logic [SET_INDEX_W-1:0]     issue_set_id,
    output logic [TAG_WIDTH-1:0]       issue_tag,
    output logic [WAY_INDEX_W-1:0]     issue_way,

    output logic                       issue_write,
    output logic [DATA_WIDTH-1:0]      issue_wdata,
    output logic [WORD_OFFSET_W-1:0]   issue_word_id,

    output logic                       issue_victim_valid,
    output logic                       issue_victim_dirty,
    output logic [TAG_WIDTH-1:0]       issue_victim_tag,
    output logic [LINE_WIDTH-1:0]      issue_victim_line,

    // Completed MSHR line selected by MSHR_File
    input  logic                       retire_valid,
    input  logic [LINE_ADDR_WIDTH-1:0] retire_line_addr,
    input  logic [LINE_WIDTH-1:0]      retire_fill_line,

    // One bundle per completed line to Dispacher
    output logic                       dispatch_valid,
    input  logic                       dispatch_ready,
    output logic [LINE_WIDTH-1:0]      dispatch_fill_line,
    output logic [WAITER_COUNT_W-1:0]  dispatch_cpu_id_count,
    output logic [CPU_ID_WIDTH-1:0]    dispatch_cpu_ids  [MAX_WAITERS],
    output logic [WORD_OFFSET_W-1:0]   dispatch_word_ids [MAX_WAITERS],

    output logic                       full,
    output logic                       almost_full,
    output logic                       empty
);

    typedef struct packed {
        logic                       valid;
        logic                       in_progress;
        logic [31:0]                age;
        logic [MSHR_ID_WIDTH-1:0]   mshr_id;

        logic [LINE_ADDR_WIDTH-1:0] line_addr;
        logic [SET_INDEX_W-1:0]     set_id;
        logic [TAG_WIDTH-1:0]       tag;
        logic [WAY_INDEX_W-1:0]     way;

        logic                       write;
        logic [DATA_WIDTH-1:0]      wdata;
        logic [WORD_OFFSET_W-1:0]   word_id;

        logic                       victim_valid;
        logic                       victim_dirty;
        logic [TAG_WIDTH-1:0]       victim_tag;
        logic [LINE_WIDTH-1:0]      victim_line;

        logic [WAITER_COUNT_W-1:0]  cpu_id_count;
        logic [CPU_ID_WIDTH-1:0]    cpu_ids  [MAX_WAITERS];
        logic [WORD_OFFSET_W-1:0]   word_ids [MAX_WAITERS];
    } rs_entry_t;

    rs_entry_t rs [RS_DEPTH];

    logic [COUNT_W-1:0] used_count;
    logic [31:0]        age_counter;

    logic free_found;
    logic [RS_ID_WIDTH-1:0] free_idx;

    logic same_line_found;
    logic [RS_ID_WIDTH-1:0] same_line_idx;
    logic same_line_has_room;

    logic [31:0] best_age;
    logic same_way_in_prog;
    logic ready_c;

    logic retire_match_found;
    logic [RS_ID_WIDTH-1:0] retire_match_idx;

    assign full        = (used_count == RS_DEPTH[COUNT_W-1:0]);
    assign almost_full = (used_count >= (RS_DEPTH - RS_AF_GAP));
    assign empty       = (used_count == '0);

    always_comb begin
        free_found = 1'b0;
        free_idx   = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (!rs[i].valid && !free_found) begin
                free_found = 1'b1;
                free_idx   = RS_ID_WIDTH'(i);
            end
        end
    end

    always_comb begin
        same_line_found = 1'b0;
        same_line_idx   = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs[i].valid && (rs[i].line_addr == alloc_line_addr) && !same_line_found) begin
                same_line_found = 1'b1;
                same_line_idx   = RS_ID_WIDTH'(i);
            end
        end
    end

    assign same_line_has_room =
        same_line_found &&
        (rs[same_line_idx].cpu_id_count < MAX_WAITERS[WAITER_COUNT_W-1:0]);

    assign alloc_ready =
        same_line_found
        ? same_line_has_room
        : (!almost_full && free_found);

    always_comb begin
        issue_valid = 1'b0;
        issue_rs_id = '0;
        best_age    = 32'hFFFF_FFFF;

        for (int i = 0; i < RS_DEPTH; i++) begin
            same_way_in_prog = 1'b0;

            for (int j = 0; j < RS_DEPTH; j++) begin
                if (rs[j].valid && rs[j].in_progress) begin
                    if ((rs[j].set_id == rs[i].set_id) &&
                        (rs[j].way    == rs[i].way)) begin
                        same_way_in_prog = 1'b1;
                    end
                end
            end

            ready_c =
                rs[i].valid &&
                !rs[i].in_progress &&
                !same_way_in_prog;

            if (ready_c && (rs[i].age < best_age)) begin
                issue_valid = 1'b1;
                issue_rs_id = RS_ID_WIDTH'(i);
                best_age    = rs[i].age;
            end
        end
    end

    assign issue_line_addr    = rs[issue_rs_id].line_addr;
    assign issue_set_id       = rs[issue_rs_id].set_id;
    assign issue_tag          = rs[issue_rs_id].tag;
    assign issue_way          = rs[issue_rs_id].way;

    assign issue_write        = rs[issue_rs_id].write;
    assign issue_wdata        = rs[issue_rs_id].wdata;
    assign issue_word_id      = rs[issue_rs_id].word_id;

    assign issue_victim_valid = rs[issue_rs_id].victim_valid;
    assign issue_victim_dirty = rs[issue_rs_id].victim_dirty;
    assign issue_victim_tag   = rs[issue_rs_id].victim_tag;
    assign issue_victim_line  = rs[issue_rs_id].victim_line;

    always_comb begin
        retire_match_found = 1'b0;
        retire_match_idx   = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs[i].valid &&
                rs[i].in_progress &&
                (rs[i].line_addr == retire_line_addr) &&
                !retire_match_found) begin
                retire_match_found = 1'b1;
                retire_match_idx   = RS_ID_WIDTH'(i);
            end
        end
    end

    assign dispatch_valid        = retire_valid && retire_match_found && dispatch_ready;
    assign dispatch_fill_line    = retire_fill_line;
    assign dispatch_cpu_id_count = rs[retire_match_idx].cpu_id_count;

    always_comb begin
        for (int i = 0; i < MAX_WAITERS; i++) begin
            dispatch_cpu_ids[i]  = rs[retire_match_idx].cpu_ids[i];
            dispatch_word_ids[i] = rs[retire_match_idx].word_ids[i];
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            used_count  <= '0;
            age_counter <= '0;

            for (int i = 0; i < RS_DEPTH; i++) begin
                rs[i] <= '0;
            end
        end
        else begin
            if (dispatch_valid) begin
                rs[retire_match_idx].valid       <= 1'b0;
                rs[retire_match_idx].in_progress <= 1'b0;
            end

            if (issue_valid && issue_accept) begin
                rs[issue_rs_id].in_progress <= 1'b1;
                rs[issue_rs_id].mshr_id     <= issue_mshr_id;
            end

            if (alloc_valid && alloc_ready) begin
                if (same_line_found) begin
                    rs[same_line_idx].cpu_ids [rs[same_line_idx].cpu_id_count] <= alloc_cpu_req_id;
                    rs[same_line_idx].word_ids[rs[same_line_idx].cpu_id_count] <= alloc_word_id;
                    rs[same_line_idx].cpu_id_count <= rs[same_line_idx].cpu_id_count + 1'b1;
                end
                else begin
                    rs[free_idx].valid        <= 1'b1;
                    rs[free_idx].in_progress  <= 1'b0;
                    rs[free_idx].age          <= age_counter;
                    rs[free_idx].mshr_id      <= '0;

                    rs[free_idx].line_addr    <= alloc_line_addr;
                    rs[free_idx].set_id       <= alloc_set_id;
                    rs[free_idx].tag          <= alloc_tag;
                    rs[free_idx].way          <= alloc_way;

                    rs[free_idx].write        <= alloc_write;
                    rs[free_idx].wdata        <= alloc_wdata;
                    rs[free_idx].word_id      <= alloc_word_id;

                    rs[free_idx].victim_valid <= alloc_victim_valid;
                    rs[free_idx].victim_dirty <= alloc_victim_dirty;
                    rs[free_idx].victim_tag   <= alloc_victim_tag;
                    rs[free_idx].victim_line  <= alloc_victim_line;

                    rs[free_idx].cpu_id_count <= WAITER_COUNT_W'(1);
                    rs[free_idx].cpu_ids[0]   <= alloc_cpu_req_id;
                    rs[free_idx].word_ids[0]  <= alloc_word_id;

                    for (int k = 1; k < MAX_WAITERS; k++) begin
                        rs[free_idx].cpu_ids[k]  <= '0;
                        rs[free_idx].word_ids[k] <= '0;
                    end

                    age_counter <= age_counter + 1'b1;
                end
            end

            case ({alloc_valid && alloc_ready && !same_line_found,
                   dispatch_valid})
                2'b10: used_count <= used_count + 1'b1;
                2'b01: used_count <= used_count - 1'b1;
                default: used_count <= used_count;
            endcase
        end
    end

endmodule