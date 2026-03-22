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
  aline2.n_type = aline.n_type;
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
  var partition = f_ChooseBestPartitionLine(list);
  // var partition = list.pop();
  node.partition.copy(partition);
  node.partition.n_type = partition.n_type;
  // if(node == bspRoot) {
  //   trace("partition line: " + node.partition.x1 + "," + node.partition.y1 + "," + node.partition.x2 + "," + node.partition.y2 + "," + node.partition.n_type);
  // }
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
  waypoints = new Array();
  sortedWaypoints = new Array();
  lineList = new Array();
  bsp = new Array();
  bspWorkingLine = new Object();
  bspIndex = 0;
  f_BuildLineList();
  bspRoot = new bspTreeNode();
  if(lineList.length) {
    f_BuildBSPTree(bspRoot,lineList);
    f_ConvertBSPtoArray(bspRoot);
    f_ConvertWaypointstoArray();
    f_DrawBsp();
  } else {
    trace("error: no lines found");
    loading.txt1.txt.text = "no lines found";
    loading.txt1.txtBG.text = loading.txt1.txt.text;
    return false;
  }
  f_PrintBSPData();
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
  bsp[bspIndex + 5] = node.partition.n_type;
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
  for(n in game.game) {
    var temp = game.game[n];
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
      line.n_type = temp.n_type;
      lineList.push(line);
      offset += 0.001;
    }
    if(temp.trailnode) {
      wp = new waypoint();
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
    if(!line.one) {
      var minDist = 999999.9;
      var minIndex = -1;
      var minEnd = -1;
      for(var j = 0; j < len; j++) {
        if(i != j) {
          var line2 = lineList[j];
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
    game.game.globalToLocal(point);
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
  var len = bsp.length;
  for(var i = 0; i < len; i += bspStructSize) {
    var temp = game.game.createEmptyMovieClip("bspLine" + i,888888 + i);
    temp.index = i;
    temp.color = random(1703936);
    f_DrawLine(temp,1.5);
  }
  var len = sortedWaypoints.length;
  for(var i = 0; i < len; i += 3) {
    var temp = game.game.createEmptyMovieClip("bspWaypoint" + i,999999 + i);
    temp.index = i;
    temp.color = random(1703936);
    f_DrawWaypoint(temp,2);
  }
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
      bspWorkingLine.n_type = bsp[index + 5];
      bspWorkingLine.n_index = index;
      bspWorkingLine.n_slope = (bY - aY) / (bX - aX);
      ret2 = t2;
    }
  }
  return ret2;
}
function f_PrintBSPData() {
  if(!bsp.length && !sortedWaypoints.length) {
    return;
  }
  if(bsp.length) {
    trace("BSPLINES");
    for(var i = 0; i < bsp.length; i++) {
      trace(bsp[i]);
    }
  }
  if(sortedWaypoints.length) {
    trace("BSPWAYPOINTS");
    for(var i = 0; i < sortedWaypoints.length; i++) {
      trace(sortedWaypoints[i]);
    }
  }
  trace("BSPEND");
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
  this.n_type = 0;
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
  var len = magnitude();
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
  // fails to stop objects with same name, inject stop doactions in xml steps?
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
    if(zone[temp] instanceof MovieClip) {
      f_StopSprites(zone[temp],visited);
    }
  }
}
function f_SelectLine(zone) {
  f_DrawLine(zone,3);
  zone.hit = true;
  selectedLine = zone;
  txtLine1.txt.text = "line #" + (zone.index / bspStructSize) + ":";
  txtLine1.txtBG.text = txtLine1.txt.text;
  txtLine2.txt.text = "pos1=(" + bsp[zone.index + 1] + "," + bsp[zone.index + 2] + ")";
  txtLine2.txtBG.text = txtLine2.txt.text;
  txtLine3.txt.text = "pos2=(" + bsp[zone.index + 3] + "," + bsp[zone.index + 4] + ")";
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
function f_UnselectLine(zone) {
  f_DrawLine(zone,1.5);
  delete zone.hit;
}
function f_SelectWaypoint(zone) {
  f_DrawWaypoint(zone,4);
  zone.hit = true;
  selectedWaypoint = zone;
  txtWaypoint1.txt.text = "waypoint #" + (zone.index / 3) + ":";
  txtWaypoint1.txtBG.text = txtWaypoint1.txt.text;
  txtWaypoint2.txt.text = "pos=(" + sortedWaypoints[zone.index] + "," + sortedWaypoints[zone.index + 1] + ")";
  txtWaypoint2.txtBG.text = txtWaypoint2.txt.text;
}
function f_UnselectWaypoint(zone) {
  f_DrawWaypoint(zone,2);
  delete zone.hit;
}
this.onEnterFrame = function() {
  // mouse movement
  if(loaded) {
    var mouseX = _xmouse;
    var mouseY = _ymouse;
    if(mouseX != prevMouseX || mouseY != prevMouseY) {
      var p1 = new Object();
      p1.x = prevMouseX;
      p1.y = prevMouseY;
      game.game.globalToLocal(p1);
      var p2 = new Object();
      p2.x = mouseX;
      p2.y = mouseY;
      game.game.globalToLocal(p2);
      txtPos.txt.text = txtPos.txtBG.text = "(" + f_FormatDecimal(p2.x) + "," + f_FormatDecimal(p2.y) + ")";
      // line highlighting
      var close;
      var closeP = -1;
      var len = bsp.length;
      for(var i = 0; i < len; i += bspStructSize) {
        var temp = game.game["bspLine" + i];
        if(temp.hit && temp != selectedLine) {
          f_UnselectLine(temp);
        }
        bspWorkingLine.x1 = p1.x;
        bspWorkingLine.y1 = p1.y;
        bspWorkingLine.x2 = p2.x;
        bspWorkingLine.y2 = p2.y;
        var p = f_CheckLineHit(i);
        if(p > closeP) {
          close = temp;
          closeP = p;
        }
      }
      if(closeP > 0 && close != selectedLine) {
        f_SelectLine(close);
      }
      // waypoint highlighting
      var len = sortedWaypoints.length;
      for(var i = 0; i < len; i += 3) {
        var temp = game.game["bspWaypoint" + i];
        if(temp.hit && temp != selectedWaypoint) {
          f_UnselectWaypoint(temp);
        }
      }
      var temp = game.game["bspWaypoint" + (f_GetClosestWaypoint(p2.x) * 3)];
      if(temp != selectedWaypoint) {
        f_SelectWaypoint(temp)
      }
      prevMouseX = mouseX;
      prevMouseY = mouseY;
    }
    if(isDragging) {
      var dX = (_xmouse - lastMouseX);
      var dY = (_ymouse - lastMouseY);
      game.game._x += dX;
      game.game._y += dY;
      lastMouseX = _xmouse;
      lastMouseY = _ymouse;
    }
    var zoomIn = Key.isDown(75) || Key.isDown(82); // J/R
    var zoomOut = Key.isDown(74) || Key.isDown(69); // K/E
    if(zoomIn || zoomOut) {
      var scale = game.game._xscale;
      var factor = zoomIn ? 1.1 : (1 / 1.1);
      var newScale = scale * factor;
      if(newScale < 5) {
        newScale = 5;
      }
      if(newScale > 500) {
        newScale = 500;
      }
      factor = newScale / scale;
      var mouseX = _xmouse;
      var mouseY = _ymouse;
      var p = new Object();
      p.x = mouseX;
      p.y = mouseY;
      game.game.globalToLocal(p);
      game.game._xscale = newScale;
      game.game._yscale = newScale;
      game.game.localToGlobal(p);
      game.game._x += (mouseX - p.x);
      game.game._y += (mouseY - p.y);
    }
    // quit
    if(Key.isDown(81)) { // Q
      fscommand("quit");
    }
  }
};
f_StopSprites(game.game);
txtPos.txt.text = txtPos.txtBG.text = "";
txtPos.txt.selectable = txtPos.txtBG.selectable = false;
txtLineNum.txt.text = txtLineNum.txtBG.text = "";
txtLineNum.txt.selectable = txtLineNum.txtBG.selectable = false;
txtWaypointNum.txt.text = txtWaypointNum.txtBG.text = "";
txtWaypointNum.txt.selectable = txtWaypointNum.txtBG.selectable = false;
for(var i = 1; i <= 6; i++) {
  this["txtLine" + i].txt.text = "";
  this["txtLine" + i].txtBG.text = this["txtLine" + i].txt.text;
  this["txtLine" + i].txt.selectable = false;
  this["txtLine" + i].txtBG.selectable = this["txtLine" + i].txt.selectable;
}
for(var i = 1; i <= 2; i++) {
  this["txtWaypoint" + i].txt.text = "";
  this["txtWaypoint" + i].txtBG.text = this["txtWaypoint" + i].txt.text;
  this["txtWaypoint" + i].txt.selectable = false;
  this["txtWaypoint" + i].txtBG.selectable = this["txtWaypoint" + i].txt.selectable;
}
for(var i = 1; i <= 3; i++) {
  this["txtHelp" + i].txt.text = "";
  this["txtHelp" + i].txtBG.text = this["txtHelp" + i].txt.text;
  this["txtHelp" + i].txt.selectable = false;
  this["txtHelp" + i].txtBG.selectable = this["txtHelp" + i].txt.selectable;
}
bspStructSize = 8;
if(f_InitLevelBSP()) {
  loaded = true;
  loading._visible = false;
  prevMouseX = _xmouse;
  prevMouseY = _ymouse;
  // counts
  var temp = 0;
  var len = bsp.length;
  for(var i = 1; i < len; i += bspStructSize) {
    temp++;
  }
  txtLineNum.txt.text = temp + " lines";
  txtLineNum.txtBG.text = txtLineNum.txt.text;
  var temp = 0;
  var len = sortedWaypoints.length;
  for(var i = 1; i < len; i += 3) {
    temp++;
  }
  txtWaypointNum.txt.text = temp + " waypoints";
  txtWaypointNum.txtBG.text = txtWaypointNum.txt.text;
  // select closest line & waypoint to center
  var p = new Object();
  p.x = 424;
  p.y = 240;
  game.game.globalToLocal(p);
  var dist = 9999999;
  var close;
  var len = bsp.length;
  for(var i = 0; i < len; i += bspStructSize) {
    // midpoint of line
    var x = (bsp[i + 1] + bsp[i + 3]) / 2;
    var y = (bsp[i + 2] + bsp[i + 4]) / 2;
    var dist2 = Math.abs(p.x - x) + Math.abs(p.y - y);
    if(dist2 < dist) {
      dist = dist2;
      close = game.game["bspLine" + i];
    }
  }
  if(close) {
    f_SelectLine(close);
  }
  f_SelectWaypoint(game.game["bspWaypoint" + (f_GetClosestWaypoint(p.x) * 3)]);
  txtPos.txt.text = txtPos.txtBG.text = "(" + p.x + "," + p.y + ")";
  // help
  txtHelp1.txt.text = "click & drag to move";
  txtHelp1.txtBG.text = txtHelp1.txt.text;
  txtHelp2.txt.text = "e/r: zoom";
  txtHelp2.txtBG.text = txtHelp2.txt.text;
  txtHelp3.txt.text = "q: quit";
  txtHelp3.txtBG.text = txtHelp3.txt.text;
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
}
_quality = "high";
stop();
