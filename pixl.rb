#!/usr/bin/env ruby
=begin
pixl.swf structure: shape is placed by sprite which sets _visible to false, fixes in-game visual bugs caused by reference sometimes
research importing image missing pixels near top left
research alpha
extracting ps3 pixl tags doesn't work
add BREC mode for import/export (PIXL instead of LXIP)
=end
require 'rmagick'
require 'pathname'
require 'tempfile'
require 'tmpdir'
require 'nokogiri'
require 'optparse'
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

options = {}
OptionParser.new do |opts|
  opts.banner = "usage: #{File.basename($0)} [image|swf] [output directory]"
  opts.on("-r","--export-raw","use raw image dimensions in export") { options[:exportraw] = true }
  opts.on("-d","--dry-run","don't write to files"){ options[:dryrun] = true }
end.parse!

if ARGV.length != 2
  puts "usage: #{File.basename($0)} [image|swf] [output directory]"
  exit 1
end

inputFile = Pathname.new(ARGV[0])
if ! File.exist?(inputFile)
  raise "#{File.basename(inputFile)} not found"
end
if ! [".png",".swf"].include?(File.extname(inputFile).downcase)
  raise "#{File.basename(inputFile)} is not a png|swf"
end

outputDir = Pathname.new(ARGV[1])
if ! Dir.exist?(outputDir)
  raise "#{outputDir} not found"
end

ffdec = findFFDec

if File.extname(inputFile).downcase == ".swf"
  # extract images from swf pixl tags

  # get xml
  swfXml = File.join(Pathname.new(Dir.tmpdir) + "temp.xml")
  system(ffdec,'-swf2xml',inputFile.to_s,swfXml.to_s)
  doc = Nokogiri::XML(File.read(swfXml)) { |config| config.huge }

  # collect unknown tags
  doc.xpath("//tags/*").each do |tag|
    if tag["unknownData"]
      data = tag["unknownData"]
      pixlHeaderIndex = data.index("4c584950")
      if pixlHeaderIndex
        # check if footer is valid
        if data[-32,32] != "24000000280000003000000003000000"
          puts "error: invalid pixl tag"
          next
        end
        # get pixl data
        columns = [data[pixlHeaderIndex + 32,8]].pack("H*").unpack1("V")
        rows = [data[pixlHeaderIndex + 40,8]].pack("H*").unpack1("V")
        placedColumns = [data[16,4]].pack("H*").unpack1("v") / 10
        placedRows = [data[32,4]].pack("H*").unpack1("v") / 10
        id = [data[pixlHeaderIndex + 160,4]].pack("H*").unpack1("v")

        # placed dimensions aren't in same order all the time, making the higher number the columns seems to work
        if placedRows > placedColumns
          placedColumns, placedRows = placedRows, placedColumns
        end

        # get correct placed values
        if placedColumns != columns
          placedColumns = placedColumns / 2 + columns
        end
        if placedRows != rows
          placedRows = placedRows / 2 + rows
        end
        puts "(#{id}) raw: #{columns}x#{rows}, placed: #{placedColumns}x#{placedRows}"

        byteLength = [data[pixlHeaderIndex + 96,103]].pack("H*").unpack1("V")
        imageData = data[pixlHeaderIndex + 192,byteLength * 2]

        # remove "cdcdcdcd" bytes from image data
        imageData = imageData.sub(/\A(cdcdcdcd)+/,"")
        imageData = [imageData].pack("H*")

        # export image
        image = Image.new(columns,rows)
        image.import_pixels(0,0,columns,rows,"BGRA",imageData,CharPixel)
        if ! options[:exportraw]
          image = image.resize(placedColumns,placedRows)
        end
        if ! options[:dryrun]
          image.write("png:" + File.join(outputDir + "#{id}.png"))
        end
      end
    end
  end

  FileUtils.rm(swfXml)
else 
  # import image into copy of pixl swf

  # read image
  image = Image.read(inputFile).first
  # if image.depth != 8
  #   raise "#{File.basename(inputFile)} depth is not 8-bit"
  # end
  if image.columns > 1024 || image.rows > 1024
    raise "#{File.basename(inputFile)} is too large (maximum 1024x1024)"  
  end
  imageData = image.export_pixels(0,0,image.columns,image.rows,"BGRA").pack('C*').unpack('H*').first

  # create pixl tag

  # swf header

  data = ""
  # character ID
  data << [65534].pack('v').unpack1('H*')
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
  data << [65534].pack('v').unpack1('H*')
  data << "00" * 14

  # image data
  data << imageData

  # footer
  data << "24000000280000003000000003000000"

  # import image

  scriptDir = Pathname.new(__FILE__).realpath.parent
  pixlSwf = File.join(scriptDir + "swf" + "pixl.swf")
  unless File.exist?(pixlSwf)
    raise "swf/pixl.swf missing in script directory"
  end
  swfXml = File.join(Pathname.new(Dir.tmpdir) + "temp.xml")
  outputSwf = File.join(Pathname.new(Dir.tmpdir) + "temp.swf")
  FileUtils.cp(pixlSwf,outputSwf)

  system(ffdec,'-replace',outputSwf.to_s,outputSwf.to_s,"65532",inputFile.to_s)
  # get XML for editing shape & pixl tags
  system(ffdec,'-swf2xml',outputSwf.to_s,swfXml.to_s)
  doc = Nokogiri::XML(File.read(swfXml)) { |config| config.huge }

  # edit XML
  tags = doc.at_xpath("//tags")
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

  File.write(swfXml,doc.to_xml(indent:2,indent_text:"  ").gsub(/<\/item><item/,"</item>\n  <item"))

  # create output swf in output directory
  if ! options[:dryrun]
    system(ffdec,'-xml2swf',swfXml.to_s,outputSwf.to_s)
    FileUtils.cp(outputSwf,File.join(outputDir,File.basename(inputFile,File.extname(inputFile)) + ".swf"))
  end

  FileUtils.rm(swfXml)
  FileUtils.rm(outputSwf)
end

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
