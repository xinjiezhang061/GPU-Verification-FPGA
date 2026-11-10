`timescale 1ns/1ps
`default_nettype none

module triangle_rasterizer #(
    parameter int WIDTH = 32,   // Legal range for both dimensions: 1..128.
    parameter int HEIGHT = 24
) (
    input  logic clk,
    input  logic rst,
    input  logic tri_valid,
    output logic tri_ready,
    input  logic signed [7:0] x0, y0, x1, y1, x2, y2,
    output logic frag_valid,
    input  logic frag_ready,
    output logic [6:0] frag_x, frag_y,
    output logic tri_done
);
    typedef enum logic [1:0] {IDLE, SCAN, DONE} state_t;
    localparam logic [6:0] LAST_X = 7'(WIDTH - 1);
    localparam logic [6:0] LAST_Y = 7'(HEIGHT - 1);

    state_t state;
    int ax, ay, bx, by, cx, cy;
    int signed_area, sample_x, sample_y;
    int edge_ab, edge_bc, edge_ca;
    logic covered;

    // Coordinates are doubled before the cross product, so each sample
    // represents an exact half-integer pixel center.
    function automatic int edge_value(
        input int ux, uy, vx, vy, px, py
    );
        edge_value = (vx - ux) * (py - uy) - (vy - uy) * (px - ux);
    endfunction

    function automatic logic includes_edge(
        input int value, ux, uy, vx, vy
    );
        includes_edge = value > 0 ||
                        (value == 0 && (vy < uy || (vy == uy && vx > ux)));
    endfunction

    assign signed_area = edge_value(
        int'(x0), int'(y0), int'(x1), int'(y1), int'(x2), int'(y2)
    );
    assign sample_x = 2 * int'(frag_x) + 1;
    assign sample_y = 2 * int'(frag_y) + 1;
    assign edge_ab = edge_value(ax, ay, bx, by, sample_x, sample_y);
    assign edge_bc = edge_value(bx, by, cx, cy, sample_x, sample_y);
    assign edge_ca = edge_value(cx, cy, ax, ay, sample_x, sample_y);
    assign covered = includes_edge(edge_ab, ax, ay, bx, by) &&
                     includes_edge(edge_bc, bx, by, cx, cy) &&
                     includes_edge(edge_ca, cx, cy, ax, ay);

    assign tri_ready = !rst && state == IDLE;
    assign frag_valid = !rst && state == SCAN && covered;
    assign tri_done = !rst && state == DONE;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            frag_x <= '0;
            frag_y <= '0;
            ax <= 0;
            ay <= 0;
            bx <= 0;
            by <= 0;
            cx <= 0;
            cy <= 0;
        end else begin
            case (state)
                IDLE: if (tri_valid) begin
                    frag_x <= '0;
                    frag_y <= '0;
                    ax <= 2 * int'(x0);
                    ay <= 2 * int'(y0);
                    // Reorder vertices to give the edge tests a positive interior.
                    bx <= 2 * (signed_area < 0 ? int'(x2) : int'(x1));
                    by <= 2 * (signed_area < 0 ? int'(y2) : int'(y1));
                    cx <= 2 * (signed_area < 0 ? int'(x1) : int'(x2));
                    cy <= 2 * (signed_area < 0 ? int'(y1) : int'(y2));
                    state <= signed_area == 0 ? DONE : SCAN;
                end
                SCAN: if (!covered || frag_ready) begin
                    if (frag_x != LAST_X)
                        frag_x <= frag_x + 1'b1;
                    else if (frag_y != LAST_Y) begin
                        frag_x <= '0;
                        frag_y <= frag_y + 1'b1;
                    end else
                        state <= DONE;
                end
                DONE: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
