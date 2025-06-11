# castle-tools

### ccCrypt.py
- Decrypts PAK files to SWF/encrypts SWF files to PAK
- Supports both NREC (steam version) & BREC (XBLA/PS3 version) PAK files
- Fixes SWF file length when decrypting (fixes missing frames/assets in JPEXS)
- Creates BSP PAK files using "bsp.swf"
- Requires blowfish (`pip install blowfish`)
- Requires ruffle for BSP creation (https://ruffle.rs/downloads)
- Original NREC decryption/encryption script by ethteck (https://github.com/ethteck/castlecrashers)

### ccDeobsfucate.py
- Deobsfucates ActionScript code (removes §§ instructions, fixes unknown 70s)
- Uses "ccDeobsfucate.txt" as input (contains ActionScript hex data), then overwrites the file with deobsfucated hex data

### bsp directory
- Contains files to assist in creating custom BSP files (info in "bspGuide.txt")

# Usage examples
- On Windows, use `py .\SCRIPT.py` to run a python script
  - If `py` or `pip` doesn't work, install Python using winget (`winget install Python.Python.3.9`)
- On Linux, use `./SCRIPT.py`

### Decrypt PAK file (NREC/BREC)
```
py .\ccCrypt.py $PAKFILE $OUTDIR
```

### Encrypt SWF file to NREC PAK
```
py .\ccCrypt.py --encrypt $SWFFILE $OUTDIR 
```

### Encrypt SWF file to BREC PAK
```
py .\ccCrypt.py --brec --encrypt $SWFFILE $OUTDIR
```

### Create BSP PAK file
```
py .\ccCrypt.py --bsp $BSPNAME $OUTDIR
```
