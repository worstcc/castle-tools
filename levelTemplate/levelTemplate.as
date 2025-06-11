function f_Init(zone) {
    _root.loader.game.game.container = true;
    var i = undefined;
    var temp = undefined;
    var n_state = zone.n_state;
    switch(n_state) {
        case 0:
            p_game = _root.loader.game.game;
            _root.p_game = _root.loader.game.game;
            console_version = false;
            if(!console_version) {
                p_game.gotoAndStop(2);
            } else {
                f_BSPLoadLevel("bsp50");
            }
            break;
        case 1:
            zone.n_counter = 0;
            console_version = false;
            if(!console_version) {
                _root.f_InitLevelBSP();
                p_game.gotoAndStop(3);
            }
            _root.f_InitCamera(zone);
            _root.f_SetEdges();
            _root.f_SetLeftEdgePosition(p_game.edgeLeft._x);
            _root.f_SetRightEdgePosition(p_game.edgeRight._x);
            _root.f_SetBottomEdgePosition(p_game.edgeLeft._y);
            break;
        case 2:
            _root.level = 13;
            f_LoadLevelClips();
            break;
        case 4:
            _root.current_vehicle = 1;
            _root.total_vehicles = 0;
            _root.level_dust = "dust_brown";
            _root.level_shockwave = "shockwave";
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
            _root.f_ResetCamera(zone);
            _root.f_SetMainfp(_root.loader.f_Main);
            _root.f_ActivatePlayers();
            _root.fader.f_FadeIn();
            _root.f_HudWaitEnd();
            if(_root.spawn_portal_num == 1) {
                i = 1;
                while(i <= 4) {
                    temp = p_game["p" + i];
                    if(temp.alive) {
                        temp.bsp_timer = -9999999; // prevent out of bounds teleporting
                        _root.f_WalkToInit(temp,p_game["p" + i + "_1"]._x,p_game["p" + i + "_1"]._y,temp.fp_StandAnim,true);
                    }
                    i++;
                }
            }
    }
    zone.n_state++;
}
function f_Main(zone) {
    _root.f_UpdateCamera(zone);
}
function f_LoadLevelClips() {
    _root.f_CreatePlayers();
    _root.f_CreateAnimals(4);
    _root.f_CreateFX(200);
}
