#!/usr/bin/env ruby
=begin
pixl.swf structure: shape is placed by sprite which sets _visible to false, fixes in-game visual bugs caused by reference sometimes
extracting ps3 pixl tags doesn't work
add BREC mode for import/export (PIXL instead of LXIP)
=end
require 'mini_magick'
require 'pathname'
require 'tempfile'
require 'tmpdir'
require 'nokogiri'
require 'optparse'

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
        width = [data[pixlHeaderIndex + 32,8]].pack("H*").unpack1("V")
        height = [data[pixlHeaderIndex + 40,8]].pack("H*").unpack1("V")
        placedWidth = ([data[16,4]].pack("H*").unpack1("v").to_f / 10).round
        placedHeight = ([data[32,4]].pack("H*").unpack1("v").to_f / 10).round
        id = [data[pixlHeaderIndex + 160,4]].pack("H*").unpack1("v")

        # only get "true" placed dimensions if they are different enough from the raw dimensions
        if (placedWidth - width).abs > 5 && (placedHeight - height).abs > 5
          if placedHeight > placedWidth
            # placed dimensions aren't in same order all the time, making the higher number the width seems to work
            placedWidth, placedHeight = placedHeight, placedWidth
          end

          # get correct placed values
          if placedWidth != width
            placedWidth = placedWidth / 2 + width
          end
          if placedHeight != height
            placedHeight = placedHeight / 2 + height
          end
        end
        puts "(#{id}) raw: #{width}x#{height}, placed: #{placedWidth}x#{placedHeight}"

        byteLength = [data[pixlHeaderIndex + 96,103]].pack("H*").unpack1("V")
        imageData = data[pixlHeaderIndex + 192,byteLength * 2]

        # remove "cdcdcdcd" bytes from image data
        imageData = [imageData.sub(/\A(cdcdcdcd)+/,"")].pack("H*").bytes
        # build matrix & reorder bgra -> rgba for MiniMagick's get_image_from_pixels structure
        rgbaPixels = imageData.each_slice(4).map do |b,g,r,a|
          # undo multiplying RGB by A
          if a == 0
            [0,0,0,0] # transparent
          else
            alpha = a / 255.0
            r2 = [[(r / alpha).round,0].max,255].min
            g2 = [[(g / alpha).round,0].max,255].min
            b2 = [[(b / alpha).round,0].max,255].min
            [r2,g2,b2,a]
          end
        end
        imagePixelMatrix = rgbaPixels.each_slice(width).map do |row|
          row
        end
        # export image
        image = MiniMagick::Image.get_image_from_pixels(imagePixelMatrix,[width,height],"rgba",8,"png")
        unless options[:exportraw] || width == placedWidth && height == placedHeight
          image.resize "!#{placedWidth}x#{placedHeight}"
        end
        unless options[:dryrun]
          image.write(File.join(outputDir + "#{id}.png"))
        end
      end
    end
  end

  FileUtils.rm(swfXml)
else 
  # import image into copy of pixl swf

  # read image
  image = MiniMagick::Image.read(inputFile)
  # if image.depth != 8
  #   raise "#{File.basename(inputFile)} depth is not 8-bit"
  # end
  if image.width > 1024 || image.height > 1024
    raise "#{File.basename(inputFile)} is too large (maximum 1024x1024)"  
  end
  pixels = image.get_pixels("RGBA")
  imageData = pixels.flat_map do |row|
    row.map do |pixel|
      r,g,b,a = pixel
      # for transparent images to render properly the RGB values need to be multiplied by A (0.0 to 1.0)
      alpha = a / 255.0
      r2 = (r * alpha).round
      g2 = (g * alpha).round
      b2 = (b * alpha).round
      [b2,g2,r2,a].pack("C4").unpack1("H*")
    end
  end.join

  # create pixl tag

  # swf header

  data = ""
  # character ID
  data << [65534].pack('v').unpack1('H*')
  data << "00" * 2
  # width
  data << [65536 - image.width * 10].pack('v').unpack1('H*')
  data << "ff" * 2
  data << [image.width * 10].pack('v').unpack1('H*')
  data << "00" * 2
  # height
  data << [65536 - image.height * 10].pack('v').unpack1('H*')
  data << "ff" * 2
  data << [image.height * 10].pack('v').unpack1('H*')
  data << "00" * 2
  # padding
  data << "cd" * 16

  # PIXL header
  data << "4c584950"
  data << "00" * 12
  # width
  data << [image.width].pack('V').unpack1('H*')
  # height
  data << [image.height].pack('V').unpack1('H*')
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
  data << [image.width].pack('V').unpack1('H*')
  data << [image.height].pack('V').unpack1('H*')
  data << [image.width].pack('V').unpack1('H*')
  data << [image.height].pack('V').unpack1('H*')
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
  shapeBounds["Xmin"] = image.width * -10;
  shapeBounds["Xmax"] = image.width * 10;
  shapeBounds["Ymin"] = image.height * -10;
  shapeBounds["Ymax"] = image.height * 10;
  bitmapMatrix = shape.at_xpath("//shapes/fillStyles/fillStyles/item[last()]/bitmapMatrix")
  bitmapMatrix["translateX"] = image.width * -10
  bitmapMatrix["translateY"] = image.height * -10
  styleChangeRecord = shape.at_xpath("//shapes/shapeRecords/item[@type='StyleChangeRecord']")
  styleChangeRecord["moveDeltaX"] = image.width * -10
  styleChangeRecord["moveDeltaY"] = image.height * -10
  straightEdgeRecords = shape.xpath("//shapes/shapeRecords/item[@type='StraightEdgeRecord']")
  straightEdgeRecords[0]["deltaX"] = image.width * 20
  straightEdgeRecords[1]["deltaY"] = image.height * 20
  straightEdgeRecords[2]["deltaX"] = image.width * -20
  straightEdgeRecords[3]["deltaY"] = image.height * -20
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
