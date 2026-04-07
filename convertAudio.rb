#!/usr/bin/env ruby

require 'optparse'
require 'tempfile'

usage = "usage: #{File.basename($PROGRAM_NAME)} [options] [input file/directory] [output directory]"
options = {}
OptionParser.new do |opts|
  opts.banner = usage
  opts.on('-i','--ima4','convert to ima4 format instead of xma') { options[:ima4] = 'ima4' }
  opts.on('-bBITRATE','--bitrate BITRATE',Integer,'audio bitrate in bps (valid: 32000,64000,96000 [default],192000)') { |bitrate| options[:bitrate] = bitrate }
end.parse!
abort usage if ARGV.length != 2

MODE = options[:ima4] || 'xma'
BITRATE = options[:bitrate] || 96000
bitrates = [32000,64000,96000,192000]
abort "invalid bitrate '#{BITRATE}', valid: (#{bitrates.join(',')})" unless bitrates.include?(BITRATE)

input = File.expand_path(ARGV[0])
abort "error: input '#{File.basename(input)}' not found" unless File.exist?(input) || File.directory?(input)
OUTPUTDIR = File.expand_path(ARGV[1])
abort "error: output '#{File.basename(OUTPUTDIR)}' not found" unless File.directory?(OUTPUTDIR)
XWMAENCODE = File.join(__dir__,'xWMAEncode.exe')
abort 'error: xWMAEncode.exe not found in script directory' unless File.exist?(XWMAENCODE)

def commandExists?(cmd)
  if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
    system('where.exe',cmd,out: File::NULL,err: File::NULL)
  else
    system('which',cmd,out: File::NULL,err: File::NULL)
  end
end

abort 'error: ffmpeg is not installed' unless commandExists?('ffmpeg')
abort 'error: wine is not installed' if RbConfig::CONFIG['host_os'] =~ /linux/ && (!commandExists?('wine') || !commandExists?('winepath'))

def convert(file)
  tempWav = Tempfile.new([File.basename(file,'.*'),'.wav'])
  system('ffmpeg','-y','-nostdin','-i',file,'-ar','44100','-c:a','pcm_s32le',tempWav.path,out: File::NULL,err: File::NULL) || return
  basename = File.basename(file,'.*')
  case MODE
  when 'xma'
    puts "converting #{File.basename(file)} (xma)"
    cmd = if RbConfig::CONFIG['host_os'] =~ /linux/
            ['wine',XWMAENCODE,'-b',BITRATE.to_s,`(winepath -w #{tempWav.path} 2>/dev/null)`.strip,`(winepath -w "#{File.join(OUTPUTDIR,"#{basename}.xma")}" 2>/dev/null)`.strip]
          else
            [XWMAENCODE,'-b',BITRATE.to_s,tempWav.path,File.join(OUTPUTDIR,"#{basename}.xma").to_s]
          end
    system(*cmd,out: File::NULL,err: File::NULL)
  when 'ima4'
    puts "converting #{File.basename(file)} (ima4)"
    sampleRate = [BITRATE / 2,44100].min
    aiff = "#{basename}.aiff"
    FileUtils.mv(aiff,File.join(OUTPUTDIR,"#{basename}.ima4")) if system('ffmpeg','-y','-i',tempWav.path,'-ar',sampleRate.to_s,'-c:a','adpcm_ima_qt',aiff,out: File::NULL,err: File::NULL)
  end
end

formats = %w[mp3 flac ogg aac m4a wav opus]
if File.directory?(input)
  children = formats.flat_map { |extension| Dir.glob(File.join(input,"*\.#{extension}")) }
  abort 'error: no audio files found in input directory' if children.empty?
  children.each do |file|
    convert(file)
  end
else
  abort 'error: input file is not an audio file' unless formats.include?(File.extname(input).downcase.delete_prefix('.'))
  convert(input)
end
