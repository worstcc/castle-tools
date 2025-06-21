#!/usr/bin/python3

import argparse
import math

def calculateMatrix(x1: float, y1: float, x2: float, y2: float) -> str:
    dx = x2 - x1
    dy = y2 - y1
    if dx == 0:
        if dy > 0:
            degrees = 90
        elif dy < 0:
            degrees = 270
        else:
            degrees = 0
    else:
        angle = math.degrees(math.atan(dy / dx))
        if dx > 0:
            degrees = angle
        else:
            degrees = angle + 180
        degrees = (degrees + 360) % 360
    width = math.sqrt(dx**2 + dy**2)
    scaleX = width / 64
    radians = math.radians(degrees)
    cos = math.cos(radians)
    sin = math.sin(radians)
    a = scaleX * cos
    b = scaleX * sin
    c = -sin
    d = cos
    e = x1 * 20
    f = y1 * 20
    matrix = f"MATRIX[{a:.3f},{b:.3f},{c:.3f},{d:.3f},{e:.3f},{f:.3f}]"
    return matrix

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("x1", type=float, help="first point X")
    parser.add_argument("y1", type=float, help="first point Y")
    parser.add_argument("x2", type=float, help="second point X")
    parser.add_argument("y2", type=float, help="second point Y")
    args = parser.parse_args()
    result = calculateMatrix(args.x1,args.y1,args.x2,args.y2)
    print(result)

