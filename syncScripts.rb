#!/usr/bin/env ruby
require 'optparse'
require 'pathname'
require 'tempfile'
require 'json'
require 'digest'

def readMetadata(dir)
  metaFile = File.join(dir,'metadata.json')
  return nil unless File.exist?(metaFile)

  JSON.parse(File.read(metaFile))
end

def writeMetadata(dir,swfFilename,swfHash,scriptHash)
  metaFile = File.join(dir,'metadata.json')
  File.write(metaFile,JSON.pretty_generate({
                                             swfFilename: swfFilename,
                                             swfHash: swfHash,
                                             scriptHash: scriptHash
                                           }))
end

def hashScripts(dir)
  dir = File.join(dir,'scripts') unless File.directory?(dir)
  return nil unless Dir.exist?(dir)

  files = Dir.glob("#{dir}/**/*.as").sort
  Digest::SHA256.hexdigest(files.map { |file| File.read(file) }.join)
end

def typeKey(path,root)
  rel = Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
  parts = rel.split(File::SEPARATOR)

  keyParts = []

  if parts.first.start_with?('frame_')
    # main timeline
    keyParts << 'main'
    keyParts << parts[1..-2].map { |p| p.gsub(/\d+/,'') } # ignore frame numbers
    keyParts << File.basename(path)
  elsif parts.first.start_with?('DefineSprite_')
    # sprite timeline
    keyParts << 'sprite'
    keyParts << parts.map { |p| p.gsub(/\d+/,'') }[0..-2] # strip IDs in path
    keyParts << File.basename(path)
  end
  keyParts.flatten.join('/')
end

def jaccard(a,b)
  return 0.0 if a.empty? || b.empty?

  (a & b).size.to_f / (a | b).size
end

def multiSetJaccard(a,b)
  return 0.0 if a.empty? || b.empty?

  fa = a.tally
  fb = b.tally

  keys = fa.keys | fb.keys

  inter = keys.sum { |k| [fa[k].to_i,fb[k].to_i].min }
  union = keys.sum { |k| [fa[k].to_i,fb[k].to_i].max }

  inter.to_f / union
end

def tokenBigrams(tokens)
  tokens.each_cons(2).map { |a,b| "#{a}_#{b}" }
end

def preProcessScript(file)
  content = File.read(file)
  noComments = content.gsub(%r{//.*?$}, '')
                      .gsub(%r{/\*.*?\*/}m, '')

  normalized = noComments
               .gsub(/\b0x[0-9A-Fa-f]+\b/) { |hex| hex.to_i(16).to_s } # hex to decimal
               .gsub(/\bfor\s*\(/,'loop(') # for loops
               .gsub(/\bwhile\s*\(/,'loop(') # while loops
               .gsub(/\bltemp\d+\b/,'tmp') # local/temp variable names
               .gsub(/\b_loc\d+\b/,'tmp')
               .gsub(/var\s+\w+\s*=\s*([^;]+);/,'\1;') # var declarations
               .gsub(/var\s+\w+[^;]*;/, '')

  { raw: content, clean: noComments, tokens: normalized.scan(/\b[a-zA-Z_]\w*|\d+\b/) }
end

def functionSignaturesFrom(clean)
  clean.scan(/function\s+([a-zA-Z_]\w*)\s*\(([^)]*)\)/)
       .map { |name,params| "#{name}(#{params.gsub(/\s+/,'')})" }
       .to_set
end

def stringLiteralsFrom(raw)
  raw.scan(/'(?:\\.|[^'])*'|'(?:\\.|[^'])*'/).to_set
end

def anchorsFrom(raw)
  raw.scan(/(?:_root|_parent|this)(?:\.[a-zA-Z_]\w*)+/).to_set
end

def clipEventTypeFrom(raw)
  raw[/onClipEvent\s*\(\s*(\w+)\s*\)/,1]
end

def structuralTokens(tokens)
  tokens.map do |token|
    if token =~ /^\d+$/
      'num'
    elsif %w[true false].include?(token)
      'bool'
    else
      token
    end
  end
end

def structuralScore(a,b)
  scoreA = structuralTokens(a)
  scoreB = structuralTokens(b)
  jaccard(scoreA.to_set,scoreB.to_set)
end

def similarity(pA,pB)
  # abort on script type mismatch
  clipEventTypeA = clipEventTypeFrom(pA[:raw])
  clipEventTypeB = clipEventTypeFrom(pB[:raw])
  return 0.0 if clipEventTypeA && clipEventTypeB && clipEventTypeA != clipEventTypeB

  # blank handling (directional)
  blankA = pA[:clean].strip.empty?
  blankB = pB[:clean].strip.empty?
  return 0.0 if blankA && !blankB
  return 0.2 if !blankA && blankB
  return 0.2 if blankA && blankB

  tokensA = pA[:tokens]
  tokensB = pB[:tokens]
  tokenScore = multiSetJaccard(tokensA,tokensB)

  bigramsA = tokenBigrams(tokensA).to_set
  bigramsB = tokenBigrams(tokensB).to_set
  bigramScore = jaccard(bigramsA,bigramsB)

  signaturesA = functionSignaturesFrom(pA[:clean])
  signaturesB = functionSignaturesFrom(pB[:clean])
  signatureScore = jaccard(signaturesA,signaturesB)

  anchorsA = anchorsFrom(pA[:raw])
  anchorsB = anchorsFrom(pB[:raw])
  anchorScore = anchorsA.empty? && anchorsB.empty? ? 0.0 : jaccard(anchorsA,anchorsB)

  stringsA = stringLiteralsFrom(pA[:raw])
  stringsB = stringLiteralsFrom(pB[:raw])
  stringScore = stringsA.empty? && stringsB.empty? ? 0.0 : jaccard(stringsA,stringsB)

  0.35 * tokenScore + 0.25 * bigramScore + 0.15 * signatureScore + 0.1 * anchorScore + 0.1 * stringScore
end

def structureFingerprint(scripts)
  Dir.glob("#{scripts}/**/*.as")
     .map { |f| Pathname.new(f).relative_path_from(Pathname.new(scripts)).to_s }
     .sort
     .join('\n')
end

def relPath(path, root)
  Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
end

def collectScripts(root)
  scripts = Hash.new { |h,k| h[k] = [] }
  Dir.glob("#{root}/**/*.as") do |f|
    scripts[typeKey(f,root)] << f
  end
  scripts
end

def sameFile?(a,b)
  Digest::SHA256.file(a).hexdigest == Digest::SHA256.file(b).hexdigest
end

usage = "usage: #{File.basename($PROGRAM_NAME)} [options] [swf] [scripts directory]"
options = {}
OptionParser.new do |opts|
  opts.banner = usage
  opts.on('-s','--skipStructure','don\'t sync script structure (useful for huge scripts like main.swf)') { options[:skipStructure] = true }
  opts.on('-f','--forceSync','force syncing if swf is different/scripts are unchanged (use when swf is renamed)') { options[:forceSync] = true }
end.parse!
abort usage if ARGV.length != 2

DEOBFUSCATESWF = File.join(__dir__,'deobfuscateSwf.rb')
abort 'error: deobfuscateSwf.rb not found in source directory' unless File.exist?(DEOBFUSCATESWF)

swf = File.expand_path(ARGV[0])
abort "error: input '#{File.basename(swf)}' not found" unless File.exist?(swf)
dir = File.expand_path(ARGV[1])

# check if directory is a ffdec script export directory (avoid wiping directories)
if Dir.exist?(dir)
  dirEntries = Dir.glob('*',base: dir).to_set
  exportFiles = Set.new(['scripts','metadata.json'])
  abort 'error: directory is not a valid script export directory (contains more than \'scripts\' and \'metadata.json\')' unless dirEntries.subset?(exportFiles)
end

swfFilename = File.basename(swf)
swfHash = Digest::SHA256.file(swf).hexdigest

unless options[:forceSync]
  currentMetadata = readMetadata(dir)
  if currentMetadata
    abort "error: swf file mismatch (expected '#{currentMetadata['swfFilename']}')" unless currentMetadata['swfFilename'] == swfFilename
    scriptHash = hashScripts(dir)
    if currentMetadata['swfHash'] == swfHash && currentMetadata['scriptHash'] == scriptHash
      warn 'swf & scripts are unchanged, skipping sync'
      exit 0
    end
  end
end

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

# initial export
unless Dir.exist?(dir)
  abort 'error: deobfuscating swf failed' unless system(RbConfig.ruby,DEOBFUSCATESWF,swf.to_s)
  system(ffdec,'-timeout','9999','-exportTimeout','9999','-export','script',dir.to_s,swf.to_s,out: File::NULL,err: File::NULL)
end

# sync
unless options[:skipStructure]
  tempDir = Dir.mktmpdir
  system(ffdec,'-timeout','9999','-exportTimeout','9999','-export','script',tempDir.to_s,swf.to_s,out: File::NULL,err: File::NULL)

  currentScripts = collectScripts(File.join(dir,'scripts'))
  tempScripts = collectScripts(File.join(tempDir,'scripts'))
  currentStructure = structureFingerprint(dir)
  tempStructure = structureFingerprint(tempDir)
  structureIdentical = currentStructure == tempStructure
  if structureIdentical
    currentScripts.each do |type,sources|
      targets = tempScripts[type]
      next unless targets && !targets.empty?

      sortedSources = sources.sort
      sortedTargets = targets.sort

      # build lookup map
      targetMap = {}
      sortedTargets.each do |target|
        targetMap[relPath(target,tempDir)] = target
      end

      used = {}
      sortedSources.each do |source|
        sourceRelative = relPath(source,dir)
        destination = targetMap[sourceRelative]
        next if destination.nil? || used[destination]

        FileUtils.cp(source,destination)
        used[destination] = true
      end
    end
  else
    currentData = {}
    tempData = {}

    currentScripts.values.flatten.each do |file|
      currentData[file] = preProcessScript(file)
    end
    tempScripts.values.flatten.each do |file|
      tempData[file] = preProcessScript(file)
    end

    currentScripts.each do |type,sources|
      targets = tempScripts[type]
      next unless targets && !targets.empty?

      sortedSources = sources.sort
      sortedTargets = targets.sort

      used = {}

      sortedSources.each do |source|
        best = nil
        bestScore = -1.0

        lengthA = currentData[source][:tokens].length

        # prune candidates by size ratio
        candidates = sortedTargets.select do |destination|
          next false if used[destination]

          lengthB = tempData[destination][:tokens].length
          next false if lengthA.zero? || lengthB.zero?

          ratio = lengthA > lengthB ? lengthA.to_f / lengthB : lengthB.to_f / lengthA
          ratio < 3.0
        end

        candidates.each do |destination|
          score = similarity(currentData[source],tempData[destination])

          if score > bestScore
            best = destination
            bestScore = score
          end
        end

        next unless best

        next unless bestScore >= 0.5

        sourceRelative = relPath(source,dir)
        destinationRelative = relPath(best,tempDir)
        puts "#{sourceRelative} -> #{destinationRelative} (#{bestScore})" unless sourceRelative == destinationRelative

        FileUtils.cp(source,best)
        used[best] = true
      end
    end
  end
  FileUtils.rm_rf(dir)
  FileUtils.mv(tempDir,dir)
end

abort 'error: scripts failed to import due to syntax error(s)' unless system(ffdec,'-importScript',swf.to_s,swf.to_s,File.join(dir,'scripts'))

newSwfHash = Digest::SHA256.file(swf).hexdigest
scriptHash = hashScripts(dir)
writeMetadata(dir,swfFilename,newSwfHash,scriptHash)
