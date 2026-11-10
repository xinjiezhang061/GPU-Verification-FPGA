`timescale 1ns/1ps
`default_nettype none

module tb_rasterizer #(
    parameter int WIDTH = 32,
    parameter int HEIGHT = 24
);
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;
    logic tri_valid = 0, tri_ready, tri_done;
    logic signed [7:0] x0 = 0, y0 = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0;
    logic frag_valid, frag_ready = 0;
    logic [6:0] frag_x, frag_y;

    triangle_rasterizer #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) dut (.*);

    string vectors_path, case_name;
    int vectors, case_count, file_width, file_height, status;
    int ax, ay, bx, by, cx, cy, expected_count;
    int checked_fragments = 0, stalled_cycles = 0;
    int empty_cases = 0, nonempty_cases = 0;
    int seed;
    logic [31:0] prng;

    // Call on a falling edge to keep drivers away from DUT sampling.
    task automatic submit(input int a_x, a_y, b_x, b_y, c_x, c_y);
        x0 = 8'(a_x); y0 = 8'(a_y);
        x1 = 8'(b_x); y1 = 8'(b_y);
        x2 = 8'(c_x); y2 = 8'(c_y);
        tri_valid = 1;
        @(posedge clk);
        if (tri_ready !== 1'b1 || tri_done !== 1'b0 || frag_valid !== 1'b0)
            $fatal(1, "%s: bad idle or command handshake", case_name);
        @(negedge clk);
        tri_valid = 0;
        // Command data becomes free to change after the handshake.
        x0 = 0; y0 = 0; x1 = 0; y1 = 0; x2 = 0; y2 = 0;
    endtask

    task automatic check_case(input int index, expected);
        int seen, cycles, forced_stalls, expected_x, expected_y;
        logic held, completed;
        logic [6:0] held_x, held_y;
        seen = 0;
        forced_stalls = 0;
        held = 0;
        completed = 0;
        for (cycles = 0; cycles < 4 * WIDTH * HEIGHT + 16 && !completed; cycles++) begin
            prng = {prng[30:0], prng[31] ^ prng[21] ^ prng[1] ^ prng[0]};
            case (index % 3)
                0: frag_ready = 1;
                1: frag_ready = forced_stalls >= 3 && prng[0];
                2: frag_ready = cycles[0];
            endcase
            @(posedge clk);
            if (tri_ready !== 1'b0)
                $fatal(1, "%s: accepted another command while busy", case_name);
            if ((frag_valid !== 1'b0 && frag_valid !== 1'b1) ||
                (tri_done !== 1'b0 && tri_done !== 1'b1))
                $fatal(1, "%s: unknown control output", case_name);
            if (held && (frag_valid !== 1'b1 || frag_x !== held_x || frag_y !== held_y))
                $fatal(1, "%s: fragment changed under backpressure", case_name);
            if (tri_done) begin
                if (frag_valid || seen != expected)
                    $fatal(1, "%s: completion after %0d of %0d fragments",
                           case_name, seen, expected);
                completed = 1;
            end
            if (frag_valid && frag_ready) begin
                if (seen >= expected)
                    $fatal(1, "%s: unexpected fragment (%0d,%0d)", case_name, frag_x, frag_y);
                if ($fscanf(vectors, "%d %d", expected_x, expected_y) != 2)
                    $fatal(1, "%s: missing expected fragment in vector file", case_name);
                if (int'(frag_x) !== expected_x || int'(frag_y) !== expected_y)
                    $fatal(1, "%s: fragment %0d got (%0d,%0d), expected (%0d,%0d)",
                           case_name, seen, frag_x, frag_y, expected_x, expected_y);
                seen++;
                checked_fragments++;
            end
            held = frag_valid && !frag_ready;
            if (held) begin
                held_x = frag_x;
                held_y = frag_y;
                forced_stalls++;
                stalled_cycles++;
            end
            @(negedge clk);
        end
        if (!completed)
            $fatal(1, "%s: timeout after %0d cycles, saw %0d of %0d fragments",
                   case_name, cycles, seen, expected);
        if (expected == 0)
            empty_cases++;
        else
            nonempty_cases++;
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vectors_path))
            $fatal(1, "Missing +VECTORS=<path>");
        if (!$value$plusargs("SEED=%d", seed))
            seed = 42;
        prng = 32'hc001cafe ^ 32'(seed);
        if (prng == 0)
            prng = 1;
        if ($test$plusargs("WAVES")) begin
            $dumpfile("rasterizer.vcd");
            $dumpvars(0, tb_rasterizer);
        end

        vectors = $fopen(vectors_path, "r");
        if (!vectors)
            $fatal(1, "Cannot open %s", vectors_path);
        status = $fscanf(vectors, "%d %d %d", case_count, file_width, file_height);
        if (status != 3 || file_width != WIDTH || file_height != HEIGHT)
            $fatal(1, "Vector header does not match viewport %0dx%0d", WIDTH, HEIGHT);

        repeat (2) @(negedge clk);
        rst = 0;
        case_name = "reset_while_stalled";
        submit(0, 0, 1, 0, 1, 1);
        repeat (3) begin
            @(posedge clk);
            if (frag_valid !== 1'b1 || frag_x !== 7'd0 || frag_y !== 7'd0 ||
                tri_ready !== 1'b0 || tri_done !== 1'b0)
                $fatal(1, "%s: expected a pending fragment at (0,0)", case_name);
        end
        @(negedge clk);
        rst = 1;
        @(negedge clk);
        rst = 0;
        @(posedge clk);
        if (tri_ready !== 1'b1 || frag_valid !== 1'b0 || tri_done !== 1'b0)
            $fatal(1, "%s: pending work survived reset", case_name);
        @(negedge clk);

        for (int index = 0; index < case_count; index++) begin
            status = $fscanf(vectors, "%s %d %d %d %d %d %d %d",
                             case_name, ax, ay, bx, by, cx, cy, expected_count);
            if (status != 8 || expected_count < 0)
                $fatal(1, "Malformed vector at case %0d", index);
            submit(ax, ay, bx, by, cx, cy);
            check_case(index, expected_count);
        end
        @(posedge clk);
        if (tri_ready !== 1'b1 || frag_valid !== 1'b0 || tri_done !== 1'b0)
            $fatal(1, "DUT did not return to idle after the final completion");
        if (stalled_cycles == 0 || empty_cases == 0 || nonempty_cases == 0)
            $fatal(1, "Missing required stall, empty, or nonempty coverage");
        $fclose(vectors);
        $display("PASS %0dx%0d seed=%0d triangles=%0d (empty=%0d) fragments=%0d stall_cycles=%0d reset_abort=1",
                 WIDTH, HEIGHT, seed, case_count, empty_cases, checked_fragments, stalled_cycles);
        $finish;
    end
endmodule

`default_nettype wire
