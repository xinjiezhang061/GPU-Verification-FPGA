"""Compile a JSON scene or generate regression commands and expected pixels."""

import argparse
import json
from pathlib import Path
from random import Random

from reference import check_oracle, generate_cases, pixels


ZERO_VERTICES = ((0, 0),) * 3


def render(commands, width, height):
    frame = []
    for draw, triangle, color, depth in commands:
        if not draw:
            frame = [(color, depth)] * (width * height)
            continue
        for x, y in pixels(triangle, width, height):
            index = y * width + x
            if depth < frame[index][1]:
                frame[index] = (color, depth)
    return frame


def load_scene(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list) or not data or not isinstance(data[0], dict):
        raise ValueError("scene must be an array of commands starting with clear")
    if data[0].get("op") != "clear":
        raise ValueError("scene must start with clear")
    commands = []
    for index, command in enumerate(data, 1):
        if not isinstance(command, dict) or command.get("op") not in ("clear", "draw"):
            raise ValueError(f"command {index}: op must be clear or draw")
        draw = command["op"] == "draw"
        color = command.get("color")
        depth = command.get("depth")
        triangle = command.get("vertices") if draw else ZERO_VERTICES
        if not isinstance(color, str) or len(color) != 6 or any(
            c not in "0123456789abcdefABCDEF" for c in color
        ):
            raise ValueError(f"command {index}: color must have six RGB hex digits")
        if type(depth) is not int or not 0 <= depth <= 65535:
            raise ValueError(f"command {index}: depth must be an integer in 0..65535")
        if draw and (
            not isinstance(triangle, list) or len(triangle) != 3
            or any(not isinstance(vertex, list) or len(vertex) != 2 or any(
                type(coord) is not int or not -128 <= coord <= 127 for coord in vertex
            ) for vertex in triangle)
        ):
            raise ValueError(f"command {index}: vertices must be three signed 8-bit [x,y] pairs")
        commands.append((draw, triangle, int(color, 16), depth))
    return commands


def regression_scenes(width, height, seed):
    triangle = ((0, 0), (4, 0), (4, 4))
    clear = (False, ZERO_VERTICES, 0x102030, 65535)
    far = (True, triangle, 0xFF0000, 500)
    near = (True, triangle, 0x00FF00, 100)
    tie = (True, triangle, 0x0000FF, 100)
    equal_clear = (True, triangle, 0xFFFFFF, 65535)
    zero = (True, triangle, 0xF08030, 0)
    scenes = {
        "far_then_near": [clear, far, near, tie],
        "near_then_far": [clear, near, far, tie],
        "equal_clear_depth": [clear, equal_clear],
        "clear_after_draw": [clear, near, (False, ZERO_VERTICES, 0x451239, 321), far],
        "zero_depth": [clear, zero, near],
    }
    # Hand-derived checks at a pixel covered by every directed triangle.
    expected_first = [(0x00FF00, 100), (0x00FF00, 100), (0x102030, 65535),
                      (0x451239, 321), (0xF08030, 0)]
    for commands, expected in zip(scenes.values(), expected_first):
        assert render(commands, width, height)[0] == expected
    rng = Random(seed)
    scenes["mixed"] = [clear] + [
        (True, vertices, rng.randrange(1 << 24), rng.choice((0, 100, 500, 65535)))
        for _, vertices in generate_cases(seed, 12, width, height)
    ]
    return scenes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scene", type=Path)
    args = parser.parse_args()
    if not (1 <= args.width <= 128 and 1 <= args.height <= 128):
        parser.error("width and height must each be in 1..128")
    check_oracle()
    if args.scene is None:
        scenes = regression_scenes(args.width, args.height, args.seed)
    else:
        try:
            scenes = {"custom": load_scene(args.scene)}
        except (OSError, ValueError) as exc:
            parser.error(str(exc))
    with args.output.open("w", encoding="ascii") as out:
        print(len(scenes), args.width, args.height, file=out)
        for name, commands in scenes.items():
            print(name, len(commands), file=out)
            for draw, triangle, color, depth in commands:
                print(int(draw), *(coord for vertex in triangle for coord in vertex),
                      f"{color:06x}", f"{depth:04x}", file=out)
            for color, depth in render(commands, args.width, args.height):
                print(f"{color:06x}", f"{depth:04x}", file=out)
    print(f"Prepared {len(scenes)} scenes for {args.width}x{args.height} (seed {args.seed}).")


if __name__ == "__main__":
    main()
