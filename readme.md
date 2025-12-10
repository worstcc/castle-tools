# castle-tools

## Dependencies:
- Ruby (scripts)
- ImageMagick (pixl tag creation)
- JPEXS (commandline operations)
- Ruffle (bsp creation)

## Installation:
Clone/download the repository, then install dependencies:
### Windows
- Install Ruby (`winget install RubyInstallerTeam.RubyWithDevKit.3.4`)
- Download [ImageMagick](https://github.com/ImageMagick/ImageMagick/releases) (Show all assets -> choose Q16-HDRI-x64-dll exe), check "Install development headers for C and C++" in installer)
### Linux
- Install Ruby & ImageMagick with system package manager (if on Debian-based/Mint, use [brew](https://brew.sh) to install)

In the repository, run:
```
gem install bundler
bundle install
```

## Scripts

### crypt.rb
- Decrypts pak files to swf/encrypts swf files to pak
- Supports both nrec (steam version) & brec (xbla/ps3 version) pak files
- Fixes swf file length when decrypting (fixes missing frames/assets in JPEXS)
- Can create bsp pak files
- Based on original nrec decryption/encryption script by ethteck (https://github.com/ethteck/castlecrashers)

### deobfuscateSwf.rb
- Deobfuscates all ActionScript 2.0 code in a swf file (fixes §§ instructions & unknown 70s)

### compile.rb
- Encrypts all swf files in an input directory then moves the created pak files to a output (game) directory
- Useful for quickly applying changes made to swf files into the game

### fixSwfTags.rb
- Renumbers & reorders tags, fixes pixl (unknown) tags from crashing the game, set hasEndTag to true for all sprites in a swf file

### pixl.rb
- Imports images to swf as pixl tags
- Exports pixl tags from swf as images

### bsp directory
- Contains files for creating custom bsp paks (info in "bspGuide.txt")

### levelTemplate directory
- Contains swf & as files for a blank level template

Most scripts have options which can be seen by running the script with the `--help` parameter.

## Usage examples

### Decrypt pak file (nrec/brec)
```
./crypt.rb [pak file] [output directory]
```

### Encrypt swf file to nrec pak
```
./crypt.rb --encrypt [swf file] [output directory]
```

### Create bsp pak file using a level swf as input
```
./crypt.rb --bsp --bspname [bsp name] [swf] [output directory]
```

### Encrypt swf file to brec pak
```
./crypt.rb --brec --encrypt [swf file] [output directory]
```

### Encrypt swf files in a directory then move the pak files to a game data directory
```
./compile.rb [input directory] [game data directory]
```

### Encrypt swf files in a directory then move the pak files to a game data directory (brec)
```
./compile.rb --brec [input directory] [game data directory]
```

### Deobfuscate AS2 in a swf file
```
./deobfuscateSwf.rb [swf file]
```

### Reorder tag IDs, fix pixl tag/hasEndTag crashes in a swf file
```
./fixSwfTags.rb [swf file]
```

### Import an image to a swf file as a pixl tag
```
./pixl.rb [png file] [output directory]
```

### Export images from pixl tags in a swf
```
./pixl.rb [swf file] [output directory]
```

### Precisely place down a BSP line in JPEXS using matrix copy & paste
```
./bsp/getLineCoords.rb $X1 $Y1 $X2 $Y2
```
