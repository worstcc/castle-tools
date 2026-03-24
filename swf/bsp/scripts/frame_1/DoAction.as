function f_ClassifyLine(partition,line) {
  var v1 = new vector2d();
  var v2 = new vector2d();
  v1.x = partition.x2 - partition.x1;
  v1.y = partition.y2 - partition.y1;
  v1.normalize();
  v2.x = line.x1 - partition.x1;
  v2.y = line.y1 - partition.y1;
  v2.normalize();
  var result1 = v1.cross(v2);
  v2.x = line.x2 - partition.x1;
  v2.y = line.y2 - partition.y1;
  v2.normalize();
  var result2 = v1.cross(v2);
  var ret = 9;
  if(result1 == 0 && result2 == 0) {
    ret = 0;
  } else if(result1 >= 0 && result2 >= 0) {
    ret = 1;
  } else if(result1 <= 0 && result2 <= 0) {
    ret = 2;
  } else if(result1 >= 0 && result2 <= 0) {
    ret = 3;
  } else if(result1 <= 0 && result2 >= 0) {
    ret = 4;
  }
  return ret;
}
function f_SplitLine(apartition,aline,aline2) {
  aline2.x2 = aline.x2;
  aline2.y2 = aline.y2;
  aline2.type = aline.type;
  var t = aline.intersect(apartition);
  var newX = aline.x1 + t * (aline.x2 - aline.x1);
  var newY = aline.y1 + t * (aline.y2 - aline.y1);
  aline.x2 = newX;
  aline.y2 = newY;
  aline2.x1 = newX;
  aline2.y1 = newY;
}
function f_BuildBSPTree(node,list) {
  var frontList = new Array();
  var backList = new Array();
  if(balancedBSP) {
    var partition = f_ChooseBestPartitionLine(list);
  } else {
    var partition = list.pop();
  }
  node.partition.copy(partition);
  node.partition.type = partition.type;
  while(list.length > 0) {
    var line = list.pop();
    var result = f_ClassifyLine(partition,line);
    switch(result) {
      case 1: frontList.push(line); break;
      case 2: backList.push(line); break;
      case 3:
        var line2 = new lineSegment();
        f_SplitLine(partition,line,line2);
        frontList.push(line);
        backList.push(line2);
        break;
      case 4:
        var line2 = new lineSegment();
        f_SplitLine(partition,line,line2);
        backList.push(line);
        frontList.push(line2);
        break;
      case 0:
    }
  }
  if(frontList.length > 0) {
    node.front = new bspTreeNode();
    f_BuildBSPTree(node.front,frontList);
  }
  if(backList.length > 0) {
    node.back = new bspTreeNode();
    f_BuildBSPTree(node.back,backList);
  }
}
function f_ChooseBestPartitionLine(list) {
  if(list.length <= 2) {
    return list.pop();
  }
  if(!list.length) {
    trace("f_ChooseBestPartitionLine");
    return;
  }
  var bestLine;
  var bestIndex = 0;
  var minRelation = 1;
  var leastSplits = 9999;
  var bestRelation = 0;
  while(!bestLine && minRelation >= 0.01) {
    var len = list.length;
    for(var i = 0; i < len; i++) {
      var line1 = list[i];
      var numPositive = 0;
      var numNegative = 0;
      var numSpanning = 0;
      for(var j = 0; j < len; j++) {
        if(i == j) {
          continue;
        }
        var line2 = list[j];
        var result = f_ClassifyLine(line1,line2);
        switch(result) {
          case 1: numPositive++; break;
          case 2: numNegative++; break;
          case 3:
          case 4: numSpanning++; break;
          case 0:
        }
      }
      if(numPositive < numNegative) {
        var relation = numPositive / numNegative;
      } else {
        var relation = numNegative / numPositive;
      }
      if(relation >= minRelation && (numSpanning < leastSplits || numSpanning == leastSplits && relation > bestRelation)) {
        bestLine = line1;
        bestIndex = i;
        leastSplits = numSpanning;
        bestRelation = relation;
      }
    }
    minRelation *= 0.5;
  }
  if(!bestLine) {
    return list.pop();
  }
  list.splice(bestIndex,1);
  return bestLine;
}
function f_InitLevelBSP() {
  loader._x = 0;
  loader._y = 0;
  loader._xscale = 100;
  loader._yscale = 100;
  loader._rotation = 0;
  loader.game._x = 0;
  loader.game._y = 0;
  loader.game._xscale = 100;
  loader.game._yscale = 100;
  loader.game._rotation = 0;
  loader.game.game._x = 0;
  loader.game.game._y = 0;
  loader.game.game._xscale = 100;
  loader.game.game._yscale = 100;
  loader.game.game._rotation = 0;
  waypoints = new Array();
  sortedWaypoints = new Array();
  lineList = new Array();
  bsp = new Array();
  bspWorkingLine = new Object();
  bspIndex = 0;
  bspStructSize = 8;
  f_BuildLineList();
  bspRoot = new bspTreeNode();
  if(lineList.length) {
    f_BuildBSPTree(bspRoot,lineList);
    f_ConvertBSPtoArray(bspRoot);
    f_ConvertWaypointstoArray();
    f_DrawBsp();
  } else {
    f_Popup("error: no lines found",true);
    return false;
  }
  f_PrintBSPData();
  if(auto == "true") {
    fscommand("quit");
  }
  return true;
}
function wpsort(a,b) {
  var ret = 0;
  if(a.x > b.x) {
    ret = 1;
  } else if(b.x > a.x) {
    ret = -1;
  }
  return ret;
}
function f_ConvertWaypointstoArray() {
  waypoints.sort(wpsort);
  var len = waypoints.length;
  for(var i = 0; i < len; i++) {
    var x = waypoints[i].x;
    var y = waypoints[i].y;
    sortedWaypoints.push(x);
    sortedWaypoints.push(y);
    sortedWaypoints.push(0);
  }
}
function f_GetClosestWaypoint(x) {
  var ret = 0;
  var len = sortedWaypoints.length / 3;
  for(var i = 0; i < len; i++) {
    if(sortedWaypoints[i * 3] > x) {
      ret = i - 1;
      if(ret < 0) {
        ret = 0;
      }
      i = len;
    }
  }
  return ret;
}
function f_ConvertBSPtoArray(node) {
  node.saveIndex = bspIndex;
  bsp[bspIndex] = 0;
  bsp[bspIndex + 1] = node.partition.x1;
  bsp[bspIndex + 2] = node.partition.y1;
  bsp[bspIndex + 3] = node.partition.x2;
  bsp[bspIndex + 4] = node.partition.y2;
  bsp[bspIndex + 5] = node.partition.type;
  if(node.front) {
    bsp[bspIndex + 6] = bspIndex + bspStructSize;
    bspIndex += bspStructSize;
    f_ConvertBSPtoArray(node.front);
    if(node.back) {
      bsp[node.saveIndex + 7] = bspIndex + bspStructSize;
      bspIndex += bspStructSize;
      f_ConvertBSPtoArray(node.back);
    } else {
      bsp[node.saveIndex + 7] = -1;
    }
  } else {
    bsp[bspIndex + 6] = -1;
    if(node.back) {
      bsp[bspIndex + 7] = bspIndex + bspStructSize;
      bspIndex += bspStructSize;
      f_ConvertBSPtoArray(node.back);
    } else {
      bsp[bspIndex + 7] = -1;
    }
  }
}
function f_QuickDist(x,y,xx,yy) {
  return (x - xx) * (x - xx) + (y - yy) * (y - yy);
}
function f_BuildLineList() {
  var offset = 0.001;
  var point = new Object();
  for(n in p_game) {
    var temp = p_game[n];
    if(temp.bsp1) {
      var line = new lineSegment();
      line.one;
      line.two;
      point.x = 0;
      point.y = 0;
      f_LocalToGame(temp.bsp1,point);
      line.x1 = point.x - offset;
      line.y1 = point.y;
      point.x = 0;
      point.y = 0;
      f_LocalToGame(temp.bsp2,point);
      line.x2 = point.x;
      line.y2 = point.y - offset;
      line.type = temp.n_type;
      // skip tightening, for single lines (exit, function, etc)
      line.noTighten = temp.noTighten;

      lineList.push(line);
      offset += 0.001;
    }
    if(temp.trailnode) {
      var wp = new waypoint();
      point.x = 0;
      point.y = 0;
      f_LocalToGame(temp.trailnode,point);
      wp.x = point.x;
      wp.y = point.y;
      waypoints.push(wp);
    }
  }
  f_TightenUpLineList();
}
function f_TightenUpLineList() {
  var len = lineList.length;
  for(var i = 0; i < len; i++) {
    var line = lineList[i];
    if(line.noTighten) {
      continue;
    }
    if(!line.one) {
      var minDist = 999999.9;
      var minIndex = -1;
      var minEnd = -1;
      for(var j = 0; j < len; j++) {
        if(i != j) {
          var line2 = lineList[j];
          if(line2.noTighten) {
            continue;
          }
          if(!line2.one) {
            var dist = f_QuickDist(line.x1,line.y1,line2.x1,line2.y1);
            if(dist < minDist) {
              minDist = dist;
              minIndex = j;
              minEnd = 1;
            }
          }
          if(!line2.two) {
            var dist = f_QuickDist(line.x1,line.y1,line2.x2,line2.y2);
            if(dist < minDist) {
              minDist = dist;
              minIndex = j;
              minEnd = 2;
            }
          }
        }
      }
      if(minIndex >= 0) {
        var line2 = lineList[minIndex];
        if(minEnd == 1) {
          var newX = (line.x1 + line2.x1) / 2;
          var newY = (line.y1 + line2.y1) / 2;
          line2.x1 = newX;
          line2.y1 = newY;
          line2.one = true;
        } else if(minEnd == 2) {
          var newX = (line.x1 + line2.x2) / 2;
          var newY = (line.y1 + line2.y2) / 2;
          line2.x2 = newX;
          line2.y2 = newY;
          line2.two = true;
        }
        line.x1 = newX;
        line.y1 = newY;
        line.one = true;
      }
    }
    if(!line.two) {
      var minDist = 999999.9;
      var minIndex = -1;
      var minEnd = -1;
      for(var j = 0; j < len; j++) {
        if(i != j) {
          var line2 = lineList[j];
          if(line2.noTighten) {
            continue;
          }
          if(!line2.one) {
            var dist = f_QuickDist(line.x2,line.y2,line2.x1,line2.y1);
            if(dist < minDist) {
              minDist = dist;
              minIndex = j;
              minEnd = 1;
            }
          }
          if(!line2.two) {
            var dist = f_QuickDist(line.x2,line.y2,line2.x2,line2.y2);
            if(dist < minDist) {
              minDist = dist;
              minIndex = j;
              minEnd = 2;
            }
          }
        }
      }
      if(minIndex >= 0) {
        var line2 = lineList[minIndex];
        if(minEnd == 1) {
          var newX = (line.x2 + line2.x1) / 2;
          var newY = (line.y2 + line2.y1) / 2;
          line2.x1 = newX;
          line2.y1 = newY;
          line2.one = true;
        } else if(minEnd == 2) {
          var newX = (line.x2 + line2.x2) / 2;
          var newY = (line.y2 + line2.y2) / 2;
          line2.x2 = newX;
          line2.y2 = newY;
          line2.two = true;
        }
        line.x2 = newX;
        line.y2 = newY;
        line.two = true;
      }
    }
  }
}
function f_LocalToGame(zone,point) {
  if(zone) {
    zone.localToGlobal(point);
    p_game.globalToLocal(point);
  }
}
function f_DrawLine(zone,width) {
  zone.clear();
  zone.lineStyle(width,zone.color,100,undefined,undefined,"none");
  zone.moveTo(bsp[zone.index + 1],bsp[zone.index + 2]);
  zone.lineTo(bsp[zone.index + 3],bsp[zone.index + 4]);
}
function f_DrawWaypoint(zone,width) {
  zone.clear();
  zone.lineStyle(width,zone.color,100,undefined,undefined,"none");
  zone.moveTo(sortedWaypoints[zone.index] - 31,sortedWaypoints[zone.index + 1]);
  zone.lineTo(sortedWaypoints[zone.index] + 31,sortedWaypoints[zone.index + 1]);
  zone.moveTo(sortedWaypoints[zone.index],sortedWaypoints[zone.index + 1] - 31);
  zone.lineTo(sortedWaypoints[zone.index],sortedWaypoints[zone.index + 1] + 31);
  // zone.moveTo(sortedWaypoints[zone.index + 1] - 31,sortedWaypoints[zone.index + 2] - 31);
  // zone.lineTo(sortedWaypoints[zone.index + 1] + 31,sortedWaypoints[zone.index + 2] + 31);
  // zone.moveTo(sortedWaypoints[zone.index + 1] + 31,sortedWaypoints[zone.index + 2] - 31);
  // zone.lineTo(sortedWaypoints[zone.index + 1] - 31,sortedWaypoints[zone.index + 2] + 31);
}
function f_DrawBsp() {
  var temp = p_game.createEmptyMovieClip("bspPath",666665);
  temp._visible = false;
  var temp = p_game.createEmptyMovieClip("bspPartition",666666);
  temp._visible = false;
  var len = bsp.length;
  for(var i = 0; i < len; i += bspStructSize) {
    var temp = p_game.createEmptyMovieClip("bspLine" + i,777777 + i);
    temp.index = i;
    temp.color = random(1703936);
    f_DrawLine(temp,1.5);
  }
  var len = sortedWaypoints.length;
  for(var i = 0; i < len; i += 3) {
    var temp = p_game.createEmptyMovieClip("bspWaypoint" + i,888888 + i);
    temp.index = i;
    temp.color = random(1703936);
    f_DrawWaypoint(temp,2);
  }
}
function f_DrawBspPath() {
  p_game.bspPath.clear();
  p_game.bspPath.lineStyle(1,0x00ffff,100,undefined,undefined,"none");
  var len = nodePath.length;
  for(var i = 0; i < len - 1; i++) {
    var fromIndex = nodePath[i];
    var toIndex = nodePath[i + 1];
    var x1 = bsp[fromIndex + 1];
    var y1 = bsp[fromIndex + 2];
    var x2 = bsp[fromIndex + 3];
    var y2 = bsp[fromIndex + 4];
    var fromX = (x1 + x2) / 2;
    var fromY = (y1 + y2) / 2;
    var x1 = bsp[toIndex + 1];
    var y1 = bsp[toIndex + 2];
    var x2 = bsp[toIndex + 3];
    var y2 = bsp[toIndex + 4];
    var toX = (x1 + x2) / 2;
    var toY = (y1 + y2) / 2;
    p_game.bspPath.moveTo(fromX,fromY);
    p_game.bspPath.lineTo(toX,toY);
  }
}
function f_BSPHitTest(x1,y1,x2,y2) {
  bspWorkingLine.x1 = x1;
  bspWorkingLine.y1 = y1;
  bspWorkingLine.x2 = x2;
  bspWorkingLine.y2 = y2;
  bspWorkingLine.type = 0;
  bspWorkingLine.index = 0;
  delete nodePath;
  nodePath = new Array();
  nodeDepth = -1;
  nodeIndex = -1;
  return f_CheckNode(0);
}
function f_CheckNode(index) {
  nodeDepth++;
  nodeIndex = index;
  nodePath.push(index);
  var ret = 0;
  if(bsp[index + 6] < 0 && bsp[index + 7] < 0) {
    ret = f_CheckLineHit(index);
  } else {
    var pX = bsp[index + 3] - bsp[index + 1];
    var pY = bsp[index + 4] - bsp[index + 2];
    var lX = bspWorkingLine.x1 - bsp[index + 1];
    var lY = bspWorkingLine.y1 - bsp[index + 2];
    var result1 = pX * lY - pY * lX;
    var lX = bspWorkingLine.x2 - bsp[index + 1];
    var lY = bspWorkingLine.y2 - bsp[index + 2];
    var result2 = pX * lY - pY * lX;
    var result = 9;
    if(result1 == 0 && result2 == 0) {
      result = 0;
    } else if(result1 >= 0 && result2 >= 0) {
      result = 1;
    } else if(result1 <= 0 && result2 <= 0) {
      result = 2;
    } else if(result1 >= 0 && result2 <= 0) {
      result = 3;
    } else if(result1 <= 0 && result2 >= 0) {
      result = 4;
    }
    if(result < 3) {
      if(result == 1) {
        if(bsp[index + 6] > 0) {
          ret = f_CheckNode(bsp[index + 6]);
        } else {
          ret = 0;
        }
      } else if(result == 2) {
        if(bsp[index + 7] > 0) {
          ret = f_CheckNode(bsp[index + 7]);
        } else {
          ret = 0;
        }
      }
    } else if(result == 3) {
      if(bsp[index + 6] > 0) {
        ret = f_CheckNode(bsp[index + 6]);
      }
      if(!ret) {
        ret = f_CheckLineHit(index);
      }
      if(!ret) {
        if(bsp[index + 7] > 0) {
          ret = f_CheckNode(bsp[index + 7]);
        }
      }
    } else if(result == 4) {
      if(bsp[index + 7] > 0) {
        ret = f_CheckNode(bsp[index + 7]);
      }
      if(!ret) {
        ret = f_CheckLineHit(index);
      }
      if(!ret) {
        if(bsp[index + 6] > 0) {
          ret = f_CheckNode(bsp[index + 6]);
        }
      }
    }
  }
  return ret;
}
function f_CheckLineHit(index) {
  var ret2 = 0;
  var aX = bsp[index + 1];
  var aY = bsp[index + 2];
  var bX = bsp[index + 3];
  var bY = bsp[index + 4];
  var cX = bspWorkingLine.x1;
  var cY = bspWorkingLine.y1;
  var dX = bspWorkingLine.x2;
  var dY = bspWorkingLine.y2;
  var t1 = -1;
  var t2 = -1;
  var num = (aY - cY) * (dX - cX) - (aX - cX) * (dY - cY);
  var denom = (bX - aX) * (dY - cY) - (bY - aY) * (dX - cX);
  if(denom != 0) {
    t1 = num / denom;
  }
  if(t1 >= 0 && t1 <= 1) {
    num = (cY - aY) * (bX - aX) - (cX - aX) * (bY - aY);
    denom = (dX - cX) * (bY - aY) - (dY - cY) * (bX - aX);
    if(denom != 0) {
      t2 = num / denom;
    }
    if(t2 >= 0 && t2 <= 1) {
      bspWorkingLine.type = bsp[index + 5];
      bspWorkingLine.index = index;
      bspWorkingLine.slope = (bY - aY) / (bX - aX);
      ret2 = t2;
    }
  }
  return ret2;
}
function f_PrintBSPData() {
  if(!bsp.length && !sortedWaypoints.length) {
    return;
  }
  trace("===bspstart===")
  if(bsp.length) {
    trace("==lines==");
    var len = bsp.length;
    for(var i = 0; i < len; i += bspStructSize) {
      var temp = new Array();
      for(var j = i; j < i + bspStructSize; j++) {
        temp.push(bsp[j]);
      }
      trace("#" + i + "=[" + temp + "]");
    }
  }
  if(sortedWaypoints.length) {
    trace("==waypoints==");
    var len = sortedWaypoints.length;
    for(var i = 0; i < len; i += 3) {
      var temp = new Array();
      for(var j = i; j < i + 3; j++) {
        temp.push(sortedWaypoints[j]);
      }
      trace("#" + (i / 3) + "=[" + temp + "]");
    }
  }
  trace("===bspend===");
}
function waypoint() {
  this.x = 0;
  this.y = 0;
}
function bspTreeNode() {
  this.partition = new lineSegment();
  this.front;
  this.back;
}
function lineSegment() {
  this.type = 0;
  this.x1 = 0;
  this.y1 = 0;
  this.x2 = 0;
  this.y2 = 0;
}
lineSegment.prototype.intersect = function(line) {
  var aX = this.x1;
  var aY = this.y1;
  var bX = this.x2;
  var bY = this.y2;
  var cX = line.x1;
  var cY = line.y1;
  var dX = line.x2;
  var dY = line.y2;
  var num = (aY - cY) * (dX - cX) - (aX - cX) * (dY - cY);
  var denom = (bX - aX) * (dY - cY) - (bY - aY) * (dX - cX);
  var ret = -1;
  if(denom != 0) {
    ret = num / denom;
  }
  return ret;
};
lineSegment.prototype.copy = function(line) {
  this.x1 = line.x1;
  this.y1 = line.y1;
  this.x2 = line.x2;
  this.y2 = line.y2;
};
function vector2d() {
  this.x = 0;
  this.y = 0;
}
vector2d.prototype.divide = function(number) {
  this.x /= number;
  this.y /= number;
};
vector2d.prototype.magnitude = function() {
  return Math.sqrt(this.x * this.x + this.y * this.y);
};
vector2d.prototype.normalize = function() {
  var len = this.magnitude();
  if(len == 0) {
    len = 0.0001;
  }
  this.divide(len);
};
vector2d.prototype.cross = function(vector) {
  return Number(this.x * vector.y - this.y * vector.x);
};
function f_FormatDecimal(n) {
  // show two decimals
  var str = "" + Math.round(n * 100) / 100;
  if(str.indexOf(".") == -1) {
    str += ".00";
  } else {
    var decimals = str.length - str.indexOf(".") - 1;
    if(decimals == 1) {
      str += "0";
    }
  }
  return str;
}
function f_StopSprites(zone,visited) {
  // recursively stop animations in a sprite
  if(!visited) {
    visited = new Array();
  }
  for(var i = 0; i < visited.length; i++) {
    if(visited[i] === zone) {
      return;
    }
  }
  visited.push(zone);
  zone.stop();
  for(var temp in zone) {
    if(typeof(zone[temp]) == "movieclip") {
      f_StopSprites(zone[temp],visited);
    }
  }
}
function f_SelectLine(zone,center) {
  if(selectedLine == zone) {
    return;
  }
  if(selectedLine) {
    f_DrawLine(selectedLine,1.5);
  }
  f_DrawLine(zone,3);
  selectedLine = zone;
  // draw partition line
  var temp = p_game.bspPartition;
  temp.clear();
  temp.lineStyle(1,0xffff00,100,undefined,undefined,"none");
  var x1 = bsp[zone.index + 1];
  var y1 = bsp[zone.index + 2];
  var x2 = bsp[zone.index + 3];
  var y2 = bsp[zone.index + 4];
  var mX = (x1 + x2) / 2;
  var mY = (y1 + y2) / 2;
  var dX = x2 - x1;
  var dY = y2 - y1;
  var len = Math.sqrt(dX * dX + dY * dY);
  var dist = 9999999;
  dX /= len;
  dY /= len;
  temp.moveTo(x1,y1);
  temp.lineTo(x1 - dX * dist,y1 - dY * dist);
  temp.moveTo(x2,y2);
  temp.lineTo(x2 + dX * dist,y2 + dY * dist);
  if(center) {
    f_CenterGame(mX,mY);
  }
  // draw arrow indicating front
  temp.lineStyle(1.5,0xffff00,100,undefined,undefined,"none");
  var arrowLen = 12;
  var frontX = mX + (- dY) * arrowLen;
  var frontY = mY + dX * arrowLen;
  temp.moveTo(mX,mY);
  temp.lineTo(frontX,frontY);
  var headLen = 6;
  var angle = Math.atan2(dX,- dY);
  temp.lineTo(frontX - headLen * Math.cos(angle - 0.5),frontY - headLen * Math.sin(angle - 0.5));
  temp.moveTo(frontX,frontY);
  temp.lineTo(frontX - headLen * Math.cos(angle + 0.5),frontY - headLen * Math.sin(angle + 0.5));
  // update text
  txtLine1.txt.text = "line #" + (zone.index / bspStructSize) + ":";
  txtLine1.txtBG.text = txtLine1.txt.text;
  txtLine2.txt.text = "x1,y1=(" + bsp[zone.index + 1] + "," + bsp[zone.index + 2] + ")";
  txtLine2.txtBG.text = txtLine2.txt.text;
  txtLine3.txt.text = "x2,y2=(" + bsp[zone.index + 3] + "," + bsp[zone.index + 4] + ")";
  txtLine3.txtBG.text = txtLine3.txt.text;
  switch(bsp[zone.index + 5]) {
    case 1: var temp = "plain"; break;
    case 2: var temp = "slide"; break;
    case 3: var temp = "slope"; break;
    case 4: var temp = "ledge"; break;
    case 5: var temp = "ledge slide"; break;
    case 6: var temp = "ledge slope"; break;
    case 100: var temp = "stairs"; break;
    case 101: var temp = "stairs entry"; break;
    case 200: var temp = "death box"; break;
    case 300: var temp = "water"; break;
    case 400: var temp = "exit"; break;
    case 700: var temp = "function"; break;
    case 1000: var temp = "table"; break;
    default: var temp = "?";
  }
  txtLine4.txt.text = "type=" + temp + " (" + bsp[zone.index + 5] + ")";
  txtLine4.txtBG.text = txtLine4.txt.text;
  var temp = bsp[zone.index + 6];
  if(temp == -1) {
    temp = "none";
  } else {
    temp = "#" + (temp /= bspStructSize);
  }
  txtLine5.txt.text = "front=" + temp;
  txtLine5.txtBG.text = txtLine5.txt.text;
  var temp = bsp[zone.index + 7];
  if(temp == -1) {
    temp = "none";
  } else {
    temp = "#" + (temp /= bspStructSize);
  }
  txtLine6.txt.text = "back=" + temp;
  txtLine6.txtBG.text = txtLine6.txt.text;
}
function f_SelectWaypoint(zone) {
  if(selectedWaypoint == zone) {
    return;
  }
  if(selectedWaypoint) {
    f_DrawWaypoint(selectedWaypoint,2);
  }
  f_DrawWaypoint(zone,4);
  selectedWaypoint = zone;
  txtWaypoint1.txt.text = "waypoint #" + (zone.index / 3) + ":";
  txtWaypoint1.txtBG.text = txtWaypoint1.txt.text;
  txtWaypoint2.txt.text = "x,y=(" + sortedWaypoints[zone.index] + "," + sortedWaypoints[zone.index + 1] + ")";
  txtWaypoint2.txtBG.text = txtWaypoint2.txt.text;
}
function f_Popup(temp,error) {
  if(temp == "") {
    popup._visible = false;
    return;
  }
  popup._visible = true;
  popup.txt1.txt.text = temp;
  popup.txt1.txtBG.text = popup.txt1.txt.text;
  popup.body._width = popup.txt1.txt.textWidth + 25;
  if(error) {
    txtHelp1.txt.text = "q: quit";
    txtHelp1.txtBG.text = txtHelp1.txt.text;
    onEnterFrame = f_Quit;
  }
}
function f_CheckPress(temp) {
  if(Key.isDown(temp)) {
    if(!this["pressed" + temp]) {
      this["pressed" + temp] = true;
      return true;
    }
  } else if(this["pressed" + temp]) {
    delete this["pressed" + temp];
  }
  return false;
}
function f_Quit() {
  if(Key.isDown(81)) { // Q
    fscommand("quit");
  }
}
function f_CenterGame(x,y) {
  var sX = p_game._xscale / 100;
  var sY = p_game._yscale / 100;
  p_game._x = 424 - (x * sX);
  p_game._y = 240 - (y * sY);
}
function f_UpdatePositionText(x,y) {
  txtPos.txt.text = "x,y=(" + f_FormatDecimal(x) + "," + f_FormatDecimal(y) + ")";
  txtPos.txtBG.text = txtPos.txt.text;
  txtDepth.txt.text = "depth=" + nodeDepth + "(#" + (nodeIndex / 8) + ")";
  txtDepth.txtBG.text = txtDepth.txt.text;
}
function f_UpdateHelpText() {
  for(var i = 1; this["txtHelp" + i]; i++) {
    var temp = this["txtHelp" + i];
    temp.txt.text = "";
    temp.txtBG.text = temp.txt.text;
  }
  if(detailedInfo) {
    txtHelp6.txt.text = "click & drag to move";
    txtHelp6.txtBG.text = txtHelp6.txt.text;
    txtHelp5.txt.text = "e/r: zoom";
    txtHelp5.txtBG.text = txtHelp5.txt.text;
    txtHelp4.txt.text = "i: toggle detailed info";
    txtHelp4.txtBG.text = txtHelp4.txt.text;
    txtHelp3.txt.text = "n/p: navigate to front/back line";
    txtHelp3.txtBG.text = txtHelp3.txt.text;
    txtHelp2.txt.text = "o: select root partition line";
    txtHelp2.txtBG.text = txtHelp2.txt.text;
    txtHelp1.txt.text = "q: quit";
    txtHelp1.txtBG.text = txtHelp1.txt.text;
  } else {
    txtHelp4.txt.text = "click & drag to move";
    txtHelp4.txtBG.text = txtHelp4.txt.text;
    txtHelp3.txt.text = "e/r: zoom";
    txtHelp3.txtBG.text = txtHelp3.txt.text;
    txtHelp2.txt.text = "i: toggle detailed info";
    txtHelp2.txtBG.text = txtHelp2.txt.text;
    txtHelp1.txt.text = "q: quit";
    txtHelp1.txtBG.text = txtHelp1.txt.text;
  }
}
function f_Load() {
  switch(state) {
    case 0:
      if(loader.b_loaded) {
        if(loader.game._totalframes == 1 && loader.game.game._totalframes > 1) {
          p_game = loader.game.game;
        } else if(loader.game._totalframes > 1 && loader.game.game._totalframes == 1) {
          p_game = loader.game;
        } else {
          f_Popup("error: game frame 2 not found",true);
          return;
        }
        p_game.gotoAndStop(2);
        f_StopSprites(loader);
        // hide non-game objects
        for(var temp in loader) {
          if(loader[temp]._name != "game" && typeof(loader[temp]) == "movieclip") {
            loader[temp]._visible = false;
          }
        }
      } else if(loader._totalframes == 1) {
        f_Popup("error: level only has one frame",true);
      } else {
        return;
      }
      f_Popup("creating bsp...");
      break;
    case 1:
      if(f_InitLevelBSP()) {
        p_game._xscale = 75;
        p_game._yscale = 75;
        f_Popup("");
        prevMouseX = _xmouse;
        prevMouseY = _ymouse;
        detailedInfo = false;
        // counts
        var temp = 0;
        var len = bsp.length;
        for(var i = 1; i < len; i += bspStructSize) {
          temp++;
        }
        txtLineNum.txt.text = temp + " lines";
        txtLineNum.txtBG.text = txtLineNum.txt.text;
        var len = sortedWaypoints.length;
        var temp = 0;
        for(var i = 1; i < len; i += 3) {
          temp++;
        }
        txtWaypointNum.txt.text = temp + " waypoints";
        txtWaypointNum.txtBG.text = txtWaypointNum.txt.text;
        f_SelectLine(p_game.bspLine0,true);
        var p = new Object();
        p.x = 424;
        p.y = 240;
        p_game.globalToLocal(p);
        if(sortedWaypoints.length > 0) {
          f_SelectWaypoint(p_game["bspWaypoint" + (f_GetClosestWaypoint(p.x) * 3)]);
        }
        f_BSPHitTest(p.x,p.y,p.x,p.y); // get node vars
        f_UpdatePositionText(p.x,p.y);
        f_UpdateHelpText();
        mouse.onPress = function() {
          isDragging = true;
          lastMouseX = _xmouse;
          lastMouseY = _ymouse;
        };
        mouse.onRelease = function() {
          isDragging = false;
        };
        mouse.onReleaseOutside = function() {
          isDragging = false;
        };
        this.onEnterFrame = f_Main;
      }
  }
  state++;
}
function f_Main() {
  // mouse movement
  var mouseX = _xmouse;
  var mouseY = _ymouse;
  if(mouseX != prevMouseX || mouseY != prevMouseY) {
    var p1 = new Object();
    p1.x = prevMouseX;
    p1.y = prevMouseY;
    p_game.globalToLocal(p1);
    var p2 = new Object();
    p2.x = mouseX;
    p2.y = mouseY;
    p_game.globalToLocal(p2);
    f_UpdatePositionText(p2.x,p2.y);
    // highlighting
    if(f_BSPHitTest(p1.x,p1.y,p2.x,p2.y)) {
      var temp = p_game["bspLine" + bspWorkingLine.index];
      if(temp) {
        f_SelectLine(temp);
      }
    }
    f_DrawBspPath();
    var temp = p_game["bspWaypoint" + (f_GetClosestWaypoint(p2.x) * 3)];
    if(temp != selectedWaypoint) {
      f_SelectWaypoint(temp)
    }
    // test
    prevMouseX = mouseX;
    prevMouseY = mouseY;
  }
  if(isDragging) {
    var dX = (_xmouse - lastMouseX);
    var dY = (_ymouse - lastMouseY);
    p_game._x += dX;
    p_game._y += dY;
    lastMouseX = _xmouse;
    lastMouseY = _ymouse;
  }
  var zoomIn = Key.isDown(75) || Key.isDown(82); // J/R
  var zoomOut = Key.isDown(74) || Key.isDown(69); // K/E
  if(zoomIn || zoomOut) {
    var scale = p_game._xscale;
    var factor = zoomIn ? 1.1 : (1 / 1.1);
    var newScale = scale * factor;
    if(newScale < 5) {
      newScale = 5;
    }
    if(newScale > 750) {
      newScale = 750;
    }
    factor = newScale / scale;
    // not at scale limit
    if(factor != 1) {
      var mouseX = _xmouse;
      var mouseY = _ymouse;
      var p = new Object();
      p.x = mouseX;
      p.y = mouseY;
      p_game.globalToLocal(p);
      p_game._xscale = newScale;
      p_game._yscale = newScale;
      p_game.localToGlobal(p);
      p_game._x += (mouseX - p.x);
      p_game._y += (mouseY - p.y);
    }
  }
  // navigate line neighbors
  if(selectedLine) {
    if(f_CheckPress(78)) { // N
      var front = bsp[selectedLine.index + 6];
      if(front != -1) {
        f_SelectLine(p_game["bspLine" + front],true);
      }
    }
    if(f_CheckPress(80)) { // P
      var back = bsp[selectedLine.index + 7];
      if(back != -1) {
        f_SelectLine(p_game["bspLine" + back],true);
      }
    }
  }
  // select root partition line
  if(f_CheckPress(79)) { // O
    f_SelectLine(p_game.bspLine0,true);
  }
  if(f_CheckPress(73)) { // I
    detailedInfo = !detailedInfo;
    if(detailedInfo) {
      var offset = -40;
      var alpha = 100;
    } else {
      var offset = 40;
      var alpha = 0;
    }
    p_game.bspPartition._visible = detailedInfo;
    p_game.bspPath._visible = detailedInfo;
    for(var i = 1; this["txtLine" + i]; i++) {
      var temp = this["txtLine" + i];
      temp._y += offset;
      if(i >= 5) {
        temp._visible = detailedInfo;
      }
    }
    for(var i = 1; this["txtWaypoint" + i]; i++) {
      var temp = this["txtWaypoint" + i];
      temp._y += offset;
    }
    txtDepth._visible = detailedInfo;
    f_UpdateHelpText();
  }
  f_Quit();
}
switch(balancedBSP) {
  case "false":
    balancedBSP = false;
    break;
  case "true":
  default:
    balancedBSP = true;
}
popup.txt1.selectable = popup.txt1.selectable = false;
txtPos.txt.text = txtPos.txtBG.text = "";
txtPos.txt.selectable = txtPos.txtBG.selectable = false;
txtDepth._visible = false;
txtDepth.txt.text = txtDepth.txtBG.text = "";
txtDepth.txt.selectable = txtDepth.txtBG.selectable = false;
txtLineNum.txt.text = txtLineNum.txtBG.text = "";
txtLineNum.txt.selectable = txtLineNum.txtBG.selectable = false;
txtWaypointNum.txt.text = txtWaypointNum.txtBG.text = "";
txtWaypointNum.txt.selectable = txtWaypointNum.txtBG.selectable = false;
for(var i = 1; this["txtLine" + i]; i++) {
  var temp = this["txtLine" + i];
  temp.txt.text = "";
  temp.txtBG.text = temp.txt.text;
  temp.txt.selectable = false;
  temp.txtBG.selectable = temp.txt.selectable;
  temp._y += 40;
  if(i >= 5) {
    temp._visible = false;
  }
}
for(var i = 1; this["txtWaypoint" + i]; i++) {
  var temp = this["txtWaypoint" + i];
  temp.txt.text = "";
  temp.txtBG.text = temp.txt.text;
  temp.txt.selectable = false;
  temp.txtBG.selectable = temp.txt.selectable;
  temp._y += 40;
}
for(var i = 1; this["txtHelp" + i]; i++) {
  var temp = this["txtHelp" + i];
  temp.txt.text = "";
  temp.txtBG.text = temp.txt.text;
  temp.txt.selectable = false;
  temp.txtBG.selectable = temp.txt.selectable;
}
f_Popup("loading level...");
_quality = "high";
state = 0;
loadMovie(inputLevel,loader);
onEnterFrame = f_Load;
