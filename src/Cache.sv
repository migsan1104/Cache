// ============================================================
// Parameterized set-associative cache skeleton
// One data/tag/flag array per way
// Address format: [tag ID][set ID][word ID]
// Uses RAM_2W1R: port A = CPU write side, port B = refill side
// ============================================================

module Cache #(
    parameter int ADDR_WIDTH    = 32,
    parameter int DATA_WIDTH    = 32,
    parameter int CACHE_BYTES   = 1024,
    parameter int LINE_BYTES    = 16,
    parameter int ASSOC         = 4,
    parameter int CPU_ID_WIDTH  = 4,
    parameter int MSHR_ID_WIDTH = 2
)(
    input  logic clk,
    input  logic rst,

    input  logic                      cpu_req_valid,
    output logic                      cpu_req_ready,

    input  logic                      cpu_req_write,
    input  logic [ADDR_WIDTH-1:0]     cpu_req_addr,
    input  logic [DATA_WIDTH-1:0]     cpu_req_wdata,
    input  logic [CPU_ID_WIDTH-1:0]   cpu_req_id,

    output logic                      cpu_resp_valid,
    input  logic                      cpu_resp_ready,

    output logic                      cpu_resp_hit,
    output logic [DATA_WIDTH-1:0]     cpu_resp_rdata,
    output logic [CPU_ID_WIDTH-1:0]   cpu_resp_id,

    output logic                      mem_req_valid,
    input  logic                      mem_req_ready,

    output logic                      mem_req_write,
    output logic [ADDR_WIDTH-1:0]     mem_req_addr,
    output logic [LINE_BYTES*8-1:0]   mem_req_wdata,
    output logic [MSHR_ID_WIDTH-1:0]  mem_req_id,

    input  logic                      mem_resp_valid,
    output logic                      mem_resp_ready,

    input  logic [MSHR_ID_WIDTH-1:0]  mem_resp_id,
    input  logic [LINE_BYTES*8-1:0]   mem_resp_rdata
);

    localparam int WORD_BYTES      = DATA_WIDTH / 8;
    localparam int WORDS_PER_LINE  = LINE_BYTES / WORD_BYTES;
    localparam int LINE_WIDTH      = LINE_BYTES * 8;
    localparam int NUM_LINES       = CACHE_BYTES / LINE_BYTES;
    localparam int NUM_SETS        = NUM_LINES / ASSOC;

    localparam int WORD_OFFSET_W   = $clog2(WORDS_PER_LINE);
    localparam int SET_INDEX_BITS  = (NUM_SETS <= 1) ? 0 : $clog2(NUM_SETS);
    localparam int SET_INDEX_W     = (SET_INDEX_BITS == 0) ? 1 : SET_INDEX_BITS;

    localparam int WORD_ADDR_W     = ADDR_WIDTH - $clog2(WORD_BYTES);
    localparam int TAG_WIDTH       = WORD_ADDR_W - WORD_OFFSET_W - SET_INDEX_BITS;
    localparam int LINE_ADDR_WIDTH = WORD_ADDR_W - WORD_OFFSET_W;

    localparam int WAY_INDEX_W     = (ASSOC <= 1) ? 1 : $clog2(ASSOC);

    localparam int FLAG_BITS       = 4;
    localparam int READ_LATENCY    = 1;

    logic [TAG_WIDTH-1:0]       addr_tag;
    logic [SET_INDEX_W-1:0]     addr_set_id;
    logic [WORD_OFFSET_W-1:0]   addr_word_id;
    logic [LINE_ADDR_WIDTH-1:0] addr_line_addr;

    logic lookup_valid_r;
    logic lookup_write_r;

    logic [ADDR_WIDTH-1:0]      lookup_addr_r;
    logic [DATA_WIDTH-1:0]      lookup_wdata_r;
    logic [CPU_ID_WIDTH-1:0]    lookup_cpu_req_id_r;
    logic [TAG_WIDTH-1:0]       lookup_tag_r;
    logic [SET_INDEX_W-1:0]     lookup_set_id_r;
    logic [WORD_OFFSET_W-1:0]   lookup_word_id_r;
    logic [LINE_ADDR_WIDTH-1:0] lookup_line_addr_r;

    logic compare_valid_r;
    logic compare_write_r;

    logic [ADDR_WIDTH-1:0]      compare_addr_r;
    logic [DATA_WIDTH-1:0]      compare_wdata_r;
    logic [CPU_ID_WIDTH-1:0]    compare_cpu_req_id_r;
    logic [TAG_WIDTH-1:0]       compare_tag_r;
    logic [SET_INDEX_W-1:0]     compare_set_id_r;
    logic [WORD_OFFSET_W-1:0]   compare_word_id_r;
    logic [LINE_ADDR_WIDTH-1:0] compare_line_addr_r;

    logic select_valid_r;
    logic select_write_r;
    logic select_hit_r;

    logic [ADDR_WIDTH-1:0]      select_addr_r;
    logic [DATA_WIDTH-1:0]      select_wdata_r;
    logic [DATA_WIDTH-1:0]      select_rdata_r;
    logic [CPU_ID_WIDTH-1:0]    select_cpu_req_id_r;
    logic [TAG_WIDTH-1:0]       select_tag_r;
    logic [WAY_INDEX_W-1:0]     select_hit_way_r;
    logic [SET_INDEX_W-1:0]     select_set_id_r;
    logic [WORD_OFFSET_W-1:0]   select_word_id_r;
    logic [LINE_ADDR_WIDTH-1:0] select_line_addr_r;

    logic [ASSOC-1:0] cpu_data_wen;
    logic [ASSOC-1:0] cpu_tag_wen;
    logic [ASSOC-1:0] cpu_flag_wen;

    logic [ASSOC-1:0] refill_data_wen;
    logic [ASSOC-1:0] refill_tag_wen;
    logic [ASSOC-1:0] refill_flag_wen;

    logic [SET_INDEX_W-1:0] array_rindex;
    logic [SET_INDEX_W-1:0] cpu_array_windex;
    logic [SET_INDEX_W-1:0] refill_array_windex;

    logic [LINE_WIDTH-1:0] cpu_data_wline [ASSOC];
    logic [TAG_WIDTH-1:0]  cpu_tag_wdata  [ASSOC];
    logic [FLAG_BITS-1:0]  cpu_flag_wdata [ASSOC];

    logic [LINE_WIDTH-1:0] refill_data_wline [ASSOC];
    logic [TAG_WIDTH-1:0]  refill_tag_wdata  [ASSOC];
    logic [FLAG_BITS-1:0]  refill_flag_wdata [ASSOC];

    logic [LINE_WIDTH-1:0] data_rline [ASSOC];
    logic [TAG_WIDTH-1:0]  tag_rdata  [ASSOC];
    logic [FLAG_BITS-1:0]  flag_rdata [ASSOC];

    logic [LINE_WIDTH-1:0] data_rline_r [ASSOC];

    logic [ASSOC-1:0]      way_hit;
    logic [DATA_WIDTH-1:0] way_word [ASSOC];
    logic [WAY_INDEX_W-1:0] hit_way;
    logic [DATA_WIDTH-1:0] selected_word;

    logic                         mshr_alloc_ready;
    logic [MSHR_ID_WIDTH-1:0]     mshr_alloc_id;

    logic [3:0]                   mshr_issue_pending;
    logic [LINE_ADDR_WIDTH-1:0]   mshr_issue_line_addr [4];
    logic [WORD_OFFSET_W-1:0]     mshr_issue_word_id   [4];

    logic                         mshr_resp_valid;
    logic                         mshr_resp_ready;
    logic [CPU_ID_WIDTH-1:0]      mshr_resp_cpu_req_id;
    logic [MSHR_ID_WIDTH-1:0]     mshr_resp_mshr_id;
    logic [LINE_ADDR_WIDTH-1:0]   mshr_resp_line_addr;
    logic [SET_INDEX_W-1:0]       mshr_resp_set_id;
    logic [WORD_OFFSET_W-1:0]     mshr_resp_word_id;
    logic [TAG_WIDTH-1:0]         mshr_resp_tag;
    logic [WAY_INDEX_W-1:0]       mshr_resp_way;
    logic                         mshr_resp_write;
    logic [DATA_WIDTH-1:0]        mshr_resp_wdata;
    logic [LINE_WIDTH-1:0]        mshr_resp_fill_line;

    logic                         mshr_full;
    logic                         mshr_empty;

    logic                         evict_valid;
    logic                         evict_ready;
    logic [ADDR_WIDTH-1:0]        evict_addr;
    logic [LINE_WIDTH-1:0]        evict_line_data;

    logic                         miss_valid;
    logic                         miss_ready;
    logic [LINE_ADDR_WIDTH-1:0]   miss_line_addr;
    logic [MSHR_ID_WIDTH-1:0]     miss_id;

    // ============================================================
    // Address decode
    // ============================================================

    Address_Decode #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .CACHE_BYTES(CACHE_BYTES),
        .LINE_BYTES (LINE_BYTES),
        .ASSOC      (ASSOC)
    ) ADDR_DECODE (
        .addr     (cpu_req_addr),
        .tag      (addr_tag),
        .set_id   (addr_set_id),
        .word_id  (addr_word_id),
        .line_addr(addr_line_addr)
    );

    assign array_rindex        = addr_set_id;
    assign cpu_array_windex    = select_set_id_r;
    assign refill_array_windex = mshr_resp_set_id;

    assign cpu_req_ready =
        (cpu_resp_ready || !cpu_resp_valid) &&
        mshr_alloc_ready;

    // ============================================================
    // Stage 1: request / address decode
    // ============================================================

    always_ff @(posedge clk) begin
        if (rst) begin
            lookup_valid_r      <= 1'b0;
            lookup_write_r      <= 1'b0;
            lookup_addr_r       <= '0;
            lookup_wdata_r      <= '0;
            lookup_cpu_req_id_r <= '0;
            lookup_tag_r        <= '0;
            lookup_set_id_r     <= '0;
            lookup_word_id_r    <= '0;
            lookup_line_addr_r  <= '0;
        end
        else if (cpu_req_ready) begin
            lookup_valid_r      <= cpu_req_valid;
            lookup_write_r      <= cpu_req_write;
            lookup_addr_r       <= cpu_req_addr;
            lookup_wdata_r      <= cpu_req_wdata;
            lookup_cpu_req_id_r <= cpu_req_id;
            lookup_tag_r        <= addr_tag;
            lookup_set_id_r     <= addr_set_id;
            lookup_word_id_r    <= addr_word_id;
            lookup_line_addr_r  <= addr_line_addr;
        end
    end

    // ============================================================
    // Stage 2: SRAM output capture / compare metadata alignment
    // ============================================================

    always_ff @(posedge clk) begin
        if (rst) begin
            compare_valid_r      <= 1'b0;
            compare_write_r      <= 1'b0;
            compare_addr_r       <= '0;
            compare_wdata_r      <= '0;
            compare_cpu_req_id_r <= '0;
            compare_tag_r        <= '0;
            compare_set_id_r     <= '0;
            compare_word_id_r    <= '0;
            compare_line_addr_r  <= '0;

            for (int i = 0; i < ASSOC; i++) begin
                data_rline_r[i] <= '0;
            end
        end
        else if (cpu_req_ready) begin
            compare_valid_r      <= lookup_valid_r;
            compare_write_r      <= lookup_write_r;
            compare_addr_r       <= lookup_addr_r;
            compare_wdata_r      <= lookup_wdata_r;
            compare_cpu_req_id_r <= lookup_cpu_req_id_r;
            compare_tag_r        <= lookup_tag_r;
            compare_set_id_r     <= lookup_set_id_r;
            compare_word_id_r    <= lookup_word_id_r;
            compare_line_addr_r  <= lookup_line_addr_r;

            for (int i = 0; i < ASSOC; i++) begin
                data_rline_r[i] <= data_rline[i];
            end
        end
    end

    // ============================================================
    // Cache ways
    // ============================================================

    genvar way;

    generate
        for (way = 0; way < ASSOC; way++) begin : GEN_WAYS

            RAM_2W1R #(
                .D_WIDTH     (LINE_WIDTH),
                .DEPTH       (NUM_SETS),
                .READ_LATENCY(READ_LATENCY)
            ) DATA_ARRAY (
                .clk    (clk),

                .wen_a  (cpu_data_wen[way]),
                .waddr_a(cpu_array_windex),
                .wdata_a(cpu_data_wline[way]),

                .wen_b  (refill_data_wen[way]),
                .waddr_b(refill_array_windex),
                .wdata_b(refill_data_wline[way]),

                .raddr  (array_rindex),
                .rdata  (data_rline[way])
            );

            RAM_2W1R #(
                .D_WIDTH     (TAG_WIDTH),
                .DEPTH       (NUM_SETS),
                .READ_LATENCY(READ_LATENCY)
            ) TAG_ARRAY (
                .clk    (clk),

                .wen_a  (cpu_tag_wen[way]),
                .waddr_a(cpu_array_windex),
                .wdata_a(cpu_tag_wdata[way]),

                .wen_b  (refill_tag_wen[way]),
                .waddr_b(refill_array_windex),
                .wdata_b(refill_tag_wdata[way]),

                .raddr  (array_rindex),
                .rdata  (tag_rdata[way])
            );

            RAM_2W1R #(
                .D_WIDTH     (FLAG_BITS),
                .DEPTH       (NUM_SETS),
                .READ_LATENCY(READ_LATENCY)
            ) FLAG_ARRAY (
                .clk    (clk),

                .wen_a  (cpu_flag_wen[way]),
                .waddr_a(cpu_array_windex),
                .wdata_a(cpu_flag_wdata[way]),

                .wen_b  (refill_flag_wen[way]),
                .waddr_b(refill_array_windex),
                .wdata_b(refill_flag_wdata[way]),

                .raddr  (array_rindex),
                .rdata  (flag_rdata[way])
            );

            Hit_compare #(
                .TAG_BITS(TAG_WIDTH)
            ) TAG_COMPARE (
                .clk       (clk),
                .rst       (rst),
                .req_tag   (lookup_tag_r),
                .stored_tag(tag_rdata[way]),
                .valid     (flag_rdata[way][0]),
                .hit       (way_hit[way])
            );

            assign way_word[way] =
                data_rline_r[way][compare_word_id_r * DATA_WIDTH +: DATA_WIDTH];

        end
    endgenerate

    // ============================================================
    // Hit selection combinational logic
    // ============================================================

    always_comb begin
        hit_way       = '0;
        selected_word = '0;

        for (int i = 0; i < ASSOC; i++) begin
            if (way_hit[i]) begin
                hit_way       = i[WAY_INDEX_W-1:0];
                selected_word = way_word[i];
            end
        end
    end

    // ============================================================
    // Stage 4: selection / response register
    // ============================================================

    always_ff @(posedge clk) begin
        if (rst) begin
            select_valid_r      <= 1'b0;
            select_write_r      <= 1'b0;
            select_hit_r        <= 1'b0;
            select_addr_r       <= '0;
            select_wdata_r      <= '0;
            select_rdata_r      <= '0;
            select_cpu_req_id_r <= '0;
            select_tag_r        <= '0;
            select_hit_way_r    <= '0;
            select_set_id_r     <= '0;
            select_word_id_r    <= '0;
            select_line_addr_r  <= '0;
        end
        else if (cpu_req_ready) begin
            select_valid_r      <= compare_valid_r;
            select_write_r      <= compare_write_r;
            select_hit_r        <= |way_hit;
            select_addr_r       <= compare_addr_r;
            select_wdata_r      <= compare_wdata_r;
            select_rdata_r      <= selected_word;
            select_cpu_req_id_r <= compare_cpu_req_id_r;
            select_tag_r        <= compare_tag_r;
            select_hit_way_r    <= hit_way;
            select_set_id_r     <= compare_set_id_r;
            select_word_id_r    <= compare_word_id_r;
            select_line_addr_r  <= compare_line_addr_r;
        end
    end

    assign cpu_resp_valid = select_valid_r && select_hit_r;
    assign cpu_resp_hit   = select_hit_r;
    assign cpu_resp_rdata = select_rdata_r;
    assign cpu_resp_id    = select_cpu_req_id_r;

    // ============================================================
    // Miss detection into MSHR file
    // ============================================================

    assign miss_valid = select_valid_r && !select_hit_r;

    MSHR_File #(
        .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH),
        .SET_INDEX_W    (SET_INDEX_W),
        .WORD_OFFSET_W  (WORD_OFFSET_W),
        .TAG_WIDTH      (TAG_WIDTH),
        .WAY_INDEX_W    (WAY_INDEX_W),
        .DATA_WIDTH     (DATA_WIDTH),
        .LINE_WIDTH     (LINE_WIDTH),
        .CPU_ID_WIDTH   (CPU_ID_WIDTH),
        .MSHR_ID_WIDTH  (MSHR_ID_WIDTH)
    ) MSHR_FILE (
        .clk                (clk),
        .rst                (rst),

        .alloc_valid        (miss_valid),
        .alloc_ready        (mshr_alloc_ready),

        .alloc_line_addr    (select_line_addr_r),
        .alloc_set_id       (select_set_id_r),
        .alloc_word_id      (select_word_id_r),
        .alloc_tag          (select_tag_r),
        .alloc_way          (select_hit_way_r),

        .alloc_write        (select_write_r),
        .alloc_wdata        (select_wdata_r),
        .alloc_cpu_req_id   (select_cpu_req_id_r),

        .alloc_mshr_id      (mshr_alloc_id),

        .issue_done_valid   (1'b0),
        .issue_done_mshr_id ('0),

        .complete_valid     (1'b0),
        .complete_mshr_id   ('0),
        .complete_word_data ('0),

        .resp_valid         (mshr_resp_valid),
        .resp_ready         (mshr_resp_ready),

        .resp_cpu_req_id    (mshr_resp_cpu_req_id),
        .resp_mshr_id       (mshr_resp_mshr_id),

        .resp_line_addr     (mshr_resp_line_addr),
        .resp_set_id        (mshr_resp_set_id),
        .resp_word_id       (mshr_resp_word_id),
        .resp_tag           (mshr_resp_tag),
        .resp_way           (mshr_resp_way),

        .resp_write         (mshr_resp_write),
        .resp_wdata         (mshr_resp_wdata),
        .resp_fill_line     (mshr_resp_fill_line),

        .issue_pending      (mshr_issue_pending),
        .issue_line_addr    (mshr_issue_line_addr),
        .issue_word_id      (mshr_issue_word_id),

        .full               (mshr_full),
        .empty              (mshr_empty)
    );

    assign mshr_resp_ready = 1'b1;

    // ============================================================
    // Placeholder refill write controls
    // ============================================================

    always_comb begin
        refill_data_wen = '0;
        refill_tag_wen  = '0;
        refill_flag_wen = '0;

        for (int i = 0; i < ASSOC; i++) begin
            refill_data_wline[i] = '0;
            refill_tag_wdata[i]  = '0;
            refill_flag_wdata[i] = '0;
        end

        if (mshr_resp_valid) begin
            refill_data_wen[mshr_resp_way]         = 1'b1;
            refill_tag_wen[mshr_resp_way]          = 1'b1;
            refill_flag_wen[mshr_resp_way]         = 1'b1;
            refill_data_wline[mshr_resp_way]       = mshr_resp_fill_line;
            refill_tag_wdata[mshr_resp_way]        = mshr_resp_tag;
            refill_flag_wdata[mshr_resp_way]       = 4'b0001;
        end
    end

    // ============================================================
    // Placeholder eviction generation
    // ============================================================

    assign evict_valid     = 1'b0;
    assign evict_addr      = '0;
    assign evict_line_data = '0;

    // ============================================================
    // Placeholder memory request unit
    // Real miss requests should eventually come from MSHR_Scheduler
    // ============================================================

    assign miss_ready     = 1'b1;
    assign miss_line_addr = '0;
    assign miss_id        = '0;

    Memory_Request_Unit #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .LINE_WIDTH     (LINE_WIDTH),
        .LINE_ADDR_WIDTH(LINE_ADDR_WIDTH),
        .LINE_BYTES     (LINE_BYTES),
        .ID_WIDTH       (MSHR_ID_WIDTH),
        .WB_DEPTH       (8),
        .MISS_DEPTH     (8)
    ) MEM_REQ_UNIT (
        .clk            (clk),
        .rst            (rst),

        .evict_valid    (evict_valid),
        .evict_ready    (evict_ready),
        .evict_addr     (evict_addr),
        .evict_line_data(evict_line_data),

        .miss_valid     (1'b0),
        .miss_ready     (miss_ready),
        .miss_line_addr (miss_line_addr),
        .miss_id        (miss_id),

        .mem_req_valid  (mem_req_valid),
        .mem_req_ready  (mem_req_ready),
        .mem_req_write  (mem_req_write),
        .mem_req_addr   (mem_req_addr),
        .mem_req_wdata  (mem_req_wdata),
        .mem_req_id     (mem_req_id)
    );

    assign mem_resp_ready = 1'b1;

    // ============================================================
    // Placeholder CPU write-hit controls
    // ============================================================

    always_comb begin
        cpu_data_wen = '0;
        cpu_tag_wen  = '0;
        cpu_flag_wen = '0;

        for (int i = 0; i < ASSOC; i++) begin
            cpu_data_wline[i] = '0;
            cpu_tag_wdata[i]  = select_tag_r;
            cpu_flag_wdata[i] = 4'b0001;
        end
    end

endmodule