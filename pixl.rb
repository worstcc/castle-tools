#!/usr/bin/env ruby

require 'digest'
require 'mini_magick'
require 'nokogiri'
require 'optparse'
require 'parallel'
require 'pathname'
require 'tempfile'
require 'tmpdir'

# TODO: export hybrid ps3 player/fx pixl tags
# TODO: xbla/ps3 import (big endian "PIXL")

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "usage: #{File.basename($PROGRAM_NAME)} [image|swf|video] [output directory]"
  opts.on('-p','--platform PLATFORM',String,'game platform to target (steam (default),xbla,ps3)') do |format|
    abort 'error: invalid format' unless format.match?(/steam|xbla|ps3/)
    options[:format] = format
  end
  opts.on('-s','--size SIZE',Integer,'import: image size to use when scaling down (default: 512, video: source height; max: 512)') { |size| options[:size] = size }
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
  opts.on('-l','--loop','video: loop sprite') { options[:loop] = true }
  opts.on('-a','--audio','video: create xma audio from input video') { options[:audio] = true }
end
parser.parse!
explicitSize = options.key?(:size)
options[:format] = 'steam' unless options[:format]
options[:size] = 512 unless options[:size]

abort parser.help if ARGV.length != 2

inputFile = File.expand_path(ARGV[0])
abort "error: #{File.basename(inputFile)} not found" unless File.exist?(inputFile)
abort "error: #{File.basename(inputFile)} is not an accepted image, swf or video" unless ['.bmp','.jpg','.jpeg','.jxl','.png','.webp','.swf','.gif','.mp4','.mkv','.webm'].include?(File.extname(inputFile).downcase)

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
abort 'error: ffmpeg is not installed' unless commandExists?('ffmpeg')

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

def pixlDataFromImageFile(path,options)
  image = MiniMagick::Image.open(path)

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
      warn 'image size is higher than 512, clamping'
      options[:size] = 512
    end
    minDimension = [image.width,image.height].min
    targetSize = minDimension >= options[:size] ? options[:size] : (minDimension & ~1)
    unless image.width == targetSize && image.height == targetSize
      image.resize "#{targetSize}x#{targetSize}!"
      image.write image.path
    end
  end

  imageToPixl(image,placedWidth,placedHeight)
end

def fitVideoSize(frameCount)
  size = Math.sqrt(10 * 1048576 / (4.0 * frameCount)).floor
  size = 2 if size < 2
  size
end

def extractVideoFrames(inputFile,tempDir,size)
  FileUtils.rm_f(Dir.glob(File.join(tempDir,'frame_*.png')))
  args = ['ffmpeg','-i',inputFile,'-r','30','-f','image2','-c:v','png']
  args += ['-vf',"scale=#{size}:#{size}"] if size
  args << File.join(tempDir,'frame_%04d.png')
  abort 'error: ffmpeg failed' unless system(*args,out: File::NULL,err: File::NULL)
  frames = Dir.glob(File.join(tempDir,'frame_*.png')).sort
  abort 'error: no frames extracted' if frames.empty?
  frames
end

def dedupeVideoFrames(frameImages)
  totalFrames = frameImages.length
  frameHashes = Parallel.map(frameImages,in_threads: Etc.nprocessors) do |image|
    Digest::SHA256.file(image).hexdigest
  end
  hashToUniqueId = {}
  frameRemap = Array.new(totalFrames + 1) # timeline frameNum (1-based) -> uniqueId (1-based)
  uniqueFrameImages = []
  frameHashes.each_with_index do |hash,idx|
    unless hashToUniqueId.key?(hash)
      hashToUniqueId[hash] = uniqueFrameImages.length + 1
      uniqueFrameImages << frameImages[idx]
    end
    frameRemap[idx + 1] = hashToUniqueId[hash]
  end
  uniqueFrames = uniqueFrameImages.length
  puts "merged #{totalFrames - uniqueFrames} identical frame(s): #{totalFrames} -> #{uniqueFrames} unique" if uniqueFrames < totalFrames
  [frameRemap,uniqueFrameImages]
end

if ['.gif','.mp4','.mkv','.webm'].include?(File.extname(inputFile).downcase)
  # import video frames into sprite in copy of pixl swf
  # swf contains a blank sprite
  # extract frames from video
  # for each frame:
  # create pixl nodes
  # change ids of nodes to be based on frame number
  # insert frame in sprite that places the frame only when the image changed,
  # otherwise emit a blank frame that holds the previous image; frames after first use placeFlagMove
  # add "stop();" action in last frame

  abort 'error: ffmpeg is not installed' unless commandExists?('ffmpeg')

  # probe source dimensions and duration for sizing and placement
  origWidth = nil
  origHeight = nil
  duration = nil
  ffprobe = commandExists?('ffprobe')
  if ffprobe
    probe = IO.popen([ffprobe,'-v','error','-select_streams','v:0','-show_entries','stream=width,height','-show_entries','format=duration','-of','csv=p=0',inputFile]).read.lines.map(&:strip)
    if probe.length >= 2
      w,h = probe[0].split(',').map(&:to_i)
      origWidth,origHeight = w,h if w.positive? && h.positive?
      d = probe[1].to_f
      duration = d if d.positive?
    end
  end

  unless explicitSize
    options[:size] = origHeight if origHeight
  end

  if options[:size] > 512 && !options[:force]
    warn 'image size is higher than 512, limiting'
    options[:size] = 512
  end

  # placed dimensions come from the source video, not the extracted frames
  options[:placedDimensions] = "#{origWidth}x#{origHeight}" if origWidth && origHeight && !options[:placedDimensions]

  CONVERTAUDIORB = File.join(__dir__,'convertAudio.rb')
  abort 'error: convertAudio.rb not found in script directory' unless File.exist?(CONVERTAUDIORB)

  tempDir = Dir.mktmpdir
  at_exit { FileUtils.rm_rf(tempDir) }
  tempAudioFile = nil

  # extract frames at the resolution actually used in pixl tags (1:1 squares) to
  # keep temp files small. the final tag size depends on the unique frame count,
  # so first extract at a conservative size based on the total frame estimate,
  # then re-extract larger only if deduplication shows the tags can be bigger.
  initialSize = options[:size]
  extractSize = nil
  if !explicitSize && !options[:noScale] && origWidth && origHeight
    target = initialSize
    totalEst = duration ? (duration * 30).ceil : nil
    if totalEst && totalEst.positive?
      target = [target,fitVideoSize(totalEst)].min
    end
    if [origWidth,origHeight].min > target
      extractSize = target
      options[:size] = target
    end
  end

  puts 'extracting frames'
  frameImages = extractVideoFrames(inputFile,tempDir,extractSize)
  totalFrames = frameImages.length
  frameRemap,uniqueFrameImages = dedupeVideoFrames(frameImages)
  uniqueFrames = uniqueFrameImages.length

  # estimate file size in megabytes and lower size to fit under 10 MB
  estimatedSize = (initialSize * initialSize * 4 * uniqueFrames).to_f / 1048576
  if estimatedSize > 10
    if explicitSize
      warn 'size too large, video may not load in-game'
    else
      options[:size] = fitVideoSize(uniqueFrames)
      puts "size too large, lowering: #{initialSize} -> #{options[:size]}"
    end
  else
    options[:size] = initialSize
  end

  if !extractSize.nil? && options[:size] > extractSize
    # deduplication found duplicates, so tags can be bigger than the stage-1
    # frames; re-extract at the final size and re-deduplicate at full accuracy
    puts 're-extracting frames at higher resolution'
    frameImages = extractVideoFrames(inputFile,tempDir,options[:size])
    totalFrames = frameImages.length
    frameRemap,uniqueFrameImages = dedupeVideoFrames(frameImages)
    uniqueFrames = uniqueFrameImages.length

    estimatedSize = (options[:size] * options[:size] * 4 * uniqueFrames).to_f / 1048576
    if estimatedSize > 10
      oldSize = options[:size]
      options[:size] = fitVideoSize(uniqueFrames)
      puts "size too large, lowering: #{oldSize} -> #{options[:size]}"
    end
  end

  SWFXMLTEMPLATE = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8"?><!--
      WARNING: The structure of this XML is not final.
      In later versions of FFDec it can be changed.
      Make sure you use compatible reader/writer based on _xmlExportMajor/_xmlExportMinor keys.
      --><swf _xmlExportMajor="2" _xmlExportMinor="1" _generator="JPEXS Free Flash Decompiler v.26.0.0 nightly build 3497" type="SWF" charset="UTF-8" compression="NONE" encrypted="false" frameCount="2" frameRate="30.0" gfx="false" hasEndTag="true" version="6">
      <displayRect type="RECT" Xmax="16960" Xmin="0" Ymax="9600" Ymin="0" nbits="16"/>
      <tags>
        <item type="SetBackgroundColorTag" forceWriteAsLong="false">
          <backgroundColor type="RGB" blue="255" green="153" red="102"/>
        </item>
        <item type="DefineSpriteTag" forceWriteAsLong="false" frameCount="1" hasEndTag="true" spriteId="65535">
          <subTags>
          </subTags>
        </item>
        <item type="ShowFrameTag" forceWriteAsLong="false"/>
      </tags>
    </swf>
  XML

  tempOutputXml = Tempfile.create(['','.xml'])
  at_exit do
    tempOutputXml.close
    File.unlink(tempOutputXml)
  end
  outputDoc = Nokogiri::XML(SWFXMLTEMPLATE,nil,nil,Nokogiri::XML::ParseOptions::HUGE)
  outputSprite = outputDoc.at_xpath("//item[@type='DefineSpriteTag'][@spriteId='65535']")
  outputSpriteSubTags = outputSprite.at_xpath('.//subTags')
  outputSwf = File.join(outputDir,"#{File.basename(inputFile,File.extname(inputFile))}.swf")

  pixlOutputs = Array.new(uniqueFrames + 1)
  map = Parallel.map((1..uniqueFrames).to_a,in_threads: Etc.nprocessors) do |uniqueId|
    print "\rprocessing frame #{uniqueId}/#{uniqueFrames}"
    pixlOptions = options.dup
    [uniqueId,pixlDataFromImageFile(uniqueFrameImages[uniqueId - 1],pixlOptions)]
  end
  map.each { |uniqueId,output| pixlOutputs[uniqueId] = output }

  # process frames
  # first frame uses the full 5 tags for jpexs display
  # subsequent frames only use the pixl tag
  # a timeline position only places when its image differs from the previous
  # position; otherwise it emits a blank frame (ShowFrame only) that holds the
  # previous image, so (1,1,1,2,2,2,3) becomes (1,x,x,2,x,x,3)
  emittedUniqueIds = {}
  prevUniqueId = nil
  (1..totalFrames).each do |frameNum|
    uniqueId = frameRemap[frameNum]
    unless emittedUniqueIds.key?(uniqueId)
      emittedUniqueIds[uniqueId] = true
      pixlNode = Nokogiri::XML::Node.new('item',outputDoc)
      pixlNode['type'] = 'UnknownTag'
      pixlNode['tagId'] = 148
      pixlNode['forceWriteAsLong'] = true
      unknownData = pixlOutputs[uniqueId].dup
      startIndex = unknownData.index('4c584950')
      if startIndex
        endIndex = unknownData.index('cdcdcdcd',startIndex)
        if endIndex
          endPos = endIndex + 8
          newIdHex = [uniqueId].pack('v').unpack1('H*')
          unknownData[0...4] = newIdHex
          unknownData[endPos...endPos + 4] = newIdHex
        end
      end
      pixlNode['unknownData'] = unknownData
      outputSprite.add_previous_sibling(pixlNode)
    end
    # add frame to video sprite, placing only on image change
    if frameNum == 1 || uniqueId != prevUniqueId
      placeObjectNode = Nokogiri::XML::Node.new('item',outputDoc)
      placeObjectNode['type'] = 'PlaceObject2Tag'
      placeObjectNode['placeFlagHasClipActions'] = false
      placeObjectNode['placeFlagHasClipDepth'] = false
      placeObjectNode['placeFlagHasRatio'] = false
      placeObjectNode['placeFlagHasColorTransform'] = false
      placeObjectNode['placeFlagHasMatrix'] = false
      placeObjectNode['placeFlagHasCharacter'] = true
      placeObjectNode['placeFlagMove'] = frameNum > 1
      placeObjectNode['depth'] = 1
      placeObjectNode['characterId'] = uniqueId
      placeObjectNode['forceWriteAsLong'] = false
      outputSpriteSubTags.add_child(placeObjectNode)
    end
    prevUniqueId = uniqueId
    showFrameNode = Nokogiri::XML::Node.new('item',outputDoc)
    showFrameNode['type'] = 'ShowFrameTag'
    outputSpriteSubTags.add_child(showFrameNode)
  end

  outputSprite['spriteId'] = uniqueFrames + 1
  outputSprite['frameCount'] = totalFrames
  outputSpriteShowFrameNodes = outputSprite.xpath(".//item[@type='ShowFrameTag']")
  # "stop();" do action
  unless options[:loop]
    outputSpriteDoActionNode = Nokogiri::XML::Node.new('item',outputDoc)
    outputSpriteDoActionNode['type'] = 'DoActionTag'
    outputSpriteDoActionNode['actionBytes'] = '0700'
    outputSpriteShowFrameNodes[-2].add_next_sibling(outputSpriteDoActionNode)
  end

  File.write(tempOutputXml,outputDoc.to_xml(indent:2,indent_text:'  ').gsub(%r{</item><item},"</item>\n  <item"))
  abort 'error: ffdec failed' unless system(ffdec,'-xml2swf',tempOutputXml.path,outputSwf)

  if options[:audio]
    puts
    puts 'processing audio'
    tempAudioFile = File.join(tempDir,"#{File.basename(inputFile,File.extname(inputFile))}.opus")
    abort 'error: ffmpeg failed' unless system('ffmpeg','-i',inputFile,'-vn','-c:a','libopus','-y',tempAudioFile,out: File::NULL,err: File::NULL)
    abort 'error: convertAudio.rb failed' unless system(RbConfig.ruby,CONVERTAUDIORB,tempAudioFile,tempDir,out: File::NULL,err: File::NULL)
  end
  FileUtils.cp(File.join(tempDir,"#{File.basename(tempAudioFile,File.extname(tempAudioFile))}.xma"),outputDir) if options[:audio]
elsif File.extname(inputFile).downcase == '.swf'
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

  unknownData = pixlDataFromImageFile(inputFile,options)

  # import image

  PIXLXML = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8"?><!--
      WARNING: The structure of this XML is not final.
      In later versions of FFDec it can be changed.
      Make sure you use compatible reader/writer based on _xmlExportMajor/_xmlExportMinor keys.
      --><swf _xmlExportMajor="4" _xmlExportMinor="2" _generator="JPEXS Free Flash Decompiler v.26.4.0 nightly build 3599" type="SWF" charset="UTF-8" compression="NONE" encrypted="false" frameCount="1" frameRate="30.0" gfx="false" hasEndTag="true" version="6">
      <displayRect type="RECT" Xmax="16960" Xmin="0" Ymax="9600" Ymin="0" nbits="16"/>
      <tags>
        <item type="SetBackgroundColorTag" forceWriteAsLong="false">
          <backgroundColor type="RGB" blue="255" green="255" red="255"/>
        </item>
        <item type="UnknownTag" tagId="148" forceWriteAsLong="true" unknownData=""/>
        <item type="ShowFrameTag" forceWriteAsLong="false"/>
      </tags>
    </swf>
  XML
  doc = Nokogiri::XML(PIXLXML,nil,nil,Nokogiri::XML::ParseOptions::HUGE)
  doc.at_xpath("//tags//item[@type='UnknownTag']")['unknownData'] = unknownData
  tempXml = Tempfile.create(['','.xml'])
  at_exit do
    tempXml.close
    File.unlink(tempXml)
  end
  File.write(tempXml,doc.to_xml(indent:2,indent_text:'  ').gsub(%r{</item><item},"</item>\n  <item"))
  abort 'error: ffdec failed' unless system(ffdec,'-xml2swf',tempXml.path,File.join(outputDir,"#{File.basename(inputFile,'.*')}.swf"))
end
