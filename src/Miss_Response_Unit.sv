// ============================================================
// Miss response unit
// Routes downstream CWF word beats into MSHRs,
// refills cache arrays when an MSHR completes,
// and returns completed miss responses
// ============================================================

module Miss_Response_Unit #(
    parameter int DATA_WIDTH    = 32,
    parameter int LINE_WIDTH    = 128,
    parameter int SET_INDEX_W   = 4,
    parameter int WORD_OFFSET_W = 2,
    parameter int TAG_WIDTH     = 16,
    parameter int WAY_INDEX_W   = 2,
    parameter int CPU_ID_WIDTH  = 4,
    parameter int MSHR_ID_WIDTH = 2
)(
    input  logic clk,
    input  logic rst,

    // ============================================================
    // DOWNSTREAM MEMORY WORD-BEAT RESPONSE
    // ============================================================

    input  logic                       mem_resp_valid,
    output logic                       mem_resp_ready,
    input  logic [MSHR_ID_WIDTH-1:0]   mem_resp_id,
    input  logic [DATA_WIDTH-1:0]      mem_resp_rdata,

    // ============================================================
    // COMPLETION BEAT INTO MSHR FILE
    // ============================================================

    output logic                       mshr_complete_valid,
    output logic [MSHR_ID_WIDTH-1:0]   mshr_complete_mshr_id,
    output logic [DATA_WIDTH-1:0]      mshr_complete_word_data,

    // ============================================================
    // COMPLETED MSHR RESPONSE FROM MSHR FILE
    // ============================================================

    input  logic                       mshr_resp_valid,
    output logic                       mshr_resp_ready,

    input  logic [CPU_ID_WIDTH-1:0]    mshr_resp_cpu_req_id,
    input  logic [MSHR_ID_WIDTH-1:0]   mshr_resp_mshr_id,
    input  logic [SET_INDEX_W-1:0]     mshr_resp_set_id,
    input  logic [WORD_OFFSET_W-1:0]   mshr_resp_word_id,
    input  logic [TAG_WIDTH-1:0]       mshr_resp_tag,
    input  logic [WAY_INDEX_W-1:0]     mshr_resp_way,

    input  logic                       mshr_resp_write,
    input  logic [DATA_WIDTH-1:0]      mshr_resp_wdata,
    input  logic [LINE_WIDTH-1:0]      mshr_resp_fill_line,

    // ============================================================
    // CACHE REFILL OUTPUT
    // ============================================================

    output logic                       refill_valid,
    output logic [SET_INDEX_W-1:0]     refill_set_id,
    output logic [WAY_INDEX_W-1:0]     refill_way,
    output logic [TAG_WIDTH-1:0]       refill_tag,
    output logic [LINE_WIDTH-1:0]      refill_line,
    output logic                       refill_dirty,

    // ============================================================
    // CPU MISS RESPONSE OUTPUT
    // ============================================================

    output logic                       miss_resp_valid,
    input  logic                       miss_resp_ready,
    output logic [CPU_ID_WIDTH-1:0]    miss_resp_cpu_req_id,
    output logic [DATA_WIDTH-1:0]      miss_resp_rdata
);

    logic [LINE_WIDTH-1:0] merged_line;

    // Store misses modify the filled line before refill.
    always_comb begin
        merged_line = mshr_resp_fill_line;

        if (mshr_resp_write) begin
            merged_line[mshr_resp_word_id * DATA_WIDTH +: DATA_WIDTH] = mshr_resp_wdata;
        end
    end

    // For now, always accept memory word beats.
    assign mem_resp_ready = 1'b1;

    // Route memory word beat into the correct MSHR entry.
    assign mshr_complete_valid     = mem_resp_valid;
    assign mshr_complete_mshr_id   = mem_resp_id;
    assign mshr_complete_word_data = mem_resp_rdata;

    // Completed MSHR becomes a cache refill and CPU response.
    assign miss_resp_valid = mshr_resp_valid;
    assign mshr_resp_ready = miss_resp_ready;

    assign refill_valid = mshr_resp_valid && miss_resp_ready;
    assign refill_set_id = mshr_resp_set_id;
    assign refill_way    = mshr_resp_way;
    assign refill_tag    = mshr_resp_tag;
    assign refill_line   = merged_line;
    assign refill_dirty  = mshr_resp_write;

    assign miss_resp_cpu_req_id = mshr_resp_cpu_req_id;

    assign miss_resp_rdata =
        merged_line[mshr_resp_word_id * DATA_WIDTH +: DATA_WIDTH];

endmodule