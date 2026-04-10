#!/usr/bin/env ruby

require 'fileutils'
require 'optparse'
require 'pathname'

def movePak(file,dir)
  fileName = File.basename(file)
  dest = if fileName.include?('level')
           File.join(dir,'levels',fileName)
         elsif fileName.include?('bsp')
           File.join(dir,'bsps',fileName)
         else
           File.join(dir,'game',fileName)
         end
  FileUtils.rm(dest) if File.exist?(dest)
  FileUtils.mv(file,dest)
  puts fileName
end

def processFile(input,inputDir,gameDir,cryptRb,options)
  if options[:brec]
    system(RbConfig.ruby,cryptRb.to_s,'-eb',input,inputDir)
  else
    system(RbConfig.ruby,cryptRb.to_s,'-e',input,inputDir)
  end
  pak = File.join(File.dirname(input),"#{File.basename(input,'.swf').downcase}.pak")
  movePak(pak,gameDir) if File.exist?(pak)
end

usage = "usage: #{File.basename($PROGRAM_NAME)} [options] [input directory] [game directory]"
options = {}
OptionParser.new do |opts|
  opts.banner = usage
  opts.on('-b','--brec', 'encrypt to brec format (xbla/ps3)') { options[:brec] = true }
  opts.on('-s','--skipSwf', 'skip encrypting to only move existing paks') { options[:skipSwf] = true }
end.parse!
abort usage if ARGV.length != 2

input = File.expand_path(ARGV[0])
abort "error: input '#{File.basename(input)}' not found" unless File.exist?(input) || File.directory?(input)
gameDir = File.expand_path(ARGV[1])
abort "error: game directory '#{File.basename(gameDir)}' not found" unless File.directory?(gameDir)
cryptRb = File.join(__dir__,'crypt.rb')
abort 'error: crypt.rb missing in script directory' unless File.exist?(cryptRb)

# check for game directories
requiredDirs = %w[game levels]
missingDirs = requiredDirs.reject do |dir|
  File.directory?(File.join(gameDir,dir))
end
abort "#{File.basename(gameDir)} is not a castle data directory" unless missingDirs.empty?

# move already present pak files
if File.directory?(input)
  children = Dir.glob(File.join(input,'*.pak')).reject { |file| File.directory?(file) }
  children.each do |file|
    movePak(file,gameDir)
  end
end

unless options[:skipSwf]
  if File.directory?(input)
    children = Dir.glob(File.join(input,'*.swf')).reject { |file| File.directory?(file) }
    abort 'error: no swf files found in input directory' if children.empty?
    children.each do |file|
      processFile(file,input,gameDir,cryptRb,options)
    end
  else
    abort 'error: input file is not a swf' unless input.downcase.end_with?('.swf')
    processFile(input,File.dirname(input),gameDir,cryptRb,options)
  end
end
