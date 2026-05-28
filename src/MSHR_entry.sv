module MSHR_Entry #(
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

    input  logic                       issue_done,

    input  logic                       complete,
    input  logic [DATA_WIDTH-1:0]      complete_word_data,

    input  logic                       free,

    output logic                       valid,
    output logic                       issue_pending,

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

    logic [BEAT_COUNT_W-1:0]     beat_count;
    logic [WORD_OFFSET_W-1:0]    fill_word_id;
    logic [DATA_WIDTH-1:0]       fill_word_data;

    assign fill_word_id = word_id + beat_count[WORD_OFFSET_W-1:0];

    always_comb begin
        fill_word_data = complete_word_data;

        if (write && (fill_word_id == word_id)) begin
            fill_word_data = wdata;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid         <= 1'b0;
            issue_pending <= 1'b0;
            completed     <= 1'b0;

            line_addr     <= '0;
            set_id        <= '0;
            word_id       <= '0;
            tag           <= '0;
            way           <= '0;

            write         <= 1'b0;
            wdata         <= '0;

            cpu_req_id    <= '0;
            mshr_id       <= '0;

            beat_count    <= '0;
            fill_line     <= '0;
        end
        else begin
            if (alloc) begin
                valid         <= 1'b1;
                issue_pending <= 1'b1;
                completed     <= 1'b0;

                line_addr     <= alloc_line_addr;
                set_id        <= alloc_set_id;
                word_id       <= alloc_word_id;
                tag           <= alloc_tag;
                way           <= alloc_way;

                write         <= alloc_write;
                wdata         <= alloc_wdata;

                cpu_req_id    <= alloc_cpu_req_id;
                mshr_id       <= alloc_mshr_id;

                beat_count    <= '0;
                fill_line     <= '0;
            end

            if (issue_done) begin
                issue_pending <= 1'b0;
            end

            if (complete && valid && !completed) begin
                fill_line[fill_word_id * DATA_WIDTH +: DATA_WIDTH] <= fill_word_data;

                if (beat_count == WORDS_PER_LINE-1) begin
                    completed <= 1'b1;
                end

                beat_count <= beat_count + 1'b1;
            end

            if (free) begin
                valid         <= 1'b0;
                issue_pending <= 1'b0;
                completed     <= 1'b0;
                beat_count    <= '0;
            end
        end
    end

endmodule