#!/usr/bin/env ruby
require 'optparse'
require 'tempfile'
require 'nokogiri'
require 'open3'

options = {}
OptionParser.new do |opts|
  opts.banner = "usage: #{File.basename($PROGRAM_NAME)} [options] [input swf] [outdir]"
  opts.on('--brec','use brec format (xbla/ps3)') { options[:brec] = true }
  opts.on('-nNAME','--name NAME',String,'name of pak file') { |name| options[:name] = name }
end.parse!

abort "usage: #{File.basename($PROGRAM_NAME)} [options] [input swf] [outdir]" if ARGV.length != 2

# get parameters, scripts, programs
swf = ARGV[0]
outDir = ARGV[1]
cryptRb = File.join(__dir__,'crypt.rb')
bspSwf = File.join(__dir__,'swf','bsp.swf')

abort "error: file '#{swf}' does not exist" unless File.exist?(swf)
abort "error: '#{swf}' is not a .swf file" unless swf.downcase.end_with?('.swf')
abort "error: directory '#{outDir}' does not exist" unless File.directory?(outDir)
abort 'error: crypt.rb not found in script directory' unless File.exist?(cryptRb)
abort 'error: bsp/bsp.swf missing in script directory' unless File.exist?(bspSwf)

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

# get bsp name
if options[:name]
  name = options[:name]
else
  print 'enter bsp name: '
  name = $stdin.gets.chomp
end
abort 'invalid name' unless !name.empty? && name.match?(/^[a-zA-Z0-9]+$/)
name = name.downcase

# create bsp

prevBspSwf = Tempfile.new(['','.swf'])
FileUtils.cp(bspSwf,prevBspSwf)
at_exit { FileUtils.cp(prevBspSwf,bspSwf) if File.exist?(prevBspSwf) }
bspXml = Tempfile.new(['','.xml'])
system(ffdec,'-swf2xml',bspSwf.to_s,bspXml.path)
levelXml = Tempfile.new(['','.xml'])
system(ffdec,'-swf2xml',swf,levelXml.path)

# copy level swf contents to bsp.swf using XML

levelDoc = Nokogiri::XML(File.read(levelXml.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)
bspDoc = Nokogiri::XML(File.read(bspXml.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)

# get game sprite
gameNode = levelDoc.at_xpath('/swf/tags/item[@type="PlaceObject2Tag" and @name="game"]')
abort 'error: input file does not contain "game" object' unless gameNode
gameSprite = levelDoc.at_xpath("//item[@type='DefineSpriteTag' and @spriteId='#{gameNode['characterId']}']")
abort 'error: could not find game sprite' unless gameSprite
# game.game
game2Node = gameSprite.at_xpath('subTags/item[@type="PlaceObject2Tag" and @name="game"]')
abort 'error: input file does not contain "game.game" object' unless game2Node
game2Sprite = levelDoc.at_xpath("//item[@type='DefineSpriteTag' and @spriteId='#{game2Node['characterId']}']")
abort 'error: could not find game.game sprite' unless game2Sprite
game2SubTags = game2Sprite.xpath('subTags/item')
# find frame boundaries
frameIndices = []
game2SubTags.each_with_index do |node,i|
  frameIndices << i if node['type'] == 'ShowFrameTag'
end
abort 'error: game has only one frame' if frameIndices.size < 2
# get game's placed frame 2 objects, these sprites keep their scripts for bsp
frame2Nodes = game2SubTags.to_a[(frameIndices[0] + 1)...frameIndices[1]]
frame2ChIds = frame2Nodes.select { |node| node['type'] == 'PlaceObject2Tag' }
frame2ChIds = frame2ChIds.map { |node| node['characterId'] }
frame2ChIds = frame2ChIds.uniq
frame2ChIds = frame2ChIds.map(&:to_s)
# remove game's frames after 2 & merge frame 1 & 2
game2SubTags[(frameIndices[1] + 1)..]&.each(&:remove)
game2SubTags[frameIndices[0]].remove
game2Sprite['frameCount'] = '1'
# remove doactions
levelDoc.xpath('//item[@type="DoActionTag"]').each do |node|
  sprite = node.at_xpath('ancestor::item[@type="DefineSpriteTag"]')
  isProtected = sprite && frame2ChIds.include?(sprite['spriteId'].to_s)
  node.remove unless isProtected
end
# remove clipactions
levelDoc.xpath('//item[@type="PlaceObject2Tag" and @placeFlagHasClipActions="true"]').each do |node|
  node['placeFlagHasClipActions'] = 'false'
  node.at_xpath('./clipActions').remove
end

# collect level tags, reject certain top-level tags
levelContent = []
levelDoc.xpath('/swf/tags/item').each do |node|
  break if node['type'] == 'ShowFrameTag' && node['forceWriteAsLong'] == 'false' && node.parent.name == 'tags'

  next if node['type'] == 'PlaceObject2Tag' && node['name'] != 'game'
  next if node['type'] == 'SetBackgroundColorTag'
  next if node['type'] == 'ExportAssetsTag'

  levelContent << node
end

# copy level tags to before bsp.swf tags (MetadataTag)
bspStartTag = bspDoc.at_xpath('//item[@type="MetadataTag" and @xmlMetadata="bsp.swf"]')
levelContent.each do |node|
  bspStartTag.add_previous_sibling(node.dup)
end

xmlOutput = bspDoc.to_xml(indent:2,indent_text:'  ')
xmlOutput = xmlOutput.gsub(%r{</item><item},"</item>\n  <item")
File.write(bspXml.path,xmlOutput)
system(ffdec,'-xml2swf',bspXml.path,bspSwf.to_s)
# get bsp data from running bsp.swf
output,_stderr,_status = Open3.capture3(ruffle,'--scale','show-all','--no-gui',bspSwf.to_s)
# process ruffle output
filteredOutput = []
output.each_line do |line|
  abort 'error: no bsp lines in input' if line.include?('error: no lines')
  break if line.include?('BSPEND')

  filteredOutput << line[78..] if line.include?('avm_trace')
end
abort 'error: no ruffle output (closed too early?)' if filteredOutput == []

# get bsp data from ruffle trace
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

# construct pdag file

# header
pdagData = Array.new(0x14,0)
if options[:brec]
  pdagData[0,4] = 'PDAG'.bytes
  pdagData[0x10,4] = [lineLength].pack('N').bytes
else
  pdagData[0,4] = 'GADP'.bytes
  pdagData[0x10,4] = [lineLength].pack('V').bytes
end
pdagData = pdagData.pack('C*')
lineData.each do |value|
  floatValue = options[:brec] ? [value].pack('g') : [value].pack('e')
  pdagData += floatValue
end
waypointData.each do |value|
  floatValue = options[:brec] ? [value].pack('g') : [value].pack('e')
  pdagData += floatValue
end
# add extra zero bytes to prevent waypoint functions reading garbage data
pdagData += "\x00" * 2352
# extra bytes for nrec
pdagData += "\x10\x00\x00\x00" unless options[:brec]

# write
pdag = File.join(Dir.tmpdir,"#{name}.pdag")
File.write(pdag,pdagData,mode:'wb')
system(RbConfig.ruby,cryptRb,'--encrypt',pdag,outDir)
FileUtils.rm(pdag)
