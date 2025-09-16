#!/usr/bin/env ruby
require 'optparse'
require 'zip'
require 'openssl'
require 'pathname'
require 'tempfile'
require 'tmpdir'
require 'mkmf'
require 'open3'
require 'nokogiri'

KEYSTRINGS = [
  "\x1b\xbf\x18\xcc\x86\x5d\xf4\x25\x07\xc3\xe5\xb3\xb9\x04\x5a\x14\xd7\xfc\x4c\x86\x8d\x4a\xcb\x8f".b,
  "\x24\x53\x4a\x1e\xda\x06\x85\x5f\x7a\xc1\xb6\x8a\x76\x41\x20\xcb\x1f\xce\x61\xd6\xad\x74\x6b\x0f".b,
  "\x77\x82\x1e\x54\x89\xd7\x87\xb6\x05\xf9\x64\xcc\x57\x0b\xcf\x8b\xf8\xd2\x35\x80\x9c\xbf\x9e\x19".b,
  "\x5a\x8d\x84\x20\x6e\x90\xfb\x91\x1f\x48\xe0\xee\xc2\x03\xa2\xaf\x60\x2f\x93\xd6\xa8\x50\x2c\xe2".b,
]

KEYSWAPINDEXES = [
  [8, 10, 12, 17],
  [1, 2, 10, 15],
  [0, 9, 12, 16],
  [5, 6, 11, 14],
]

def unzipFile(inFile)
  Zip::File.open(inFile) do |zip|
    raise "more than one file in archive" if zip.entries.size != 1
    entry = zip.entries.first
    return [entry.name.upcase, entry.get_input_stream.read]
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
  nameCRC = 0
  name.each_byte { |b| nameCRC = ((nameCRC * 0x25) + b) & 0xffffffff}

  sizeTemp = ((dataLength / 16) % 16).to_i
  keyIndexes = KEYSWAPINDEXES[sizeTemp / 4]
 key = KEYSTRINGS[sizeTemp % 4].byteslice(0,18).bytes

  keyIndexes.each do |i|
    key[i] = nameCRC & 0xff
    nameCRC >>= 8
  end

  key.pack('C*')
end

def blowfishCrypt(name,data,mode)
  key = getBlowfishKey(name,data.length)
  OpenSSL::Provider.load('legacy')
  cipher = OpenSSL::Cipher.new('bf-ecb')
  if mode == "encrypt"
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
    blockLE = (blockBytes[0, 4].reverse + blockBytes[4, 4].reverse).pack('C*')
    encryptedBlock = cipher.update(blockLE)
    # reverse output bytes within each 32-bit word
    encryptedBlockBytes = encryptedBlock.bytes
    encrypted << (encryptedBlockBytes[0, 4].reverse + encryptedBlockBytes[4, 4].reverse).pack('C*')
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
  ck2 = calcChecksum(data[0...-4] + "\x00\x00\x00\x00")
  raise "checksum mismatch: %08X != %08X" % [ck1,chk2] if ck1 != ck2
end

def buildHeaderNREC(data)
  ret = Array.new(0x80,0)
  ret[0,4] = '6KOC'.bytes
  ret[0x10,4] = [data.bytesize].pack('V').bytes
  ret[0x14,4] = [0x80].pack('V').bytes
  ret.pack('C*')
end

def buildFooterNREC(data)
  ret = []
  # add initial padding to align the file to 4 bytes
  align4Length = (4 - (data.bytesize % 4)) % 4
  ret.concat([0x00] * align4Length)
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

def decryptSWFNREC(data)
  size,offset = data[0x10,4].unpack1('V'),data[0x14,4].unpack1('V')
  data[offset,size]
end

def decryptNREC(inFile,outDir)
  puts "decrypting #{File.basename(inFile)} (NREC)"
  name, inputData = unzipFile(inFile)
  decrypted = blowfishCrypt(name,inputData,"decrypt")
  # sanity checks: validate checksum, confirm we can properly rebuild the footer
  validateChecksum(decrypted)
  swfData = decryptSWFNREC(decrypted)
  newSWFData = swfData

  # remove "CD" bytes and everything after
  pattern = [0x40,0x00,0x00,0x00,0xCD].pack('C*').force_encoding('ASCII-8BIT')
  newSWFData.force_encoding('ASCII-8BIT')
  cdIndex = newSWFData.rindex(pattern)
  if cdIndex
    newSWFData = newSWFData[0,cdIndex + 4]
  end
  # update SWF header file length
  newLength = newSWFData.length
  newSWFData = newSWFData[0,4] + [newLength].pack('V') + newSWFData[8..-1]

  File.write(File.join(outDir,name.split('.')[0] + ".swf"), newSWFData, mode: "wb")
end

def encryptNREC(inFile,outDir)
  puts "encrypting #{File.basename(inFile)} (NREC)"
  swfData = File.binread(inFile)
  preData = buildHeaderNREC(swfData) + swfData
  preData += buildFooterNREC(preData)
  checksum = calcChecksum(preData)
  preData[-4,4] = [checksum].pack('V')
  archiveName = File.basename(inFile,".swf").upcase + ".COK6.NREC"
  encrypted = blowfishCrypt(archiveName,preData,"encrypt")
  zipPath = outDir + "/#{File.basename(inFile, '.*').downcase}.pak"
  zipFile(zipPath,archiveName,encrypted)
end

def buildHeaderBREC(data)
  ret = Array.new(0x80,0)
  ret[0,4] = 'COK6'.bytes
  ret[0x10,4] = [data.bytesize].pack('N').bytes
  ret[0x14,4] = [0x80].pack('N').bytes
  ret.pack('C*')
end

def buildFooterBREC(data)
  ret = [0xCD,0xCD]
  # add initial padding to align the file to 4 bytes
  align4Length = (4 - ((data.bytesize + 2) % 4)) % 4
  ret.concat([0x00] * align4Length)
  # add 0x14, 1
  ret.concat([0x00,0x00,0x00,0x14,0x00,0x00,0x00,0x01])
  ret.pack('C*')
end

def decryptSWFBREC(data)
  size,offset = data[0x10,4].unpack1('N'),data[0x14,4].unpack1('N')
  data[offset,size]
end

def decryptBREC(inFile,outDir)
  puts "decrypting #{File.basename(inFile)} (BREC)"
  name, inputData = unzipFile(inFile)
  swfData = decryptSWFBREC(inputData)
  newSWFData = swfData
  # remove "CD" bytes and everything after
  pattern = [0x40,0x00,0x00,0x00,0xCD].pack('C*').force_encoding('ASCII-8BIT')
  newSWFData.force_encoding('ASCII-8BIT')
  cdIndex = newSWFData.rindex(pattern)
  if cdIndex
    newSWFData = newSWFData[0,cdIndex + 4]
  end
  # update SWF header file length
  newLength = newSWFData.length
  newSWFData = newSWFData[0,4] + [newLength].pack('N') + newSWFData[8..-1]

  File.write(File.join(outDir,name.split('.')[0] + ".swf"),newSWFData,mode: "wb")
end

def encryptBREC(inFile,outDir)
  puts "encrypting #{File.basename(inFile)} (BREC)"
  swfData = File.binread(inFile)
  preData = buildHeaderBREC(swfData) + swfData
  preData += buildFooterBREC(preData)
  archiveName = File.basename(inFile,".swf").upcase + ".COK6.BREC"
  zipPath = outDir + "/#{File.basename(inFile, '.*').downcase}.pak"
  zipFile(zipPath,archiveName,preData)
end
def padPDAG(data,blockSize = 8)
  totalLength = data.bytesize + 4
  padLength = (blockSize - (totalLength % blockSize)) % blockSize
  data + ("\x00" * padLength)
end
def decryptPDAGNREC(inFile,outDir)
  puts "decrypting #{File.basename(inFile)} (NREC)"
  name, inputData = unzipFile(inFile)
  decrypted = blowfishCrypt(name,inputData,"decrypt")
  decrypted = decrypted.byteslice(0...-8) # remove checksum footer
  File.write(File.join(outDir,name.split('.')[0] + ".pdag"),decrypted,mode:"wb")
end
def encryptPDAGNREC(inFile,outDir)
  puts "encrypting #{File.basename(inFile)} (NREC)"
  data = File.binread(inFile)
  preData = padPDAG(data)
  checksum = calcChecksum(preData + "\x00\x00\x00\x00")
  preData += [checksum].pack('V')
  archiveName = File.basename(inFile,".pdag").upcase + ".PDAG.NREC"
  encrypted = blowfishCrypt(archiveName,preData,"encrypt")
  zipPath = outDir + "/#{File.basename(inFile,'.*').downcase}.pak"
  zipFile(zipPath,archiveName,encrypted)
end
def buildHeaderPDAGNREC(data)
  ret = Array.new(0x14,0)
  ret[0,4] = 'GADP'.bytes
  ret[0x10,4] = [data].pack('V').bytes
  ret.pack('C*')
end
def decryptPDAGBREC(inFile,outDir)
  puts "decrypting #{File.basename(inFile)} (BREC)"
  name,data = unzipFile(inFile)
  File.write(File.join(outDir,name.split('.')[0] + ".pdag"),data)
end
def encryptPDAGBREC(inFile,outDir)
  puts "encrypting #{File.basename(inFile)} (BREC)"
  data = File.binread(inFile)
  data = padPDAG(data)
  archiveName = File.basename(inFile,".pdag").upcase + ".PDAG.BREC"
  zipPath = outDir + "/#{File.basename(inFile,".*").downcase}.pak"
  zipFile(zipPath,archiveName,data)
end
def buildHeaderPDAGBREC(data)
  ret = Array.new(0x14,0)
  ret[0,4] = 'PDAG'.bytes
  ret[0x10,4] = [data].pack('N').bytes
  ret.pack('C*')
end
def createBSP(inFile,outDir,bspName,brec = false)
  scriptDir = Pathname.new(__FILE__).realpath.parent
  bspSWF = scriptDir + "bsp" + "bsp.swf"
  unless bspSWF.exist?
    puts "bsp/bsp.swf missing in script directory"
    exit 1
  end
  # get ruffle & FFDec
  ruffleFound = false
  ffdec = nil
  if RUBY_PLATFORM =~ /mswin|mingw|jruby/
    ruffle = "C:\\Program Files\\ruffle\\bin\\ruffle.exe"
    ffdec = "C:\\Program Files (x86)\\FFDec\\ffdec-cli.exe"
  elsif RUBY_PLATFORM =~ /linux/
    ruffle = `which ruffle`.strip
    ffdec = "/usr/bin/ffdec"
    unless File.exist?(ffdec)
      ffdec = `which ffdec`.strip
    end
  end
  if ruffle.nil? || !File.exist?(ruffle)
    puts "error: ruffle is not installed on the system/not in PATH (download: https://ruffle.rs/downloads)"
    exit 1
  end
  if ffdec.nil? || !File.exist?(ffdec)
    puts "error: JPEXS is not installed on the system"
    exit 1
  end
  bspSWFBackup = Pathname.new(Dir.tmpdir) + "bspBackup.swf"
  FileUtils.cp(bspSWF,bspSWFBackup)
  # get XML files
  bspXML = Pathname.new(Dir.tmpdir) + "bsp.xml"
  system(ffdec,'-swf2xml',bspSWF.to_s,bspXML.to_s)
  levelXML = Pathname.new(Dir.tmpdir) + "#{File.basename(inFile,'.swf')}.xml"
  system(ffdec,'-swf2xml',inFile,levelXML.to_s)
  # copy level SWF contents to bsp.swf using XML
  levelDoc = Nokogiri::XML(File.read(levelXML.to_s))
  bspDoc = Nokogiri::XML(File.read(bspXML.to_s))
  foundGameObj = false
  filteredContent = []
  levelDoc.xpath('/swf/tags/item').each do |node|
    if node['type'] == 'PlaceObject2Tag' && node['name'] == 'game'
      foundGameObj = true
    end
    break if node['type'] == 'ShowFrameTag' && node['forceWriteAsLong'] == 'false' && node.parent.name == 'tags'
    filteredContent << node
  end
  unless foundGameObj
    puts "error: input file does not contain \"game\" object"
    exit 1
  end
  frameLabelNode = bspDoc.at_xpath('//item[@type="FrameLabelTag" and @name="level"]')
  filteredContent.reverse_each do |node|
    frameLabelNode.add_next_sibling(node.dup)
  end
  xmlOutput = bspDoc.to_xml(indent:2,indent_text:"  ")
  xmlOutput = xmlOutput.gsub(/<\/item><item/,"</item>\n  <item")
  File.write(bspXML.to_s,xmlOutput)
  system(ffdec,'-xml2swf',bspXML.to_s,bspSWF.to_s)
  # get BSP data from running bsp.swf
  stdout,stderr,status = Open3.capture3(ruffle,'--scale','no-scale',bspSWF.to_s)
  output = stdout
  # clean up XML files & restore bsp.swf
  FileUtils.rm(bspXML)
  FileUtils.rm(levelXML)
  FileUtils.cp(bspSWFBackup,bspSWF)
  FileUtils.rm(bspSWFBackup)
  # process ruffle output
  filteredOutput = []
  output.each_line do |line|
    if line.include?("error: no lines")
      puts "error: no BSP lines in input"
      exit 1
    end
    break if line.include?("BSPEND")
    if line.include?("avm_trace")
      filteredOutput << line[78..-1]
    end
  end
  if filteredOutput == []
    puts "error: no ruffle output (closed too early?)"
    exit 1
  end
  # generate BSP arrays
  waypoints = false
  lineLength = 0
  lineData = []
  waypointData = []
  filteredOutput.each do |line|
    line = line.strip
    next if line == "BSPLINES"
    if line == "BSPWAYPOINTS"
      waypoints = true
      next
    end
    next if line == "BSPEND"
    if waypoints
      waypointData << line.to_f
    else
      lineLength += 1
      lineData << line.to_f
    end
  end
  bspData = brec ? buildHeaderPDAGBREC(lineLength) : buildHeaderPDAGNREC(lineLength)
  lineData.each do |value|
    floatValue = brec ? [value].pack('g') : [value].pack('e')
    bspData += floatValue
  end
  waypointData.each do |value|
    floatValue = brec ? [value].pack('g') : [value].pack('e')
    bspData += floatValue
  end
  # add extra zero bytes to prevent waypoint functions reading garbage data
  bspData += "\x00" * 2352
  # extra bytes for NREC
  unless brec
    bspData += "\x10\x00\x00\x00"
  end
  # write BSP file
  pdag = Pathname.new(Dir.tmpdir) + "#{bspName}.pdag"
  File.write(pdag,bspData,mode:'wb')
  # create BSP PAK file
  brec ? encryptPDAGBREC(pdag,outDir) : encryptPDAGNREC(pdag,outDir)
  FileUtils.rm(pdag)
end
def decryptFile(inFile, outDir)
  Zip::File.open(inFile) do |zip|
    fileList = zip.entries.map(&:name)
    isPDAG = fileList.any? { |f| f.include?('PDAG') }
    hasNREC = fileList.any? { |f| f.include?('.NREC') }
    hasBREC = fileList.any? { |f| f.include?('.BREC') }
    if hasNREC
      isPDAG ? decryptPDAGNREC(inFile,outDir) : decryptNREC(inFile,outDir)
    elsif hasBREC
      isPDAG ? decryptPDAGBREC(inFile,outDir) : decryptBREC(inFile,outDir)
    end
  end
end
options = {}
OptionParser.new do |opts|
  opts.banner = "usage: crypt.rb [options]"
  opts.on("--encrypt", "encrypt the input file instead of decrypting") { options[:encrypt] = true }
  opts.on("--brec", "when using --encrypt, output to BREC format (XBLA/PS3)") { options[:brec] = true }
  opts.on("--bsp", "create a BSP PAK file from input level SWF") { options[:bsp] = true }
  opts.on("--bspname NAME",String,"BSP PAK file name when using --bsp option") { |name| options[:bspname] = name }
end.parse!

if ARGV.length != 2
  puts "usage: crypt.rb [options] $INFILE $OUTDIR"
  exit 1
end

inFile = ARGV[0]
outDir = ARGV[1]

if not File.exist?(inFile)
  puts "error: input \"#{inFile}\" not found"
  exit 1
end
if not File.directory?(outDir)
  puts "error: output \"#{outDir}\" not found"
  exit 1
end

if options[:bsp]
  if options[:bspname]
    bspName = options[:bspname]
  else
    print "enter BSP name: "
    bspName = STDIN.gets.chomp
  end
  bspName = bspName.downcase
  createBSP(inFile,outDir,bspName,options[:brec])
  exit 0
elsif options[:encrypt]
  if inFile.end_with?(".pdag")
    options[:brec] ? encryptPDAGBREC(inFile,outDir) : encryptPDAGNREC(inFile,outDir)
  else
    options[:brec] ? encryptBREC(inFile,outDir) : encryptNREC(inFile,outDir)
  end 
else
  decryptFile(inFile,outDir)
end
