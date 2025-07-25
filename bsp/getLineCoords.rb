#!/usr/bin/env ruby

def calculateMatrix(x1,y1,x2,y2)
    dx = x2 - x1
    dy = y2 - y1
    if dx == 0
      if dy > 0
        degrees = 90
      elsif dy < 0
        degrees = 270
      else
        degrees = 0
      end
    else
      angle = Math.atan(dy / dx) * 180 / Math::PI
      degrees = dx > 0 ? angle : angle + 180
      degrees = (degrees + 360) % 360
    end
    width = Math.sqrt(dx**2 + dy**2)
    scaleX = width / 64
    radians = degrees * Math::PI / 180
    cos = Math.cos(radians)
    sin = Math.sin(radians)
    a = scaleX * cos
    b = scaleX * sin
    c = -sin
    d = cos
    e = x1 * 20
    f = y1 * 20
    format("MATRIX[%.3f,%.3f,%.3f,%.3f,%.3f,%.3f]",a,b,c,d,e,f)
end

if ARGV.length != 4
  puts "usage: getLineCoords.rb $X1 $Y1 $X2 $Y2"
  exit 1
end

begin
  x1 = Float(ARGV[0])
  y1 = Float(ARGV[1])
  x2 = Float(ARGV[2])
  y2 = Float(ARGV[3])
rescue ArgumentError
  puts "error: all arguments must be valid float values"
  exit 1
end
puts calculateMatrix(x1,y1,x2,y2)
