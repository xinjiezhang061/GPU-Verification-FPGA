"""Exact scanline oracle and deterministic regression-vector generator."""

import argparse
from fractions import Fraction
from itertools import permutations
from math import ceil
from pathlib import Path
from random import Random


def pixels(triangle, width, height):
    """Intersect each sample row with the triangle, then fill [left, right)."""
    edges = list(zip(triangle, triangle[1:] + triangle[:1]))
    for y in range(height):
        row = Fraction(2 * y + 1, 2)
        crossings = []
        for a, b in edges:
            (x0, y0), (x1, y1) = sorted((a, b), key=lambda p: p[1])
            if y0 <= row < y1:
                crossings.append(x0 + (row - y0) * Fraction(x1 - x0, y1 - y0))
        if len(crossings) == 2:
            left, right = sorted(crossings)
            start = max(0, ceil(left - Fraction(1, 2)))
            stop = min(width, ceil(right - Fraction(1, 2)))
            for x in range(start, stop):
                yield x, y


def check_oracle():
    a, b, c, d = (0, 0), (4, 0), (4, 4), (0, 4)
    first = set(pixels((a, b, c), 4, 4))
    second = set(pixels((a, c, d), 4, 4))
    assert first == {(x, y) for y in range(4) for x in range(y, 4)}
    assert second == {(x, y) for y in range(4) for x in range(y)}
    assert not first & second
    assert len(first | second) == 16
    assert list(pixels(((-3, -3), (0, 0), (3, 3)), 4, 4)) == []
    assert list(pixels(((-4, -4), (4, 0), (0, 4)), 1, 1)) == [(0, 0)]


def generate_cases(seed, count, width, height):
    a, b, c, d = (0, 0), (4, 0), (4, 4), (0, 4)
    directed = [
        ("shared_upper", (a, b, c)),
        ("shared_lower", (a, c, d)),
        ("shared_other_upper", (a, b, d)),
        ("shared_other_lower", (b, c, d)),
        ("single_pixel", ((0, 0), (1, 0), (1, 1))),
        ("last_pixel", ((width - 1, height - 1), (width, height - 1), (width, height))),
        ("collinear", ((-3, -3), (0, 0), (3, 3))),
        ("duplicate_vertex", ((0, 0), (0, 0), (4, 4))),
        ("all_equal", ((2, 2), (2, 2), (2, 2))),
        ("subpixel_coverage_empty", ((0, 0), (0, 1), (1, 1))),
        ("offscreen_left", ((-8, 0), (-1, 0), (-4, 6))),
        ("offscreen_right", ((width, 0), (width + 4, 0), (width + 2, 6))),
        ("offscreen_top", ((0, -8), (6, -8), (3, -1))),
        ("offscreen_bottom", ((0, height), (6, height), (3, height + 4))),
        ("clip_left_top", ((-4, -4), (6, 0), (0, 6))),
        ("clip_right_bottom", ((width - 4, height - 4), (width + 4, height - 4),
                               (width - 4, height + 4))),
        ("signed_extremes", ((-128, -128), (127, -128), (127, 127))),
        ("full_viewport", ((-width, -height), (3 * width, -height),
                           (-width, 3 * height))),
    ]
    for index, order in enumerate(permutations((a, b, c))):
        directed.append((f"permutation_{index}", order))

    rng = Random(seed)
    for name, triangle in directed:
        # Adapt positive overflow when testing the maximum supported viewport.
        yield name, tuple((min(x, 127), min(y, 127)) for x, y in triangle)
    for index in range(count):
        if index % 3 == 0:
            triangle = tuple((rng.randint(-128, 127), rng.randint(-128, 127))
                             for _ in range(3))
        else:
            triangle = tuple((rng.randint(-4, min(width + 4, 127)),
                              rng.randint(-4, min(height + 4, 127))) for _ in range(3))
        yield f"random_{index}", triangle


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--random-count", type=int, default=200)
    parser.add_argument("--width", type=int, default=32)
    parser.add_argument("--height", type=int, default=24)
    args = parser.parse_args()
    if not (1 <= args.width <= 128 and 1 <= args.height <= 128):
        parser.error("width and height must each be in 1..128")
    if args.random_count < 0:
        parser.error("random count must be nonnegative")

    check_oracle()
    cases = list(generate_cases(args.seed, args.random_count, args.width, args.height))
    total = 0
    with args.output.open("w", encoding="ascii") as out:
        print(len(cases), args.width, args.height, file=out)
        for name, triangle in cases:
            expected = list(pixels(triangle, args.width, args.height))
            total += len(expected)
            print(name, *(coord for vertex in triangle for coord in vertex),
                  len(expected), file=out)
            for x, y in expected:
                print(x, y, file=out)
    print(f"Oracle checks passed. Generated {len(cases)} triangles and {total} fragments "
          f"for {args.width}x{args.height} (seed {args.seed}).")


if __name__ == "__main__":
    main()
