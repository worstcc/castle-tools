#!/usr/bin/env ruby

require 'mini_magick'
require 'nokogiri'
require 'optparse'
require 'pathname'
require 'tempfile'
require 'tmpdir'

# TODO: export hybrid ps3 player/fx pixl tags
# TODO: xbla/ps3 import (big endian "PIXL")

options = {}
OptionParser.new do |opts|
  opts.banner = "usage: #{File.basename($PROGRAM_NAME)} [image|swf] [output directory]"
  opts.on('-p','--platform PLATFORM',String,'game platform to target (steam (default),xbla,ps3)') do |format|
    abort 'error: invalid format' unless format.match?(/steam|xbla|ps3/)
    options[:format] = format
  end
  opts.on('-s','--size SIZE',Integer,'import: image size to use when scaling down (default/max: 512)') { |size| options[:size] = size }
  opts.on('-d','--placedDimensions DIMENSIONS',String,'import: dimensions to use for image shape (default: original image dimensions') do |dimensions|
    abort 'error: invalid dimensions format, use WIDTHxHEIGHT (e.g. 1024x512)' unless dimensions.match?(/^\d+(\.\d+)?x\d+(\.\d+)?$/i)
    options[:placedDimensions] = dimensions
  end
  opts.on('-o','--placedOffset OFFSETS',String,'import: offset to use for image shape (default: none)') do |offset|
    abort 'error: invalid dimensions format, use X,Y (e.g. 512,0)' unless offset.match?(/^-?\d+(\.\d+)?,-?\d+(\.\d+)?$/)
    options[:placedOffset] = offset
  end
  opts.on('-n','--noScale','import: don\'t scale down image (greatly increases file size)') { options[:noScale] = true }
  opts.on('-f','--noSizeLimit','import: allow image size larger than 512 (not recommended, will cause issues)') { options[:force] = true }
  opts.on('-r','--raw','export: use raw image dimensions instead of placed dimensions') { options[:exportRaw] = true }
  opts.on('-x','--printData','import: print unknownData of pixl tag instead of outputting to swf') { options[:xml] = true }
end.parse!
options[:format] = 'steam' unless options[:format]
options[:size] = 512 unless options[:size]

abort "usage: #{File.basename($PROGRAM_NAME)} [image|swf] [output directory]" if ARGV.length != 2

inputFile = File.expand_path(ARGV[0])
abort "error: #{File.basename(inputFile)} not found" unless File.exist?(inputFile)
abort "error: #{File.basename(inputFile)} is not an accepted image or swf" unless ['.bmp','.jpg','.jpeg','.jxl','.png','.gif','.webp','.swf'].include?(File.extname(inputFile).downcase)

outputDir = File.expand_path(ARGV[1])
abort "error: #{outputDir} not found" unless Dir.exist?(outputDir)

def commandExists?(cmd)
  path = if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
           `where.exe #{cmd}`.split("\n").first
         else
           `which #{cmd}`.strip
         end
  path.empty? ? false : path
end

ffdec = nil
if RUBY_PLATFORM =~ /mswin|mingw|jruby/
  ffdec = 'C:\\Program Files (x86)\\FFDec\\ffdec-cli.exe'
elsif RUBY_PLATFORM =~ /linux/
  ffdec = commandExists?('ffdec')
end
abort 'error: jpexs is not installed' if ffdec.nil? || !File.exist?(ffdec)

if File.extname(inputFile).downcase == '.swf'
  # extract images from swf pixl tags

  # get xml
  tempXml = Tempfile.create(['','.xml'])
  at_exit do
    tempXml.close
    File.unlink(tempXml)
  end
  abort 'error: ffdec failed' unless system(ffdec,'-swf2xml',inputFile.to_s,tempXml.path)
  doc = Nokogiri::XML(File.read(tempXml.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)

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
      endian2 = 'v'
    when 'xbla'
      if data[-32,32] != '00000024000000280000003000000003'
        puts 'invalid pixl tag'
        next
      end
      endian = 'N' # big endian
      endian2 = 'n'
    when 'ps3'
      if data[-32,32] != '00000024000000280000003000000003'
        puts 'invalid pixl tag'
        next
      end
      # get pixl data
      endian = 'N'
      endian2 = 'n'
      next if data[pixlHeaderIndex,8] == '4c584950' # odd hybrid version seen in ps3 player.swf
    end

    # get image properties
    width = [data[pixlHeaderIndex + 32,8]].pack('H*').unpack1(endian)
    height = [data[pixlHeaderIndex + 40,8]].pack('H*').unpack1(endian)
    id = [data[pixlHeaderIndex + 160,8]].pack('H*').unpack1(endian)

    # average the inverted & direct values to get each placement dimension
    placedWidthInverted = (65536 - [data[8,4]].pack('H*').unpack1(endian2)).to_f / 10
    placedWidthDirect = [data[16,4]].pack('H*').unpack1(endian2).to_f / 10
    placedWidth = (placedWidthInverted + placedWidthDirect).to_f / 2
    xOffset = (placedWidthDirect - placedWidth) / 2
    placedHeightInverted = (65536 - [data[24,4]].pack('H*').unpack1(endian2)).to_f / 10
    placedHeightDirect = [data[32,4]].pack('H*').unpack1(endian2).to_f / 10
    placedHeight = (placedHeightInverted + placedHeightDirect).to_f / 2
    yOffset = (placedHeightDirect - placedHeight) / 2
    byteLength = [data[pixlHeaderIndex + 96,103]].pack('H*').unpack1(endian)
    imageData = data[pixlHeaderIndex + 192,byteLength * 2]
    if !xOffset.zero? || !yOffset.zero?
      puts "(#{id}) raw: #{width}x#{height}, placed: #{placedWidth}x#{placedHeight}, offset: (#{xOffset},#{yOffset})"
    else
      puts "(#{id}) raw: #{width}x#{height}, placed: #{placedWidth}x#{placedHeight}"
    end

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
    image.resize "!#{placedWidth}x#{placedHeight}" unless options[:exportRaw] || width == placedWidth && height == placedHeight
    image.write(File.join(outputDir,"#{id}.bmp"))
    FileUtils.rm(image.path)
  end

  puts 'no pixl tags found' unless found
else
  # import image into copy of pixl swf
  # scale down the image for pixl tag to save space, then scale back up for shape

  def imageToPixl(image,placedWidth,placedHeight)
    imageData = image.get_pixels('RGBA').flat_map do |row|
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

    data = ''

    # swf header

    # character id
    data << [65534].pack('v').unpack1('H*')
    data << '00' * 2
    # placed width
    data << [65536 - placedWidth * 10].pack('v').unpack1('H*') # inverted
    data << 'ff' * 2
    data << [placedWidth * 10].pack('v').unpack1('H*') # direct
    data << '00' * 2
    # placed height
    data << [65536 - placedHeight * 10].pack('v').unpack1('H*') # inverted
    data << 'ff' * 2
    data << [placedHeight * 10].pack('v').unpack1('H*') # direct
    data << '00' * 2
    # padding
    data << 'cd' * 16

    # pixl header

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

    data
  end

  # read image
  image = MiniMagick::Image.open(inputFile)

  if options[:placedDimensions]
    placedWidth,placedHeight = options[:placedDimensions].split('x').map(&:to_f)
  else
    placedWidth = image.width
    placedHeight = image.height
  end

  if options[:noScale]
    if !options[:force] && (image.width > 512 || image.height > 512)
      width = [image.width,512].min
      height = [image.height,512].min
      warn "image is too large, scaling #{image.width}x#{image.height} to #{width}x#{height}"
      image.resize "#{width}x#{height}!"
      image.write image.path
    end
  else
    if !options[:force] && options[:size] > 512
      warn 'image size is higher than 512, limiting'
      options[:size] = 512
    end
    minDimension = [image.width,image.height].min
    targetSize = minDimension >= options[:size] ? options[:size] : (minDimension & ~1)
    image.resize "#{targetSize}x#{targetSize}!"
    image.write image.path
  end

  if options[:xml]
    puts imageToPixl(image,placedWidth,placedHeight)
    exit 0
  end

  # import image

  pixlSwf = File.join(__dir__,'swf','pixl.swf')
  abort 'swf/pixl.swf missing in script directory' unless File.exist?(pixlSwf)
  tempXml = Tempfile.create(['','.xml'])
  at_exit do
    tempXml.close
    File.unlink(tempXml)
  end
  tempSwf = Tempfile.create(['','.swf'])
  at_exit do
    tempSwf.close
    File.unlink(tempSwf)
  end
  FileUtils.cp(pixlSwf,tempSwf)

  # convert image to png for ffdec import
  Tempfile.create(['','.png']) do |file|
    MiniMagick.convert do |cmd|
      cmd << "#{image.path}[0]"
      cmd << file.path
    end
    abort 'error: ffdec failed' unless system(ffdec,'-replace',tempSwf.path,tempSwf.path,'65531',file.path)
  end

  # get XML for editing shape & pixl tags
  abort 'error: ffdec failed' unless system(ffdec,'-swf2xml',tempSwf.path,tempXml.path)
  doc = Nokogiri::XML(File.read(tempXml.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)

  tags = doc.at_xpath('//tags')
  # make shape place image, centered & scaled to placed dimensions
  shape = tags.at_xpath("//item[@type='DefineShapeTag']")
  shapeBounds = shape.at_xpath('//shapeBounds')
  shapeBounds['Xmin'] = (placedWidth * -10).to_i
  shapeBounds['Xmax'] = (placedWidth * 10).to_i
  shapeBounds['Ymin'] = (placedHeight * -10).to_i
  shapeBounds['Ymax'] = (placedHeight * 10).to_i
  bitmapMatrix = shape.at_xpath('//shapes/fillStyles/fillStyles/item[last()]/bitmapMatrix')
  bitmapMatrix['translateX'] = (placedWidth * -10).to_i
  bitmapMatrix['translateY'] = (placedHeight * -10).to_i
  bitmapMatrix['scaleX'] = (placedWidth.to_f / image.width) * 20
  bitmapMatrix['scaleY'] = (placedHeight.to_f / image.height) * 20
  styleChangeRecord = shape.at_xpath("//shapes/shapeRecords/item[@type='StyleChangeRecord']")
  styleChangeRecord['moveDeltaX'] = (placedWidth * -10).to_i
  styleChangeRecord['moveDeltaY'] = (placedHeight * -10).to_i

  # split straight edge records to avoid exceeding max edge length
  def splitEdge(delta)
    return [delta] if delta.abs <= 32767

    numSegments = (delta.abs.to_f / 32767).ceil
    segmentSize = (delta.abs.to_f / numSegments).round
    sign = delta <=> 0

    segments = Array.new(numSegments - 1,sign * segmentSize)
    remainder = delta.abs - segmentSize * (numSegments - 1)
    segments << sign * remainder
    segments
  end

  straightEdgeRecords = shape.xpath("//shapes/shapeRecords/item[@type='StraightEdgeRecord']")
  segments = [
    splitEdge((placedWidth * 20).to_i), # right
    splitEdge((placedHeight * 20).to_i), # down
    splitEdge((placedWidth * -20).to_i), # left
    splitEdge((placedHeight * -20).to_i) # up
  ]
  shapeRecords = shape.at_xpath('//shapes/shapeRecords')
  segments.each_with_index do |directionSegments,edgeIndex|
    straightEdgeRecords[edgeIndex]['deltaX'] = directionSegments[0] if edgeIndex.even?
    straightEdgeRecords[edgeIndex]['deltaY'] = directionSegments[0] if edgeIndex.odd?
    straightEdgeRecords[edgeIndex]['numBits'] = Math.log2(directionSegments[0].abs + 1).ceil + 1
    directionSegments[1..].each do |segment|
      newRecord = Nokogiri::XML::Element.new('item',shapeRecords.document)
      newRecord['type'] = 'StraightEdgeRecord'
      newRecord['generalLineFlag'] = segment >= 0 ? 'false' : 'true'
      newRecord['numBits'] = Math.log2(segment.abs + 1).ceil + 1
      newRecord['vertLineFlag'] = edgeIndex.odd? ? 'true' : 'false'
      if edgeIndex.even?
        newRecord['deltaX'] = segment
        newRecord['deltaY'] = 0
      else
        newRecord['deltaX'] = 0
        newRecord['deltaY'] = segment
      end
      straightEdgeRecords[edgeIndex].add_next_sibling(newRecord)
    end
  end

  tags.at_xpath("//item[@type='UnknownTag']")['unknownData'] = imageToPixl(image,placedWidth,placedHeight)

  # apply offset to pixl sprite if specified
  if options[:placedOffset]
    xOffset,yOffset = options[:placedOffset].split(',').map(&:to_f)

    sprite = tags.at_xpath("//item[@type='DefineSpriteTag'][@spriteId='65535']")
    return unless sprite

    placeObjectNodes = sprite.xpath(".//item[@type='PlaceObject2Tag']")
    placeObjectNodes.each do |node|
      node['placeFlagHasMatrix'] = 'true'
      # create matrix
      matrix = node.at_xpath('./matrix') || Nokogiri::XML::Element.new('matrix',doc)
      matrix['type'] = 'MATRIX'
      matrix['hasScale'] = true
      matrix['scaleX'] = 1.0
      matrix['scaleY'] = 1.0
      matrix['hasRotate'] = true
      matrix['rotateSkew0'] = 0.0
      matrix['rotateSkew1'] = 0.0
      matrix['translateX'] = (xOffset * 20).to_i
      matrix['translateY'] = (yOffset * 20).to_i
      node.add_child(matrix) unless node.at_xpath('matrix')
    end
  end

  File.write(tempXml,doc.to_xml(indent:2,indent_text:'  ').gsub(%r{</item><item},"</item>\n  <item"))

  if options[:xml]
    FileUtils.cp(tempXml,File.join(outputDir,"#{File.basename(inputFile,'.*')}.xml"))
  else
    abort 'error: ffdec failed' unless system(ffdec,'-xml2swf',tempXml.path,tempSwf.path)
    FileUtils.cp(tempSwf,File.join(outputDir,"#{File.basename(inputFile,'.*')}.swf"))
  end
end
