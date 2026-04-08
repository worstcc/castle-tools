#!/usr/bin/env ruby

require 'tempfile'
require 'nokogiri'
require 'pathname'

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

abort "usage: #{File.basename($PROGRAM_NAME)} [input swf]" if ARGV.length != 1

swf = File.expand_path(ARGV[0])
abort "error: #{File.basename(swf)} not found" unless File.exist?(swf)
abort "error: #{File.basename(swf)} is not a swf" unless File.extname(swf).downcase.include?('swf')

ffdec = findFFDec

xml = Tempfile.new(['','.xml'])
system(ffdec,'-swf2xml',swf,xml.path)
doc = Nokogiri::XML(File.read(xml.path),nil,nil,Nokogiri::XML::ParseOptions::HUGE)

scriptNodes = doc.xpath('//*[@actionBytes]')

abort 'error: swf contains no scripts' if scriptNodes.empty?

ssInstructions = 0
unknown70s = 0
byteValues = %w[02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12]
unknown70Pattern = /70129d02/

scriptNodes.each do |node|
  original = node['actionBytes']
  contents = original.dup

  byteValues.each do |byteValue|
    pattern = /a[01234]#{byteValue}00/
    matches = contents.scan(pattern).length
    if matches.positive?
      contents.gsub!(pattern,"96#{byteValue}00")
      ssInstructions += matches
    end
  end

  matches = contents.scan(unknown70Pattern).length
  if matches.positive?
    contents.gsub!(unknown70Pattern,'70709d02')
    unknown70s += matches
  end

  node['actionBytes'] = contents if contents != original
end

if ssInstructions.zero? && unknown70s.zero?
  puts 'no obsfucation found'
  exit 0
end

File.write(xml,doc.to_xml(indent:0))
system(ffdec,'-xml2swf',xml.path,swf)

puts "fixed #{ssInstructions} SS instructions"
puts "fixed #{unknown70s} unknown 70s"
