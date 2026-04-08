#!/usr/bin/env ruby
require 'optparse'
require 'pathname'
require 'tempfile'
require 'json'
require 'digest'

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

def normalizeTokens(file)
  File.read(file)
      .gsub(%r{//.*?$}, '') # line comments
      .gsub(%r{/\*.*?\*/}m, '') # block comments
      .gsub(/var\s+\w+[^;]*;/, '') # var declarations
      .scan(/\b[a-zA-Z_]\w*|\d+\b/) # identifiers/literals
end

def clipEventType(file)
  File.read(file)[/onClipEvent\s*\(\s*(\w+)\s*\)/,1]
end

def shortScript?(file)
  File.readlines(file).count { |l| l.strip != '' } <= 6
end

def stringLiterals(file)
  File.read(file).scan(/'(?:\\.|[^'])*'|'(?:\\.|[^'])*'/).to_set
end

def anchors(file)
  File.read(file)
      .scan(/(?:_root|_parent|this)(?:\.[a-zA-Z_]\w*)+/)
      .to_set
end

def blankScript?(file)
  File.read(file)
      .gsub(%r{//.*?$},'') # line comments
      .gsub(%r{/\*.*?\*/}m,'') # block comments
      .strip
      .empty?
end

def jaccard(a,b)
  return 0.0 if a.empty? || b.empty?

  (a & b).size.to_f / (a | b).size
end

def similarity(a,b)
  blankA = blankScript?(a)
  blankB = blankScript?(b)

  # blank handling (directional)
  return 0.0 if blankA && !blankB
  return 0.2 if !blankA && blankB
  return 0.2 if blankA && blankB

  # hard stop on script type mismatch
  ea = clipEventType(a)
  eb = clipEventType(b)
  return 0.0 if ea && eb && ea != eb

  tokensA = normalizeTokens(a).to_set
  tokensB = normalizeTokens(b).to_set
  anchorsA = anchors(a)
  anchorsB = anchors(b)
  stringsA = stringLiterals(a)
  stringsB = stringLiterals(b)

  tokenScore = jaccard(tokensA,tokensB)
  anchorScore = anchorsA.empty? && anchorsB.empty? ? 0.0 : jaccard(anchorsA,anchorsB)
  stringScore = stringsA.empty? && stringsB.empty? ? 0.0 : jaccard(stringsA,stringsB)

  # score
  0.50 * tokenScore + 0.30 * anchorScore + 0.20 * stringScore
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

ffdec = findFFDec

# initial export
unless Dir.exist?(dir)
  abort 'error: deobfuscating swf failed' unless system(RbConfig.ruby,DEOBFUSCATESWF,swf.to_s)
  system(ffdec,'-timeout','9999','-exportTimeout','9999','-export','script',dir.to_s,swf.to_s)
end

# sync
unless options[:skipStructure]
  tempDir = Dir.mktmpdir
  system(ffdec,'-timeout','9999','-exportTimeout','9999','-export','script',tempDir.to_s,swf.to_s)

  currentScripts = collectScripts(File.join(dir,'scripts'))
  tempScripts = collectScripts(File.join(tempDir,'scripts'))
  currentStructure = structureFingerprint(dir)
  tempStructure = structureFingerprint(tempDir)
  structureIdentical = currentStructure == tempStructure
  currentScripts.each do |type,sources|
    targets = tempScripts[type]
    next unless targets && !targets.empty?

    # sort by path ascending
    sortedSources = sources.sort
    sortedTargets = targets.sort

    used = {}

    sortedSources.each do |src|
      if structureIdentical
        # structure hasn't changed, match 1:1
        srcRel = relPath(src,dir)
        dest = sortedTargets.find do |script|
          !used[script] && relPath(script,tempDir) == srcRel
        end
        if dest
          FileUtils.cp(src,dest)
          used[dest] = true
        end
      else
        # structure has changed, match scripts to most similar script
        best = nil
        bestScore = -1.0

        sortedTargets.each do |dest|
          next if used[dest]

          score = similarity(src,dest)
          # puts "comparing #{src.split(File::SEPARATOR)[src.split(File::SEPARATOR).index('scripts') + 1..].join(File::SEPARATOR)} with #{dest.split(File::SEPARATOR)[dest.split(File::SEPARATOR).index('scripts') + 1..].join(File::SEPARATOR)} (#{score})"
          if score > bestScore
            best = dest
            bestScore = score
          end
        end

        next unless best

        # puts "best: #{src} (#{bestScore})"
        minScore = shortScript?(src) || shortScript?(best) ? 0.60 : 0.45
        next unless bestScore >= minScore

        puts "matching #{src.split(File::SEPARATOR)[src.split(File::SEPARATOR).index('scripts') + 1..].join(File::SEPARATOR)} with #{best.split(File::SEPARATOR)[best.split(File::SEPARATOR).index('scripts') + 1..].join(File::SEPARATOR)} (#{bestScore})"
        FileUtils.cp(src,best)
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
