// ============================================================
// Parameterized set-associative cache skeleton
// One data/tag/flag array per way
// Address format: [tag ID][set ID][word ID]
// Uses RAM_2W1R: port A = CPU write side, port B = refill side
// Downstream memory interface is one-word request/response
//
// Pipeline split:
//   Compare -> Hit Select -> Response
//   Compare -> Replacement -> Miss Select -> MSHR_File absorption FIFO
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
    localparam int MSHR_COUNT      = 4;

    localparam int FLAG_VALID_BIT  = 0;
    localparam int FLAG_DIRTY_BIT  = 1;

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

    logic miss_select_valid_r;
    logic miss_select_write_r;

    logic [ADDR_WIDTH-1:0]      miss_select_addr_r;
    logic [DATA_WIDTH-1:0]      miss_select_wdata_r;
    logic [CPU_ID_WIDTH-1:0]    miss_select_cpu_req_id_r;
    logic [TAG_WIDTH-1:0]       miss_select_tag_r;
    logic [SET_INDEX_W-1:0]     miss_select_set_id_r;
    logic [WORD_OFFSET_W-1:0]   miss_select_word_id_r;
    logic [LINE_ADDR_WIDTH-1:0] miss_select_line_addr_r;
    logic [WAY_INDEX_W-1:0]     miss_select_way_r;

    logic                       miss_select_victim_valid_r;
    logic                       miss_select_victim_dirty_r;
    logic [TAG_WIDTH-1:0]       miss_select_victim_tag_r;
    logic [LINE_WIDTH-1:0]      miss_select_victim_line_r;

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
    logic [TAG_WIDTH-1:0]  tag_rdata_r  [ASSOC];
    logic [FLAG_BITS-1:0]  flag_rdata_r [ASSOC];

    logic [ASSOC-1:0]       way_hit;
    logic [DATA_WIDTH-1:0]  way_word [ASSOC];
    logic [WAY_INDEX_W-1:0] hit_way;
    logic [DATA_WIDTH-1:0]  selected_word;

    logic [ASSOC-1:0]       compare_valid_bits;
    logic [WAY_INDEX_W-1:0] victim_way;

    logic                   victim_valid;
    logic                   victim_dirty;
    logic [TAG_WIDTH-1:0]   victim_tag;
    logic [LINE_WIDTH-1:0]  victim_line;

    logic                   compare_miss;

    logic                         mshr_alloc_ready;
    logic [MSHR_ID_WIDTH-1:0]     mshr_alloc_id;

    logic                         mshr_full;
    logic                         mshr_empty;

    logic [MSHR_COUNT-1:0]        mshr_req_valid;
    logic [MSHR_COUNT-1:0]        mshr_req_write;
    logic [ADDR_WIDTH-1:0]        mshr_req_addr  [MSHR_COUNT];
    logic [DATA_WIDTH-1:0]        mshr_req_wdata [MSHR_COUNT];
    logic [MSHR_ID_WIDTH-1:0]     mshr_req_id    [MSHR_COUNT];
    logic [MSHR_COUNT-1:0]        mshr_issued;

    logic                         miss_cpu_resp_valid;
    logic [CPU_ID_WIDTH-1:0]      miss_cpu_resp_id;
    logic [DATA_WIDTH-1:0]        miss_cpu_resp_data;

    logic                         refill_wen;
    logic [SET_INDEX_W-1:0]       refill_set_id;
    logic [TAG_WIDTH-1:0]         refill_tag;
    logic [WAY_INDEX_W-1:0]       refill_way;
    logic                         refill_dirty;
    logic [LINE_WIDTH-1:0]        refill_line;

    logic hit_resp_valid;
    logic miss_resp_valid;
    logic hit_resp_ready;
    logic miss_resp_ready;

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
    assign refill_array_windex = refill_set_id;

    assign cpu_req_ready = hit_resp_ready && mshr_alloc_ready;

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
                tag_rdata_r[i]  <= '0;
                flag_rdata_r[i] <= '0;
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
                tag_rdata_r[i]  <= tag_rdata[i];
                flag_rdata_r[i] <= flag_rdata[i];
            end
        end
    end

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

            RAM_2W1R_Reset #(
                .D_WIDTH     (FLAG_BITS),
                .DEPTH       (NUM_SETS),
                .READ_LATENCY(READ_LATENCY)
            ) FLAG_ARRAY (
                .clk    (clk),
                .rst    (rst),

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
                .valid     (flag_rdata[way][FLAG_VALID_BIT]),
                .hit       (way_hit[way])
            );

            assign way_word[way] =
                data_rline_r[way][compare_word_id_r * DATA_WIDTH +: DATA_WIDTH];

        end
    endgenerate

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

    assign compare_miss = compare_valid_r && !(|way_hit);

    always_comb begin
        for (int i = 0; i < ASSOC; i++) begin
            compare_valid_bits[i] = flag_rdata_r[i][FLAG_VALID_BIT];
        end
    end

    Replacement #(
        .ASSOC      (ASSOC),
        .NUM_SETS   (NUM_SETS),
        .WAY_INDEX_W(WAY_INDEX_W),
        .SET_INDEX_W(SET_INDEX_W)
    ) REPLACEMENT (
        .clk         (clk),
        .rst         (rst),

        .lookup_set  (compare_set_id_r),
        .valid_bits  (compare_valid_bits),
        .victim_way  (victim_way),

        .update_valid(compare_miss),
        .update_set  (compare_set_id_r),
        .update_way  (victim_way)
    );

    always_comb begin
        victim_line  = data_rline_r[victim_way];
        victim_tag   = tag_rdata_r[victim_way];
        victim_valid = flag_rdata_r[victim_way][FLAG_VALID_BIT];
        victim_dirty = flag_rdata_r[victim_way][FLAG_DIRTY_BIT];
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            miss_select_valid_r        <= 1'b0;
            miss_select_write_r        <= 1'b0;
            miss_select_addr_r         <= '0;
            miss_select_wdata_r        <= '0;
            miss_select_cpu_req_id_r   <= '0;
            miss_select_tag_r          <= '0;
            miss_select_set_id_r       <= '0;
            miss_select_word_id_r      <= '0;
            miss_select_line_addr_r    <= '0;
            miss_select_way_r          <= '0;

            miss_select_victim_valid_r <= 1'b0;
            miss_select_victim_dirty_r <= 1'b0;
            miss_select_victim_tag_r   <= '0;
            miss_select_victim_line_r  <= '0;
        end
        else if (cpu_req_ready) begin
            miss_select_valid_r        <= compare_miss;
            miss_select_write_r        <= compare_write_r;
            miss_select_addr_r         <= compare_addr_r;
            miss_select_wdata_r        <= compare_wdata_r;
            miss_select_cpu_req_id_r   <= compare_cpu_req_id_r;
            miss_select_tag_r          <= compare_tag_r;
            miss_select_set_id_r       <= compare_set_id_r;
            miss_select_word_id_r      <= compare_word_id_r;
            miss_select_line_addr_r    <= compare_line_addr_r;
            miss_select_way_r          <= victim_way;

            miss_select_victim_valid_r <= victim_valid;
            miss_select_victim_dirty_r <= victim_dirty;
            miss_select_victim_tag_r   <= victim_tag;
            miss_select_victim_line_r  <= victim_line;
        end
    end

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
        .MSHR_ID_WIDTH   (MSHR_ID_WIDTH),
        .MISSQ_DEPTH     (16)
    ) MSHR_FILE (
        .clk                 (clk),
        .rst                 (rst),

        .alloc_valid         (miss_select_valid_r),
        .alloc_ready         (mshr_alloc_ready),

        .alloc_line_addr     (miss_select_line_addr_r),
        .alloc_set_id        (miss_select_set_id_r),
        .alloc_word_id       (miss_select_word_id_r),
        .alloc_tag           (miss_select_tag_r),
        .alloc_way           (miss_select_way_r),

        .alloc_write         (miss_select_write_r),
        .alloc_wdata         (miss_select_wdata_r),
        .alloc_cpu_req_id    (miss_select_cpu_req_id_r),

        .alloc_victim_valid  (miss_select_victim_valid_r),
        .alloc_victim_dirty  (miss_select_victim_dirty_r),
        .alloc_victim_tag    (miss_select_victim_tag_r),
        .alloc_victim_line   (miss_select_victim_line_r),

        .alloc_mshr_id       (mshr_alloc_id),

        .issue_done          (mshr_issued),

        .mem_resp_valid      (mem_resp_valid),
        .mem_resp_id         (mem_resp_id),
        .mem_resp_rdata      (mem_resp_rdata),

        .miss_valid          (miss_cpu_resp_valid),
        .miss_id             (miss_cpu_resp_id),

        .refill_wen          (refill_wen),
        .refill_set_id       (refill_set_id),
        .refill_tag          (refill_tag),
        .refill_way          (refill_way),
        .refill_dirty        (refill_dirty),
        .refill_line         (refill_line),

        .issue_pending       (),
        .issue_line_addr     (),
        .issue_word_id       (),

        .req_valid           (mshr_req_valid),
        .req_write           (mshr_req_write),
        .req_addr            (mshr_req_addr),
        .req_wdata           (mshr_req_wdata),
        .req_id              (mshr_req_id),

        .full                (mshr_full),
        .empty               (mshr_empty)
    );

    Delay_r #(
        .D_WIDTH(DATA_WIDTH),
        .DELAY  (2)
    ) MISS_RESP_DATA_DELAY (
        .clk (clk),
        .rst (rst),
        .din (mem_resp_rdata),
        .dout(miss_cpu_resp_data)
    );

    MSHR_Request_Arbiter #(
        .MSHR_COUNT   (MSHR_COUNT),
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

    assign hit_resp_valid  = select_valid_r && select_hit_r;
    assign miss_resp_valid = miss_cpu_resp_valid;

    Response_Unit #(
        .DATA_WIDTH  (DATA_WIDTH),
        .CPU_ID_WIDTH(CPU_ID_WIDTH),
        .FIFO_DEPTH  (128)
    ) RESPONSE_UNIT (
        .clk           (clk),
        .rst           (rst),

        .hit_valid     (hit_resp_valid),
        .hit_ready     (hit_resp_ready),
        .hit_data      (select_rdata_r),
        .hit_id        (select_cpu_req_id_r),

        .miss_valid    (miss_resp_valid),
        .miss_ready    (miss_resp_ready),
        .miss_data     (miss_cpu_resp_data),
        .miss_id       (miss_cpu_resp_id),

        .cpu_resp_valid(cpu_resp_valid),
        .cpu_resp_ready(cpu_resp_ready),
        .cpu_resp_hit  (cpu_resp_hit),
        .cpu_resp_rdata(cpu_resp_rdata),
        .cpu_resp_id   (cpu_resp_id)
    );

    Refill_Write_Control #(
        .ASSOC      (ASSOC),
        .LINE_WIDTH (LINE_WIDTH),
        .TAG_WIDTH  (TAG_WIDTH),
        .FLAG_BITS  (FLAG_BITS),
        .WAY_INDEX_W(WAY_INDEX_W)
    ) REFILL_WRITE_CONTROL (
        .refill_valid(refill_wen),
        .refill_write(refill_dirty),
        .refill_way  (refill_way),
        .refill_line (refill_line),
        .refill_tag  (refill_tag),

        .data_wen    (refill_data_wen),
        .tag_wen     (refill_tag_wen),
        .flag_wen    (refill_flag_wen),
        .data_wline  (refill_data_wline),
        .tag_wdata   (refill_tag_wdata),
        .flag_wdata  (refill_flag_wdata)
    );

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