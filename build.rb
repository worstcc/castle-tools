#!/usr/bin/env ruby

require 'English'
require 'digest'
require 'find'
require 'json'
require 'optparse'
require 'parallel'
require 'securerandom'
require 'seven_zip_ruby'
require 'tmpdir'

# TODO: 'sync only' mode

usage = "usage: #{File.basename($PROGRAM_NAME)} [options] [source directory] [output directory]"
options = {}
OptionParser.new do |opts|
  opts.banner = usage
  opts.separator ''
  opts.separator 'generates an installable mod data directory from a \'source\' directory.'
  opts.separator ''
  opts.separator 'expected directories in the source directory:'
  opts.separator '- audio (music & sound files in common audio formats)'
  opts.separator '- fonts (castle font files)'
  opts.separator '- src (swf script directories generated with syncScripts.rb)'
  opts.separator '- swf (game/levels swf files)'
  opts.separator ''
  opts.separator 'it also runs substitutions in script files:'
  opts.separator '- "$MODINFO" -> "<mod name> <date/version>", where \'<mod name>\' is specifed by \'--modName\' option, and <date/version> is the current system time in dev mode or version specified in \'version.txt\' file in source directory in public mode. The line that contains "$MODINFO" needs to be preceded by comment: \'// BUILD: MOD INFO\'.'
  opts.separator '- "$RANDOM(VALUE)" -> random value, inclusive'
  opts.separator '- in public mode, remove code surrounded by \'// BUILD: BEGIN DEV ONLY\' & \'// BUILD: END DEV ONLY\' comments.'
  opts.separator ''
  opts.on('-a','--archive','compress archive using 7zip') { options[:archive] = true }
  opts.on('-l','--protect','when using --archive, password protect the archive') { options[:protect] = true }
  opts.on('-nNAME','--modName NAME',String,'mod name to use for archive/$MODINFO') { |name| options[:modName] = name }
  opts.on('-vNAME','--modVersion NAME',String,'version to use for archive/$MODINFO') { |name| options[:modVersion] = name }
  opts.on('-p','--public','omit code in dev blocks, use version number over date for mod info') { options[:public] = true }
  opts.on('-f','--force','make build if data directory/archive already exists') { options[:force] = true }
end.parse!
OPTIONS = options
abort usage if ARGV.length != 2

SRCDIR = File.expand_path(ARGV[0])
abort "error: directory '#{SRCDIR}' not found" unless Dir.exist?(SRCDIR)
OUTDIR = File.expand_path(ARGV[1])
abort "error: directory '#{OUTDIR}' not found" unless Dir.exist?(OUTDIR)
CRYPTRB = File.join(__dir__,'crypt.rb')
abort 'error: crypt.rb not found in source directory' unless File.exist?(CRYPTRB)
BSPRB = File.join(__dir__,'bsp.rb')
abort 'error: bsp.rb not found in source directory' unless File.exist?(BSPRB)
SYNCSCRIPTSRB = File.join(__dir__,'syncScripts.rb')
abort 'error: syncScripts.rb not found in source directory' unless File.exist?(SYNCSCRIPTSRB)
CONVERTAUDIORB = File.join(__dir__,'convertAudio.rb')
abort 'error: convertAudio.rb not found in source directory' unless File.exist?(CONVERTAUDIORB)
XWMAENCODE = File.join(__dir__,'xWMAEncode.exe')
abort 'error: xWMAEncode.exe not found in script directory' unless File.exist?(XWMAENCODE)

def commandExists?(cmd)
  if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
    `where.exe #{cmd}`.split("\n").first
  else
    `which #{cmd}`.strip
  end
end

ffdec = nil
if RUBY_PLATFORM =~ /mswin|mingw|jruby/
  ffdec = 'C:\\Program Files (x86)\\FFDec\\ffdec-cli.exe'
elsif RUBY_PLATFORM =~ /linux/
  ffdec = commandExists?('ffdec')
end
abort 'error: jpexs is not installed' if ffdec.nil? || !File.exist?(ffdec)

abort 'error: ruffle is not installed' unless commandExists?('ruffle')
abort 'error: ffmpeg is not installed' unless commandExists?('ffmpeg')
abort 'error: wine is not installed' if RbConfig::CONFIG['host_os'] =~ /linux/ && (!commandExists?('wine') || !commandExists?('winepath'))

AUDIODIR = File.join(SRCDIR,'audio')
FONTSDIR = File.join(SRCDIR,'fonts')
SWFSRCDIR = File.join(SRCDIR,'src')
SWFDIR = File.join(SRCDIR,'swf')

# abort if no source directories found or only src directory exists
abort 'error: source directory does not contain the expected directories' if (!Dir.exist?(AUDIODIR) || !Dir.exist?(FONTSDIR) || !Dir.exist?(SWFSRCDIR) || !Dir.exist?(SWFDIR)) || (Dir.exist?(SWFSRCDIR) && !Dir.exist?(AUDIODIR) && !Dir.exist?(FONTSDIR) && !Dir.exist?(SWFDIR))

# get data directory
if OPTIONS[:archive]
  DATAPARENTDIR = Dir.mktmpdir
  DATADIR = File.join(DATAPARENTDIR,'data')
  at_exit { FileUtils.rm_rf(DATAPARENTDIR) }
else
  DATADIR = File.join(OUTDIR,'data')
  if OPTIONS[:force]
    FileUtils.rm_rf(DATADIR)
  elsif Dir.exist?(DATADIR)
    abort '\'data\' already exists in output directory'
  end
end
Dir.mkdir(DATADIR)

buildFile = File.join(SRCDIR,'build.json')
buildJson = nil
buildJson = JSON.parse(File.read(buildFile)) if File.exist?(buildFile)

if Dir.exist?(SWFDIR)
  SWFFILES = Dir.glob(File.join(SWFDIR,'*.swf'))

  # seed random based on hash of swfs combined, so the same build produces the same random values
  SWFFILESHASH = Digest::SHA256.hexdigest(SWFFILES.sort.map { |file| File.read(file) }.join)
  srand(SWFFILESHASH.to_i)
end

# get mod info
if OPTIONS[:modName]
  MODINFONAME = OPTIONS[:modName]
elsif buildJson && buildJson['name']
  MODINFONAME = buildJson['name'].to_s.strip
else
  warn 'mod name not specified, using \'Mod\' as the name'
  MODINFONAME = 'Mod'.freeze
end
if OPTIONS[:public]
  if OPTIONS[:version]
    MODINFOVERSION = OPTIONS[:modVersion]
  elsif buildJson && buildJson['version']
    MODINFOVERSION = buildJson['version'].to_s.strip
  else
    MODINFOVERSION = '1.0'.freeze
    warn 'version not specified, using \'1.0\' as the version'
  end
else
  MODINFOVERSION = "dev #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} (#{SWFFILESHASH[0...8]})".freeze
end

puts "building \"#{MODINFONAME} #{MODINFOVERSION}\""

# get vanilla bsp/dev only whitelists
VANILLABSPS = (buildJson && buildJson['vanillaBsps']) || []
DEVONLYFILES = (buildJson && buildJson['devOnlyFiles']) || []

# get archive file name
if OPTIONS[:archive]
  archiveName = MODINFOVERSION.dup
  archiveName.gsub!(/\bdev\b/,'Dev')
  archiveName.gsub!(/\s+/,'')
  archiveName.gsub!('.','_')
  archiveName.gsub!(/(\d{4})-(\d{2})-(\d{2})/,'\1\2\3')
  archiveName.gsub!(/(\d{2}):(\d{2}):(\d{2})/,'\1\2\3')
  ARCHIVEFILE = File.join(OUTDIR,"#{MODINFONAME}#{archiveName}.7z")
  if OPTIONS[:force]
    FileUtils.rm(ARCHIVEFILE) if File.exist?(ARCHIVEFILE)
  elsif File.exist?(ARCHIVEFILE)
    abort "build already made (#{File.basename(ARCHIVEFILE)})"
  end
end

def processFonts!
  return unless Dir.exist?(FONTSDIR)

  puts 'copying fonts...'

  fontsDir = File.join(DATADIR,'fonts')
  FileUtils.mkdir(fontsDir)

  Dir.glob(File.join(FONTSDIR,'*')).each do |file|
    next unless File.file?(file)
    next if OPTIONS[:public] && DEVONLYFILES.include?(File.basename(file))

    FileUtils.cp(file,fontsDir)
  end
end

def findMetadataFromScript(startDir)
  current = startDir
  while current != SRCDIR && current != '/'
    return File.join(current,'metadata.json') if File.exist?(File.join(current,'metadata.json'))
    break if Dir.exist?(File.join(current,'scripts'))

    current = File.dirname(current)
  end
  nil
end

def truncatePath(path)
  path.sub("#{SRCDIR}/",'')
end

def processBsps!
  return unless Dir.exist?(SWFSRCDIR)
  return unless Dir.exist?(SWFDIR)

  puts 'creating bsps...'

  bspList = []
  bspDir = File.join(DATADIR,'bsps')

  FileUtils.mkdir(bspDir)

  # collect bsp names
  Find.find(SWFSRCDIR).each do |file|
    next unless File.file?(file)

    File.readlines(file).each do |line|
      next unless line =~ /f_BSPLoadLevel\("\$?([\w-]+)"\)/

      bspName = Regexp.last_match(1)
      next if bspName.start_with?('bsp') && !VANILLABSPS.include?(bspName)
      next if OPTIONS[:public] && DEVONLYFILES.include?(bspName)

      bspList << [bspName,file] unless bspList.any? { |name,_| name == bspName }
    end
  end
  return if bspList.empty?

  # match bsp name to their swf file then create bsp
  Parallel.each(bspList,in_threads: Etc.nprocessors / 2) do |(bspName,srcFile)|
    metadataFile = findMetadataFromScript(File.dirname(srcFile))
    unless metadataFile
      warn "(bsp) scripts directory not found for #{truncatePath(srcFile)}, skipping"
      next
    end

    metadata = JSON.parse(File.read(metadataFile))
    swfName = metadata['swfFilename']
    swfFile = File.join(SWFDIR,swfName)
    unless File.exist?(swfFile)
      warn "(bsp) swf file not found (#{truncatePath(swfFile)}), skipping"
      next
    end

    system(RbConfig.ruby,BSPRB,'-a','-n',bspName,swfFile,bspDir,out: File::NULL,err: File::NULL)
  end
end

def findMetadataForSwf(swfName)
  # cache metadata to avoid repeating parsing
  @metadataCache ||= begin
    cache = {}
    Dir.glob(File.join(SWFSRCDIR,'**','metadata.json')).each do |file|
      metadata = JSON.parse(File.read(file))
      cache[metadata['swfFilename']] = file
    end
    cache
  end
  @metadataCache[swfName]
end

def processSwfs!
  return unless SWFFILES

  gameDir = File.join(DATADIR,'game')
  levelsDir = File.join(DATADIR,'levels')
  FileUtils.mkdir(gameDir)
  FileUtils.mkdir(levelsDir)

  syncingMessage = nil
  modifiedSwfs = {}

  SWFFILES.each do |swfFile|
    swfName = File.basename(swfFile)

    if OPTIONS[:public] && DEVONLYFILES.include?(swfName)
      tempSwf = "#{swfFile}.tmp"
      FileUtils.mv(swfFile,tempSwf)
      at_exit { FileUtils.mv(tempSwf,tempSwf.sub('.tmp','')) }
      next
    end

    # sync scripts
    metadataFile = findMetadataForSwf(swfName)
    next unless metadataFile

    scriptsDir = File.dirname(metadataFile)
    next unless Dir.exist?(scriptsDir)

    if syncingMessage.nil?
      puts 'syncing swf scripts...'
      syncingMessage = true
    end

    puts "syncing #{swfName}"

    # perform script substitutions
    modifiedScripts = {}
    originalMetadata = nil
    devBlocks = 0
    modInfoCount = 0
    randomCount = 0
    Dir.glob(File.join(scriptsDir,'**','*.as')).each do |file|
      original = File.read(file)
      modified = original

      # public mode: remove dev only blocks
      if OPTIONS[:public]
        modified = modified.gsub(%r{// BUILD: BEGIN DEV ONLY.*?// BUILD: END DEV ONLY}m,'')
        devBlocks += 1 if modified != original
      end

      # update '$MODINFO' & '$RANDOM()' in strings
      lines = modified.split("\n")
      lines.each_with_index do |line,i|
        nextLine = lines[i + 1]
        next unless nextLine

        if line.strip.include?('// BUILD: MOD INFO')
          if nextLine =~ /".*\$MODINFO.*"/
            lines[i + 1] = nextLine.gsub('$MODINFO',"#{MODINFONAME} #{MODINFOVERSION}")
            modInfoCount += 1
          end
        elsif line.strip.include?('// BUILD: RANDOM')
          if nextLine =~ /"s*\$RANDOM\((\d+)\)\s*"/
            randomVal = Regexp.last_match(1).to_i
            if randomVal.positive?
              lines[i + 1] = nextLine.gsub(/"s*\$RANDOM\((\d+)\)\s*"/,rand(1..randomVal).to_s)
              randomCount += 1
            else
              warn '(swf) not substituting non-positive random value'
            end
          end
        end
      end

      modified = lines.join("\n") if modInfoCount.positive? || randomCount.positive?

      next unless modified != original

      File.write(file,modified)
      modifiedScripts[file] = original
      originalMetadata = File.read(metadataFile)
      originalSwf = File.read(swfFile)
      modifiedSwfs[swfFile] = originalSwf
    end

    if system(RbConfig.ruby,SYNCSCRIPTSRB,swfFile,scriptsDir,out: File::NULL,err: File::NULL)
      puts "(swf) removed #{devBlocks} dev code block(s) from #{swfName}" if devBlocks.positive?
      puts "(swf) substituted #{modInfoCount} mod info string(s) in #{swfName}" if modInfoCount.positive?
      puts "(swf) substituted #{randomCount} random value(s) in #{swfName}" if randomCount.positive?
    else
      warn "(swf) scripts in #{swfName} failed to import"
    end

    # restore modified scripts
    modifiedScripts.each do |file,original|
      File.write(file,original)
    end
    File.write(metadataFile,originalMetadata) unless originalMetadata.nil?
  end

  # batch encrypt
  puts 'encrypting swfs...'
  tempDir = Dir.mktmpdir
  at_exit { FileUtils.rm_rf(tempDir) }
  system(RbConfig.ruby,CRYPTRB,'-e',SWFDIR,tempDir)
  Dir.glob(File.join(tempDir,'*.pak')).each do |pakFile|
    pakName = File.basename(pakFile)
    outDir = pakName.include?('level') ? levelsDir : gameDir
    FileUtils.mv(pakFile,outDir)
  end

  # restore modified swfs
  modifiedSwfs.each do |swfFile,originalContent|
    File.write(swfFile,originalContent)
  end
end

def processAudio!
  return unless Dir.exist?(AUDIODIR)

  puts 'converting audio...'

  audioFiles = Dir.glob(File.join(AUDIODIR,'*.{mp3,flac,ogg,aac,m4a,wav,opus}'))
  return if audioFiles.empty?

  if OPTIONS[:public]
    audioFiles.each do |file|
      next unless DEVONLYFILES.include?(File.basename(file))

      tempFile = "#{file}.tmp"
      FileUtils.mv(file,tempFile)
      at_exit { FileUtils.mv(tempFile,tempFile.sub('.tmp','')) }
    end
    audioFiles.reject! { |file| DEVONLYFILES.include?(File.basename(file)) }
  end

  musicDir = File.join(DATADIR,'music')
  soundsDir = File.join(DATADIR,'sounds')
  FileUtils.mkdir(musicDir)
  FileUtils.mkdir(soundsDir)

  Parallel.each(audioFiles,in_threads: Etc.nprocessors / 2) do |audioFile|
    filename = File.basename(audioFile)
    if filename =~ /sound/i
      system(RbConfig.ruby,CONVERTAUDIORB,audioFile,soundsDir)
    else
      system(RbConfig.ruby,CONVERTAUDIORB,audioFile,musicDir)
    end
  end
end

def archive!
  return unless OPTIONS[:archive]

  password = nil
  if OPTIONS[:protect]
    password = SecureRandom.base64
    puts "creating archive... (password: #{password})"
  else
    puts 'creating archive...'
  end

  Dir.chdir(DATAPARENTDIR) do
    File.open(ARCHIVEFILE,'wb') do |file|
      SevenZipRuby::Writer.open(file,password: password) do |szr|
        szr.method = 'LZMA2'
        szr.level = 9
        szr.add_directory(File.basename(DATADIR))
      end
    end
  end
end

processFonts!
processBsps!
processSwfs!
processAudio!
archive!

if OPTIONS[:archive]
  puts "done (#{ARCHIVEFILE})"
else
  puts "done (#{DATADIR})"
end
