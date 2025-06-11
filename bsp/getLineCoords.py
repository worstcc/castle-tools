#! /usr/bin/python3

import math
import argparse

def calculate_coordinates(x1, y1, x2, y2):
    distance = round(math.sqrt((x1 - x2)**2 + (y1 - y2)**2), 7)

    if x2 - x1 == 0:
        if y2 - y1 > 0:
            angle = 90
        elif y2 - y1 < 0:
            angle = 270
        else:
            angle = 0
    else:
        slope = (y2 - y1) / (x2 - x1)
        angle = round(math.degrees(math.atan(slope)), 7)

    xPos = round((x1 + x2) / 2 - 32, 2)
    yPos = round((y1 + y2) / 2 - 4, 2)

    print(f"X,Y: {xPos},{yPos}")
    print(f"width: {distance}")
    print(f"angle: {angle}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("x1", type=float, help="X coordinate of the first point")
    parser.add_argument("y1", type=float, help="Y coordinate of the first point")
    parser.add_argument("x2", type=float, help="X coordinate of the second point")
    parser.add_argument("y2", type=float, help="Y coordinate of the second point")

    args = parser.parse_args()

    calculate_coordinates(args.x1, args.y1, args.x2, args.y2)
