/*
    - edited functions -
    f_PlainMCH (fix incorrect groundtype, smart ledges/tables, slope toggle)
    f_PlainMCV (smart ledges/tables, slope toggle)
    f_PlainProjectileMove (slope toggle)
    f_TableMCH (smart tables)
    f_TableMCV (smart tables)
    f_ResetLevelVars (reset root variables)
    f_KidSettings (reset smart ledge/table variables, enemy table body_y fix)
    f_StandSettings (reset smart ledge/table variables)
    f_AutoJump (smart ledge/table jumping)
    f_EndHang (smart ledge jumping)
    f_BeefyEnemyWalk (enemy beefy jump support)
    f_NPCWalk (NPC beefy jump support)
    f_Character (c_skipAnim variable)
    f_CharacterBeefy (c_skipAnim variable)
    f_EnemyWalk (c_skipAnim variable)
    f_NPCWalking (c_skipAnim variable)
*/
function f_PlainMCH(zone, speed) { // collision: fix incorrect groundtype, smart ledges/tables, slope toggle
    var x1 = zone.x;
    var y1 = zone.y;
    var move_y = 0;
    var ret = 0;
    var p = f_BSPHitTest(x1,y1,x1 + speed,y1);
    if(!p) {
        zone.x += speed;
        var bottom = f_BSPHitTest(x1,y1,x1,y1 + 400) * 400;
        if(bottom) {
            var n_type = f_BSPCheckLastHitType();
            if(!c_disableSlopes && (n_type == 3 || n_type == 6) || (n_type == 2 || n_type == 5) && bottom < 10) {
                var n_slope = f_BSPCheckLastHitSlope();
                if(Math.abs(n_slope) > 0.1) {
                    move_y = n_slope * speed;
                }
            }
        }
    } else {
        var n_type = f_BSPCheckLastHitType();
        var index = f_BSPCheckLastHitIndex();
        ret = 0.9 - p;
        if(ret < 0) {
            ret = 0;
        }
        var parametric_x = x1 + (p + 0.001) * speed; // incorrect groundtype fix (0.0001 (original) -> 0.001 (PS3))
        switch(n_type) {
            case 1: // plain
                break;
            case 3: // slope
                if(!(p && c_disableSlopes)) {
                    zone.hitwall_h = true;
                }
            case 2: // slide
                var done = false;
                var q = f_BSPHitTest(x1,y1,x1,y1 - 400);
                if(q) {
                    if(index == f_BSPCheckLastHitIndex()) {
                        move_y = q * 400;
                        if(move_y < 3) {
                            move_y = 3;
                        }
                        ret = 0;
                        done = true;
                    }
                }
                if(!done) {
                    var r = f_BSPHitTest(x1,y1,x1,y1 + 400);
                    if(r) {
                        if(index == f_BSPCheckLastHitIndex()) {
                            move_y = - r * 400;
                            if(move_y > -3) {
                                move_y = -3;
                            }
                            ret = 0;
                            done = true;
                        }
                    }
                }
                if(!done) {
                    if(q > r) {
                        move_y = -3;
                        ret = 0;
                    } else {
                        move_y = 3;
                        ret = 0;
                    }
                }
                break;
            case 4: // ledge
            case 5: // ledge slide
            case 6: // ledge slope
                if(!zone.hostage && !zone.captor || zone.nohit || !c_smartLedges) {
                    var done = false;
                    var hanging = 90;
                    if(Math.abs(f_BSPCheckLastHitSlope()) <= 0.1) {
                        hanging = 0;
                    }
                    var q = f_BSPHitTest(parametric_x,y1,parametric_x,y1 - 800);
                    if(q) { // down -> up
                        if(index != f_BSPCheckLastHitIndex()) {
                            var qy = y1 - (q + 0.00001) * 800;
                            var n_type = f_BSPCheckLastHitType();
                            if(Math.abs(f_BSPCheckLastHitSlope()) <= 0.1) {
                                hanging = 0;
                            }
                            if(n_type == 4 || n_type == 5 || n_type == 6) {
                                var diff = y1 + zone.body_y - qy;
                                if(diff < hanging) {
                                    HiFps_ResetRecursive(zone);
                                    HiFps_Reset(zone.shadow_pt);
                                    zone.x = parametric_x;
                                    zone.body_y -= qy - zone.y;
                                    zone.y = qy;
                                    f_Depth(zone,zone.y);
                                    done = true;
                                    if(diff > 0) {
                                        zone.body_y = 0;
                                        zone.body._y = zone.body_y;
                                        zone.speed_jump = 0;
                                        zone.jumping = false;
                                        if(!zone.nohit || !c_smartLedges) {
                                            if(!zone.beefy) {
                                                zone.busy = true;
                                                f_DashReset(zone);
                                                zone.hanging = true;
                                                if(c_smartLedges && (!zone.human || zone.npc)) {
                                                    zone.c_enemyLedgeEndHangJump = true;
                                                }
                                                zone.gotoAndStop("hanging");
                                            } else if(c_smartLedges) {
                                                zone.gotoAndStop("beefy_land");
                                                zone.c_skipAnim = true;
                                            }
                                        }

                                    }
                                } else if(c_smartLedges && (!zone.human || zone.npc) && !zone.nohit && !zone.c_enemyLedgeJump) {
                                    if(zone._xscale > 0 && x1 < parametric_x ||
                                    zone._xscale < 0 && x1 > parametric_x) { // is facing the ledge line
                                        zone.c_enemyLedgeJump = true;
                                        zone.speed_toss_x = zone._xscale > 0 ? 2 : -2;
                                        zone.speed_toss_y = 0;
                                        var u_distance = Math.abs(qy - (y1 + zone.body_y));
                                        var u_ledgeSpeedJump = Math.sqrt(2 * zone.gravity * u_distance) * 2/3;
                                        zone.speed_jump = -u_ledgeSpeedJump;
                                        if(!zone.beefy) {
                                            zone.dashing = false;
                                            f_AutoJumpInit(zone);
                                        } else {
                                            if(zone.npc) {
                                                zone.c_NPCBeefyJump = true;
                                            }
                                            zone.jumping = true;
                                            zone.gotoAndStop("beefy_jump");
                                        }
                                        zone.c_skipAnim = true;
                                    }
                                }
                            }
                        }
                    }
                    if(!done) {
                        var q = f_BSPHitTest(parametric_x,y1,parametric_x,y1 + 800);
                        if(q) { // up -> down
                            if(index != f_BSPCheckLastHitIndex()) {
                                var qy = y1 + (q + 0.00001) * 800;
                                n_type = f_BSPCheckLastHitType();
                                if(n_type == 4 || n_type == 5 || n_type == 6) {
                                    if(!zone.horse && !zone.hanging) {
                                        var body_y_mod = - (qy - zone.y);
                                        var body_y = qy - zone.y;
                                        if(f_SZ_OnScreenBody(parametric_x,qy,zone.n_width,zone.body_y - body_y,body_y_mod)) {
                                            if(!zone.jumping && (!zone.nohit || zone.dashing || !c_smartLedges)) {
                                                if(zone.human && !zone.npc || !c_smartLedges) {
                                                    zone.jumped = true;
                                                    zone.jumping = true;
                                                    zone.blocking = false;
                                                    zone.jump_attack = true;
                                                    if(zone.dashing) {
                                                        zone.dashjump = true;
                                                    } else {
                                                        zone.dashjump = false;
                                                    }
                                                    zone.speed_jump = 0;
                                                    zone.gotoAndStop("jump");
                                                } else { // enemy walks off ledge
                                                    if(zone._xscale > 0 && zone.x < parametric_x ||
                                                    zone._xscale < 0 && zone.x > parametric_x) {
                                                        zone.c_enemyLedgeJump = true;
                                                        zone.speed_toss_x = speed;
                                                        zone.speed_toss_y = 0;
                                                        zone.speed_jump = 0;
                                                        if(!zone.beefy) {
                                                            zone.dashing = false;
                                                            f_AutoJumpInit(zone);
                                                        } else {
                                                            if(zone.npc) {
                                                                zone.c_NPCBeefyJump = true;
                                                            }
                                                            zone.jumping = true;
                                                            zone.gotoAndStop("beefy_jump");
                                                        }
                                                        zone.c_skipAnim = true;
                                                    } else {
                                                        var u_enemyNotFacingLedge = true;
                                                    }
                                                }
                                            }
                                            if(!u_enemyNotFacingLedge) {
                                                HiFps_ResetRecursive(zone);
                                                HiFps_Reset(zone.shadow_pt);
                                                zone.x = parametric_x;
                                                zone.body_y_mod = body_y_mod;
                                                zone.body_y -= body_y;
                                                zone.y = qy;
                                                f_Depth(zone,zone.y);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        f_Depth(zone,zone.y);
                    }
                }
                break;
            case 100: // stairs
            case 101: // stairs entry
                zone.n_groundtype = 100;
                zone.x = parametric_x;
                break;
            case 200: // deathbox
                zone.n_groundtype = 200;
                zone.x = parametric_x;
                break;
            case 300: // water
                zone.n_groundtype = 300;
                zone.x = parametric_x;
                break;
            case 400: // exit
                if(zone.human && !zone.npc && !main.leash_right_x) {
                    zone.n_groundtype = 400;
                } else {
                    zone.x = parametric_x;
                }
                break;
            case 700: // function
                if(fp_FunctionLine) {
                    if(speed > 0) {
                        zone.upright = true;
                    } else {
                        zone.upright = false;
                    }
                    move_y = 0;
                    var x = zone.x;
                    zone.x = parametric_x;
                    if(!fp_FunctionLine(zone)) {
                        zone.x = x;
                    }
                }
                break;
            case 1000: // table
                if(zone.body._y < -20 && (!c_smartTables || zone.nohit || !zone.hostage && !zone.captor)) {
                    zone.n_groundtype = 1000;
                    zone.x = parametric_x;
                    zone.body_y += 20;
                    zone.body_table_y = -20;
                    move_y = 0;
                    zone.shadow_pt.gotoAndStop("off");
                    zone.shadow.gotoAndStop("on");
                    zone.shadow._y = zone.body_table_y;
                } else if(c_smartTables && (!zone.human || zone.npc) && !zone.nohit && !zone.jumping) { // enemy jumps onto table
                    if(parametric_x && (zone._xscale > 0 && zone.x < parametric_x ||
                    zone._xscale < 0 && zone.x > parametric_x)) {
                        zone.speed_toss_x = speed;
                        zone.speed_jump = - Math.sqrt(2 * zone.gravity * 20);
                        if(!zone.beefy) {
                            zone.dashing = false;
                            f_AutoJumpInit(zone);
                        } else {
                            if(zone.npc) {
                                zone.c_NPCBeefyJump = true;
                            }
                            zone.jumping = true;
                            zone.gotoAndStop("beefy_jump");
                        }
                        zone.c_skipAnim = true;
                    }
                }
                break;
            case 1001: // table (unused)
                break;
            default:
                // Error("f_PlainMCH");
                return undefined;
        }
    }
    if(move_y && ret == 0) {
        f_MoveCharV(zone,move_y,0);
    }
    return ret;
}
function f_PlainMCV(zone, speed) { // collision: smart ledges/tables, slope toggle
    var x1 = zone.x;
    var y1 = zone.y;
    var ret = 0;
    var p = f_BSPHitTest(x1,y1,x1,y1 + speed);
    if(!p) {
        zone.y += speed;
    } else {
        ret = 0.9 - p;
        if(ret < 0) {
            ret = 0;
        }
        var n_type = f_BSPCheckLastHitType();
        var index = f_BSPCheckLastHitIndex();
        var n_slope = f_BSPCheckLastHitSlope(); // for smart ledges
        var parametric_y = y1 + (p + 0.0001) * speed;
        switch(n_type) {
            case 1: // plain
            case 2: // slide
            case 3: // slope
                break;
            case 4: // ledge
            case 5: // ledge slide
            case 6: // ledge slope
                if(!zone.hostage && !zone.captor || zone.nohit || !c_smartLedges) {
                    if(speed > 0) { // up -> down
                        var q = f_BSPHitTest(x1,parametric_y,x1,parametric_y + 800);
                        if(q) {
                            if(index != f_BSPCheckLastHitIndex()) {
                                var qy = parametric_y + (q + 0.00001) * 800;
                                var n_type = f_BSPCheckLastHitType();
                                if(n_type == 500 && q * 800 < 15) {
                                    if(zone.body_y == 0) {
                                        zone.n_groundtype = n_type;
                                        zone.y = qy;
                                        zone.body_y = 0;
                                        f_ShadowSize(zone);
                                        zone.busy = true;
                                        zone.ladder = true;
                                        zone.shadow_pt.gotoAndStop("off");
                                        zone.gotoAndStop("climb");
                                    }
                                } else if(!zone.horse && !zone.hanging) {
                                    if(n_type == 4 || n_type == 5 || n_type == 6) {
                                        var wasJumping = zone.jumping;
                                        if(!zone.jumping && (!zone.nohit || !c_smartLedges)) {
                                            if(zone.human && !zone.npc || !c_smartLedges) {
                                                zone.jumped = true;
                                                zone.jumping = true;
                                                zone.blocking = false;
                                                zone.jump_attack = true;
                                                if(zone.dashing) {
                                                    zone.dashjump = true;
                                                } else {
                                                    zone.dashjump = false;
                                                }
                                                zone.speed_jump = 0;
                                            } else { // enemy walks off ledge
                                                var u_enemyJump = false;
                                                if(Math.abs(n_slope) > 0.1) {
                                                    var u_checkX = zone._xscale > 0 ? 50 : -50;
                                                    var parametric_h = f_BSPHitTest(x1,y1,x1 + u_checkX,y1);
                                                    if(parametric_h && index == f_BSPCheckLastHitIndex()) {
                                                        var parametric_x = x1 + (parametric_h + 0.001) * u_checkX;
                                                    }
                                                    if(parametric_x && (zone._xscale > 0 && zone.x < parametric_x ||
                                                    zone._xscale < 0 && zone.x > parametric_x)) {
                                                        if(zone._xscale > 0) {
                                                            zone.speed_toss_x = speed;
                                                        } else {
                                                            zone.speed_toss_x = -speed;
                                                        }
                                                        u_enemyJump = true;
                                                    } else {
                                                        var u_enemyNotFacingLedge = true;
                                                    }
                                                } else {
                                                    zone.speed_toss_x = 0;
                                                    u_enemyJump = true;
                                                }
                                                if(u_enemyJump) {
                                                    zone.c_enemyLedgeJump = true;
                                                    zone.speed_toss_y = 0;
                                                    zone.speed_jump = 0;
                                                    if(!zone.beefy) {
                                                        f_AutoJumpInit(zone);
                                                    } else {
                                                        if(zone.npc) {
                                                            zone.c_NPCBeefyJump = true;
                                                        }
                                                        zone.jumping = true;
                                                        zone.gotoAndStop("beefy_jump");
                                                    }
                                                    zone.c_skipAnim = true;
                                                }
                                            }
                                        }
                                        if(!u_enemyNotFacingLedge) {
                                            HiFps_ResetRecursive(zone);
                                            HiFps_Reset(zone.shadow_pt);
                                            zone.body_y -= qy - zone.y;
                                            zone.y = qy;
                                            if(!wasJumping && zone.human && !zone.npc && !zone.nohit || !c_smartLedges) {
                                                zone.gotoAndStop("jump");
                                            }
                                        }
                                    } else {
                                        // Error("f_PlainMCV");
                                        return undefined;
                                    }
                                }
                            }
                        }
                    } else { // down -> up
                        var q = f_BSPHitTest(x1,parametric_y,x1,parametric_y - 800);
                        if(q) {
                            var dist = (q + 0.0001) * 800;
                            var qy = parametric_y - dist;
                            var n_type = f_BSPCheckLastHitType();
                            if(n_type == 500) {
                                if(zone.body_y == 0) {
                                    if(dist < 25) {
                                        zone.pre_ladder_x = zone.x;
                                        zone.pre_ladder_y = zone.y;
                                        var oy = zone.y;
                                        zone.y = qy;
                                        zone.gotoAndStop("climb");
                                        zone.n_groundtype = n_type;
                                        f_Depth(zone,zone.y);
                                        zone.shadow_pt.gotoAndStop("off");
                                        zone.busy = true;
                                        zone.ladder = true;
                                    }
                                } else if(dist < 25) {
                                    var r = f_BSPHitTest(x1,qy,x1,qy - 800);
                                    if(r) {
                                        var dist2 = (r + 0.0001) * 800;
                                        var ry = qy - dist2;
                                        if(ry < qy + zone.body_y) {
                                            zone.pre_ladder_x = zone.x;
                                            zone.pre_ladder_y = zone.y;
                                            var oy = zone.y;
                                            zone.y = qy + zone.body_y;
                                            zone.gotoAndStop("climb");
                                            zone.n_groundtype = n_type;
                                            f_Depth(zone,zone.y);
                                            zone.body_y = 0;
                                            f_ShadowSize(zone);
                                            zone.busy = true;
                                            zone.ladder = true;
                                            zone.shadow_pt.gotoAndStop("off");
                                        }
                                    }
                                }
                            } else if(n_type == 4 || n_type == 5 || n_type == 6) {
                                if(y1 + zone.body_y < qy) {
                                    HiFps_ResetRecursive(zone);
                                    HiFps_Reset(zone.shadow_pt);
                                    zone.body_y -= qy - zone.y;
                                    zone.y = qy;
                                    f_Depth(zone,zone.y);
                                } else if(c_smartLedges && (!zone.human || zone.npc) && !zone.nohit && !zone.c_enemyLedgeJump) {
                                    var u_enemyJump = false;
                                    if(Math.abs(n_slope) > 0.1) {
                                        var u_checkX = zone._xscale > 0 ? 50 : -50;
                                        var parametric_h = f_BSPHitTest(x1,y1,x1 + u_checkX,y1);
                                        if(parametric_h && index == f_BSPCheckLastHitIndex()) {
                                            var parametric_x = x1 + (parametric_h + 0.001) * u_checkX;
                                        }
                                        if(parametric_x && (zone._xscale > 0 && x1 < parametric_x ||
                                        zone._xscale < 0 && x1 > parametric_x)) {
                                            u_enemyJump = true;
                                        }
                                    } else { // vertical ledge
                                        u_enemyJump = true;
                                    }
                                    if(u_enemyJump) {
                                        zone.c_enemyJumpV = true;
                                        zone.c_enemyLedgeJump = true;
                                        zone.speed_toss_x = 0;
                                        zone.speed_toss_y = -2;
                                        var u_distance = Math.abs(qy - (y1 + zone.body_y));
                                        var u_ledgeSpeedJump = Math.sqrt(2 * zone.gravity * u_distance);
                                        zone.speed_jump = -u_ledgeSpeedJump;
                                        if(!zone.beefy) {
                                            zone.dashing = false;
                                            f_AutoJumpInit(zone);
                                        } else {
                                            if(zone.npc) {
                                                zone.c_NPCBeefyJump = true;
                                            }
                                            zone.jumping = true;
                                            zone.gotoAndStop("beefy_jump");
                                        }
                                        zone.c_skipAnim = true;
                                    }
                                }
                            }
                        }
                    }
                }
                break;
            case 100: // stairs
            case 101: // stairs entry
                zone.n_groundtype = 100;
                zone.y = parametric_y;
                break;
            case 200: // deathbox
                zone.n_groundtype = 200;
                zone.y = parametric_y;
                break;
            case 300: // water
                zone.n_groundtype = 300;
                zone.y = parametric_y;
                break;
            case 400: // exit
                if(zone.human && !zone.npc && !main.leash_right_x) {
                    zone.n_groundtype = 400;
                } else {
                    zone.y = parametric_y;
                }
                break;
            case 700: // function
                if(fp_FunctionLine) {
                    if(speed > 0) {
                        zone.upright = false;
                    } else {
                        zone.upright = true;
                    }
                    var y = zone.y;
                    zone.y = parametric_y;
                    if(!fp_FunctionLine(zone)) {
                        zone.y = y;
                    }
                }
                break;
            case 1000: // table
                if(zone.body._y < -20 && (!c_smartTables || zone.nohit || !zone.hostage && !zone.captor)) {
                    zone.n_groundtype = 1000;
                    zone.y = parametric_y;
                    zone.body_y += 20;
                    zone.body_table_y = -20;
                    zone.shadow_pt.gotoAndStop("off");
                    zone.shadow.gotoAndStop("on");
                    zone.shadow._y = zone.body_table_y;
                } else if(c_smartTables && (!zone.human || zone.npc) && !zone.nohit && !zone.jumping) { // enemy jumps onto table
                    var u_enemyJump = false;
                    if(Math.abs(n_slope) > 0.1) {
                        var u_checkX = zone._xscale > 0 ? 50 : -50;
                        var parametric_h = f_BSPHitTest(x1,y1,x1 + u_checkX,y1);
                        if(parametric_h && index == f_BSPCheckLastHitIndex()) {
                            var parametric_x = x1 + (parametric_h + 0.001) * u_checkX;
                        }
                        if(parametric_x && (zone._xscale > 0 && zone.x < parametric_x ||
                        zone._xscale < 0 && zone.x > parametric_x)) {
                            u_enemyJump = true;
                        }
                    } else { // vertical line
                        u_enemyJump = true;
                    }
                    if(u_enemyJump) {
                        zone.c_enemyJumpV = true;
                        zone.speed_toss_x = 0;
                        zone.speed_toss_y = speed > 0 ? 1 : -1;
                        zone.speed_jump = - Math.sqrt(2 * zone.gravity * 20);
                        if(!zone.beefy) {
                            zone.dashing = false;
                            f_AutoJumpInit(zone);
                        } else {
                            if(zone.npc) {
                                zone.c_NPCBeefyJump = true;
                            }
                            zone.jumping = true;
                            zone.gotoAndStop("beefy_jump");
                        }
                        zone.c_skipAnim = true;
                    }
                }
                break;
            case 1001: // table (unused)
                break;
            default:
                // trace("f_PlainMCV");
                // Error(n_type);
                return undefined;
        }
    }
    return ret;
}
function f_PlainProjectileMove(zone, speed) { // collision: slope toggle
    var x1 = zone.x;
    var y1 = zone.y;
    var move_y = 0;
    var ret = 0;
    var p = f_BSPHitTest(x1,y1,x1 + speed,y1);
    if(!p) {
        zone.x += speed;
        if(!c_disableSlopes) {
            var n_check = true;
            var n_type = 0;
            var bottom = f_BSPHitTest(x1,y1,x1,y1 + 400) * 400;
            if(bottom) {
                n_type = f_BSPCheckLastHitType();
                if(n_type == 3 || n_type == 6) {
                    var n_slope = f_BSPCheckLastHitSlope();
                    var diff = n_slope * speed;
                    if(diff < 0) {
                        move_y = diff;
                        n_check = false;
                        zone.body._y -= diff;
                    }
                }
            }
        }
    } else {
        var n_type = f_BSPCheckLastHitType();
        var index = f_BSPCheckLastHitIndex();
        ret = 0.9 - p;
        if(ret < 0) {
            ret = 0;
        }
        var parametric_x = x1 + (p + 0.01) * speed;
        switch(n_type) {
            case 1: // plain
            case 2: // slide
            case 3: // slope
                zone.x = parametric_x;
                if(Math.abs(f_BSPCheckLastHitSlope()) > 0.1) {
                    ret = -1;
                }
                break;
            case 4: // ledge plain
            case 5: // ledge slide
            case 6: // ledge slope
                var done = false;
                var q = f_BSPHitTest(parametric_x,y1,parametric_x,y1 - 4000);
                ret = -1;
                if(q) {
                    if(index != f_BSPCheckLastHitIndex()) {
                        var qy = y1 - (q + 0.0001) * 4000;
                        var n_type = f_BSPCheckLastHitType();
                        if(n_type != 500 && n_type != 600) {
                            var diff = y1 + zone.body._y - qy;
                            if(diff < 0) {
                                HiFps_Reset(zone.shadow_pt);
                                zone.x = parametric_x;
                                zone.body._y -= qy - zone.y;
                                zone.y = qy;
                                f_Depth(zone,zone.y);
                                ret = 0;
                            }
                            done = true;
                        }
                    }
                }
                if(!done) {
                    var q = f_BSPHitTest(parametric_x,y1,parametric_x,y1 + 4000);
                    if(q) {
                        if(index != f_BSPCheckLastHitIndex()) {
                            var qy = y1 + (q + 0.0001) * 4000;
                            var n_type = f_BSPCheckLastHitType();
                            if(n_type != 500 && n_type != 600) {
                                HiFps_Reset(zone.shadow_pt);
                                zone.x = parametric_x;
                                zone.body._y -= qy - zone.y;
                                zone.y = qy;
                                f_Depth(zone,zone.y);
                                ret = 0;
                            }
                        }
                    }
                    f_Depth(zone,zone.y);
                }
                break;
            case 100: // stairs
            case 101: // stairs entry
                zone.n_groundtype = 100;
                zone.x = parametric_x;
                break;
            case 200: // deathbox
                zone.n_groundtype = 200;
                zone.x = parametric_x;
                break;
            case 300: // water
                zone.n_groundtype = 300;
                zone.x = parametric_x;
                break;
            case 400: // exit
                zone.n_groundtype = 400;
                zone.x = parametric_x;
                break;
            case 500: // ladder (unused)
            case 600: // side ladder (unused)
                // Error(n_type);
                ret = -1;
                break;
            case 700: // function
                if(fp_FunctionLineProjectile) {
                    zone.x = parametric_x;
                    if(!fp_FunctionLineProjectile(zone)) {
                        ret = -1;
                    }
                } else {
                    ret = -1;
                }
                break;
            case 1000: // table
                if(zone.body._y < -20) {
                    zone.n_groundtype = 1000;
                    zone.x = parametric_x;
                } else {
                    ret = -1;
                }
                break;
            case 1001: // table (unused)
                ret = -1;
                break;
            default:
                // Error(n_type);
                ret = -1;
        }
    }
    if(move_y && ret == 0) {
        f_ProjectileMoveY(zone,move_y);
    }
    return ret;
}
function f_TableMCH(zone, speed) { // collision: smart tables
    var x1 = zone.x;
    var y1 = zone.y;
    var ret = 0;
    var p = f_BSPHitTest(x1,y1,x1 + speed,y1);
    var n_type = f_BSPCheckLastHitType();
    if(!p) {
        zone.x += speed;
    } else if(n_type == 1000 && (!c_smartTables || zone.nohit || !zone.hostage && !zone.captor)) {
        ret = 0.9 - p;
        if(ret < 0) {
            ret = 0;
        }
        zone.x = x1 + (p + 0.001) * speed;
        if(!zone.jumping && (!zone.nohit || !c_smartTables)) {
            if(zone.human && !zone.npc || !c_smartTables) {
                zone.jumped = true;
                zone.jumping = true;
                zone.blocking = false;
                zone.hanging = false;
                zone.ladder = false;
                zone.busy = false;
                zone.jump_attack = true;
                zone.speed_jump = zone.speed_launch * 0.15;
                zone.gotoAndStop("jump");
            } else {
                zone.speed_toss_x = speed;
                zone.speed_jump = -3;
                if(!zone.beefy) {
                    f_AutoJumpInit(zone);
                } else {
                    if(zone.npc) {
                        zone.c_NPCBeefyJump = true;
                    }
                    zone.jumping = true;
                    zone.gotoAndStop("beefy_jump");
                }
                zone.c_skipAnim = true;
            }
        }
        zone.body_y += zone.body_table_y;
        zone.body_table_y = 0;
        zone.n_groundtype = 0;
        HiFps_Reset(zone.shadow_pt);
        zone.shadow_pt.gotoAndStop("on");
        f_ShadowSize(zone);
        zone.shadow.gotoAndStop("off");
    }
    return ret;
}
function f_TableMCV(zone, speed) { // collision: smart tables
    var x1 = zone.x;
    var y1 = zone.y;
    var ret = 0;
    var p = f_BSPHitTest(x1,y1,x1,y1 + speed);
    var n_type = f_BSPCheckLastHitType();
    if(!p) {
        zone.y += speed;
    } else if(n_type == 1000 && (!c_smartTables || zone.nohit || !zone.hostage && !zone.captor)) {
        ret = 0.9 - p;
        if(ret < 0) {
            ret = 0;
        }
        zone.y = y1 + (p + 0.001) * speed;
        if(!zone.jumping && (!zone.nohit || !c_smartTables)) {
            if(zone.human && !zone.npc || !c_smartTables) {
                zone.jumped = true;
                zone.jumping = true;
                zone.blocking = false;
                zone.hanging = false;
                zone.ladder = false;
                zone.busy = false;
                zone.jump_attack = true;
                zone.speed_jump = zone.speed_launch * 0.15;
                zone.gotoAndStop("jump");
            } else {
                zone.c_enemyJumpV = true;
                zone.speed_toss_x = 0;
                zone.speed_toss_y = speed;
                zone.speed_jump = -3;
                if(!zone.beefy) {
                    f_AutoJumpInit(zone);
                } else {
                    if(zone.npc) {
                        zone.c_NPCBeefyJump = true;
                    }
                    zone.jumping = true;
                    zone.gotoAndStop("beefy_jump");
                }
                zone.c_skipAnim = true;
            }
        }
        zone.body_y += zone.body_table_y;
        zone.body_table_y = 0;
        zone.n_groundtype = 0;
        HiFps_Reset(zone.shadow_pt);
        zone.shadow_pt.gotoAndStop("on");
        f_ShadowSize(zone);
        zone.shadow.gotoAndStop("off");
    }
    return ret;
}
function f_ResetLevelVars() { // collision: reset root variables
    SetFlashGlobal("g_bMap",0);
    SetFlashGlobal("g_bMenu",0);
    if(_root.main) {
        _root.main.p_cinema_clip = undefined;
    }
    _root.cinema_letterbox.active = false;
    _root.go_arrow.gotoAndStop(1);
    current_depth_mod = 99;
    total_huds = 6;
    combo_count = 0;
    combo_timer = 0;
    current_shadow = 1;
    object_index = 0;
    static_index = 0;
    kills = 0;
    kills_goal = 0;
    stuck_timer = 0;
    healthmeter.gotoAndStop(1);
    boss_fight = false;
    f_ClearUnlockDisplay();
    f_CreatePickupArray();
    _root.fp_FunctionLine = undefined;
    _root.fp_FunctionLineProjectile = undefined;
    grass = new Object();
    grass_total = 0;
    shovelspots = new Object();
    shovelspots_total = 0;
    bombspots = new Object();
    bombspots_total = 0;
    secrets = new Object();
    secrets_total = 0;
    trees = new Object();
    trees_total = 0;
    exits = new Object();
    exits_total = 0;
    ladders = new Object();
    ladders_total = 0;
    ripoffs = new Object();
    ripoffs_total = 0;
    ride_rotation = 0;
    AutoRun = false;
    level_dust = "dust_brown";
    f_ResetHudGoldCounters();
    f_SetLetterbox(true);
    // collision variables
    c_disableSlopes = false; // disables slope lines (line types 3 & 6) from affecting movement
    c_smartLedges = true; // fix buggy behavior, enemies can navigate ledges, better animations, beefy grab fix
    c_smartTables = true; // fix buggy behavior, enemies can navigate tables
}
function f_KidSettings(zone) { // collision: reset smart ledge/table variables, enemy table body_y fix
    zone.nohit = false;
    zone.falling = false;
    zone.dashing = false;
    zone.onground = false;
    zone.onfire = 1;
    zone.bounces = 0;
    zone.damage_chain = 0;
    zone.toss_clock = 0;
    zone.current_weight = zone.weight;
    zone.root = true;
    f_PunchReset(zone);
    zone.horse_move = false;
    zone.ladder = undefined;
    zone.busy = false;
    zone.spinning = false;
    zone.float_timer = 0;
    zone.sheathing = false;
    zone.blocking = false;
    zone.blocked = false;
    if(c_smartLedges) { // fix enemies not being able to interact with ledges after going up one
        zone.hanging = false;
    }
    zone.c_enemyJumpV = undefined;
    zone.c_enemyLedgeJump = undefined;
    zone.c_enemyLedgeEndHangJump = undefined;
    if(zone.grappler) {
        zone.grappler.grappler = undefined;
        zone.grappler = undefined;
    }
    if(zone.body_y >= 0) {
        zone.jumping = false;
    }
    zone.nohit = false;
    zone.onfire = 1;
    zone.onground = false;
    if(zone.health <= 0) {
        if(zone.humanoid) {
            s_Ground3.start(0,0);
            zone.alive = false;
            zone.gotoAndStop("hitground1");
        }
    }
    if(c_smartTables && zone.n_groundtype == 1000) { // fix enemy body_y being wrong for a frame after standing on table
        zone.body._y = zone.body_table_y;
    }
}
function f_StandSettings(zone) { // collision: reset smart ledge/table variables
    f_PunchReset(zone);
    zone.busy = false;
    zone.spinning = false;
    zone.damage_chain = 0;
    zone.float_timer = 0;
    zone.dashing = false;
    zone.sheathing = false;
    zone.blocking = false;
    zone.blocked = false;
    zone.horse_move = false;
    zone.toss_clock = 0;
    if(zone.grappler) {
        zone.grappler.grappler = undefined;
        zone.grappler = undefined;
    }
    zone.stunned = false;
    if(zone.body_y >= 0) {
        zone.jumping = false;
    }
    zone.hitby = undefined;
    zone.hitbydamage = undefined;
    zone.cpr = undefined;
    zone.ladder = undefined;
    zone.nohit = false;
    zone.onfire = 1;
    zone.onground = false;
    zone.current_weight = zone.weight;
    if(c_smartLedges) {
        zone.hanging = false; // fix ledge sliding bug when hit during hanging animation
    }
    zone.c_enemyJumpV = undefined;
    zone.c_enemyLedgeJump = undefined;
    zone.c_enemyLedgeEndHangJump = undefined;
    zone.c_NPCBeefyJump = undefined;
    if(zone.thrusting) {
        zone.thrusting = false;
        if(zone.prev_fp_UniqueHit) {
            zone.fp_UniqueHit = zone.prev_fp_UniqueHit;
            zone.prev_fp_UniqueHit = undefined;
        } else {
            zone.uniquehit = false;
            zone.fp_UniqueHit = undefined;
        }
    }
    f_CheckHealth(zone);
    if(!zone.jumping) {
        zone.body._y = zone.body_table_y;
    } else {
        zone.body._y = zone.body_y + zone.body_table_y;
    }
}
function f_AutoJump(zone) { // collision: smart ledge/table jumping
    f_MoveCharH(zone,zone.speed_toss_x,0);
    zone.body_y += zone.speed_jump;
    zone.body._y = zone.body_y + zone.body_table_y;
    zone.speed_jump += zone.gravity;
    if(zone.c_enemyJumpV) {
        f_MoveCharV(zone,zone.speed_toss_y,0);
    }
    if(zone.c_enemyLedgeJump) {
        if(zone.hanging) {
            zone.c_enemyJumpV = undefined;
            zone.c_enemyLedgeJump = undefined;
            zone.hanging = false;
            return undefined;
        }
    }
    if(zone.body_y >= 0) {
        zone.body_y = 0;
        zone.body._y = zone.body_y + zone.body_table_y;
        zone.shadow_pt._xscale = 100;
        zone.shadow_pt._yscale = 100;
        zone.gotoAndStop("land");
    } else {
        f_ShadowSize(zone);
        if(!zone.beefy) { // enemy beefy jump support
            if(zone.magic_jump) {
                if(zone.speed_jump - gravity <= 0 && zone.speed_jump > 0) {
                    zone.magic_jump = false;
                    zone.fp_MagicMove = f_MagicBulletDown;
                    zone.gotoAndStop("magic_air_down");
                    return undefined;
                }
            }
            if(!zone.npc && zone.prey.mount_type < 1) {
                if(Math.abs(zone.y - zone.prey.y) <= 25) {
                    if(Math.abs(zone.x - zone.prey.x) < 100 || zone.archer) {
                        if(zone.archer) {
                            if(zone.body_y - zone.speed_jump > zone.prey.body_y - 25 && zone.body_y <= zone.prey.body_y - 25) {
                                zone.fp_Ranged(zone);
                            }
                        } else if(zone.body_y - zone.speed_jump <= zone.prey.body_y - 60 && zone.body_y > zone.prey.body_y - 60) {
                            zone.punching = true;
                            zone.speed_jump = 1;
                            s_Swing4.start(0,0);
                            zone.punch_group = 11;
                            if(random(2) == 1) {
                                zone.punch_num = 2;
                                zone.gotoAndStop("punch11_2");
                            } else {
                                zone.punch_num = 1;
                                zone.gotoAndStop("punch11_1");
                            }
                        }
                    }
                }
            }
        }
    }
}
function f_EndHang(zone) { // collision: smart ledge jumping
    zone.body_y = 0;
    zone.body._y = 0;
    zone.blocking = false;
    zone.hanging = false;
    zone.busy = false;
    if(zone.c_enemyLedgeEndHangJump) {
        zone.c_enemyLedgeEndHangJump = undefined;
        zone.speed_toss_x = zone._xscale > 0 ? zone.speed : - zone.speed;
        zone.speed_jump = -20 / 3;
        f_AutoJumpInit(zone);
    } else {
        zone.speed_jump = zone.speed_launch / 3;
        zone.gotoAndStop("jump");
        zone.jumping = true;
        zone.jump_attack = true;
    }
}
function f_BeefyEnemyWalk(zone) { // collision: enemy beefy jump support
    if(zone.alive) {
        zone.enemy_spawn_timer++;
        if(zone.jumping) {
            f_AutoJump(zone);
        } else if(!_root.f_BeefyGrapple(zone)) {
            _root.f_EnemyWalkInit(zone);
            _root.f_EnemyMelee(zone);
            _root.f_EnemyClose(zone);
            _root.f_EnemyWalk(zone);
        }
    }
}
function f_NPCWalk(zone) { // collision: NPC beefy jump support
    if(!zone.prey) {
        f_NPCPickPlayer(zone);
    }
    if(zone.c_NPCBeefyJump) {
        f_AutoJump(zone);
    } else {
        if(zone.peaceful || zone.follow) {
            zone.dashing = false;
            f_FollowWalkInit(zone);
            f_EnemyClose(zone);
            f_NPCMidJump(zone);
            f_NPCWalking(zone);
        } else {
            f_EnemyWalkInit(zone);
            f_EnemyMelee(zone);
            f_EnemyClose(zone);
            f_NPCMidJump(zone);
            f_EnemyWalk(zone);
        }
    }
}
function f_Character(zone) { // collision: c_skipAnim variable
    if(!pause) {
        if(!zone.busy) {
            f_MagicMode(zone);
            f_Jump(zone);
            f_Block(zone);
            f_Walk(zone);
            if(zone.c_skipAnim) {
                // this is for calling animations in a function that stems from f_Walk,
                // as this function will override any animation call while player is standing or walking/dashing
                zone.c_skipAnim = undefined;
                return undefined;
            }
            if(!zone.hanging) {
                if(!zone.ladder) {
                    if(zone.jumping) {
                        f_Jumping(zone);
                    } else if(zone.blocking) {
                        if(zone.walking and level != 23 and level != 102) {
                            if(zone.reverse) {
                                zone.body.gotoAndStop("retreat");
                                zone.body._y = zone.body_table_y;
                            } else {
                                zone.body.gotoAndStop("walk");
                                zone.body._y = zone.body_table_y;
                            }
                        } else {
                            zone.body.gotoAndStop("stand");
                            zone.body._y = zone.body_table_y;
                        }
                    } else if(zone.dashing) {
                        zone.dashing_timer++;
                        if(zone.dashing_timer == 1 or zone.dashing_timer % 5 == 0) {
                            var u_scale = (80 + random(20)) / 100;
                            if(zone.n_groundtype < 300 or zone.n_groundtype > 302) {
                                var u_temp = f_FX(zone.x,zone.y + 1,int(zone.y) + 1,level_dust,zone._xscale * u_scale,100 * u_scale);
                                u_temp._x += random(10) - 5;
                                u_temp._y += random(4) - 2;
                            }
                        }
                        if(zone.pet.animal_type == 3 and zone.truespeed) {
                            f_AnimalRamHit(zone.pet,1);
                        }
                        zone.fp_DashAnim(zone);
                        zone.body._y = zone.body_table_y;
                    } else {
                        zone.dashing_timer = 0;
                        if(zone.walking) {
                            zone.fp_WalkAnim(zone);
                            zone.body._y = zone.body_table_y;
                        } else {
                            zone.fp_StandAnim(zone);
                            zone.body._y = zone.body_table_y;
                        }
                    }
                }
            }
            if(!zone.busy) {
                f_Punch(zone);
            }
        }
    }
}
function f_CharacterBeefy(zone) { // collision: c_skipAnim Variable
    if(!pause) {
        if(!zone.busy) {
            if(f_BeefyGrapple(zone)) {
                return undefined;
            }
            f_Jump(zone);
            f_BeefyBlock(zone);
            f_Walk(zone);
            if(zone.c_skipAnim) {
                zone.c_skipAnim = undefined;
                return undefined;
            }
            if(!zone.hanging) {
                if(!zone.ladder) {
                    if(zone.jumping) {
                        f_Jumping(zone);
                    } else if(zone.blocking) {
                        if(zone.walking) {
                            if(zone.reverse) {
                                zone.body.gotoAndStop("retreat");
                                zone.body._y = zone.body_table_y;
                            } else {
                                zone.body.gotoAndStop("walk");
                                zone.body._y = zone.body_table_y;
                            }
                        } else {
                            zone.body.gotoAndStop("stand");
                            zone.body._y = zone.body_table_y;
                        }
                    } else if(zone.dashing) {
                        zone.dashing_timer++;
                        if(zone.dashing_timer == 1 or zone.dashing_timer % 5 == 0) {
                            if(zone.n_groundtype < 300 or zone.n_groundtype > 302) {
                                var u_scale = (80 + random(20)) / 100;
                                var u_temp = f_FX(zone.x,zone.y + 1,int(zone.y) + 1,level_dust,zone._xscale * u_scale,100 * u_scale);
                                u_temp._x += random(10) - 5;
                                u_temp._y += random(4) - 2;
                            }
                        }
                        zone.fp_DashAnim(zone);
                        zone.body._y = zone.body_table_y;
                    } else {
                        zone.dashing_timer = 0;
                        if(zone.walking) {
                            zone.fp_WalkAnim(zone);
                            zone.body._y = zone.body_table_y;
                        } else {
                            zone.fp_StandAnim(zone);
                            zone.body._y = zone.body_table_y;
                        }
                    }
                }
            }
            if(!zone.busy) {
                f_Punch(zone);
            }
            f_CheckHealth(zone);
        }
    }
}
function f_EnemyWalk(zone) { // collision: c_skipAnim Variable
    if(total_players > 0) {
        if(zone.walking) {
            var u_temp = zone.x;
            var u_temp2 = zone.y;
            zone.prev_x = zone.x;
            zone.prev_y = zone.y;
            f_MoveCharH(zone,zone.temp_speed_x,0);
            if(zone.y == u_temp2 or Math.abs(zone.temp_speed_x) < 0.5) {
                f_MoveCharV(zone,zone.temp_speed_y,0);
            }
            if(zone.c_skipAnim) {
                zone.c_skipAnim = undefined;
                return undefined;
            }
            if(zone.wander) {
                if(u_temp == zone.x or u_temp2 == zone.y) {
                    zone.wander = false;
                } else if(zone.x > main.right) {
                    if(zone.temp_speed_x > 0) {
                        zone.temp_speed_x *= -1;
                    }
                } else if(zone.x < main.left) {
                    if(zone.temp_speed_x < 0) {
                        zone.temp_speed_x *= -1;
                    }
                }
            }
            if(!zone.horse) {
                zone.fp_WalkAnim(zone);
            }
            zone.body._y = zone.body_table_y;
            zone.zone.x = zone.x;
            zone.zone.w = zone.w;
        } else if(zone.standing) {
            if(!zone.horse) {
                zone.fp_StandAnim(zone);
            }
            zone.body._y = zone.body_table_y;
        }
    } else if(zone.wait_timer > 0) {
        if(!zone.horse) {
            zone.gotoAndStop("wait");
        }
        zone.body._y = zone.body_table_y;
    } else {
        zone.walking = false;
        if(!zone.horse) {
            zone.fp_StandAnim(zone);
        }
        zone.body._y = zone.body_table_y;
    }
}
function f_NPCWalking(zone) { // collision: c_skipAnim Variable
    zone.dashing = false;
    if(total_players > 0) {
        if(zone.walking or zone.ladder) {
            zone.prev_x = zone.x;
            zone.prev_y = zone.y;
            if(zone.prey.dashing) {
                zone.dashing = true;
                var x = zone.temp_speed_x * 2;
                var y = zone.temp_speed_y * 1.75;
            } else {
                var x = zone.temp_speed_x;
                var y = zone.temp_speed_y * 0.75;
            }
            zone.success_x = f_MoveCharH(zone,x,0);
            zone.success_y = f_MoveCharV(zone,y,0);
            if(!zone.success_x) {
                zone.success_x = f_MoveCharH(zone,x,0);
                if(!zone.success_y){
                    zone.success_y = f_MoveCharV(zone,y,0);
                }
            }
            if(zone.c_skipAnim) {
                zone.c_skipAnim = undefined;
                return undefined;
            }
            if(!zone.jumping and !zone.ladder and !zone.horse) {
                if(Math.abs(zone.x - zone.prev_x) < 0.5 and Math.abs(zone.y - zone.prev_y) < 0.5) {
                    zone.fp_StandAnim(zone);
                } else {
                    zone.fp_WalkAnim(zone);
                }
                zone.body._y = zone.body_table_y;
            }
        } else if(zone.standing) {
            if(!zone.jumping and !zone.ladder and !zone.horse) {
                zone.fp_StandAnim(zone);
                zone.body._y = zone.body_table_y;
            }
        }
    } else if(!zone.jumping and !zone.ladder and !zone.horse) {
        zone.fp_StandAnim(zone);
        zone.body._y = zone.body_table_y;
    }
}
