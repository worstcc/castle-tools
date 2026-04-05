#!/usr/bin/env ruby
# todo:
# pixl.swf structure: shape is placed by sprite which sets _visible to false, fixes in-game visual bugs caused by reference sometimes
# specify placed dimensions for import
# export hybrid ps3 player/fx pixl tags
# xbla/ps3 import (big endian "PIXL")
require 'mini_magick'
require 'pathname'
require 'tempfile'
require 'tmpdir'
require 'nokogiri'
require 'optparse'

def findFFDec
  ffdecPath = nil
  if RUBY_PLATFORM =~ /mswin|mingw|jruby/
    ffdecPath = 'C:\\Program Files (x86)\\FFDec\\ffdec-cli.exe'
  elsif RUBY_PLATFORM =~ /linux/
    ffdecPath = '/usr/bin/ffdec'
    ffdecPath = `which ffdec`.strip unless File.exist?(ffdecPath)
  end
  abort 'error: JPEXS not found' if ffdecPath.nil? || !File.exist?(ffdecPath)
  ffdecPath
end

options = {}
OptionParser.new do |opts|
  opts.banner = "usage: #{File.basename($PROGRAM_NAME)} [image|swf] [output directory]"
  opts.on('-f','--format FORMAT',String,'game version to target (steam,xbla,ps3) steam is default') do |format|
    abort 'error: invalid format' unless format.match?(/steam|xbla|ps3/)
    options[:format] = format
  end
  opts.on('-r','--export-raw','use raw image dimensions in export') { options[:exportraw] = true }
  opts.on('-d','--dry-run','don\'t write to files') { options[:dryrun] = true }
end.parse!

options[:format] = 'steam' unless options[:format]

abort "usage: #{File.basename($PROGRAM_NAME)} [image|swf] [output directory]" if ARGV.length != 2

inputFile = File.expand_path(ARGV[0])
abort "error: #{File.basename(inputFile)} not found" unless File.exist?(inputFile)
abort "error: #{File.basename(inputFile)} is not a bmp|swf" unless ['.bmp','.swf'].include?(File.extname(inputFile).downcase)

outputDir = File.expand_path(ARGV[1])
abort "error: #{outputDir} not found" unless Dir.exist?(outputDir)

ffdec = findFFDec

if File.extname(inputFile).downcase == '.swf'
  # extract images from swf pixl tags

  # get xml
  swfXml = Tempfile.new(['','.xml'])
  system(ffdec,'-swf2xml',inputFile.to_s,swfXml.path)
  doc = Nokogiri::XML(File.read(swfXml.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)

  # collect unknown tags
  found = false
  doc.xpath('//tags/*').each do |tag|
    next unless tag['unknownData']

    data = tag['unknownData']
    pixlHeaderIndex = data.index('4c584950') || data.index('5049584c')
    next unless pixlHeaderIndex

    found = true
    # check if footer is valid
    case options[:format]
    when 'steam'
      if data[-32,32] != '24000000280000003000000003000000'
        puts 'invalid pixl tag'
        next
      end
      endian = 'V' # little endian
    when 'xbla'
      if data[-32,32] != '00000024000000280000003000000003'
        puts 'invalid pixl tag'
        next
      end
      endian = 'N' # big endian
    when 'ps3'
      if data[-32,32] != '00000024000000280000003000000003'
        puts 'invalid pixl tag'
        next
      end
      # get pixl data
      endian = 'N'
      next if data[pixlHeaderIndex,8] == '4c584950' # odd hybrid version seen in ps3 player.swf
    end

    # get image properties
    width = [data[pixlHeaderIndex + 32,8]].pack('H*').unpack1(endian)
    height = [data[pixlHeaderIndex + 40,8]].pack('H*').unpack1(endian)
    id = [data[pixlHeaderIndex + 160,8]].pack('H*').unpack1(endian)
    placedWidth = ([data[16,4]].pack('H*').unpack1('v').to_f / 10)
    placedHeight = ([data[32,4]].pack('H*').unpack1('v').to_f / 10)
    byteLength = [data[pixlHeaderIndex + 96,103]].pack('H*').unpack1(endian)
    imageData = data[pixlHeaderIndex + 192,byteLength * 2]
    # only get "true" placed dimensions if they are different enough from the raw dimensions
    if (placedWidth - width).abs > 5 && (placedHeight - height).abs > 5
      if placedHeight > placedWidth
        # placed dimensions aren't in same order all the time, making the higher number the width seems to work
        placedWidth, placedHeight = placedHeight, placedWidth
      end

      # get correct placed values
      placedWidth = placedWidth / 2 + width if placedWidth != width
      placedHeight = placedHeight / 2 + height if placedHeight != height
    end
    puts "(#{id}) raw: #{width}x#{height}, placed: #{placedWidth}x#{placedHeight}"

    # remove "cdcdcdcd" bytes from image data
    imageData = [imageData.sub(/\A(cdcdcdcd)+/,'')].pack('H*').bytes

    # build matrix & reorder bgra -> rgba for MiniMagick's get_image_from_pixels structure
    rgbaPixels = imageData.each_slice(4).map do |pixel|
      case options[:format]
      when 'steam'
        b,g,r,a = pixel
      when 'xbla'
        a,r,g,b = pixel
      when 'ps3'
        r,g,b,a = pixel
      end
      # undo multiplying RGB by A
      if a.zero?
        [0,0,0,0] # transparent
      else
        alpha = a / 255.0
        [[[(r / alpha).round,0].max,255].min,[[(g / alpha).round,0].max,255].min,[[(b / alpha).round,0].max,255].min,a]
      end
    end
    imagePixelMatrix = rgbaPixels.each_slice(width).map { |row| row }

    # export image

    image = MiniMagick::Image.get_image_from_pixels(imagePixelMatrix,[width,height],'rgba',8,'bmp')
    image.resize "!#{placedWidth}x#{placedHeight}" unless options[:exportraw] || width == placedWidth && height == placedHeight
    image.write(File.join(outputDir,"#{id}.bmp")) unless options[:dryrun]
  end

  puts 'no pixl tags found' unless found

  FileUtils.rm(swfXml)
else
  # import image into copy of pixl swf

  # read image
  image = MiniMagick::Image.open(inputFile)
  # if image.depth != 8
  #   raise "#{File.basename(inputFile)} depth is not 8-bit"
  # end
  # abort "#{File.basename(inputFile)} is too large (maximum 1024x1024)" if image.width > 1024 || image.height > 1024
  pixels = image.get_pixels('RGBA')
  imageData = pixels.flat_map do |row|
    row.map do |pixel|
      r,g,b,a = pixel
      # for transparent images to render properly the RGB values need to be multiplied by A (0.0 to 1.0)
      alpha = a / 255.0
      r2 = (r * alpha).round
      g2 = (g * alpha).round
      b2 = (b * alpha).round
      [b2,g2,r2,a].pack('C4').unpack1('H*')
    end
  end.join

  # create pixl tag
  data = ''
  # swf header

  # character id
  data << [65534].pack('v').unpack1('H*')
  data << '00' * 2
  # width
  data << [65536 - image.width * 10].pack('v').unpack1('H*')
  data << 'ff' * 2
  data << [image.width * 10].pack('v').unpack1('H*')
  data << '00' * 2
  # height
  data << [65536 - image.height * 10].pack('v').unpack1('H*')
  data << 'ff' * 2
  data << [image.height * 10].pack('v').unpack1('H*')
  data << '00' * 2
  # padding
  data << 'cd' * 16

  # PIXL header
  data << '4c584950'
  data << '00' * 12
  # width
  data << [image.width].pack('V').unpack1('H*')
  # height
  data << [image.height].pack('V').unpack1('H*')
  # planes
  data << [1].pack('V').unpack1('H*')
  # bitcount
  data << [32].pack('V').unpack1('H*')
  # compression
  data << [0].pack('V').unpack1('H*')
  # ?
  data << '60000000'
  # x pixels per meter
  data << [2835].pack('V').unpack1('H*')
  # y pixels per meter
  data << [2835].pack('V').unpack1('H*')
  # image length
  data << [imageData.length / 2].pack('V').unpack1('H*')
  # ?
  data << '01000000' * 2
  # width/height/width/height
  data << [image.width].pack('V').unpack1('H*')
  data << [image.height].pack('V').unpack1('H*')
  data << [image.width].pack('V').unpack1('H*')
  data << [image.height].pack('V').unpack1('H*')
  data << 'cd' * 4
  # character id
  data << [65534].pack('v').unpack1('H*')
  data << '00' * 14

  # image data
  data << imageData
  # footer
  data << '24000000280000003000000003000000'

  # import image

  pixlSwf = File.join(__dir__,'swf','pixl.swf')
  abort 'swf/pixl.swf missing in script directory' unless File.exist?(pixlSwf)
  swfXml = Tempfile.new(['','.xml'])
  outputSwf = Tempfile.new(['','.swf'])
  FileUtils.cp(pixlSwf,outputSwf)

  system(ffdec,'-replace',outputSwf.path,outputSwf.path,'65531',inputFile.to_s)
  # get XML for editing shape & pixl tags
  system(ffdec,'-swf2xml',outputSwf.path,swfXml.path)
  doc = Nokogiri::XML(File.read(swfXml.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)

  # edit XML
  tags = doc.at_xpath('//tags')
  # shape
  shape = tags.at_xpath("//item[@type='DefineShapeTag']")
  shapeBounds = shape.at_xpath('//shapeBounds')
  shapeBounds['Xmin'] = image.width * -10
  shapeBounds['Xmax'] = image.width * 10
  shapeBounds['Ymin'] = image.height * -10
  shapeBounds['Ymax'] = image.height * 10
  bitmapMatrix = shape.at_xpath('//shapes/fillStyles/fillStyles/item[last()]/bitmapMatrix')
  bitmapMatrix['translateX'] = image.width * -10
  bitmapMatrix['translateY'] = image.height * -10
  styleChangeRecord = shape.at_xpath("//shapes/shapeRecords/item[@type='StyleChangeRecord']")
  styleChangeRecord['moveDeltaX'] = image.width * -10
  styleChangeRecord['moveDeltaY'] = image.height * -10
  straightEdgeRecords = shape.xpath("//shapes/shapeRecords/item[@type='StraightEdgeRecord']")
  straightEdgeRecords[0]['deltaX'] = image.width * 20
  straightEdgeRecords[1]['deltaY'] = image.height * 20
  straightEdgeRecords[2]['deltaX'] = image.width * -20
  straightEdgeRecords[3]['deltaY'] = image.height * -20
  # pixl
  tags.at_xpath("//item[@type='UnknownTag']")['unknownData'] = data

  File.write(swfXml,doc.to_xml(indent:2,indent_text:'  ').gsub(%r{</item><item},"</item>\n  <item"))

  # create output swf in output directory
  unless options[:dryrun]
    system(ffdec,'-xml2swf',swfXml.path,outputSwf.path)
    FileUtils.cp(outputSwf,File.join(outputDir,"#{File.basename(inputFile,'.*')}.swf"))
  end
end
