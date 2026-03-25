#!/usr/bin/env ruby

require 'optparse'
options = {}

OptionParser.new do |opts|
  opts.banner = "usage: #{File.basename($PROGRAM_NAME)} [pdag]"
  opts.on('-a','--array','print in AS2 array format') { options[:array] = true }
end.parse!

abort "usage: #{File.basename($PROGRAM_NAME)} [pdag]" if ARGV.empty?

pdag = File.expand_path(ARGV[0])
abort "error: file '#{pdag}' does not exist" unless File.exist?(pdag)
abort "error: '#{pdag}' is not a .pdag file" unless pdag.downcase.end_with?('.pdag')

File.open(pdag,'rb') do |f|
  # get header
  header = f.read(4)
  abort 'error: pdag header not found' unless %w[PDAG GADP].include?(header)
  brec = header == 'PDAG'

  puts '===bspstart===' unless options[:array]
  # get line array length
  f.seek(0x10)
  data = f.read(4)
  aBSPLength = if brec
                 datakunpack1('N')
               else
                 data.unpack1('V')
               end
  numLines = aBSPLength / 8

  # get lines
  puts '==lines==' if numLines.positive? && !options[:array]
  bspArray = [] if options[:array]
  f.seek(0x14)
  numLines.times do |i|
    data = f.read(32)
    values = if brec
               data.unpack('g8')
             else
               data.unpack('e8')
             end

    if options[:array]
      bspArray << values
    else
      values[6] = values[6] / 8 unless values[6].negative?
      values[7] = values[7] / 8 unless values[7].negative?
      puts "##{i}=[#{values[0].to_i},#{format('%.15g',values[1])},#{format('%.15g',values[2])},#{format('%.15g',values[3])},#{format('%.15g',values[4])},#{values[5].to_i},#{values[6].to_i},#{values[7].to_i}]"
    end
  end

  puts "bsp = new Array(#{bspArray.join(',')});" if options[:array]

  # get waypoints
  numWaypoints = 0
  waypointArray = [] if options[:array]
  loop do
    data = f.read(12)
    values = if brec
               data.unpack('g3')
             else
               data.unpack('e3')
             end
    break if values[0].zero? && values[1].zero? && values[2].zero?

    puts '==waypoints==' if numWaypoints.zero? && !options[:array]

    if options[:array]
      waypointArray << values
    else
      puts "##{numWaypoints}=[#{format('%.15g',values[0])},#{format('%.15g',values[1])},#{values[2].to_i}]"
      numWaypoints += 1
    end
  end
  if options[:array]
    puts "waypoints = new Array(#{waypointArray.join(',')});"
  else
    puts '===bspend==='
  end
end
