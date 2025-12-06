#!/usr/bin/env ruby
require 'rmagick'
require 'pathname'
require 'tempfile'
require 'tmpdir'
require 'nokogiri'
include Magick

def findFFDec
  ffdecPath = nil
  if RUBY_PLATFORM =~ /mswin|mingw|jruby/
    # windows
    ffdecPath = "C:\\Program Files (x86)\\FFDec\\ffdec-cli.exe"
  elsif RUBY_PLATFORM =~ /linux/
    # linux
    ffdecPath = "/usr/bin/ffdec"
    unless File.exist?(ffdecPath)
      ffdecPath = `which ffdec`.strip
    end
  end
  
  if ffdecPath.nil? || !File.exist?(ffdecPath)
    puts "error: JPEXS not found"
    exit 0
  else
    return ffdecPath
  end
end

# options = {}
# OptionParser.new do |opts|
#   opts.banner = "usage: #{File.basename($0)} [options] [image]"
# end.parse!

if ARGV.length != 2
  puts "usage: #{File.basename($0)} [image] [swf]"
  exit 1
end

imageFile = ARGV[0]
if ! File.exist?(imageFile)
  raise "#{File.basename(imageFile)} not found"
end
if ! [".jpg",".jpeg",".png"].include?(File.extname(imageFile).downcase)
  raise "#{File.basename(imageFile)} is not a jpg|jpeg|png"
end

swfFile = ARGV[1]
if ! File.exist?(swfFile)
  raise "#{File.basename(swfFile)} not found"
end
if File.extname(swfFile).downcase != ".swf"
  raise "#{File.basename(swfFile)} is not a swf"
end

ffdec = findFFDec

# read image
image = Image.read(imageFile).first
if image.columns > 1024 || image.rows > 1024
  raise "#{File.basename(imageFile)} is too large (maximum 1024x1024)"  
end
imageData = image.export_pixels(0,0,image.columns,image.rows,"BGRA").pack('C*').unpack('H*').first

# create pixl tag

# SWF header

data = ""
# character ID
data << [49002].pack('v').unpack1('H*')
data << "00" * 2
# width
data << [65536 - image.columns * 10].pack('v').unpack1('H*')
data << "ff" * 2
data << [image.columns * 10].pack('v').unpack1('H*')
data << "00" * 2
# height
data << [65536 - image.rows * 10].pack('v').unpack1('H*')
data << "ff" * 2
data << [image.rows * 10].pack('v').unpack1('H*')
data << "00" * 2
# padding
data << "cd" * 16

# PIXL header
data << "4c584950"
data << "00" * 12
# width
data << [image.columns].pack('V').unpack1('H*')
# height
data << [image.rows].pack('V').unpack1('H*')
data << "01000000" * 2
data << "00" * 4
# ?
data << "60000000"
data << "00" * 4
data << "01000000"
# image length
data << [imageData.length / 2].pack('V').unpack1('H*')
data << "01000000" * 2
# width/height/width/height
data << [image.columns].pack('V').unpack1('H*')
data << [image.rows].pack('V').unpack1('H*')
data << [image.columns].pack('V').unpack1('H*')
data << [image.rows].pack('V').unpack1('H*')
data << "cd" * 4
# character ID
data << [49002].pack('v').unpack1('H*')
data << "00" * 14

# image data
data << imageData

# footer
data << "24000000280000003000000003000000"

scriptDir = Pathname.new(__FILE__).realpath.parent
pixlSWF = scriptDir + "swf" + "pixl.swf"
unless pixlSWF.exist?
  raise "swf/pixl.swf missing in script directory"
end
pixlSWFBak = Pathname.new(Dir.tmpdir) + "pixl.swf"
pixlXML = Pathname.new(Dir.tmpdir) + "pixl.xml"
FileUtils.cp(pixlSWF,pixlSWFBak)

# import image
system(ffdec,'-replace',pixlSWF.to_s,pixlSWF.to_s,'49000',imageFile)
# get XML for editing shape & pixl tags
system(ffdec,'-swf2xml',pixlSWF.to_s,pixlXML.to_s)
pixlDoc = Nokogiri::XML(File.read(pixlXML)) { |config| config.huge }

# edit XML
tags = pixlDoc.at_xpath("//tags")
# shape
shape = tags.at_xpath("//item[@type='DefineShapeTag']")
shapeBounds = shape.at_xpath("//shapeBounds")
shapeBounds["Xmin"] = image.columns * -10;
shapeBounds["Xmax"] = image.columns * 10;
shapeBounds["Ymin"] = image.rows * -10;
shapeBounds["Ymax"] = image.rows * 10;
bitmapMatrix = shape.at_xpath("//shapes/fillStyles/fillStyles/item[last()]/bitmapMatrix")
bitmapMatrix["translateX"] = image.columns * -10
bitmapMatrix["translateY"] = image.rows * -10
styleChangeRecord = shape.at_xpath("//shapes/shapeRecords/item[@type='StyleChangeRecord']")
styleChangeRecord["moveDeltaX"] = image.columns * -10
styleChangeRecord["moveDeltaY"] = image.rows * -10
straightEdgeRecords = shape.xpath("//shapes/shapeRecords/item[@type='StraightEdgeRecord']")
straightEdgeRecords[0]["deltaX"] = image.columns * 20
straightEdgeRecords[1]["deltaY"] = image.rows * 20
straightEdgeRecords[2]["deltaX"] = image.columns * -20
straightEdgeRecords[3]["deltaY"] = image.rows * -20
# pixl
tags.at_xpath("//item[@type='UnknownTag']")["unknownData"] = data

# copy pixl tags to SWF file

# get SWF XML
swfXML = Pathname.new(Dir.tmpdir) + "swf.xml"
system(ffdec,'-swf2xml',swfFile.to_s,swfXML.to_s)
swfDoc = Nokogiri::XML(File.read(swfXML)) { |config| config.huge }

# collect pixl tags
pixlXMLContent = []
found = false
pixlDoc.xpath('/swf/tags/item').each do |node|
  if node['type'] == 'SetBackgroundColorTag'
    found = true
    next
  end
  break if node['type'] == 'ShowFrameTag'
  pixlXMLContent << node if found
end

# import pixl tags to SWF
swfXMLInsertNode = swfDoc.at_xpath("/swf/tags/item[@type='SetBackgroundColorTag']")
pixlXMLContent.each do |node|
  new = node.dup
  swfXMLInsertNode.add_next_sibling(new)
  swfXMLInsertNode = new
end

File.write(swfXML.to_s,swfDoc.to_xml(indent:2,indent_text:"  ").gsub(/<\/item><item/,"</item>\n  <item"))
system(ffdec,'-xml2swf',swfXML.to_s,swfFile.to_s)

FileUtils.cp(pixlSWFBak,pixlSWF)
FileUtils.rm(pixlSWFBak)
FileUtils.rm(pixlXML)
FileUtils.rm(swfXML)

=begin
shape notes

shapeBounds
Xmin: width * -10
Xmax: width * 10
Ymin: height * -10
Ymax: height * 10

shapes
fillStyle[1]
bitmapId: image ID
bitmapMatrix
translateX: width * -10
translateY: height * -10

shapeRecords
record[0]
moveDeltaX: width * -10
moveDeltaY: height * -10
record[1]
deltaX: width * 20
record[2]
deltaY: height * 20
record[3]
deltaX: width * -20
record[4]
deltaY: height * -20
=end
