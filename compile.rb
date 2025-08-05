#!/usr/bin/env ruby

require 'fileutils'
require 'optparse'
require 'pathname'

def movePak(file,dir)
  filename = File.basename(file)
  if filename.include?("level")
    dest = File.join(dir,"levels",filename)
  elsif filename.include?("bsp")
    dest = File.join(dir,"bsps",filename)
  else
    dest = File.join(dir,"game",filename)
  end
  FileUtils.rm(dest) if File.exist?(dest)
  FileUtils.mv(file,dest)
  puts filename
end

options = {}
OptionParser.new do |opts|
  opts.banner = "usage: compile.rb [options] $INDIR $GAMEDIR"
  opts.on("--brec", "encrypt SWFs to BREC format (XBLA/PS3)") do
    options[:brec] = true
  end
  opts.on("--skipSWF", "skip encrypting SWFs and only move existing PAK files") do
    options[:skipSWF] = true
  end
end.parse!

if ARGV.length != 2
  puts "usage: ccCompile.rb [options] $INDIR $GAMEDIR"
  exit 1
end

indir = File.expand_path(ARGV[0])
gamedir = File.expand_path(ARGV[1])

unless File.directory?(gamedir)
  raise "gamedir is not a valid directory"
end

if File.file?(indir)
  unless indir.downcase.end_with?('.swf')
    raise "input file must be a SWF file"
  end
  workingDir = File.dirname(indir)
  swfFiles = [File.basename(indir)]
elsif File.directory?(indir)
  workingDir = indir
  swfFiles = Dir.glob(File.join(workingDir,"*.swf")).sort_by { |f| File.size(f) }
else
  raise "indir is not a valid directory"
end

crypt = Pathname.new(__FILE__).dirname.join("crypt.rb")
unless crypt.file?
  raise "crypt.rb missing from script directory"
end

Dir.chdir(workingDir)

# move already existing PAK files
Dir.glob("*.pak").each do |file|
  movePak(file,gamedir)
end

# get SWF files, sorted from least size to most size
unless options[:skipSWF]
  swfFiles.each do |file|
    if options[:brec]
      system("ruby", crypt.to_s, "--brec", "--encrypt", file, ".")
    else
      system("ruby", crypt.to_s, "--encrypt", file, ".")
    end
    pakFile = File.basename(file, ".swf").downcase + ".pak"
    movePak(pakFile,gamedir)
  end
end
