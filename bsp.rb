#!/usr/bin/env ruby
require 'optparse'
require 'tempfile'
require 'nokogiri'
require 'open3'

options = {}
OptionParser.new do |opts|
  opts.banner = "usage: #{File.basename($PROGRAM_NAME)} [options] [input swf/txt file] [outdir]"
  opts.on('-b','--brec','use brec format (xbla/ps3)') { options[:brec] = true }
  opts.on('-nNAME','--name NAME',String,'name of pak file') { |name| options[:name] = name }
  opts.on('-u','--unbalanced',"don't balance bsp") { options[:unbalanced] = true }
  opts.on('-a','--auto','automatically close bsp viewer') { options[:auto] = true }
  opts.on('-v','--verbose','show bsp creation progress') { options[:verbose] = true }
  opts.on('--blank','create a blank bsp (useful for level development)') { options[:blank] = true }
end.parse!

# get parameters, scripts, programs
if options[:blank]
  outDir = ARGV[0]
  abort "usage: #{File.basename($PROGRAM_NAME)} [options] [input swf/txt file] [outdir]" if ARGV.length != 1
else
  abort "usage: #{File.basename($PROGRAM_NAME)} [options] [input swf/txt file] [outdir]" if ARGV.length != 2
  inputFile = File.expand_path(ARGV[0])
  outDir = File.expand_path(ARGV[1])
  abort "error: file '#{File.basename(inputFile)}' does not exist" unless File.exist?(inputFile)
  isSwf = inputFile.downcase.end_with?('.swf')
  isTxt = inputFile.downcase.end_with?('.txt')
  abort "error: '#{File.basename(inputFile)}' is not a swf or txt file" unless isTxt || isSwf
  bspSwf = File.join(__dir__,'swf','bsp.swf')
  abort 'error: bsp/bsp.swf missing in script directory' unless File.exist?(bspSwf)

  ruffle = nil
  if RUBY_PLATFORM =~ /mswin|mingw|jruby/
    ruffle = 'C:\\Program Files\\ruffle\\bin\\ruffle.exe'
  elsif RUBY_PLATFORM =~ /linux/
    ruffle = `which ruffle`.strip
  end
  abort 'error: ruffle is not installed on the system/not in PATH (download: https://ruffle.rs/downloads)' if ruffle.nil? || !File.exist?(ruffle)
  abort "error: directory '#{File.basename(outDir)}' does not exist" unless File.directory?(outDir)
end
cryptRb = File.join(__dir__,'crypt.rb')
abort 'error: crypt.rb not found in script directory' unless File.exist?(cryptRb)

# get bsp name
if options[:name]
  name = options[:name]
else
  print 'enter bsp name: '
  name = $stdin.gets.chomp
end
abort 'invalid name' unless !name.empty? && name.match?(/^[a-zA-Z0-9]+$/)
name = name.downcase

# create bsp

if options[:blank]
  bspData = <<~LINES.split("\n")
    ===bspstart===
    ==lines==
    #0=[0,0,0,0,0,1,-1,-1]
    ===bspend===
  LINES
elsif isTxt
  # manual bsp import
  bspData = File.read(inputFile).split("\n")
else
  # get bsp data from bsp.swf
  parameters = ['--scale','show-all','--no-gui','--filesystem-access-mode','allow',"-PinputLevel=#{inputFile}"]
  parameters << '-Pauto=true' if options[:auto]
  parameters << '-Pverbose=true' if options[:verbose]
  parameters << '-PbalancedBSP=false' if options[:unbalanced]
  bspData = []
  inBspBlock = false
  IO.popen([ruffle,*parameters,bspSwf.to_s],'r') do |io|
    io.each_line do |line|
      # clean line ansi
      line = line.gsub(/\e\[[\d;]*m/,'')

      next unless line.include?('avm_trace: ')

      line = line[line.index('avm_trace: ') + 11..]

      inBspBlock = true if line.include?('===bspstart===')

      if inBspBlock
        bspData << line
        break if line.include?('===bspend===')
      end

      puts line unless inBspBlock
    end
  end
  abort 'error: bsp data not found in ruffle output (closed too early?)' if bspData == []
  # puts bspData
end

# retrieve bsp data
lineData = []
waypointData = []
mode = nil
bspData.each do |line|
  line = line.strip
  break if line.include?('===bspend===')
  next if line.include?('===bspstart===')

  case line
  when '==lines=='
    mode = :lines
  when '==waypoints=='
    mode = :waypoints
  when /^\#\d+=\[.+\]$/
    content = line.match(/\[(.+)\]/)[1]
    values = content.split(',').map(&:to_f)
    if mode == :lines
      values[6] = values[6] * 8 unless values[6].negative?
      values[7] = values[7] * 8 unless values[7].negative?
      lineData.concat(values[0..7])
    elsif mode == :waypoints
      waypointData.concat(values[0..2])
    end
  end
end

# construct pdag file
# header
pdagData = Array.new(0x14,0)
if options[:brec]
  pdagData[0,4] = 'PDAG'.bytes
  pdagData[0x10,4] = [lineData.size].pack('N').bytes
else
  pdagData[0,4] = 'GADP'.bytes
  pdagData[0x10,4] = [lineData.size].pack('V').bytes
end
pdagData = pdagData.pack('C*')
lineData.each do |value|
  floatValue = options[:brec] ? [value].pack('g') : [value].pack('e')
  pdagData += floatValue
end
waypointData.each do |value|
  floatValue = options[:brec] ? [value].pack('g') : [value].pack('e')
  pdagData += floatValue
end
# add extra zero bytes to prevent waypoint functions reading garbage data
pdagData += "\x00" * 2352
# extra bytes for nrec
pdagData += "\x10\x00\x00\x00" unless options[:brec]

# write
pdag = File.join(Dir.tmpdir,"#{name}.pdag")
File.write(pdag,pdagData,mode:'wb')
system(RbConfig.ruby,cryptRb,'--encrypt',pdag,outDir)
FileUtils.rm(pdag)
