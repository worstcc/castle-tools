#!/usr/bin/python3

import os
import glob
import subprocess
import argparse
import sys
from pathlib import Path

def movePak(file, dir):
    filename = os.path.basename(file)
    if "level" in filename:
        dest = os.path.join(dir, "levels", filename)
    elif "bsp" in filename:
        dest = os.path.join(dir, "bsps", filename)
    else:
        dest = os.path.join(dir, "game", filename)
    if os.path.exists(dest):
        os.remove(dest)
    os.rename(file, dest)
    print(filename)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("indir", type=str, help="input directory")
    parser.add_argument("gamedir", type=str, help="game data directory (contains 'game', 'levels' directories)")
    parser.add_argument("--brec", action="store_true", help="encrypt SWFs to BREC format (XBLA/PS3)")
    args = parser.parse_args()

    indir = os.path.abspath(args.indir)
    gamedir = os.path.abspath(args.gamedir)

    if not os.path.isdir(indir):
        raise RuntimeError("indir is not a valid directory")
    if not os.path.isdir(gamedir):
        raise RuntimeError("gamedir is not a valid directory")

    ccCrypt = Path(__file__).parent / "ccCrypt.py"
    if not ccCrypt.is_file():
        raise RuntimeError("ccCrypt.py missing from script directory")

    os.chdir(indir)

    # move already existing PAK files
    for file in glob.glob("*.pak"):
        movePak(file, gamedir)

    # get SWF files, sorted from least size to most size
    swfFiles = sorted(glob.glob("*.swf"), key=os.path.getsize)
    for file in swfFiles:
        if args.brec:
            subprocess.run([sys.executable, str(Path(__file__).parent / "ccCrypt.py"), "--brec", "--encrypt", file, "."])
        else:
            subprocess.run([sys.executable, str(Path(__file__).parent / "ccCrypt.py"), "--encrypt", file, "."])

        pakFile = os.path.splitext(file)[0].lower() + ".pak"
        movePak(pakFile, gamedir)
