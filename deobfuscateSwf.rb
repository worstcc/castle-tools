#!/usr/bin/env ruby
require 'tmpdir'
require 'pathname'
require 'nokogiri'
def findFFDec
  ffdecPath = nil
  if RUBY_PLATFORM =~ /mswin|mingw|jruby/
    # windows
    ffdecPath = "C:\\Program Files (x86)\\FFDec\\ffdec-cli.exe"
  elsif RUBY_PLATFORM =~ /linux/
    # linux
    ffdecPath = "/usr/bin/ffdec"
    unless File.exist?(ffdecPath)
      ffdecPath = `which ffdec`.strip
    end
  end
  
  if ffdecPath.nil? || !File.exist?(ffdecPath)
    puts "error: JPEXS not found"
    exit 0
  else
    return ffdecPath
  end
end

if ARGV.length < 1
  puts "usage: deobsfucateSWF.rb $SWFFILE"
  exit 1
end

swf = Pathname.new(ARGV[0])
unless swf.file?
  puts "error: file not found: ${swf}"
  exit 1
end
unless swf.extname == ".swf"
  puts "error: input file is not a SWF file"
  exit 1
end

ffdec = findFFDec

xml = Pathname.new(Dir.tmpdir) + "#{swf.basename('.swf')}.xml"
system(ffdec, "-swf2xml", swf.to_s, xml.to_s)

doc = Nokogiri::XML(File.read(xml))
elems = doc.xpath('//*[@actionBytes]')

if elems.empty?
  puts "error: SWF file contains no ActionScript"
  File.delete(xml) if File.exist?(xml)
  exit 0
end

ssInstructions = 0
unknown70s = 0
byteValues = %w[02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12]
ssPatternTemplate = /a[01234](?:#{byteValues.join('|')})00/
  unknown70Pattern = /70129d02/

elems.each do |elem|
  original = elem['actionBytes']
  contents = original.dup

  byteValues.each do |bv|
    pattern = /a[01234]#{bv}00/
    matches = contents.scan(pattern).length
    if matches > 0
      contents.gsub!(pattern,"96#{bv}00")
      ssInstructions += matches
    end
  end

  matches = contents.scan(unknown70Pattern).length
  if matches > 0
    contents.gsub!(unknown70Pattern,'70709d02')
    unknown70s += matches
  end

  elem['actionBytes'] = contents if contents != original
end

if ssInstructions.zero? && unknown70s.zero?
  puts "no obsfucation found"
  File.delete(xml) if File.exist?(xml)
  exit 1
end

File.write(xml,doc.to_xml(indent:0))
system(ffdec,"-xml2swf",xml.to_s,swf.to_s)
File.delete(xml) if File.exist?(xml)

puts "fixed #{ssInstructions} SS instructions"
puts "fixed #{unknown70s} unknown 70s"
