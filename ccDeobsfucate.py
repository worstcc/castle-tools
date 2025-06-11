#!/usr/bin/python3

import re

# open file
with open('ccDeobsfucate.txt', 'r+') as f:
    # read file
    contents = f.read()

    # remove §§ instructions
    ssInstructions = 0

    # define regex search & replace
    byteValues = ["02", "03", "04", "05", "06", "07", "08", "09", "0a", "0b", "0c", "0d", "0e", "0f", "10", "11", "12"]

    for byteValue in byteValues:
        pattern = rf'(a[01234])\s+{byteValue}\s+00'
        replacement = rf'96 {byteValue} 00'

        # replace
        newContents, count = re.subn(pattern, replacement, contents)
        if count > 0:
            contents = newContents
            ssInstructions += count

    print(f"fixed {ssInstructions} §§ instructions")

    # fix unknown 70s
    unknown70s = 0

    newContents, count = re.subn(r'70\s+12\s+9d\s+02', r'70 70 9d 02', contents)
    if count > 0:
        contents = newContents
        unknown70s += count

    print(f"fixed {unknown70s} unknown 70s")

    # go to beginning
    f.seek(0)

    # write
    f.write(contents)

    # remove leftovers at the end
    f.truncate()
