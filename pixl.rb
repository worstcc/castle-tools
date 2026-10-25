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
parser = OptionParser.new do |opts|
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
end
parser.parse!
options[:format] = 'steam' unless options[:format]
options[:size] = 512 unless options[:size]

abort parser.help if ARGV.length != 2

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

    # get rectangle bounds
    xMin = [data[8,8]].pack('H*').unpack1('l<') / 10.0
    xMax = [data[16,8]].pack('H*').unpack1('l<') / 10.0
    yMin = [data[24,8]].pack('H*').unpack1('l<') / 10.0
    yMax = [data[32,8]].pack('H*').unpack1('l<') / 10.0
    placedWidth = (xMax - xMin) / 2.0
    placedHeight = (yMax - yMin) / 2.0
    xOffset = (xMax + xMin) / 4.0
    yOffset = (yMax + yMin) / 4.0
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
    data << [1].pack('v').unpack1('H*')
    data << '00' * 2
    # rectangle bounds (xMin,xMax,yMin,yMax)
    data << [(-placedWidth * 10).round].pack('l<').unpack1('H*')
    data << [(placedWidth * 10).round].pack('l<').unpack1('H*')
    data << [(-placedHeight * 10).round].pack('l<').unpack1('H*')
    data << [(placedHeight * 10).round].pack('l<').unpack1('H*')
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
    data << [1].pack('v').unpack1('H*')
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

  abort 'error: ffdec failed' unless system(ffdec,'-swf2xml',tempSwf.path,tempXml.path)
  doc = Nokogiri::XML(File.read(tempXml.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)
  doc.at_xpath("//tags//item[@type='UnknownTag']")['unknownData'] = imageToPixl(image,placedWidth,placedHeight)
  File.write(tempXml,doc.to_xml(indent:2,indent_text:'  ').gsub(%r{</item><item},"</item>\n  <item"))
  if options[:xml]
    FileUtils.cp(tempXml,File.join(outputDir,"#{File.basename(inputFile,'.*')}.xml"))
  else
    abort 'error: ffdec failed' unless system(ffdec,'-xml2swf',tempXml.path,tempSwf.path)
    FileUtils.cp(tempSwf,File.join(outputDir,"#{File.basename(inputFile,'.*')}.swf"))
  end
end
