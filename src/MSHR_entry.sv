// ============================================================
// Single MSHR entry
// Stores one outstanding cache miss transaction
// ============================================================

module MSHR_Entry #(
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

    // Allocate/update this entry
    input  logic alloc,

    input  logic [LINE_ADDR_WIDTH-1:0] alloc_line_addr,
    input  logic [SET_INDEX_W-1:0]     alloc_set_id,
    input  logic [WORD_OFFSET_W-1:0]   alloc_word_id,
    input  logic [TAG_WIDTH-1:0]       alloc_tag,
    input  logic [WAY_INDEX_W-1:0]     alloc_way,

    input  logic                       alloc_write,
    input  logic [DATA_WIDTH-1:0]      alloc_wdata,

    input  logic [1:0]                 alloc_resp_id,

    // Memory fill completed for this entry
    input  logic                       complete,
    input  logic [LINE_WIDTH-1:0]      complete_fill_line,

    // Free this entry
    input  logic                       free,

    // ============================================================
    // Stored MSHR state
    // ============================================================

    output logic                       valid,

    output logic [LINE_ADDR_WIDTH-1:0] line_addr,
    output logic [SET_INDEX_W-1:0]     set_id,
    output logic [WORD_OFFSET_W-1:0]   word_id,
    output logic [TAG_WIDTH-1:0]       tag,
    output logic [WAY_INDEX_W-1:0]     way,

    output logic                       write,
    output logic [DATA_WIDTH-1:0]      wdata,

    output logic [1:0]                 resp_id,

    output logic                       completed,
    output logic [LINE_WIDTH-1:0]      fill_line
);

    always_ff @(posedge clk) begin

        if (rst) begin

            valid      <= 1'b0;
            completed  <= 1'b0;

            line_addr  <= '0;
            set_id     <= '0;
            word_id    <= '0;
            tag        <= '0;
            way        <= '0;

            write      <= 1'b0;
            wdata      <= '0;

            resp_id    <= '0;
            fill_line  <= '0;

        end

        else begin

            // Allocate new miss transaction
            if (alloc) begin

                valid      <= 1'b1;
                completed  <= 1'b0;

                line_addr  <= alloc_line_addr;
                set_id     <= alloc_set_id;
                word_id    <= alloc_word_id;
                tag        <= alloc_tag;
                way        <= alloc_way;

                write      <= alloc_write;
                wdata      <= alloc_wdata;

                resp_id    <= alloc_resp_id;

            end

            // Memory fill completed
            if (complete) begin

                completed <= 1'b1;
                fill_line <= complete_fill_line;

            end

            // Free this entry
            if (free) begin

                valid <= 1'b0;

            end

        end

    end

endmodule