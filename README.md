# castle-tools

### ccCrypt.py
- Decrypts PAK files to SWF/encrypts SWF files to PAK
- Supports both NREC (steam version) & BREC (XBLA/PS3 version) PAK files
- Fixes SWF file length when decrypting (fixes missing frames/assets in JPEXS)
- Can create BSP PAK files
- Requires blowfish (`pip install blowfish`)
- Requires ruffle for BSP creation (https://ruffle.rs/downloads)
- Original NREC decryption/encryption script by ethteck (https://github.com/ethteck/castlecrashers)

### ccDeobsfucate.py
- Deobsfucates AS2 (ActionScript 2.0) code (fixes §§ instructions & unknown 70s)
- Uses "ccDeobsfucate.txt" as input (contains AS2 hex data), then overwrites the file with deobsfucated hex data

### ccCompile.py
- Encrypts all SWF files in an input directory then moves the created PAK files to a output (game) directory
- Useful for quickly applying changes made to SWF files into the game

### bsp directory
- Contains files for creating custom BSP PAKs (info in "bspGuide.txt")

### levelTemplate directory
- Contains SWF & AS files for a blank level template

# Usage examples
- On Windows, use `py .\SCRIPT.py` to run a python script
  - If `py` or `pip` doesn't work, uninstall Python, then reinstall using winget (`winget install Python.Python.3.9`)
- On Linux, use `./SCRIPT.py`

### Decrypt PAK file (NREC/BREC)
```
ccCrypt.py $PAKFILE $OUTDIR
```

### Encrypt SWF file to NREC PAK
```
ccCrypt.py --encrypt $SWFFILE $OUTDIR 
```

### Encrypt SWF file to BREC PAK
```
ccCrypt.py --brec --encrypt $SWFFILE $OUTDIR
```

### Create BSP PAK file
```
ccCrypt.py --bsp $BSPNAME $OUTDIR
```

### Deobsfucate AS2 hex data in "ccDeobsfucate.txt"
```
ccDeobsfucate.py
```

### Encrypt SWF files in a directory then move the PAK files to a game data directory
```
ccCompile.py $INDIR $GAMEDIR
```

### Encrypt SWF files in a directory then move the PAK files to a game data directory (BREC)
```
ccCompile.py --brec $INDIR $GAMEDIR
```
