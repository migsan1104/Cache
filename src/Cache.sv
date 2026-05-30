// ============================================================
// Parameterized set-associative cache skeleton
// One data/tag/flag array per way
// Address format: [tag ID][set ID][word ID]
// Uses RAM_2W1R: port A = CPU write side, port B = refill side
// Downstream memory interface is one-word request/response
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
    output logic [DATA_WIDTH-1:0]     mem_req_wdata,
    output logic [MSHR_ID_WIDTH-1:0]  mem_req_id,

    input  logic                      mem_resp_valid,
    output logic                      mem_resp_ready,

    input  logic [MSHR_ID_WIDTH-1:0]  mem_resp_id,
    input  logic [DATA_WIDTH-1:0]     mem_resp_rdata
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

    logic [ASSOC-1:0]       way_hit;
    logic [DATA_WIDTH-1:0]  way_word [ASSOC];
    logic [WAY_INDEX_W-1:0] hit_way;
    logic [DATA_WIDTH-1:0]  selected_word;

    logic [WAY_INDEX_W-1:0] victim_way;

    logic                         mshr_alloc_ready;
    logic [MSHR_ID_WIDTH-1:0]     mshr_alloc_id;

    logic                         mshr_resp_valid;
    logic                         mshr_resp_ready;
    logic                         mshr_resp_fire;

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
    logic [DATA_WIDTH-1:0]        mshr_resp_word_data;

    logic                         mshr_full;
    logic                         mshr_empty;

    logic [3:0]                   mshr_req_valid;
    logic [3:0]                   mshr_req_write;
    logic [ADDR_WIDTH-1:0]        mshr_req_addr  [4];
    logic [DATA_WIDTH-1:0]        mshr_req_wdata [4];
    logic [MSHR_ID_WIDTH-1:0]     mshr_req_id    [4];
    logic [3:0]                   mshr_issued;

    logic                         miss_valid;

    logic                         hit_resp_valid;
    logic                         miss_resp_valid;

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

    assign victim_way = '0; // placeholder until Replacement.sv is wired

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

    // ============================================================
    // Miss detection into MSHR file
    // ============================================================

    assign miss_valid = select_valid_r && !select_hit_r;

    MSHR_File #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .LINE_ADDR_WIDTH (LINE_ADDR_WIDTH),
        .SET_INDEX_W     (SET_INDEX_W),
        .WORD_OFFSET_W   (WORD_OFFSET_W),
        .TAG_WIDTH       (TAG_WIDTH),
        .WAY_INDEX_W     (WAY_INDEX_W),
        .DATA_WIDTH      (DATA_WIDTH),
        .LINE_WIDTH      (LINE_WIDTH),
        .CPU_ID_WIDTH    (CPU_ID_WIDTH),
        .MSHR_ID_WIDTH   (MSHR_ID_WIDTH)
    ) MSHR_FILE (
        .clk                (clk),
        .rst                (rst),

        .alloc_valid        (miss_valid),
        .alloc_ready        (mshr_alloc_ready),

        .alloc_line_addr    (select_line_addr_r),
        .alloc_set_id       (select_set_id_r),
        .alloc_word_id      (select_word_id_r),
        .alloc_tag          (select_tag_r),
        .alloc_way          (victim_way),

        .alloc_write        (select_write_r),
        .alloc_wdata        (select_wdata_r),
        .alloc_cpu_req_id   (select_cpu_req_id_r),

        .alloc_mshr_id      (mshr_alloc_id),

        .issued             (mshr_issued),

        .complete_valid     (mem_resp_valid),
        .complete_mshr_id   (mem_resp_id),
        .complete_word_data (mem_resp_rdata),

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

        .req_valid          (mshr_req_valid),
        .req_write          (mshr_req_write),
        .req_addr           (mshr_req_addr),
        .req_wdata          (mshr_req_wdata),
        .req_id             (mshr_req_id),

        .full               (mshr_full),
        .empty              (mshr_empty)
    );

    // ============================================================
    // MSHR request arbiter directly drives downstream memory port
    // ============================================================

    MSHR_Request_Arbiter #(
        .MSHR_COUNT   (4),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .MSHR_ID_WIDTH(MSHR_ID_WIDTH)
    ) MSHR_REQ_ARBITER (
        .clk          (clk),
        .rst          (rst),

        .req_valid    (mshr_req_valid),
        .req_write    (mshr_req_write),
        .req_addr     (mshr_req_addr),
        .req_wdata    (mshr_req_wdata),
        .req_id       (mshr_req_id),

        .issued       (mshr_issued),

        .mem_req_valid(mem_req_valid),
        .mem_req_ready(mem_req_ready),
        .mem_req_write(mem_req_write),
        .mem_req_addr (mem_req_addr),
        .mem_req_wdata(mem_req_wdata),
        .mem_req_id   (mem_req_id)
    );

    assign mem_resp_ready = 1'b1;

    // ============================================================
    // CPU response mux: hit response or completed miss response
    // ============================================================

    assign hit_resp_valid  = select_valid_r && select_hit_r;
    assign miss_resp_valid = mshr_resp_valid;

    assign mshr_resp_word_data =
        mshr_resp_fill_line[mshr_resp_word_id * DATA_WIDTH +: DATA_WIDTH];

    assign cpu_resp_valid = hit_resp_valid || miss_resp_valid;

    assign cpu_resp_hit =
        hit_resp_valid ? 1'b1 : 1'b0;

    assign cpu_resp_rdata =
        hit_resp_valid ? select_rdata_r : mshr_resp_word_data;

    assign cpu_resp_id =
        hit_resp_valid ? select_cpu_req_id_r : mshr_resp_cpu_req_id;

    assign mshr_resp_ready = cpu_resp_ready && !hit_resp_valid;
    assign mshr_resp_fire  = mshr_resp_valid && mshr_resp_ready;

    // ============================================================
    // Refill write controls
    // ============================================================

    Refill_Write_Control #(
        .ASSOC      (ASSOC),
        .LINE_WIDTH (LINE_WIDTH),
        .TAG_WIDTH  (TAG_WIDTH),
        .FLAG_BITS  (FLAG_BITS),
        .WAY_INDEX_W(WAY_INDEX_W)
    ) REFILL_WRITE_CONTROL (
        .refill_valid(mshr_resp_fire),
        .refill_write(mshr_resp_write),
        .refill_way  (mshr_resp_way),
        .refill_line (mshr_resp_fill_line),
        .refill_tag  (mshr_resp_tag),

        .data_wen    (refill_data_wen),
        .tag_wen     (refill_tag_wen),
        .flag_wen    (refill_flag_wen),
        .data_wline  (refill_data_wline),
        .tag_wdata   (refill_tag_wdata),
        .flag_wdata  (refill_flag_wdata)
    );

    // ============================================================
    // CPU write-hit controls
    // ============================================================

    CPU_Write_Hit_Control #(
        .ASSOC        (ASSOC),
        .DATA_WIDTH   (DATA_WIDTH),
        .LINE_WIDTH   (LINE_WIDTH),
        .TAG_WIDTH    (TAG_WIDTH),
        .FLAG_BITS    (FLAG_BITS),
        .WAY_INDEX_W  (WAY_INDEX_W),
        .WORD_OFFSET_W(WORD_OFFSET_W)
    ) CPU_WRITE_HIT_CONTROL (
        .valid     (select_valid_r),
        .hit       (select_hit_r),
        .write     (select_write_r),
        .hit_way   (select_hit_way_r),
        .word_id   (select_word_id_r),
        .wdata     (select_wdata_r),
        .tag       (select_tag_r),
        .old_line  (data_rline_r),

        .data_wen  (cpu_data_wen),
        .tag_wen   (cpu_tag_wen),
        .flag_wen  (cpu_flag_wen),
        .data_wline(cpu_data_wline),
        .tag_wdata (cpu_tag_wdata),
        .flag_wdata(cpu_flag_wdata)
    );

endmodule