#!/usr/bin/env ruby

abort "usage: #{File.basename($PROGRAM_NAME)} [pdag]" if ARGV.empty? || ARGV[0] == '--help' || ARGV[0] == '-h'

pdag = ARGV[0]
abort "error: file '#{pdag}' does not exist" unless File.exist?(pdag)
abort "error: '#{pdag}' is not a .pdag file" unless pdag.downcase.end_with?('.pdag')

File.open(pdag,'rb') do |f|
  # get header
  header = f.read(4)
  abort 'error: pdag header not found' unless %w[PDAG GADP].include?(header)
  brec = header == 'PDAG'

  puts '===bspstart==='
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
  puts '==lines==' if numLines.positive?
  f.seek(0x14)
  numLines.times do |i|
    data = f.read(32)
    values = if brec
               data.unpack('g8')
             else
               data.unpack('e8')
             end

    values[6] = values[6] / 8 unless values[6].negative?
    values[7] = values[7] / 8 unless values[7].negative?
    puts "##{i}=[#{values[0].to_i},#{format('%.15g',values[1])},#{format('%.15g',values[2])},#{format('%.15g',values[3])},#{format('%.15g',values[4])},#{values[5].to_i},#{values[6].to_i},#{values[7].to_i}]"
  end

  # get waypoints
  numWaypoints = 0
  loop do
    data = f.read(12)
    values = if brec
               data.unpack('g4')
             else
               data.unpack('e4')
             end
    break if values[0].zero? && values[1].zero? && values[2].zero?

    puts '==waypoints==' if numWaypoints.zero?

    puts "##{numWaypoints}=[#{format('%.15g',values[0])},#{format('%.15g',values[1])},#{values[2].to_i}]"
    numWaypoints += 1
  end
  puts '===bspend==='
end
