#! /usr/bin/python3

import argparse
import zipfile
import blowfish
import subprocess
import struct
import os
import shutil
from typing import Optional
from ctypes import c_uint16, c_uint32
from pathlib import Path

keystrings = [
    b"\x1b\xbf\x18\xcc\x86\x5d\xf4\x25\x07\xc3\xe5\xb3\xb9\x04\x5a\x14\xd7\xfc\x4c\x86\x8d\x4a\xcb\x8f",
    b"\x24\x53\x4a\x1e\xda\x06\x85\x5f\x7a\xc1\xb6\x8a\x76\x41\x20\xcb\x1f\xce\x61\xd6\xad\x74\x6b\x0f",
    b"\x77\x82\x1e\x54\x89\xd7\x87\xb6\x05\xf9\x64\xcc\x57\x0b\xcf\x8b\xf8\xd2\x35\x80\x9c\xbf\x9e\x19",
    b"\x5a\x8d\x84\x20\x6e\x90\xfb\x91\x1f\x48\xe0\xee\xc2\x03\xa2\xaf\x60\x2f\x93\xd6\xa8\x50\x2c\xe2",
]

key_swap_indexes = [
    [ 8, 10, 12, 17 ],
    [ 1, 2, 10, 15 ],
    [ 0, 9, 12, 16 ],
    [ 5, 6, 11, 14 ],
]

def write_file(data: bytes, path: Path):
    with open(path, 'wb') as f:
        f.write(data)

def unzipFile(infile: Path):
    with zipfile.ZipFile(infile, 'r') as f:
        infolist = f.infolist()
        if len(infolist) > 1:
            raise RuntimeError("More than one file in archive")
        cok6 = infolist[0]
        with f.open(cok6, "r") as fo:
            return cok6.filename.upper(), fo.read()

def get_blowfish_key(name: str, data_len: int) -> bytes:
    name_crc = c_uint32(0)
    for i in range(len(name)):
        name_crc = c_uint32(name_crc.value * 0x25)
        name_crc = c_uint32(name_crc.value + ord(name[i]))

    # Do some math on the size of the .COK6.NREC to get a value from 0 to 15
    size_tmp = c_uint32(int(data_len / 16) % 16)

    # Select one of the 4 keystrings (division of the size var by 4)
    key_indexes = key_swap_indexes[int(size_tmp.value / 4)]

    # Select one of the 4 key byte arrays (mod of the size var by 4)
    mf3b = keystrings[size_tmp.value % 4]

    key = bytearray(mf3b[0:18])

    # Swap some 4 of the bytes out of the key with values based on the name crc
    for i in key_indexes:
        key[i] = name_crc.value & 0xFF
        name_crc = c_uint32(name_crc.value >> 8)

    return bytes(key)

def blowfish_decrypt(name: str, data: bytes) -> bytes:
    key = get_blowfish_key(name, len(data))

    cipher = blowfish.Cipher(key, byte_order="little")
    return b"".join(cipher.decrypt_ecb(data))

def blowfish_encrypt(name: str, data: bytes) -> bytes:
    key = get_blowfish_key(name, len(data))

    cipher = blowfish.Cipher(key, byte_order="little")
    return b"".join(cipher.encrypt_ecb(data))

def calc_checksum(data: bytes) -> int:
    result = c_uint32(0)
    work = c_uint16(0xD971)
    for b in data:
        tmp = b ^ (work.value >> 8)
        work = c_uint16(0x58BF + 0xCE6D * (work.value + tmp))
        result = c_uint32(result.value + tmp)
    return result.value

def validate_checksum(data: bytes):
    ck1 = int.from_bytes(data[-4:], byteorder="little")
    ck2 = calc_checksum(data[:-4] + b'\0\0\0\0')
    if ck1 != ck2:
        raise RuntimeError("Checksum mismatch: {:08X} (actual) != {:08X} (computed)".format(ck1, ck2))

def buildHeaderNREC(data: bytes) -> bytes:
    ret = b''

    ret = bytearray(0x80)
    ret[0:4] = b'6KOC'
    ret[0x10:0x14] = len(data).to_bytes(4, byteorder="little")
    ret[0x14:0x18] = 0x80.to_bytes(4, byteorder="little")

    return bytes(ret)

def buildFooterNREC(data: bytes) -> bytes:
    ret = b''

    # Add initial padding to align the file to 4 bytes
    align_4_len = 4 - (len(data) % 4)
    if align_4_len == 4:
        align_4_len = 0
    ret += b'\0' * align_4_len

    # Add 0x14, 1
    ret += b'\x14\x00\x00\x00\x01\x00\x00\x00'

    # Add padding to align the final file to 16 bytes (existing data, footer so far, int for number of zeros, int for checksum)
    align_16_len = 16 - ((len(data + ret) + 8) % 16)

    if align_16_len == 16:
        align_16_len = 0
    ret += b'\0' * align_16_len

    # Add a u32 describing the number of zeros added + 8
    ret += (align_16_len + 8).to_bytes(4, byteorder="little")

    # Add a space for the checksum
    ret += b'\0\0\0\0'

    return ret

def decryptSWFNREC(data: bytes):
    out_size = int.from_bytes(data[0x10:0x14], byteorder="little")
    out_offset = int.from_bytes(data[0x14:0x18], byteorder="little")
    return data[out_offset:out_size + out_offset]

def decryptSWFBREC(data: bytes):
    out_size = int.from_bytes(data[0x10:0x14], byteorder="big")
    out_offset = int.from_bytes(data[0x14:0x18], byteorder="big")
    return data[out_offset:out_size + out_offset]

def decryptNREC(infile: Path, outdir: Optional[Path]):
    print("decrypting " + infile.name + " (NREC)")

    name, input_data = unzipFile(infile)

    blowfish_decrypted = blowfish_decrypt(name, input_data)

    # Sanity checks: validate checksum, confirm we can properly rebuild the footer
    validate_checksum(blowfish_decrypted)

    swf_bytes = decryptSWFNREC(blowfish_decrypted)
    newSWFBytes = swf_bytes

    # remove "CD" bytes and everything after
    cdcd_index = newSWFBytes.rfind(b'\x40\x00\00\00\xCD')
    if cdcd_index != -1:
        newSWFBytes = newSWFBytes[:cdcd_index + 4]
    # update SWF header file length
    new_length = len(newSWFBytes)
    newSWFBytes = newSWFBytes[:4] + new_length.to_bytes(4, byteorder='little') + newSWFBytes[8:]

    footer_data = buildFooterNREC(swf_bytes)
    if footer_data[:-4] != blowfish_decrypted[-len(footer_data):-4]:
        raise RuntimeError("Footer mismatch")

    raw_name = name.split(".")[0]

    write_file(newSWFBytes, outdir / (raw_name + ".swf"))

def encryptNREC(infile: Path, outdir: Optional[Path] = None):
    print("encrypting " + infile.name + " (NREC)")

    with open(infile, "rb") as f:
        swf_data = f.read()

    pre_compression_data = buildHeaderNREC(swf_data)
    pre_compression_data += swf_data
    pre_compression_data += buildFooterNREC(pre_compression_data)

    checksum = calc_checksum(pre_compression_data)

    pre_compression_data = pre_compression_data[:-4] + checksum.to_bytes(4, byteorder="little")

    archive_name = infile.stem.upper() + ".COK6.NREC"

    blowfish_encrypted = blowfish_encrypt(archive_name, pre_compression_data)

    zip_path = outdir / (infile.stem.lower() + ".pak")

    zipFile(zip_path, archive_name, blowfish_encrypted)

def padPDAG(data: bytes, blockSize: int = 8) -> bytes:
    totalLength = len(data) + 4
    padLength = (blockSize - (totalLength % blockSize)) % blockSize
    return data + (b'\x00' * padLength)

def decryptBREC(infile: Path, outdir: Optional[Path]):
    print("decrypting " + infile.name + " (BREC)")
    name, input_data = unzipFile(infile)
    swf_bytes = decryptSWFBREC(input_data)
    # remove "CD" bytes and everything after
    cdcd_index = swf_bytes.rfind(b'\x40\x00\00\00\xCD')
    if cdcd_index != -1:
        swf_bytes = swf_bytes[:cdcd_index + 4]
    # update SWF header file length
    new_length = len(swf_bytes)
    swf_bytes = swf_bytes[:4] + new_length.to_bytes(4, byteorder='little') + swf_bytes[8:]
    raw_name = name.split(".")[0]
    write_file(swf_bytes, outdir / (raw_name + ".swf"))

def zipFile(outfile: Path, archive_name: str, data: bytes):
    with zipfile.ZipFile(outfile, 'w') as f:
        with f.open(archive_name, "w") as fo:
            fo.write(data)

def buildHeaderBREC(data: bytes) -> bytes:
    ret = b''

    ret = bytearray(0x80)
    ret[0:4] = b'COK6'
    ret[0x10:0x14] = len(data).to_bytes(4, byteorder="big")
    ret[0x14:0x18] = 0x80.to_bytes(4, byteorder="big")

    return bytes(ret)

def buildFooterBREC(data: bytes) -> bytes:
    ret = b'\xCD\xCD'

    # Add initial padding to align the file to 4 bytes
    align_4_len = 4 - (len(data + ret) % 4)
    if align_4_len == 4:
        align_4_len = 0
    ret += b'\0' * align_4_len

    # Add 0x14, 1
    ret += b'\x00\x00\x00\x14\x00\x00\x00\x01'

    return ret

def decryptPDAGNREC(infile: Path, outdir: Optional[Path]):
    print("decrypting " + infile.name + " (NREC)")

    name, input_data = unzipFile(infile)

    blowfish_decrypted = blowfish_decrypt(name, input_data)

    # remove checksum footer
    blowfish_decrypted = blowfish_decrypted[:-8]

    raw_name = name.split(".")[0]

    write_file(blowfish_decrypted, outdir / (raw_name + ".pdag"))

def decryptPDAGBREC(infile: Path, outdir: Optional[Path]):
    print("decrypting " + infile.name + " (BREC)")
    name, input_data = unzipFile(infile)
    pdagBytes = decryptSWFBREC(input_data)
    raw_name = name.split(".")[0]
    write_file(pdagBytes, outdir / (raw_name + ".pdag"))

def encryptBREC(infile: Path, outdir: Optional[Path] = None):
    print("encrypting " + infile.name + (" (BREC)"))
    with open(infile, "rb") as f:
        swf_data = f.read()
    pre_compression_data = buildHeaderBREC(swf_data)
    pre_compression_data += swf_data
    pre_compression_data += buildFooterBREC(pre_compression_data)
    archive_name = infile.stem.upper() + ".COK6.BREC"
    zip_path = outdir / (infile.stem.lower() + ".pak")
    zipFile(zip_path, archive_name, pre_compression_data)

def decryptFile(infile, outdir):
    with zipfile.ZipFile(infile, 'r') as zf:
        fileList = zf.namelist()
        isPDAG = any('PDAG' in f for f in fileList)
        hasNREC = any(f.endswith('.NREC') for f in fileList)
        hasBREC = any(f.endswith('.BREC') for f in fileList)
        if(hasNREC):
            if(isPDAG):
                decryptPDAGNREC(infile, outdir)
            else:
                decryptNREC(infile, outdir)
        if(hasBREC):
            if(isPDAG):
                decryptPDAGBREC(infile, outdir)
            else:
                decryptBREC(infile, outdir)

def buildHeaderPDAGNREC(data: int) -> bytes:
    ret = b''

    ret = bytearray(0x14)
    ret[0:4] = b'GADP'
    ret[0x10:0x14] = data.to_bytes(4, byteorder="little")

    return bytes(ret)

def encryptPDAGNREC(infile: Path, outdir: Optional[Path] = None):
    print("encrypting " + infile.stem.lower() + " (NREC)")

    with open(infile, "rb") as f:
        pdagData = f.read()

    paddedData = padPDAG(pdagData)

    checksum = calc_checksum(paddedData + b'\0\0\0\0')
    pdagWithChecksum = paddedData + checksum.to_bytes(4, byteorder="little")

    archiveName = infile.stem.upper() + ".PDAG.NREC"
    encryptedData = blowfish_encrypt(archiveName, pdagWithChecksum)

    outputPath = outdir / (infile.stem.lower() + ".pak")
    zipFile(outputPath, archiveName, encryptedData)

def buildHeaderPDAGBREC(data: int) -> bytes:
    ret = b''

    ret = bytearray(0x14)
    ret[0:4] = b'PDAG'
    ret[0x10:0x14] = data.to_bytes(4, byteorder="big")

    return bytes(ret)

def encryptPDAGBREC(infile: Path, outdir: Optional[Path] = None):
    print("encrypting " + infile.stem.lower() + " (BREC)")

    with open(infile, "rb") as f:
        pdagData = f.read()

    paddedData = padPDAG(pdagData)

    archiveName = infile.stem.upper() + ".PDAG.BREC"

    outputPath = outdir / (infile.stem.lower() + ".pak")
    zipFile(outputPath, archiveName, paddedData)

def createBSP(bspname: str, brec: Optional[bool] = False):
    scriptDir = Path(__file__).parent
    bspSWF = scriptDir / "bsp" / "bsp.swf"

    if not bspSWF.exists():
        raise RuntimeError("bsp/bsp.swf missing in script directory")

    # check if ruffle is installed
    if shutil.which("ruffle") is None:
        raise RuntimeError("ruffle is not installed on the system/not in PATH (download: https://ruffle.rs/downloads)")

    process = subprocess.run(["ruffle", "--scale", "no-scale", str(bspSWF)], capture_output=True, text=True)
    output = process.stdout

    filteredOutput = []
    for line in output.splitlines():
        if "error: no lines" in line:
            raise RuntimeError("no lines in BSP SWF")
        if "BSPEND" in line: # don't include traces not output by BSP script
            break
        if "avm_trace" in line: # collect BSP trace lines
            filteredOutput.append(line[78:])

    # handle BSP data
    waypoints = False
    lineLength = 0
    lineData = []
    waypointData = []
    
    for line in filteredOutput:
        line = line.strip()
        if line == "BSPLINES":
            continue
        if line == "BSPWAYPOINTS":
            waypoints = True
            continue
        if line == "BSPEND":
            continue
        if waypoints:
            waypointData.append(float(line))
        else:
            lineLength += 1
            lineData.append(float(line))

    if brec:
        bspData = buildHeaderPDAGBREC(lineLength)
    else:
        bspData = buildHeaderPDAGNREC(lineLength)

    for value in lineData:
        if brec:
            floatValue = struct.pack('>f', value)
        else:
            floatValue = struct.pack('<f', value)
        bspData += floatValue
    for value in waypointData:
        if brec:
            floatValue = struct.pack('>f', value)
        else:
            floatValue = struct.pack('<f', value)
        bspData += floatValue

    # footer

    # add extra zero bytes to prevent waypoint functions reading garbage data
    bspData += b'\x00' * 2352
    # extra bytes for NREC
    if not brec:
        bspData += b'\x10\x00\x00\x00'

    write_file(bspData, Path(__file__).parent / (bspname + ".PDAG"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("infile", type=str, help="input file or directory (used as BSP name when using --bsp)")
    parser.add_argument("outdir", type=str, help="output directory")
    parser.add_argument("--brec", action="store_true", help="when using --encrypt, output to BREC format (XBLA/PS3)")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--encrypt", action="store_true", help="encrypt the input file(s)")
    group.add_argument("--bsp", action="store_true", help="create a BSP PAK file from bsp/bsp.swf")

    args = parser.parse_args()

    if args.bsp:
        if args.infile:
            if args.outdir:
                # use infile as BSP name
                infile = args.infile
                outdir = Path(args.outdir)
                scriptDir = Path(__file__).parent
                pdagFile = (scriptDir / (infile + ".PDAG"))
                createBSP(infile, brec=args.brec)
                if args.brec:
                    encryptPDAGBREC(pdagFile,outdir)
                else:
                    encryptPDAGNREC(pdagFile,outdir)
                if (pdagFile.is_file()):
                    os.remove(pdagFile)
            else:
                parser.error("outdir not set")
        else:
            parser.error("infile (BSP name) not set")
    else:
        if args.infile:
            if args.outdir:
                infile = Path(args.infile)
                outdir = Path(args.outdir)
                if args.encrypt:
                    if(args.brec):
                        if infile.suffix.lower() == '.pdag':
                            encryptPDAGBREC(infile, outdir)
                        else:
                            encryptBREC(infile, outdir)
                    else:
                        if infile.suffix.lower() == '.pdag':
                            encryptPDAGNREC(infile, outdir)
                        else:
                            encryptNREC(infile, outdir)
                else:
                    in_path = infile
                    if in_path.is_dir():
                        for f in in_path.rglob("*.pak"):
                            decryptFile(f, outdir)
                    else:
                        decryptFile(infile, outdir)
            else:
                parser.error("outdir not set")
        else:
            parser.error("infile not set")

