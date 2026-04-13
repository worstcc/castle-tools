#!/usr/bin/env ruby

require 'nokogiri'
require 'optparse'
require 'tempfile'
require 'tmpdir'

# TODO: add detecting & deleting unused tags
# TODO: fix taking multiple runs to sort tags (caused by tags across frames)

def fixMalformedPixlTag(tag)
  # on each copy/move, JPEXS adds 6 bytes at the start & removes 6 bytes at the end
  # tag can be recovered 2 copies deep, 2+ then image data is lost
  # identify tag header through two pairs of "ffff" that are always the same distance relatively
  ret = 0
  data = tag['unknownData']
  ffOffset = 0
  prev = nil
  while (index = data.index('ffff',ffOffset))
    if prev && (index - prev == 16)
      if prev > 36 # 2+ copies deep
        id = [data[prev - 12,prev - 8]].pack('H*').unpack1('V').to_s
        puts "warning: unrecoverable pixl tag, removing (id=#{id})"
        ret = 2
      elsif prev > 12
        # header (remove)
        data = data[prev - 12..]
        # footer (add)
        case prev
        when 24
          data << '000003000000'
        when 36
          data << '280000003000000003000000'
        end
        tag['unknownData'] = data
        ret = 1
      end
      break
    end
    prev = index
    ffOffset = index + 4
  end
  ret
end

def getTagID(tag)
  return tag['shapeId'] if tag['shapeId']
  return tag['spriteId'] if tag['spriteId']
  return tag['fontID'] if tag['fontID']
  return tag['characterID'] if tag['characterID']
  return tag['buttonId'] if tag['buttonId']
  # extract ID from unknown tag
  return [tag['unknownData'][0,8]].pack('H*').unpack1('V').to_s if tag['unknownData']

  nil
end

def getTagDependencies(tag,allTags,idToTag,visited = Set.new)
  # prevent infinite recursion
  return [] if visited.include?(tag)

  # $__benchmark_start ||= Time.now
  # start = Time.now
  visited.add(tag)
  deps = []
  case tag['type']
  when 'PlaceObject2Tag'
    if tag['characterId']
      definingTag = idToTag[tag['characterId']]
      if definingTag
        definingTag['tempHasDependency'] = true
        deps << definingTag
        deps.concat(getTagDependencies(definingTag,allTags,idToTag,visited))
      end
    end
  when 'DefineEditTextTag'
    if tag['fontId']
      definingTag = idToTag[tag['fontId']]
      if definingTag
        definingTag['tempHasDependency'] = true
        deps << definingTag
        deps.concat(getTagDependencies(definingTag,allTags,idToTag,visited))
      end
    end
  when 'DefineShapeTag'
    bitmapID = tag['tempBitmapId']
    if bitmapID.to_i.positive?
      definingTag = idToTag[bitmapID]
      if definingTag
        definingTag['tempHasDependency'] = true
        deps << definingTag
        deps.concat(getTagDependencies(definingTag,allTags,idToTag,visited))
      end
    end
  when 'DefineSpriteTag'
    tag.xpath('subTags/item').each do |subTag|
      next unless subTag['type'] == 'PlaceObject2Tag' && subTag['characterId']

      definingTag = idToTag[subTag['characterId']]
      next unless definingTag

      definingTag['tempHasDependency'] = true
      deps << definingTag
      deps.concat(getTagDependencies(definingTag,allTags,idToTag,visited))
    end
  when 'RemoveObject2Tag'
    if tag['depth']
      depth = tag['depth']
      placingTag = allTags.find do |tag2|
        tag2['type'] == 'PlaceObject2Tag' && tag2['depth'] == depth
      end
      deps << placingTag if placingTag
    end
  end
  deps.uniq
end

def topologicalSort(frame,allTags,pairs,idToTag)
  # identify secondary tags to exclude from dependency graph
  secondaryTags = pairs.values.to_set
  # build dependency graph for the frame
  graph = Hash.new { |h,k| h[k] = [] }
  frame.each do |tag|
    next if secondaryTags.include?(tag)

    graph[tag] = getTagDependencies(tag,allTags,idToTag).select { |dep| frame.include?(dep) && !secondaryTags.include?(dep) }
  end
  # topological sort
  visited = Set.new
  result = []
  frame.each do |tag|
    next if secondaryTags.include?(tag)

    dfs(tag,graph,visited,result,frame)
  end
  # insert paired secondary tags immediately after their primary tags
  finalResult = []
  result.each do |tag|
    finalResult << tag
    finalResult << pairs[tag] if pairs.key?(tag) && frame.include?(pairs[tag]) && !finalResult.include?(pairs[tag])
  end
  frame.each do |tag|
    finalResult << tag unless finalResult.include?(tag)
  end
  # ensure ShowFrameTag is last if present
  showFrame = finalResult.find { |t| t['type'] == 'ShowFrameTag' }
  if showFrame
    finalResult.delete(showFrame)
    finalResult << showFrame
  end
  finalResult
end

def dfs(tag,graph,visited,result,frame)
  return if visited.include?(tag)

  visited.add(tag)
  graph[tag].each do |dep|
    dfs(dep,graph,visited,result,frame) if frame.include?(dep)
  end
  result << tag
end

usage = "usage: #{File.basename($PROGRAM_NAME)} [options] [swf]"
options = {}
OptionParser.new do |opts|
  opts.banner = usage
  opts.on('-n','--no-backup','don\'t create a backup of swf') { options[:nobackup] = true }
  opts.on('-i','--start-id ID',Integer,'ID to start from when reordering (default: 1)') do |id|
    raise 'invalid ID (allowed range: 1-65535)' if id > 65535 || id < 1

    options[:id] = id
  end
  opts.on('-v','--verbose','print ID mapping & pixl tag diffs') { options[:verbose] = true }
  opts.on('-r','--remove-unused','remove unused ExportAssets tags') { options[:removeunused] = true }
  opts.on('-d','--dry-run','don\'t modify the swf') { options[:dryrun] = true }
end.parse!

abort usage if ARGV.length != 1

options[:id] = 1 unless options[:id]

swf = File.expand_path(ARGV[0])
abort "error: input '#{File.basename(swf)} not found" unless File.exist?(swf) || File.directory?(swf)
abort "error: input '#{File.basename(swf)} is not a swf" unless swf.downcase.end_with?('.swf')

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

# start
swfXml = Tempfile.new(['','.xml'])
system(ffdec,'-swf2xml',swf,swfXml.path)
doc = Nokogiri::XML(File.read(swfXml.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)

tagsNode = doc.at_xpath('//tags')
tags = tagsNode.xpath('item').to_a

# fix malformed pixl tags to get correct IDs
tags.reject! do |tag|
  next unless tag['unknownData']

  ret = fixMalformedPixlTag(tag)
  ret == 2
end

# set hasEndTag to true for all sprites
tags.each do |tag|
  tag['hasEndTag'] = true if tag['type'] == 'DefineSpriteTag'
end

# check if IDs are actually incorrect for savings
correctIDOrder = true
prev = nil
tags.each do |tag|
  id = getTagID(tag)
  next if id.nil?

  id = id.to_i
  if prev.nil?
    if id != options[:id]
      correctIDOrder = false
      break
    end
  elsif id - prev != 1
    correctIDOrder = false
    break
  end
  prev = id
end

if correctIDOrder == false
  showFrameIndices = tags.each_index.select { |i| tags[i]['type'] == 'ShowFrameTag' }

  # identify paired tags (DefineSprite/ExportAssets & DefineFont2/DefineFontName)
  pairs = {}
  idToTag = {}
  tags.each_with_index do |tag,i|
    id = getTagID(tag)
    idToTag[id] = tag if id
    next unless i + 1 < tags.length

    pairs[tag] = tags[i + 1] if id.nil? && tags[i + 1]['type'] == 'ExportAssetsTag' && tags[i + 1].at_xpath('tags/item').text == id || tag['type'] == 'DefineFont2Tag' && tags[i + 1]['type'] == 'DefineFontNameTag'
  end

  # assign tags to frames
  frameGroups = []
  startIndex = 0
  showFrameIndices.each do |endIndex|
    frameGroups << tags[startIndex..endIndex]
    startIndex = endIndex + 1
  end
  frameGroups << tags[startIndex..] if startIndex < tags.length

  # get bitmapId for shape fillstyles ahead of time to avoid very slow searching in getTagDependencies
  tags.each do |tag|
    if tag['type'] == 'DefineShapeTag'
      node = tag.at_xpath('.//fillStyles/fillStyles/item[last()]')
      tag['tempBitmapId'] = node ? node['bitmapId'] : '0'
    end
  end

  loop do # loop: if unused tags are removed, the dependencies need to be obtained again
    # relocate dependencies to the frame of their use
    # map tags to their current frame index
    tagToFrame = {}
    frameGroups.each_with_index do |frame,i|
      frame.each { |tag| tagToFrame[tag] = i }
    end
    # find the earliest frame where each tag is needed
    tagToEarliestFrame = {}
    tags.each do |tag|
      next unless %w[PlaceObject2Tag DefineSpriteTag].include?(tag['type'])

      currentFrame = tagToFrame[tag]
      # get all dependencies recursively
      deps = getTagDependencies(tag,tags,idToTag)
      deps.each do |dep|
        # assign dependency to the earliest frame where it's needed
        tagToEarliestFrame[dep] = [tagToEarliestFrame[dep] || currentFrame,currentFrame].min

        # move paired secondary tag with its primary tag
        tagToEarliestFrame[pairs[dep]] = tagToEarliestFrame[dep] if pairs[dep]
      end
    end
    # rebuild frame groups with relocated tags
    frameGroups = frameGroups.map { [] }
    tags.each do |tag|
      targetFrame = tagToEarliestFrame[tag] || tagToFrame[tag]
      frameGroups[targetFrame] << tag
    end
    found = false
    break unless found
  end

  # sort tags by dependencies
  sortedTags = []
  frameGroups.each do |frame|
    sortedFrame = topologicalSort(frame,tags,pairs,idToTag)
    sortedTags.concat(sortedFrame)
  end

  # renumber IDs to be consecutive
  # collect all tags with IDs
  idTags = tags.select { |tag| tag['shapeId'] || tag['spriteId'] || tag['fontID'] || tag['characterID'] || tag['buttonId'] || tag ['unknownData'] }
  # create mapping of old IDS to new consecutive IDs
  idMapping = {}
  idTags.each_with_index do |tag,index|
    oldID = getTagID(tag)
    newID = (index + options[:id])
    abort 'error: highest tag ID is greater than maximum (65535)' if newID > 65535
    newID = newID.to_s
    idMapping[oldID] = newID
    # update tag ID
    if tag['shapeId']
      tag['shapeId'] = newID
    elsif tag['spriteId']
      tag['spriteId'] = newID
    elsif tag['fontID']
      tag['fontID'] = newID
    elsif tag['characterID']
      tag['characterID'] = newID
    elsif tag['buttonId']
      tag['buttonId'] = newID
    elsif tag['unknownData']
      newData = [newID.to_i].pack('V').unpack1('H*')
      lxipSequence = '4c584950'
      lxipIndex = tag['unknownData'].index(lxipSequence)
      if lxipIndex
        lxipIDIndex = lxipIndex + 160
        tag['unknownData'] = newData + tag['unknownData'][8...lxipIDIndex] + newData + tag['unknownData'][lxipIDIndex + 8..]
      end
    end
  end

  # update characterID
  tags.each do |tag|
    if tag['type'] == 'PlaceObject2Tag' && tag['characterId']
      oldID = tag['characterId']
      tag['characterId'] = idMapping[oldID] if idMapping[oldID]
    end
    if tag['type'] == 'DefineEditTextTag'
      oldID = tag['fontId']
      tag['fontId'] = idMapping[oldID] if idMapping[oldID]
    end
    if tag['type'] == 'DefineShapeTag'
      tag.xpath('shapes/fillStyles/fillStyles/item[@type="FILLSTYLE"]').each do |subTag|
        if subTag['type'] == 'FILLSTYLE' && subTag['bitmapId']
          oldID = subTag['bitmapId']
          subTag['bitmapId'] = idMapping[oldID] if idMapping[oldID]
        end
      end
    end
    if tag['type'] == 'DefineSpriteTag'
      tag.xpath('subTags/item').each do |subTag|
        if subTag['type'] == 'PlaceObject2Tag' && subTag['characterId']
          oldID = subTag['characterId']
          subTag['characterId'] = idMapping[oldID] if idMapping[oldID]
        end
      end
    end
    if tag['type'] == 'DefineButton2Tag'
      tag.xpath('characters/item').each do |subTag|
        if subTag['type'] == 'BUTTONRECORD' && subTag['characterId']
          oldID = subTag['characterId']
          subTag['characterId'] = idMapping[oldID] if idMapping[oldID]
        end
      end
    end
    next unless pairs.key?(tag)

    secondary = pairs[tag]
    if secondary['type'] == 'ExportAssetsTag'
      secondary.xpath('tags/item').each do |item|
        oldID = item.content
        item.content = idMapping[oldID] if idMapping[oldID]
      end
    elsif secondary['type'] == 'DefineFontNameTag' && secondary['fontId']
      oldID = secondary['fontId']
      secondary['fontId'] = idMapping[oldID] if idMapping[oldID]
    end
  end
  puts "ids: #{idMapping}" if options[:verbose]

  # remove temp variables
  sortedTags.each do |tag|
    tag.remove_attribute('tempHasDependency')
    tag.remove_attribute('tempBitmapId')
  end

  # replace original tags with sorted tags
  tagsNode.children = Nokogiri::XML::NodeSet.new(doc)
  sortedTags.each do |tag|
    tagsNode.add_child(tag)
  end
end

FileUtils.cp(swf,File.join(File.dirname(swf),"#{File.basename(swf)}.bak")) unless options[:nobackup]

unless options[:dryrun]
  File.write(swfXml,doc.to_xml(indent:2,indent_text:'  ').gsub(%r{</item><item},"</item>\n  <item"))
  system(ffdec,'-xml2swf',swfXml.path,swf)
end

# fix pixl padding
swfData = File.binread(swf)
swfByteDiff = 0
found = false
doc.xpath('//tags/*').each do |tag|
  next unless tag['unknownData']

  data = tag['unknownData']
  lxipIndex = data.index('4c584950')
  next unless lxipIndex

  # adjust padding
  segment = data[0..lxipIndex + 7]
  binSegment = [segment].pack('H*')
  offset = swfData.index(binSegment) + swfByteDiff
  next unless offset

  lxipOffset = offset + (lxipIndex / 2)
  # 32 bytes instead of 16?
  next unless lxipOffset % 32 != 0

  found = true
  bytesToDelete = (lxipIndex / 2) - 20
  newLXIPOffset = offset + 20
  paddingLength = ((32 - newLXIPOffset % 32) % 32)
  if options[:verbose]
    # byte difference
    id = [data[0,8]].pack('H*').unpack1('V').to_s
    puts "pixl (ID #{id}): #{(d = paddingLength - bytesToDelete) >= 0 ? '+' : ''}#{d} bytes"
  end
  swfByteDiff += (bytesToDelete * -1) + paddingLength
  paddingHex = 'CD' * paddingLength
  tag['unknownData'] = data[0...40] + paddingHex + data[lxipIndex..]
end
if found && options[:dryrun]
  File.write(xml.to_s,doc.to_xml(indent:2,indent_text:'  ').gsub(%r{</item><item},"</item>\n  <item"))
  system(ffdec,'-xml2swf',swfXml.path,swf)
end
