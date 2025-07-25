function f_Init(zone) {
    game.game.container = true;
    var i;
    var temp;
    switch(zone.n_state) {
        case 0:
            p_game = game.game;
            _root.p_game = game.game;
            console_version = false;
            if(!console_version) {
                p_game.gotoAndStop(2);
            } else {
                f_BSPLoadLevel("bspexample"); // load BSP from the game's "bsp" folder
            }
            p_game.gotoAndStop(2); // view collision
            break;
        case 1:
            zone.n_counter = 0;
            console_version = false;
            if(!console_version) {
                _root.f_InitLevelBSP();
                p_game.gotoAndStop(3);
            }
            _root.f_InitCamera(zone);
            f_SetPortals(); // set behavior for "exit" collision lines
            _root.f_SetEdges();
            _root.f_SetRightEdgePosition(p_game.edge_right._x);
            _root.f_SetLeftEdgePosition(p_game.edge_left._x);
            _root.f_SetBottomEdgePosition(p_game.edge_right._y);
            break;
        case 2:
            _root.level = 14;
            f_LoadLevelClips();
            break;
        case 4:
            _root.current_vehicle = 1;
            _root.total_vehicles = 0;
            _root.level_dust = "dust_brown";
            _root.level_shockwave = "shockwave";
            _root.water_default = _root.color_water;

            // define functions to be called for function lines
            _root.fp_FunctionLine = f_FunctionLine;
            _root.fp_FunctionLineProjectile = f_FunctionLine;

            _root.f_CreateShadows(30);
            i = 1;
            while(i <= _root.object_index) {
                temp = p_game["object" + i];
                if(temp.has_shadow) {
                    temp.shadow_pt = _root.f_NewShadow();
                    temp.shadow_pt._x = temp.x;
                    temp.shadow_pt._y = temp.y;
                }
                i++;
            }
            _root.f_SetDepths();
            _root.f_LevelInitSpawnPlayers();
            _root.f_PlayerArray();
            break;
        case 5:
            StopMusic();
            _root.f_ResetCamera(zone);
            _root.f_SetMainfp(f_Main);
            _root.f_ActivatePlayers();
            _root.f_HudWaitEnd();
            _root.fader.f_FadeIn();
            i = 1;
            while(i <= 4) {
                temp = p_game["p" + i];
                if(temp.alive) {
                    _root.f_WalkToInit(temp,p_game["p" + i + "_1"]._x,p_game["p" + i + "_1"]._y,temp.fp_StandAnim,true);
                }
                i++;
            }
    }
    zone.n_state++;
}
function f_Main(zone) {
    var temp;
    _root.f_UpdateCamera(zone);
    // waypoints
    var wp = zone.newwaypoint;
    if(zone.waypoint != wp) {
        // optional code block to add support for waypoints that are only triggered when moving left
        // to use, add extra condition "zone.wp_dir == -1" after the "f_GetWPHit" condition in the waypoint's hit check
        /*
        if(wp > zone.waypoint) {
            zone.wp_dir = 1;
        } else {
            zone.wp_dir = -1;
            wp++;
        }
        */
        switch(wp) {
            case 1:
                if(!f_GetWPHit(1)) {
                    f_SetWPHit(1);
                    _root.f_SetLeash(_root.main.right + 50,0,_root.main.left - 125,0);
                    temp = _root.f_SpawnBarbarian(f_GetWPX(1) - 200,f_GetWPY(1));
                    if(temp) {
                        temp.health_max = 1;
                        temp.health = temp.health_max;
                        temp.aggressiveness = 9999;
                        _root.kills_goal++;
                    }
                    _root.f_SetTargets();
                    _root.fp_SpecialEvent = f_WP1_Clear;
                }
        }
        zone.lastwaypoint = zone.waypoint;
        zone.waypoint = zone.newwaypoint;
    }
}
function f_LoadLevelClips() {
    _root.f_CreatePlayers();
    _root.f_CreateEnemies(12);
    _root.f_CreateAnimals(4);
    _root.f_CreateFX(200);
}
function f_SetPortals() {
    var i = 1;
    while(i < 10) {
        _root["portal" + i].open = false;
        i++;
    }
    _root.num_portals = 2;

    // the portal ID corresponds to the closest "door" object near the player when it hits an exit line
    // in this level's case, the exit will use "_root.portal2", since "door2" is the closest door object
    _root.portal2.open = true;
    _root.portal2.target_level = "../map/map.swf";
    _root.portal2.fp_activate = _root.f_ExitAutoRight;
    _root.portal2.spawn_portal_num = 1;
}
function f_WP1_Clear() {
    wp1Clear = true;
    return false;
}
function f_FunctionLine(zone) {
    // function line collision is enabled before wave 1 (wp1) is cleared
    if(wp1Clear) {
        return true;
    }
    return false;
}
