# castle-tools

### Requirements:
- ruby (`winget install RubyInstallerTeam.Ruby.3.4`)
- rubyzip & nokogiri gems (after installing Ruby: `gem install rubyzip:3.0.2`,`gem install nokogiri`)
- JPEXS (latest nightly recommended) (https://github.com/jindrapetrik/jpexs-decompiler/releases) 
- ruffle (https://ruffle.rs/downloads)

### crypt.rb
- Decrypts PAK files to SWF/encrypts SWF files to PAK
- Supports both NREC (steam version) & BREC (XBLA/PS3 version) PAK files
- Fixes SWF file length when decrypting (fixes missing frames/assets in JPEXS)
- Can create BSP PAK files
- Based on original NREC decryption/encryption script by ethteck (https://github.com/ethteck/castlecrashers)

### deobfuscateSWF.rb
- Deobfuscates all AS2 (ActionScript 2.0) code in a SWF file (fixes §§ instructions & unknown 70s)

### compile.rb
- Encrypts all SWF files in an input directory then moves the created PAK files to a output (game) directory
- Useful for quickly applying changes made to SWF files into the game

### fixSWFTags.rb
- For input SWF: renumbers & reorders tags, fixes pixl (unknown) tags from crashing the game, set hasEndTag to true for all sprites

### bsp directory
- Contains files for creating custom BSP PAKs (info in "bspGuide.txt")

### levelTemplate directory
- Contains SWF & AS files for a blank level template

# Usage examples

### Decrypt PAK file (NREC/BREC)
```
./crypt.rb $PAKFILE $OUTDIR
```

### Encrypt SWF file to NREC PAK
```
./crypt.rb --encrypt $SWFFILE $OUTDIR 
```

### Create BSP PAK file using a level SWF as input
```
./crypt.rb --bsp --bspname $BSPNAME $SWFFILE $OUTDIR
```

### Encrypt SWF file to BREC PAK
```
./crypt.rb --brec --encrypt $SWFFILE $OUTDIR
```

### Encrypt SWF files in a directory then move the PAK files to a game data directory
```
./compile.rb $INDIR $GAMEDIR
```

### Encrypt SWF files in a directory then move the PAK files to a game data directory (BREC)
```
./compile.rb --brec $INDIR $GAMEDIR
```

### Deobfuscate AS2 in a SWF file
```
./deobfuscateSWF.rb $SWFFILE
```

### Precisely place down a BSP line in JPEXS using matrix copy & paste
```
./bsp/getLineCoords.rb $X1 $Y1 $X2 $Y2
```
