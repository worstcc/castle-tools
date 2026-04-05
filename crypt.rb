#!/usr/bin/env ruby
require 'optparse'
require 'zip'
require 'openssl'
require 'pathname'
require 'tempfile'
require 'tmpdir'
require 'mkmf'

KEYSTRINGS = [
  "\x1b\xbf\x18\xcc\x86\x5d\xf4\x25\x07\xc3\xe5\xb3\xb9\x04\x5a\x14\xd7\xfc\x4c\x86\x8d\x4a\xcb\x8f".b,
  "\x24\x53\x4a\x1e\xda\x06\x85\x5f\x7a\xc1\xb6\x8a\x76\x41\x20\xcb\x1f\xce\x61\xd6\xad\x74\x6b\x0f".b,
  "\x77\x82\x1e\x54\x89\xd7\x87\xb6\x05\xf9\x64\xcc\x57\x0b\xcf\x8b\xf8\xd2\x35\x80\x9c\xbf\x9e\x19".b,
  "\x5a\x8d\x84\x20\x6e\x90\xfb\x91\x1f\x48\xe0\xee\xc2\x03\xa2\xaf\x60\x2f\x93\xd6\xa8\x50\x2c\xe2".b
].freeze

KEYSWAPINDEXES = [
  [8, 10, 12, 17],
  [1, 2, 10, 15],
  [0, 9, 12, 16],
  [5, 6, 11, 14]
].freeze

def unzipFile(inFile)
  Zip::File.open(inFile) do |zip|
    abort 'error: more than one file in archive' if zip.entries.size != 1

    entry = zip.entries.first
    return [entry.name.upcase, entry.get_input_stream.read.b]
  end
end

def zipFile(outFile,archiveName,data)
  FileUtils.rm_f(outFile) if File.exist?(outFile)
  Tempfile.create(binmode:true) do |tempFile|
    tempFile.write(data)
    tempFile.rewind
    Zip::File.open(outFile,create:true) do |zip|
      zip.add_stored(archiveName,tempFile.path)
    end
  end
end

def getBlowfishKey(name,dataLength)
  nameCrc = 0
  name.each_byte { |b| nameCrc = ((nameCrc * 0x25) + b) & 0xffffffff }

  sizeTemp = ((dataLength / 16) % 16).to_i
  keyIndexes = KEYSWAPINDEXES[sizeTemp / 4]
  key = KEYSTRINGS[sizeTemp % 4].byteslice(0,18).bytes

  keyIndexes.each do |i|
    key[i] = nameCrc & 0xff
    nameCrc >>= 8
  end

  key.pack('C*')
end

def blowfishCrypt(name,data,mode)
  key = getBlowfishKey(name,data.length)
  OpenSSL::Provider.load('legacy')
  cipher = OpenSSL::Cipher.new('bf-ecb')
  if mode == 'encrypt'
    cipher.encrypt
  else
    cipher.decrypt
  end
  cipher.key_len = key.length
  cipher.key = key
  cipher.padding = 0
  # encrypt data in 8-byte blocks with 32-bit word byte reversal
  encrypted = ''
  (0...(data.length / 8)).each do |i|
    block = data[i * 8, 8]
    # reverse bytes within each 32-bit word
    blockBytes = block.bytes
    blockLe = (blockBytes[0,4].reverse + blockBytes[4,4].reverse).pack('C*')
    encryptedBlock = cipher.update(blockLe)
    # reverse output bytes within each 32-bit word
    encryptedBlockBytes = encryptedBlock.bytes
    encrypted << (encryptedBlockBytes[0,4].reverse + encryptedBlockBytes[4,4].reverse).pack('C*')
  end
  encrypted
end

def calcChecksum(data)
  result = 0
  work = 0xd971
  data.each_byte do |b|
    tmp = b ^ (work >> 8)
    work = (0x58bf + 0xce6d * (work + tmp)) & 0xffff
    result = (result + tmp) & 0xffffffff
  end
  result
end

def validateChecksum(data)
  ck1 = data[-4,4].unpack1('V')
  ck2 = calcChecksum("#{data[0...-4]}\x00\x00\x00\x00")
  abort format('error: checksum mismatch: %<ck1>08X != %<ck2>08X',ck1:ck1,ck2:ck2) if ck1 != ck2
end

def buildHeaderNrec(data)
  ret = Array.new(0x80,0)
  ret[0,4] = '6KOC'.bytes
  ret[0x10,4] = [data.bytesize].pack('V').bytes
  ret[0x14,4] = [0x80].pack('V').bytes
  ret.pack('C*')
end

def buildFooterNrec(data)
  ret = []
  # add initial padding to align the file to 4 bytes
  alignFourLength = (4 - (data.bytesize % 4)) % 4
  ret.concat([0x00] * alignFourLength)
  # add 0x14, 1
  ret.concat([0x14,0x00,0x00,0x00,0x01,0x00,0x00,0x00])
  # add padding to align the final file to 16 bytes (existing data, footer so far, int for number of zeroes, int for checksum)
  totalLength = data.bytesize + ret.size + 8
  align16Length = (16 - (totalLength % 16)) % 16
  ret.concat([0x00] * align16Length)
  # add a u32 describing the number of zeros added + 8
  ret.concat([align16Length + 8].pack('V').bytes)
  # add a space for the checksum
  ret.concat([0x00,0x00,0x00,0x00])
  ret.pack('C*')
end

def decryptSwfNrec(data)
  size = data[0x10,4].unpack1('V')
  offset = data[0x14,4].unpack1('V')
  data[offset,size]
end

def decryptNrec(inFile,outDir)
  puts "decrypting #{File.basename(inFile)} (nrec)"
  name, inputData = unzipFile(inFile)
  decrypted = blowfishCrypt(name,inputData,'decrypt')
  # sanity checks: validate checksum, confirm we can properly rebuild the footer
  validateChecksum(decrypted)
  swfData = decryptSwfNrec(decrypted)
  newSwfData = swfData

  # remove "CD" bytes and everything after
  pattern = [0x40,0x00,0x00,0x00,0xCD].pack('C*').force_encoding('ASCII-8BIT')
  newSwfData.force_encoding('ASCII-8BIT')
  cdIndex = newSwfData.rindex(pattern)
  newSwfData = newSwfData[0,cdIndex + 4] if cdIndex
  # update swf header file length
  newLength = newSwfData.length
  newSwfData = newSwfData[0,4] + [newLength].pack('V') + newSwfData[8..]

  File.write(File.join(outDir,"#{name.split('.')[0]}.swf"),newSwfData,mode:'wb')
end

def encryptNrec(inFile,outDir)
  puts "encrypting #{File.basename(inFile)} (nrec)"
  swfData = File.binread(inFile)
  preData = buildHeaderNrec(swfData) + swfData
  preData += buildFooterNrec(preData)
  checksum = calcChecksum(preData)
  preData[-4,4] = [checksum].pack('V')
  archiveName = "#{File.basename(inFile,'.swf').upcase}.COK6.NREC"
  encrypted = blowfishCrypt(archiveName,preData,'encrypt')
  zipPath = outDir + "/#{File.basename(inFile, '.*').downcase}.pak"
  zipFile(zipPath,archiveName,encrypted)
end

def buildHeaderBrec(data)
  ret = Array.new(0x80,0)
  ret[0,4] = 'COK6'.bytes
  ret[0x10,4] = [data.bytesize].pack('N').bytes
  ret[0x14,4] = [0x80].pack('N').bytes
  ret.pack('C*')
end

def buildFooterBrec(data)
  ret = [0xCD,0xCD]
  # add initial padding to align the file to 4 bytes
  alignFourLength = (4 - ((data.bytesize + 2) % 4)) % 4
  ret.concat([0x00] * alignFourLength)
  # add 0x14, 1
  ret.concat([0x00,0x00,0x00,0x14,0x00,0x00,0x00,0x01])
  ret.pack('C*')
end

def decryptSwfBrec(data)
  size = data[0x10,4].unpack1('N')
  offset = data[0x14,4].unpack1('N')
  data[offset,size]
end

def decryptBrec(inFile,outDir)
  puts "decrypting #{File.basename(inFile)} (brec)"
  name, inputData = unzipFile(inFile)
  swfData = decryptSwfBrec(inputData)
  newSwfData = swfData
  # remove "CD" bytes and everything after
  pattern = [0x40,0x00,0x00,0x00,0xCD].pack('C*').force_encoding('ASCII-8BIT')
  newSwfData.force_encoding('ASCII-8BIT')
  cdIndex = newSwfData.rindex(pattern)
  newSwfData = newSwfData[0,cdIndex + 4] if cdIndex
  # update swf header file length
  newLength = newSwfData.length
  newSwfData = newSwfData[0,4] + [newLength].pack('N') + newSwfData[8..]
  File.write(File.join(outDir,"#{name.split('.')[0]}.swf"),newSwfData,mode:'wb')
end

def encryptBrec(inFile,outDir)
  puts "encrypting #{File.basename(inFile)} (brec)"
  swfData = File.binread(inFile)
  preData = buildHeaderBrec(swfData) + swfData
  preData += buildFooterBrec(preData)
  archiveName = "#{File.basename(inFile,'.swf').upcase}.COK6.BREC"
  zipPath = outDir + "/#{File.basename(inFile, '.*').downcase}.pak"
  zipFile(zipPath,archiveName,preData)
end

def padPdag(data,blockSize = 8)
  totalLength = data.bytesize + 4
  padLength = (blockSize - (totalLength % blockSize)) % blockSize
  data + ("\x00" * padLength)
end

def decryptPdagNrec(inFile,outDir)
  puts "decrypting #{File.basename(inFile)} (nrec)"
  name, inputData = unzipFile(inFile)
  decrypted = blowfishCrypt(name,inputData,'decrypt')
  decrypted = decrypted.byteslice(0...-8) # remove checksum footer
  File.write(File.join(outDir,"#{name.split('.')[0]}.pdag"),decrypted,mode:'wb')
end

def encryptPdagNrec(inFile,outDir)
  puts "encrypting #{File.basename(inFile)} (nrec)"
  data = File.binread(inFile)
  preData = padPdag(data)
  checksum = calcChecksum("#{preData}\x00\x00\x00\x00")
  preData += [checksum].pack('V')
  archiveName = "#{File.basename(inFile,'.pdag').upcase}.PDAG.NREC"
  encrypted = blowfishCrypt(archiveName,preData,'encrypt')
  zipPath = outDir + "/#{File.basename(inFile,'.*').downcase}.pak"
  zipFile(zipPath,archiveName,encrypted)
end

def decryptPdagBrec(inFile,outDir)
  puts "decrypting #{File.basename(inFile)} (brec)"
  name,data = unzipFile(inFile)
  File.write(File.join(outDir,"#{name.split('.')[0]}.pdag"),data)
end

def encryptPdagBrec(inFile,outDir)
  puts "encrypting #{File.basename(inFile)} (brec)"
  data = File.binread(inFile)
  data = padPdag(data)
  archiveName = "#{File.basename(inFile,'.pdag').upcase}.PDAG.BREC"
  zipPath = outDir + "/#{File.basename(inFile,'.*').downcase}.pak"
  zipFile(zipPath,archiveName,data)
end

def decrypt(inFile, outDir)
  Zip::File.open(inFile) do |zip|
    fileList = zip.entries.map(&:name)
    isPdag = fileList.any? { |f| f.include?('PDAG') }
    hasNrec = fileList.any? { |f| f.include?('.NREC') }
    hasBrec = fileList.any? { |f| f.include?('.BREC') }
    if hasNrec
      isPdag ? decryptPdagNrec(inFile,outDir) : decryptNrec(inFile,outDir)
    elsif hasBrec
      isPdag ? decryptPdagBrec(inFile,outDir) : decryptBrec(inFile,outDir)
    end
  end
end

def processFile(input,outputDir,options)
  if options[:encrypt]
    if input.end_with?('.pdag')
      options[:brec] ? encryptPdagBrec(input,outputDir) : encryptPdagNrec(input,outputDir)
    else
      options[:brec] ? encryptBrec(input,outputDir) : encryptNrec(input,outputDir)
    end
  else
    decrypt(input,outputDir)
  end
end

usage = "usage: #{File.basename($PROGRAM_NAME)} [options] [input file/directory] [output directory]"
options = {}
OptionParser.new do |opts|
  opts.banner = usage
  opts.on('-e','--encrypt','encrypt the input file/directory instead of decrypting') { options[:encrypt] = true }
  opts.on('-b','--brec','when encrypting, output to brec format (xbla/ps3)') { options[:brec] = true }
end.parse!
abort usage if ARGV.length != 2

input = File.expand_path(ARGV[0])
abort "error: input '#{File.basename(input)}' not found" unless File.exist?(input) || File.directory?(input)
outputDir = File.expand_path(ARGV[1])
abort "error: output '#{File.basename(outputDir)}' not found" unless File.directory?(outputDir)

extensions = options[:encrypt] ? '{.swf,.pdag}' : '.pak'
extensionsError = options[:encrypt] ? 'swf/pdag' : 'pak'
if File.directory?(input)
  children = Dir.glob(File.join(input,"*#{extensions}")).reject { |file| File.directory?(file) }
  abort "error: no #{extensionsError} files found in input directory" if children.empty?
  children.each do |file|
    processFile(file,outputDir,options)
  end
else
  abort "error: input file is not a #{extensionsError}" unless input.downcase.end_with?(*(options[:encrypt] ? ['.swf','.pdag'] : ['.pak']))
  processFile(input,outputDir,options)
end
