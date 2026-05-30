// ============================================================
// Single MSHR entry
// Owns miss state, issues one-word downstream requests,
// collects refill responses, and exposes completed refill line
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

    input  logic                       issued,

    input  logic                       complete,
    input  logic [DATA_WIDTH-1:0]      complete_word_data,

    input  logic                       free,

    output logic                       valid,

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

    output logic                       write,
    output logic [DATA_WIDTH-1:0]      wdata,

    output logic [CPU_ID_WIDTH-1:0]    cpu_req_id,
    output logic [MSHR_ID_WIDTH-1:0]   mshr_id,

    output logic                       completed,
    output logic [LINE_WIDTH-1:0]      fill_line
);

    localparam int WORDS_PER_LINE = LINE_WIDTH / DATA_WIDTH;
    localparam int BEAT_COUNT_W   = (WORDS_PER_LINE <= 1) ? 1 : $clog2(WORDS_PER_LINE);

    typedef enum logic [1:0] {
        S_IDLE,
        S_ISSUE,
        S_WAIT_R,
        S_DONE
    } state_t;

    state_t state;

    logic [BEAT_COUNT_W-1:0]  issue_count;
    logic [BEAT_COUNT_W-1:0]  recv_count;

    logic [WORD_OFFSET_W-1:0] issue_word_id;
    logic [WORD_OFFSET_W-1:0] recv_word_id;

    logic [DATA_WIDTH-1:0] fill_word_data;

    assign valid     = (state != S_IDLE);
    assign completed = (state == S_DONE);

    assign issue_word_id = word_id + issue_count[WORD_OFFSET_W-1:0];
    assign recv_word_id  = word_id + recv_count[WORD_OFFSET_W-1:0];

    assign req_valid   = (state == S_ISSUE);
    assign req_write   = 1'b0;
    assign req_wdata   = '0;
    assign req_mshr_id = mshr_id;

    assign req_addr = {{(ADDR_WIDTH-LINE_ADDR_WIDTH-WORD_OFFSET_W){1'b0}},
                       line_addr,
                       issue_word_id};

    always_comb begin
        fill_word_data = complete_word_data;

        if (write && (recv_word_id == word_id)) begin
            fill_word_data = wdata;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= S_IDLE;

            line_addr   <= '0;
            set_id      <= '0;
            word_id     <= '0;
            tag         <= '0;
            way         <= '0;

            write       <= 1'b0;
            wdata       <= '0;

            cpu_req_id  <= '0;
            mshr_id     <= '0;

            issue_count <= '0;
            recv_count  <= '0;
            fill_line   <= '0;
        end
        else begin
            case (state)

                S_IDLE: begin
                    if (alloc) begin
                        line_addr   <= alloc_line_addr;
                        set_id      <= alloc_set_id;
                        word_id     <= alloc_word_id;
                        tag         <= alloc_tag;
                        way         <= alloc_way;

                        write       <= alloc_write;
                        wdata       <= alloc_wdata;

                        cpu_req_id  <= alloc_cpu_req_id;
                        mshr_id     <= alloc_mshr_id;

                        issue_count <= '0;
                        recv_count  <= '0;
                        fill_line   <= '0;

                        state       <= S_ISSUE;
                    end
                end

                S_ISSUE: begin
                    if (issued) begin
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
                    if (complete) begin
                        fill_line[recv_word_id * DATA_WIDTH +: DATA_WIDTH] <= fill_word_data;

                        if (recv_count == WORDS_PER_LINE-1) begin
                            recv_count <= '0;
                            state      <= S_DONE;
                        end
                        else begin
                            recv_count <= recv_count + 1'b1;
                        end
                    end
                end

                S_DONE: begin
                    if (free) begin
                        state       <= S_IDLE;
                        issue_count <= '0;
                        recv_count  <= '0;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule