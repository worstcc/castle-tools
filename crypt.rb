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

def buildHeaderPdagNrec(data)
  ret = Array.new(0x14,0)
  ret[0,4] = 'GADP'.bytes
  ret[0x10,4] = [data].pack('V').bytes
  ret.pack('C*')
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

def buildHeaderPdagBrec(data)
  ret = Array.new(0x14,0)
  ret[0,4] = 'PDAG'.bytes
  ret[0x10,4] = [data].pack('N').bytes
  ret.pack('C*')
end

def createBsp(inFile,outDir,bspName,options)
  bspSwf = File.join(__dir__,'swf','bsp.swf')
  abort 'error: bsp/bsp.swf missing in script directory' unless File.exist?(bspSwf)

  # get ruffle & FFDec
  ffdec = nil
  if RUBY_PLATFORM =~ /mswin|mingw|jruby/
    ruffle = 'C:\\Program Files\\ruffle\\bin\\ruffle.exe'
    ffdec = 'C:\\Program Files (x86)\\FFDec\\ffdec-cli.exe'
  elsif RUBY_PLATFORM =~ /linux/
    ruffle = `which ruffle`.strip
    ffdec = '/usr/bin/ffdec'
    ffdec = `which ffdec`.strip unless File.exist?(ffdec)
  end
  abort 'error: ruffle is not installed on the system/not in PATH (download: https://ruffle.rs/downloads)' if ruffle.nil? || !File.exist?(ruffle)
  abort 'error: JPEXS is not installed on the system' if ffdec.nil? || !File.exist?(ffdec)

  prevBspSwf = Tempfile.new(['','.swf'])
  FileUtils.cp(bspSwf,prevBspSwf)
  # get XML files
  # bspXml = File.join(Dir.tmpdir,'bsp.xml')
  bspXml = Tempfile.new(['','.xml'])
  system(ffdec,'-swf2xml',bspSwf.to_s,bspXml.path)
  levelXml = Tempfile.new(['','.xml'])
  system(ffdec,'-swf2xml',inFile,levelXml.path)
  # copy level swf contents to bsp.swf using XML
  levelDoc = Nokogiri::XML(File.read(levelXml.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)
  bspDoc = Nokogiri::XML(File.read(bspXml.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)
  foundGameObj = false
  filteredContent = []
  levelDoc.xpath('/swf/tags/item').each do |node|
    foundGameObj = true if node['type'] == 'PlaceObject2Tag' && node['name'] == 'game'
    break if node['type'] == 'ShowFrameTag' && node['forceWriteAsLong'] == 'false' && node.parent.name == 'tags'

    filteredContent << node
  end
  abort 'error: input file does not contain "game" object' unless foundGameObj

  frameLabelNode = bspDoc.at_xpath('//item[@type="FrameLabelTag" and @name="level"]')
  filteredContent.reverse_each do |node|
    frameLabelNode.add_next_sibling(node.dup)
  end
  xmlOutput = bspDoc.to_xml(indent:2,indent_text:'  ')
  xmlOutput = xmlOutput.gsub(%r{</item><item},"</item>\n  <item")
  File.write(bspXml.path,xmlOutput)
  system(ffdec,'-xml2swf',bspXml.path,bspSwf.to_s)
  # get bsp data from running bsp.swf
  output,_stderr,_status = Open3.capture3(ruffle,'--scale','no-scale',bspSwf.to_s)
  # restore bsp.swf
  FileUtils.cp(prevBspSwf,bspSwf)
  # process ruffle output
  filteredOutput = []
  output.each_line do |line|
    abort 'error: no bsp lines in input' if line.include?('error: no lines')
    break if line.include?('BSPEND')

    filteredOutput << line[78..] if line.include?('avm_trace')
  end
  abort 'error: no ruffle output (closed too early?)' if filteredOutput == []

  # generate bsp arrays
  waypoints = false
  lineLength = 0
  lineData = []
  waypointData = []
  filteredOutput.each do |line|
    line = line.strip
    next if line == 'BSPLINES'

    if line == 'BSPWAYPOINTS'
      waypoints = true
      next
    end
    next if line == 'BSPEND'

    if waypoints
      waypointData << line.to_f
    else
      lineLength += 1
      lineData << line.to_f
    end
  end
  bspData = options[:brec] ? buildHeaderPdagBrec(lineLength) : buildHeaderPdagNrec(lineLength)
  lineData.each do |value|
    floatValue = options[:brec] ? [value].pack('g') : [value].pack('e')
    bspData += floatValue
  end
  waypointData.each do |value|
    floatValue = options[:brec] ? [value].pack('g') : [value].pack('e')
    bspData += floatValue
  end
  # add extra zero bytes to prevent waypoint functions reading garbage data
  bspData += "\x00" * 2352
  # extra bytes for nrec
  bspData += "\x10\x00\x00\x00" unless options[:brec]
  # write bsp file
  pdag = File.join(Dir.tmpdir,"#{bspName}.pdag")
  File.write(pdag,bspData,mode:'wb')
  # create bsp pak file
  options[:brec] ? encryptPdagBrec(pdag,outDir) : encryptPdagNrec(pdag,outDir)
  FileUtils.rm(pdag)
end

def decryptFile(inFile, outDir)
  abort 'error: input file is not a .pak' if File.extname(inFile) != '.pak'

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

options = {}
OptionParser.new do |opts|
  opts.banner = 'usage: crypt.rb [options]'
  opts.on('--encrypt','encrypt the input file instead of decrypting') { options[:encrypt] = true }
  opts.on('--brec','when using --encrypt, output to brec format (xbla/ps3)') { options[:brec] = true }
  opts.on('--bsp','create a bsp pak file from input level swf') { options[:bsp] = true }
  opts.on('--bspname NAME',String,'bsp pak file name when using --bsp option') { |name| options[:bspname] = name }
end.parse!

if ARGV.length != 2
  puts 'usage: crypt.rb [options] $INFILE $OUTDIR'
  exit 1
end

inFile = ARGV[0]
outDir = ARGV[1]

abort "error: input \"#{inFile}\" not found" unless File.exist?(inFile)
abort "error: output \"#{outDir}\" not found" unless File.directory?(outDir)

if options[:bsp]
  if options[:bspname]
    bspName = options[:bspname]
  else
    print 'enter bsp name: '
    bspName = $stdin.gets.chomp
  end
  bspName = bspName.downcase
  createBsp(inFile,outDir,bspName,options)
elsif options[:encrypt]
  if inFile.end_with?('.pdag')
    options[:brec] ? encryptPdagBrec(inFile,outDir) : encryptPdagNrec(inFile,outDir)
  else
    options[:brec] ? encryptBrec(inFile,outDir) : encryptNrec(inFile,outDir)
  end
else
  decryptFile(inFile,outDir)
end
