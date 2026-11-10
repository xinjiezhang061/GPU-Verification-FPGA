`timescale 1ns/1ps
`default_nettype none

module gpu_renderer #(
    parameter int WIDTH = 32,
    parameter int HEIGHT = 24
) (
    input  logic clk,
    input  logic rst,
    input  logic cmd_valid,
    output logic cmd_ready,
    input  logic cmd_draw,  // 0: clear, 1: draw.
    input  logic signed [7:0] x0, y0, x1, y1, x2, y2,
    input  logic [23:0] cmd_color,
    input  logic [15:0] cmd_depth,
    output logic cmd_done,
    input  logic read_valid,
    output logic read_ready,
    input  logic [6:0] read_x, read_y,
    output logic pixel_valid,
    output logic [23:0] pixel_color,
    output logic [15:0] pixel_depth
);
    localparam int PIXELS = WIDTH * HEIGHT;
    localparam int ADDR_BITS = PIXELS > 1 ? $clog2(PIXELS) : 1;
    localparam logic [ADDR_BITS-1:0] LAST_PIXEL = ADDR_BITS'(PIXELS - 1);

    typedef enum logic [1:0] {IDLE, CLEAR, DRAW, DONE} state_t;
    state_t state;
    logic [39:0] framebuffer [0:PIXELS-1]; // {depth, RGB}
    logic [39:0] draw_data, prior_pixel;
    logic [ADDR_BITS-1:0] clear_address, pending_address, memory_address;
    logic raster_ready, raster_done, frag_valid, frag_ready, pending;
    logic [6:0] frag_x, frag_y;
    logic read_in_bounds, read_hit, accept_read, accept_fragment;

    assign cmd_ready = !rst && state == IDLE && (!cmd_draw || raster_ready);
    assign read_ready = !rst && state == IDLE && !cmd_valid;
    assign cmd_done = !rst && state == DONE;
    assign frag_ready = !rst && state == DRAW && !pending;
    assign accept_read = read_ready && read_valid;
    assign accept_fragment = frag_ready && frag_valid;
    assign read_in_bounds = int'(read_x) < WIDTH && int'(read_y) < HEIGHT;

    triangle_rasterizer #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) rasterizer (
        .clk(clk), .rst(rst), .tri_valid(cmd_valid && cmd_ready && cmd_draw),
        .tri_ready(raster_ready), .x0(x0), .y0(y0), .x1(x1), .y1(y1),
        .x2(x2), .y2(y2), .frag_valid(frag_valid), .frag_ready(frag_ready),
        .frag_x(frag_x), .frag_y(frag_y), .tri_done(raster_done)
    );

    // Fragment fetches and host reads share a synchronous memory read port.
    assign memory_address = accept_fragment
        ? ADDR_BITS'(int'(frag_y) * WIDTH + int'(frag_x))
        : ADDR_BITS'(int'(read_y) * WIDTH + int'(read_x));

    always_ff @(posedge clk) begin
        if (accept_fragment || (accept_read && read_in_bounds))
            prior_pixel <= framebuffer[memory_address];

        if (!rst && state == CLEAR)
            framebuffer[clear_address] <= draw_data;
        else if (!rst && state == DRAW && pending && draw_data[39:24] < prior_pixel[39:24])
            framebuffer[pending_address] <= draw_data;
    end

    assign {pixel_depth, pixel_color} = read_hit ? prior_pixel : 40'b0;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            pixel_valid <= 0;
            read_hit <= 0;
            pending <= 0;
            draw_data <= '0;
            clear_address <= '0;
            pending_address <= '0;
        end else begin
            pixel_valid <= accept_read;
            read_hit <= accept_read && read_in_bounds;
            pending <= accept_fragment;
            if (accept_fragment)
                pending_address <= memory_address;

            case (state)
                IDLE: if (cmd_valid && cmd_ready) begin
                    draw_data <= {cmd_depth, cmd_color};
                    clear_address <= '0;
                    if (cmd_draw)
                        state <= DRAW;
                    else
                        state <= CLEAR;
                end
                CLEAR: if (clear_address == LAST_PIXEL)
                    state <= DONE;
                else
                    clear_address <= clear_address + 1'b1;
                DRAW: if (raster_done)
                    // If the last fragment is pending, it commits on this edge.
                    state <= DONE;
                DONE: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
