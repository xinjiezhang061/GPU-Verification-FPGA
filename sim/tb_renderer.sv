`timescale 1ns/1ps
`default_nettype none

module tb_renderer #(
    parameter int WIDTH = 32,
    parameter int HEIGHT = 24
);
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;
    logic cmd_valid = 0, cmd_ready, cmd_draw = 0, cmd_done;
    logic signed [7:0] x0 = 0, y0 = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0;
    logic [23:0] cmd_color = 0, pixel_color;
    logic [15:0] cmd_depth = 0, pixel_depth;
    logic read_valid = 0, read_ready, pixel_valid;
    logic [6:0] read_x = 0, read_y = 0;
    gpu_renderer #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) dut (.*);

    string vectors_path, ppm_path, scene;
    int vectors, ppm, scene_count, file_width, file_height, command_count;
    int draw, ax, ay, bx, by, cx, cy, total_commands = 0, total_pixels = 0;
    logic [23:0] color;
    logic [15:0] depth;

    // Task entry and return are on falling edges.
    task automatic send_command(
        input logic draw_op,
        input int a_x, a_y, b_x, b_y, c_x, c_y,
        input logic [23:0] rgb,
        input logic [15:0] z
    );
        cmd_valid = 1;
        cmd_draw = draw_op;
        cmd_color = rgb;
        cmd_depth = z;
        x0 = 8'(a_x); y0 = 8'(a_y);
        x1 = 8'(b_x); y1 = 8'(b_y);
        x2 = 8'(c_x); y2 = 8'(c_y);
        // Offer a read in the same cycle to check command priority.
        read_valid = 1;
        @(posedge clk);
        if (cmd_ready !== 1'b1 || read_ready !== 1'b0 || cmd_done !== 1'b0)
            $fatal(1, "%s: command handshake or read arbitration failed", scene);
        @(negedge clk);
        cmd_valid = 0;
        read_valid = 0;
        cmd_color = '0;
        cmd_depth = '0;
        x0 = 0; y0 = 0; x1 = 0; y1 = 0; x2 = 0; y2 = 0;
    endtask

    task automatic wait_for_done(input int command_index);
        logic complete;
        complete = 0;
        for (int cycle = 0; cycle < 2 * WIDTH * HEIGHT + 8 && !complete; cycle++) begin
            @(posedge clk);
            if (cmd_ready !== 1'b0 || read_ready !== 1'b0 || pixel_valid !== 1'b0)
                $fatal(1, "%s: invalid busy outputs for command %0d", scene, command_index);
            complete = cmd_done === 1'b1;
            @(negedge clk);
        end
        if (!complete)
            $fatal(1, "%s: command %0d timed out", scene, command_index);
        total_commands++;
    endtask

    task automatic check_pixel(
        input int x, y,
        input logic [23:0] expected_color,
        input logic [15:0] expected_depth
    );
        read_valid = 1;
        read_x = 7'(x);
        read_y = 7'(y);
        @(posedge clk);
        if (read_ready !== 1'b1 || cmd_done !== 1'b0)
            $fatal(1, "%s: readback handshake failed", scene);
        #1;
        if (pixel_valid !== 1'b1 || pixel_color !== expected_color || pixel_depth !== expected_depth)
            $fatal(1, "%s: pixel (%0d,%0d) got %06h/%04h, expected %06h/%04h",
                   scene, x, y, pixel_color, pixel_depth, expected_color, expected_depth);
        if (ppm)
            $fdisplay(ppm, "%0d %0d %0d", pixel_color[23:16], pixel_color[15:8], pixel_color[7:0]);
        @(negedge clk);
        read_valid = 0;
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vectors_path))
            $fatal(1, "Missing +VECTORS=<path>");
        if ($test$plusargs("WAVES")) begin
            $dumpfile("renderer.vcd");
            $dumpvars(0, tb_renderer);
        end
        vectors = $fopen(vectors_path, "r");
        if (!vectors)
            $fatal(1, "Cannot open %s", vectors_path);
        if ($fscanf(vectors, "%d %d %d", scene_count, file_width, file_height) != 3 ||
            scene_count < 1 || file_width != WIDTH || file_height != HEIGHT)
            $fatal(1, "Invalid scene header for %0dx%0d", WIDTH, HEIGHT);

        repeat (2) @(negedge clk);
        rst = 0;
        scene = "reset_during_draw";
        send_command(0, 0, 0, 0, 0, 0, 0, 24'habcdef, 16'hffff);
        wait_for_done(0);
        send_command(1, 0, 0, 1, 0, 1, 1, 24'h123456, 16'h0001);
        @(negedge clk); // Fragment (0,0) has been fetched and is pending.
        rst = 1;
        @(negedge clk);
        rst = 0;
        @(posedge clk);
        if (cmd_ready !== 1'b1 || read_ready !== 1'b1 ||
            cmd_done !== 1'b0 || pixel_valid !== 1'b0)
            $fatal(1, "Reset did not abort pending draw");
        @(negedge clk);

        for (int index = 0; index < scene_count; index++) begin
            if ($fscanf(vectors, "%s %d", scene, command_count) != 2 || command_count < 1)
                $fatal(1, "Invalid scene record %0d", index);
            for (int command_index = 0; command_index < command_count; command_index++) begin
                if ($fscanf(vectors, "%d %d %d %d %d %d %d %h %h",
                            draw, ax, ay, bx, by, cx, cy, color, depth) != 9)
                    $fatal(1, "%s: invalid command %0d", scene, command_index);
                send_command(draw != 0, ax, ay, bx, by, cx, cy, color, depth);
                wait_for_done(command_index);
            end
            if (index == scene_count - 1 && $value$plusargs("PPM=%s", ppm_path)) begin
                ppm = $fopen(ppm_path, "w");
                if (!ppm)
                    $fatal(1, "Cannot open %s", ppm_path);
                $fdisplay(ppm, "P3\n%0d %0d\n255", WIDTH, HEIGHT);
            end
            for (int y = 0; y < HEIGHT; y++) begin
                for (int x = 0; x < WIDTH; x++) begin
                    if ($fscanf(vectors, "%h %h", color, depth) != 2)
                        $fatal(1, "%s: missing expected pixel (%0d,%0d)", scene, x, y);
                    check_pixel(x, y, color, depth);
                    total_pixels++;
                end
            end
            if (ppm) begin
                $fclose(ppm);
                ppm = 0;
            end
            if (WIDTH < 128)
                check_pixel(WIDTH, 0, '0, '0);
            if (HEIGHT < 128)
                check_pixel(0, HEIGHT, '0, '0);
            @(posedge clk);
            #1;
            if (pixel_valid !== 1'b0)
                $fatal(1, "%s: unsolicited read response", scene);
            @(negedge clk);
        end
        $fclose(vectors);
        $display("PASS renderer %0dx%0d scenes=%0d commands=%0d readback_pixels=%0d reset_abort=1",
                 WIDTH, HEIGHT, scene_count, total_commands, total_pixels);
        $finish;
    end
endmodule

`default_nettype wire
