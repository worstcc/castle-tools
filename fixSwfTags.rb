#!/usr/bin/env ruby

require 'nokogiri'
require 'optparse'
require 'tempfile'
require 'tmpdir'

def fixMalformedPixlTags(tags)
  # on each copy/move, JPEXS adds 6 bytes at the start & removes 6 bytes at the end
  # tag can be recovered 2 copies deep, 2+ then image data is lost
  # identify tag header through two pairs of "ffff" that are always the same distance relatively
  i = 0
  tags.reject! do |tag|
    i += 1
    next unless tag['unknownData']

    data = tag['unknownData']
    next unless data.index('4c584950')

    footer = data[-32..]
    next if footer.end_with?('24000000280000003000000003000000')

    if footer.end_with?('24000000280000003000')
      data = data[12..]
      data << '000003000000'
      tag['unknownData'] = data
      next
    elsif footer.end_with?('24000000')
      data = data[24..]
      data << '280000003000000003000000'
      tag['unknownData'] = data
      next
    else
      puts "warning: unrecoverable pixl tag, removing (pixl ##{i})"
      true
    end
  end
end

def setHasEndTags(tags)
  tags.each do |tag|
    tag['hasEndTag'] = true if tag['type'] == 'DefineSpriteTag'
  end
end

def padPixlTags
  swfData = File.binread(SWF)
  swfByteDiff = 0
  found = false
  DOC.xpath('//tags/*').each do |tag|
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
    # byte difference
    byteDifference = paddingLength - bytesToDelete
    unless byteDifference.zero?
      id = [data[0,8]].pack('H*').unpack1('V').to_s
      puts "pixl (id=#{id}): #{byteDifference.positive? ? '+' : ''}#{byteDifference} bytes"
    end
    swfByteDiff += (bytesToDelete * -1) + paddingLength
    paddingHex = 'CD' * paddingLength
    tag['unknownData'] = data[0...40] + paddingHex + data[lxipIndex..]
  end
  return unless found || OPTIONS[:dryrun]

  File.write(SWFXML.path,DOC.to_xml(indent:2,indent_text:'  ').gsub(%r{</item><item},"</item>\n  <item"))
  system(FFDEC,'-xml2swf',SWFXML.path,SWF)
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

def updateTagId(tag,id)
  if tag['shapeId']
    tag['shapeId'] = id
  elsif tag['spriteId']
    tag['spriteId'] = id
  elsif tag['fontID']
    tag['fontID'] = id
  elsif tag['characterID']
    tag['characterID'] = id
  elsif tag['buttonId']
    tag['buttonId'] = id
  elsif tag['type'] == 'ExportAssetsTag'
    tag.at_xpath('tags/item')&.content = id
  elsif tag['type'] == 'DefineFontNameTag' && tag['fontId']
    tag['fontId'] = id
  elsif tag['unknownData']
    newData = [id.to_i].pack('V').unpack1('H*')
    lxipSequence = '4c584950'
    lxipIndex = tag['unknownData'].index(lxipSequence)
    if lxipIndex
      lxipIDIndex = lxipIndex + 160
      tag['unknownData'] = newData + tag['unknownData'][8...lxipIDIndex] + newData + tag['unknownData'][lxipIDIndex + 8..]
    end
  end
end

def getTagDependencies(tag,allTags,idToTag,visited = Set.new)
  # prevent infinite recursion
  return [] if visited.include?(tag)

  visited.add(tag)
  deps = []
  case tag['type']
  when 'PlaceObject2Tag'
    if tag['characterId']
      definingTag = idToTag[tag['characterId']]
      if definingTag
        deps << definingTag
        deps.concat(getTagDependencies(definingTag,allTags,idToTag,visited))
      end
    end
  when 'DefineEditTextTag'
    if tag['fontId']
      definingTag = idToTag[tag['fontId']]
      if definingTag
        deps << definingTag
        deps.concat(getTagDependencies(definingTag,allTags,idToTag,visited))
      end
    end
  when 'DefineShapeTag'
    bitmapID = tag['tempBitmapId']
    if bitmapID.to_i.positive?
      definingTag = idToTag[bitmapID]
      if definingTag
        deps << definingTag
        deps.concat(getTagDependencies(definingTag,allTags,idToTag,visited))
      end
    end
  when 'DefineSpriteTag'
    tag.xpath('subTags/item').each do |subTag|
      next unless subTag['type'] == 'PlaceObject2Tag' && subTag['characterId']

      definingTag = idToTag[subTag['characterId']]
      next unless definingTag

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

def topologicalSort(frame,allTags,idToTag)
  graph = Hash.new { |h,k| h[k] = [] }
  frame.each do |tag|
    graph[tag] = getTagDependencies(tag,allTags,idToTag).select { |dep| frame.include?(dep) }
  end

  depthCache = {}
  depth = lambda do |tag|
    depthCache[tag] ||= begin
      dependencies = graph[tag]
      dependencies.map { |dependency| depth.call(dependency) }.max.to_i + 1
    end
  end

  visited = Set.new
  result = []
  anchorTypes = %w[RemoveObject2Tag ShowFrameTag DoAction ExportAssetsTag]
  segments = []
  current = []
  frame.each do |tag|
    if anchorTypes.include?(tag['type'])
      segments << current unless current.empty?
      segments << [tag]
      current = []
    else
      current << tag
    end
  end
  segments << current unless current.empty?

  segments.each do |segment|
    if segment.length == 1 && anchorTypes.include?(segment[0]['type'])
      result << segment[0]
      next
    end
    segment.sort_by { |tag| - depth.call(tag) }.each do |tag|
      dfs(tag,graph,visited,result,frame)
    end
  end

  # ensure ShowFrameTag is last if present
  showFrame = result.find { |tag| tag['type'] == 'ShowFrameTag' }
  if showFrame
    result.delete(showFrame)
    result << showFrame
  end
  result
end

def dfs(tag,graph,visited,result,frame)
  return if visited.include?(tag)

  visited.add(tag)
  graph[tag].each do |dep|
    dfs(dep,graph,visited,result,frame) if frame.include?(dep)
  end
  result << tag
end

def buildPrimaryTagMap(sortedTags,tagType,idAttribute)
  map = {}
  sortedTags.each do |tag|
    map[tag[idAttribute]] = tag if tag['type'] == tagType && tag[idAttribute]
  end
  map
end

def processSecondaryTags(sortedTags,secondaryType,primaryMap,idAttribute,tagsToRemove)
  byTarget = {}
  seenExportNames = Set.new
  sortedTags.each do |tag|
    next unless tag['type'] == secondaryType

    if secondaryType == 'ExportAssetsTag'
      name = tag.at_xpath('names/item')&.content
      if name && seenExportNames.include?(name)
        tagsToRemove.add(tag)
        next
      end
      seenExportNames.add(name) if name
    end

    targetId = tag[idAttribute] || tag.at_xpath('tags/item')&.text
    if targetId.nil? || !primaryMap.key?(targetId)
      tagsToRemove.add(tag)
      next
    end
    if byTarget.key?(targetId)
      tagsToRemove.add(tag)
    else
      byTarget[targetId] = tag
    end
  end
  byTarget
end

def insertSecondaryTag(sortedTags,primaryTag,secondaryTag)
  return unless primaryTag && secondaryTag

  primaryIndex = sortedTags.index(primaryTag)
  return unless primaryIndex

  secondaryIndex = sortedTags.index(secondaryTag)
  return unless secondaryIndex

  sortedTags.delete_at(secondaryIndex)
  sortedTags.insert(primaryIndex + 1 > secondaryIndex ? primaryIndex : primaryIndex + 1,secondaryTag)
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
  opts.on('-c','--clean','remove unused tags from swf instead of moving them') { options[:clean] = true }
  opts.on('-d','--dry-run','don\'t modify the swf') { options[:dryrun] = true }
end.parse!

abort usage if ARGV.length != 1

options[:id] = 1 unless options[:id]
OPTIONS = options

SWF = File.expand_path(ARGV[0])
abort "error: input '#{File.basename(SWF)} not found" unless File.exist?(SWF) || File.directory?(SWF)
abort "error: input '#{File.basename(SWF)} is not a swf" unless SWF.downcase.end_with?('.swf')

def commandExists?(cmd)
  path = if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
           `where.exe #{cmd}`.split("\n").first
         else
           `which #{cmd}`.strip
         end
  path.empty? ? false : path
end

if RUBY_PLATFORM =~ /mswin|mingw|jruby/
  FFDEC = 'C:\\Program Files (x86)\\FFDec\\ffdec-cli.exe'.freeze
elsif RUBY_PLATFORM =~ /linux/
  FFDEC = commandExists?('ffdec')
end
abort 'error: jpexs is not installed' if FFDEC.nil? || !File.exist?(FFDEC)

SWFXML = Tempfile.new(['','.xml'])
system(FFDEC,'-swf2xml',SWF,SWFXML.path)
DOC = Nokogiri::XML(File.read(SWFXML.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)

tagsNode = DOC.at_xpath('//tags')
tags = tagsNode.xpath('item').to_a

fixMalformedPixlTags(tags)
setHasEndTags(tags)

showFrameIndices = tags.each_index.select { |i| tags[i]['type'] == 'ShowFrameTag' }

idToTag = {}
tags.each do |tag|
  id = getTagID(tag)
  idToTag[id] = tag if id
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

# move tags to the frame of their earliest placement
charIdToEarliestPlacement = {}
tagToFrame = {}
tagToEarliestFrame = {}
spriteExportPlacements = {}
# placeobject placements
frameGroups.each_with_index do |frame,i|
  frame.each do |tag|
    tagToFrame[tag] ||= i
    next unless tag['type'] == 'PlaceObject2Tag' && tag['characterId']

    charIdToEarliestPlacement[tag['characterId']] = [charIdToEarliestPlacement[tag['characterId']],i].compact.min

    definingTag = idToTag[tag['characterId']]
    next unless definingTag

    getTagDependencies(definingTag,tags,idToTag).each do |dep|
      next unless (id = getTagID(dep))

      charIdToEarliestPlacement[id] = [charIdToEarliestPlacement[id],i].compact.min
    end
  end
end
# exportassets placements
exportAssetsNameToId = {}
tags.each do |tag|
  next unless tag['type'] == 'ExportAssetsTag'

  next unless (name = tag.at_xpath('names/item')&.content) && (id = tag.at_xpath('tags/item')&.content)

  exportAssetsNameToId[name] ||= id
end
exportAssetsReferences = exportAssetsNameToId.values.to_set
tags.each do |tag|
  if tag['type'] == 'DefineSpriteTag' && tag['spriteId'] && exportAssetsReferences.include?(tag['spriteId'])
    spriteExportPlacements[tag['spriteId']] = tagToFrame[tag]
    charIdToEarliestPlacement[tag['spriteId']] = [charIdToEarliestPlacement[tag['spriteId']],tagToFrame[tag]].compact.min
  end

  # move tags based on placement
  id = getTagID(tag)
  next unless id

  earliest = spriteExportPlacements[id] || charIdToEarliestPlacement[id]
  next unless earliest

  tagToEarliestFrame[tag] = earliest
  getTagDependencies(tag,tags,idToTag).each do |dep|
    tagToEarliestFrame[dep] = [tagToEarliestFrame[dep],earliest].compact.min
  end
end

# handle unused tags
usedIds = tagToEarliestFrame.keys.filter_map { |tag| getTagID(tag) }.to_set
unusedTags = []
tags.each_with_index do |tag,i|
  next unless (id = getTagID(tag))
  next if usedIds.include?(id)
  next if tag['zlibBitmapData'] && tags[i + 1..].any? { |tag| tag['unknownData'] && usedIds.include?(getTagID(tag)) }

  unusedTags << tag
end
if unusedTags.any?
  if OPTIONS[:clean]
    unusedTags.each { |tag| tags.delete(tag) }
    puts "#{unusedTags.length} unused tag(s) removed"
  else
    targetFrame = showFrameIndices.length - 1
    targetIndex = showFrameIndices.last
    unusedTags.each do |tag|
      tags.delete(tag)
      tags.insert(targetIndex,tag)
      tagToEarliestFrame[tag] = targetFrame
    end
    puts "#{unusedTags.length} unused tag(s) moved to end of timeline"
  end
end

# rebuild frame groups after moving tags
frameGroups = frameGroups.map { [] }
tags.each do |tag|
  targetFrame = tagToEarliestFrame[tag] || tagToFrame[tag]
  frameGroups[targetFrame] << tag
end

# sort tags to mimic flash export layout
sortedTags = []
frameGroups.each do |frame|
  sortedFrame = topologicalSort(frame,tags,idToTag)
  sortedTags.concat(sortedFrame)
end

# process tag pairs (DefineSprite/ExportAssets,DefineFont2/DefineFontName)
# also reject duplicate & invalid secondary tags
spriteIdToTag = buildPrimaryTagMap(sortedTags,'DefineSpriteTag','spriteId')
fontIdToTag = buildPrimaryTagMap(sortedTags,'DefineFont2Tag','fontID')
tagsToRemove = Set.new
exportAssetsByTarget = processSecondaryTags(sortedTags,'ExportAssetsTag',spriteIdToTag,nil,tagsToRemove)
fontNameByTarget = processSecondaryTags(sortedTags,'DefineFontNameTag',fontIdToTag,'fontId',tagsToRemove)
sortedTags.reject! { |tag| tagsToRemove.include?(tag) }
exportAssetsByTarget.each do |id,tag|
  insertSecondaryTag(sortedTags,spriteIdToTag[id],tag)
end
fontNameByTarget.each do |id,tag|
  insertSecondaryTag(sortedTags,fontIdToTag[id],tag)
end

# renumber IDs to be consecutive
# collect all tags with IDs
idTags = sortedTags.select { |tag| tag['shapeId'] || tag['spriteId'] || tag['fontID'] || tag['characterID'] || tag['buttonId'] || tag ['unknownData'] }
# create mapping of old IDS to new consecutive IDs
idMapping = {}
idTags.each_with_index do |tag,index|
  oldID = getTagID(tag)
  newID = (index + OPTIONS[:id])
  abort 'error: highest tag ID is greater than maximum (65535)' if newID > 65535
  newID = newID.to_s
  idMapping[oldID] = newID
  updateTagId(tag,newID)
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
  next unless tag['type'] == 'DefineButton2Tag'

  tag.xpath('characters/item').each do |subTag|
    if subTag['type'] == 'BUTTONRECORD' && subTag['characterId']
      oldID = subTag['characterId']
      subTag['characterId'] = idMapping[oldID] if idMapping[oldID]
    end
  end
end

exportAssetsByTarget.each do |id,tag|
  spriteTag = spriteIdToTag[id]
  next unless spriteTag

  updateTagId(tag,idMapping[id])
end

fontNameByTarget.each do |id,tag|
  updateTagId(tag,idMapping[id])
end

# remove temp variables
sortedTags.each do |tag|
  tag.remove_attribute('tempBitmapId')
end

# replace original tags with sorted tags
tagsNode.children = Nokogiri::XML::NodeSet.new(DOC)
sortedTags.each do |tag|
  tagsNode.add_child(tag)
end

FileUtils.cp(SWF,File.join(File.dirname(SWF),"#{File.basename(SWF)}.bak")) unless OPTIONS[:nobackup]

unless OPTIONS[:dryrun]
  File.write(SWFXML,DOC.to_xml(indent:2,indent_text:'  ').gsub(%r{</item><item},"</item>\n  <item"))
  system(FFDEC,'-xml2swf',SWFXML.path,SWF)
end

padPixlTags
