#include <amxmodx>
#include <cstrike>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <xs>
#include <zombieplague>

// Item Name
new const ITEM_NAME[] = "Lasermines";

// Item Cost
const ITEM_COST = 20;

// Constants
const m_pOwner = EV_INT_iuser1;
const m_pBeam = EV_INT_iuser2;
const m_rgpDmgTime = EV_INT_iuser3;
const m_flPowerUp = EV_FL_starttime;
const m_vecEnd = EV_VEC_endpos;
const m_flSparks = EV_FL_ltime;
const Float:EXPLOSION_RADIUS = 150.0;   // Explosion effect radius

const Float:KICKBACK_RADIUS = 150.0;   // How far the kickback effect reaches (e.g., 250 units)
const Float:KICKBACK_STRENGTH = 500.0; // How strong the push force is (e.g., 450 units/second)
const Float:KICKBACK_UP_LIFT = 500.0;  // Adds a bit of upward push (e.g., 100 units/second)

const MAXPLAYERS = 32;
new limit[33]
const OFFSET_CSMENUCODE = 205;

// Enums
enum _:tripmine_e
{
    TRIPMINE_IDLE1 = 0,
    TRIPMINE_IDLE2,
    TRIPMINE_ARM1,
    TRIPMINE_ARM2,
    TRIPMINE_FIDGET,
    TRIPMINE_HOLSTER,
    TRIPMINE_DRAW,
    TRIPMINE_WORLD,
    TRIPMINE_GROUND,
};

enum
{
    BEAM_POINTS = 0,
    BEAM_ENTPOINT,
    BEAM_ENTS,
    BEAM_HOSE,
};

// Tasks
const TASK_SETLASER = 100;
const TASK_DELLASER = 200;
const TASK_IDLE = 300;

// Variables
new g_iMsgBarTime;
new g_iTripmine[MAXPLAYERS+1], g_iTripmineHealth[MAXPLAYERS+1][100], bool:g_bCantPlant[MAXPLAYERS+1];
new bool:g_bGhostActive[MAXPLAYERS+1];
new g_iTripmineId, cvar_tripmine_health, cvar_tripmine_bonus;
new g_iMsgSayTxt
new g_smokeSpr
new bool:g_bShowingHUD[MAXPLAYERS+1]

public plugin_init()
{
    register_plugin("[ZP] Extra Item: Laser Tripmine", "1.0", "Lost-Souls")

    // Register Message
    g_iMsgBarTime = get_user_msgid("BarTime");

    // Register Event
    register_event("HLTV", "EventNewRound", "a", "1=0", "2=0");

    // Register Item
    g_iTripmineId = zp_register_extra_item(ITEM_NAME, ITEM_COST, ZP_TEAM_HUMAN);

    // Register Forwards
    RegisterHam(Ham_Killed, "player", "CBasePlayer_Killed_Post", 1);
    RegisterHam(Ham_TakeDamage, "player", "CBasePlayer_TakeDamage_Pre");
    RegisterHam(Ham_TakeDamage, "info_target", "Tripmine_TakeDamage_Pre");
    RegisterHam(Ham_TakeDamage, "info_target", "Tripmine_TakeDamage_Post", 1);
    RegisterHam(Ham_Killed, "info_target", "Tripmine_Killed_Post", 1);

    register_forward(FM_OnFreeEntPrivateData, "OnFreeEntPrivateData");
    register_forward(FM_TraceLine, "Tripmine_ShowInfo_Post", 1);

    // Register Think
    register_think("zp_tripmine", "Tripmine_Think");

    // Register Cvars
    cvar_tripmine_health = register_cvar("zp_tripmine_health", "600");
    cvar_tripmine_bonus = register_cvar("zp_tripmine_bonus", "5");

    g_iMsgSayTxt = get_user_msgid("SayText")
    // Register Binds
    register_concmd("+setlaser", "CmdSetLaser");
    register_concmd("-setlaser", "CmdUnsetLaser");
    register_concmd("+dellaser", "CmdDelLaser");
    register_concmd("-dellaser", "CmdUndelLaser");

    // Register Commands
    register_clcmd("say /lm", "showMenuLasermine");
    register_clcmd("say_team /lm", "showMenuLasermine");
}

public plugin_precache()
{
    precache_model("models/ls_lasermine.mdl");
    precache_model("sprites/laserbeam.spr");
    precache_sound("weapons/mine_deploy.wav");
    precache_sound("weapons/mine_charge.wav");
    precache_sound("weapons/mine_activate.wav");
    precache_sound("debris/beamstart9.wav");
    
    // Add these new precache lines
    g_smokeSpr = precache_model("sprites/steam1.spr");
    precache_sound("weapons/explode3.wav");
    precache_sound("weapons/explode4.wav");
    precache_sound("weapons/explode5.wav");
}

// The first three public fuctions below make sure that this plugin won't stop running if the modules below ain't running
public plugin_natives()
{
    set_module_filter("moduleFilter")
    set_native_filter("nativeFilter")
}

public moduleFilter(const szModule[])
{
    return PLUGIN_CONTINUE;
}

public nativeFilter(const szName[], iId, iTrap)
{
    if (!iTrap)
        return PLUGIN_HANDLED;
    
    return PLUGIN_CONTINUE;
}

public client_disconnected(this)
{
    g_iTripmine[this] = 0;
    g_bShowingHUD[this] = false;
    Tripmine_StopGhost(this);

    Tripmine_Kill(this);
    show_menu(this, 0, "^n", 1);
}

public EventNewRound()
{
    new pTripmine = -1;

    while ((pTripmine = find_ent_by_class(pTripmine, "zp_tripmine")) != 0)
        remove_entity(pTripmine);

    arrayset(g_iTripmine, 0, sizeof g_iTripmine);

    new rgpPlayers[MAXPLAYERS], iPlayersCount, pPlayer;
    get_players(rgpPlayers, iPlayersCount);

    for (new i = 0; i < iPlayersCount; i++)
    {
        pPlayer = rgpPlayers[i];
        limit[pPlayer] = 0
        g_bGhostActive[pPlayer] = false;
        g_bShowingHUD[pPlayer] = false;
        Tripmine_Kill(pPlayer);
        Tripmine_StopGhost(pPlayer);
    }
}

stock ClearTripmineHUD(id)
{
    if (g_bShowingHUD[id])
    {
        // Clear the HUD message by showing empty message
        set_hudmessage(0, 0, 0, -1.0, 0.55, 0, 0.0, 0.1, 0.0, 0.0, .channel = 1);
        show_hudmessage(id, "");
        g_bShowingHUD[id] = false;
    }
}

public CmdSetLaser(this)
{
    if (!is_user_alive(this))
        return PLUGIN_HANDLED;
    
    if (zp_get_user_zombie(this))
        return PLUGIN_HANDLED;

    if (task_exists(this+TASK_SETLASER))
        return PLUGIN_HANDLED;

    if (!g_iTripmine[this])
    {
        client_printcolor(this, "!y[!gZP!y] You do not have lasermines to plant");
        return PLUGIN_HANDLED;
    }

    if (task_exists(this+TASK_DELLASER))
        return PLUGIN_HANDLED;

    new rgpData[1];

    new pTripmine = rgpData[0] = Tripmine_Spawn(this);
    Tripmine_RelinkTripmine(pTripmine);

    if (g_bCantPlant[this])
    {
        client_printcolor(this, "!y[!gZP!y] You Can't plant a !gLasermine !yat this location!");

        Tripmine_Kill(this);
        return PLUGIN_HANDLED;
    }
    
    set_task(0.27, "TaskIdle", this+TASK_IDLE, rgpData, sizeof rgpData, "b");
    set_task(1.0, "TaskSetLaser", this+TASK_SETLASER, rgpData, sizeof rgpData);

    BarTime(this, 1);
    emit_sound(this, CHAN_ITEM, "weapons/c4_disarm.wav", VOL_NORM, ATTN_NORM, 0, PITCH_NORM);

    return PLUGIN_HANDLED;
}

public CmdUnsetLaser(this)
{
    if (!task_exists(this+TASK_SETLASER))
        return PLUGIN_HANDLED;

    Tripmine_Kill(this);
    return PLUGIN_HANDLED;
}

public CmdDelLaser(this)
{
    if (!is_user_alive(this))
        return PLUGIN_HANDLED;

    if (zp_get_user_zombie(this))
        return PLUGIN_HANDLED;

    if (task_exists(this+TASK_SETLASER))
        return PLUGIN_HANDLED;

    new iBody, pEnt;

    get_user_aiming(this, pEnt, iBody, 128);

    if (!is_valid_ent(pEnt))
        return PLUGIN_HANDLED;

    new szClassName[32];

    entity_get_string(pEnt, EV_SZ_classname, szClassName, charsmax(szClassName));

    if (!equal(szClassName, "zp_tripmine"))
        return PLUGIN_HANDLED;

    if (entity_get_int(pEnt, m_pOwner) != this)
        return PLUGIN_HANDLED;

    new rgpData[1];

    rgpData[0] = pEnt;

    set_task(1.0, "TaskDelLaser", this+TASK_DELLASER, rgpData, sizeof rgpData);
    set_task(0.27, "TaskIdle", this+TASK_IDLE, rgpData, sizeof rgpData, "b");
    
    BarTime(this, 1);
    emit_sound(this, CHAN_ITEM, "weapons/c4_disarm.wav", VOL_NORM, ATTN_NORM, 0, PITCH_NORM);

    return PLUGIN_HANDLED;
}

public CmdUndelLaser(this)
{
    if (!task_exists(this+TASK_DELLASER))
        return PLUGIN_HANDLED;

    Tripmine_Kill(this);
    return PLUGIN_HANDLED;
}

public TaskIdle(rgpData[], iTaskId)
{
    new Float:vecVelocity[3], pEnt, iBody;

    new pPlayer = iTaskId - TASK_IDLE;

    get_user_aiming(pPlayer, pEnt, iBody, 128);
    entity_get_vector(pPlayer, EV_VEC_velocity, vecVelocity);

    if (vector_length(vecVelocity) > 6.0 || task_exists(pPlayer+TASK_DELLASER) && rgpData[0] != pEnt)
        Tripmine_Kill(pPlayer);
}

public TaskSetLaser(rgpData[], iTaskId)
{
    new pPlayer = iTaskId - TASK_SETLASER;

    if (g_bCantPlant[pPlayer])
    {
        client_printcolor(pPlayer, "!y[!gRE44!y] You do not have any more lasermines");
        Tripmine_StopGhost(pPlayer);
        Tripmine_Kill(pPlayer);
        return;
    }
    
    g_iTripmine[pPlayer] -= 1;

    if (!g_iTripmine[pPlayer])
        client_printcolor(pPlayer, "!y[!gRE44!y] You do not have any more lasermines");
    else
        client_printcolor(pPlayer, "!y[!gRE44!y] You have !g%d !ymore Lasermine(s) to plant", g_iTripmine[pPlayer]);

    new pBeam = entity_get_int(rgpData[0], m_pBeam);

    remove_task(pPlayer+TASK_IDLE);

    entity_set_vector(pBeam, EV_VEC_rendercolor, Float:{0.0, 255.0, 0.0});
    entity_set_int(pBeam, EV_INT_effects, entity_get_int(pBeam, EV_INT_effects) | EF_NODRAW);

    Tripmine_Render(rgpData[0]);

    entity_set_float(rgpData[0], EV_FL_nextthink, get_gametime() + 2.5);
    entity_set_float(rgpData[0], m_flPowerUp, 1.0);
    entity_set_int(rgpData[0], EV_INT_rendermode, kRenderNormal);

    emit_sound(rgpData[0], CHAN_VOICE, "weapons/mine_deploy.wav", VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
    emit_sound(rgpData[0], CHAN_BODY, "weapons/mine_charge.wav", 0.2, ATTN_NORM, 0, PITCH_NORM);
    
    if (!g_iTripmine[pPlayer])
    {
        Tripmine_StopGhost(pPlayer);
    }
    else
    {
    // Restart ghost for next lasermine placement
        Tripmine_StartGhost(pPlayer);
    }
}

public TaskDelLaser(rgpData[], iTaskId)
{
    if (!is_valid_ent(rgpData[0]))
        return;
    
    new pPlayer = iTaskId - TASK_DELLASER;

    g_iTripmineHealth[pPlayer][g_iTripmine[pPlayer]] = floatround(entity_get_float(rgpData[0], EV_FL_health));

    remove_entity(rgpData[0]);
    remove_task(pPlayer+TASK_IDLE);

    emit_sound(pPlayer, CHAN_ITEM, "weapons/c4_disarmed.wav", VOL_NORM, ATTN_NORM, 0, PITCH_NORM);

    g_iTripmine[pPlayer]++;
    
    // Add ghost after removing a lasermine
    if (g_iTripmine[pPlayer] > 0)
    {
        Tripmine_StartGhost(pPlayer);
    }
}

public zp_user_humanized_post(this)
{
    g_iTripmine[this] = 0;
    Tripmine_StopGhost(this);
    Tripmine_Kill(this);

    // Check if array handle is valid before destroying
    new Array:hDmgTime = Array:entity_get_int(this, m_rgpDmgTime);
    if (hDmgTime != Array:0)
    {
        ArrayDestroy(hDmgTime);
    }

    new pBeam = entity_get_int(this, m_pBeam);
    if (is_valid_ent(pBeam))
    {
        remove_entity(pBeam);
    }
}

public zp_user_infected_post(this)
{
    g_iTripmine[this] = 0;
    Tripmine_StopGhost(this);
    Tripmine_Kill(this);

    // Check if array handle is valid before destroying
    new Array:hDmgTime = Array:entity_get_int(this, m_rgpDmgTime);
    if (hDmgTime != Array:0)
    {
        ArrayDestroy(hDmgTime);
    }

    new pBeam = entity_get_int(this, m_pBeam);
    if (is_valid_ent(pBeam))
    {
        remove_entity(pBeam);
    }
}

public remove_preview(id)
{
    g_iTripmine[id] = 0;
    Tripmine_StopGhost(id);
    Tripmine_Kill(id);

    // Check if array handle is valid before destroying
    new Array:hDmgTime = Array:entity_get_int(id, m_rgpDmgTime);
    if (hDmgTime != Array:0)
    {
        ArrayDestroy(hDmgTime);
    }

    new pBeam = entity_get_int(id, m_pBeam);
    if (is_valid_ent(pBeam))
    {
        remove_entity(pBeam);
    }
}

public zp_extra_item_selected(pPlayer, iItemId)
{
    if (iItemId != g_iTripmineId)
        return;

    new iHealth = get_pcvar_num(cvar_tripmine_health);
    g_iTripmineHealth[pPlayer][g_iTripmine[pPlayer]] = iHealth;
    g_iTripmine[pPlayer] += 1;
    limit[pPlayer]++
    client_printcolor(pPlayer, "!y[!gRE44!y] You Bought !g%d !yLasermine!y!", g_iTripmine[pPlayer]);

    // Start showing ghost automatically
    Tripmine_StartGhost(pPlayer);

    // Show menu automatically
    showMenuLasermine(pPlayer);
}

public CBasePlayer_Killed_Post(this)
{
    g_iTripmine[this] = 0;
    Tripmine_StopGhost(this);

    Tripmine_Kill(this);
    show_menu(this, 0, "^n", 1);
}

public CBasePlayer_TakeDamage_Pre(this, pInflictor, pAttacker, Float:flDamage)
{
    if (!FClassnameIs(pInflictor, "zp_tripmine_exp"))
        return HAM_IGNORED;

    // If victim is human, block damage (friendly fire protection)
    if (!zp_get_user_zombie(this))
        return HAM_SUPERCEDE;

    // NEW: Get the owner of the lasermine that exploded
    new iMineOwner = entity_get_int(pInflictor, EV_INT_iuser1);
    
    // NEW: If the victim is the owner, block damage
    if (this == iMineOwner)
        return HAM_SUPERCEDE;

    // Only zombies (except owner) take damage from lasermine explosions
    SetHamParamInteger(5, DMG_GENERIC);
    SetHamParamEntity(3, entity_get_int(pInflictor, EV_INT_iuser1));
    SetHamParamFloat(4, floatmax(flDamage * 6.0, 600.0));

    return HAM_HANDLED;
}

public OnFreeEntPrivateData(this)
{
    new szClassName[32];

    entity_get_string(this, EV_SZ_classname, szClassName, charsmax(szClassName));

    if (!equal(szClassName, "zp_tripmine"))
        return FMRES_IGNORED;

    // Check if array handle is valid before destroying
    new Array:hDmgTime = Array:entity_get_int(this, m_rgpDmgTime);
    if (hDmgTime != Array:0)
    {
        ArrayDestroy(hDmgTime);
    }
    
    new pBeam = entity_get_int(this, m_pBeam);
    if (is_valid_ent(pBeam))
    {
        remove_entity(pBeam);
    }
    
    return FMRES_IGNORED;
}

Tripmine_Spawn(pOwner)
{
    new pTripmine = create_entity("info_target");
    new Array:hDmgTime = ArrayCreate(1, 1);

    for (new i = 0; i < MAXPLAYERS+1; i++)
        ArrayPushCell(hDmgTime, 0.0);

    entity_set_int(pTripmine, EV_INT_movetype, MOVETYPE_FLY);
    entity_set_int(pTripmine, EV_INT_solid, SOLID_NOT);
    entity_set_model(pTripmine, "models/ls_lasermine.mdl");
    entity_set_int(pTripmine, EV_INT_body, 11);
    entity_set_int(pTripmine, EV_INT_sequence, TRIPMINE_WORLD);
    entity_set_string(pTripmine, EV_SZ_classname, "zp_tripmine");
    entity_set_size(pTripmine, Float:{-8.0, -8.0, -8.0}, Float:{8.0, 8.0, 8.0});
    entity_set_int(pTripmine, EV_INT_rendermode, kRenderTransAdd);
    entity_set_float(pTripmine, EV_FL_renderamt, 200.0);
    entity_set_int(pTripmine, m_pOwner, pOwner);
    entity_set_int(pTripmine, m_rgpDmgTime, _:hDmgTime);
    entity_set_float(pTripmine, EV_FL_health, float(g_iTripmineHealth[pOwner][g_iTripmine[pOwner] - 1]));
    entity_set_float(pTripmine, EV_FL_max_health, 600.0);
    entity_set_float(pTripmine, EV_FL_nextthink, get_gametime() + 0.02);
    
    new pBeam = Beam_BeamCreate("sprites/laserbeam.spr", 11.0);
    Beam_EntsInit(pBeam, pTripmine, pOwner);

    entity_set_vector(pBeam, EV_VEC_rendercolor, Float:{0.0, 255.0, 0.0});
    entity_set_float(pBeam, EV_FL_frame, 10.0);
    entity_set_float(pBeam, EV_FL_animtime, 255.0);
    entity_set_float(pBeam, EV_FL_renderamt, 200.0);
    entity_set_int(pTripmine, m_pBeam, pBeam);
    entity_set_int(pBeam, EV_INT_effects, entity_get_int(pBeam, EV_INT_effects));
    
    return pTripmine;
}

public Tripmine_TakeDamage_Pre(this, pInflictor, pAttacker)
{
    if (!FClassnameIs(this, "zp_tripmine"))
        return HAM_IGNORED;

    if (!is_user_alive(pAttacker))
        return HAM_SUPERCEDE;

    // Now both humans and zombies can damage lasermines
    // Remove the human restriction
    
    return HAM_IGNORED;
}

public Tripmine_TakeDamage_Post(this, pInflictor, pAttacker)
{
    if (!FClassnameIs(this, "zp_tripmine"))
        return;

    if (GetHamReturnStatus() == HAM_SUPERCEDE)
        return;

    Tripmine_Render(this);
}

public Tripmine_Killed_Post(this, pAttacker)
{
    if (!FClassnameIs(this, "zp_tripmine"))
        return;
    
    // Ensure the attacker is a valid, alive player
    if (!is_user_connected(pAttacker) || !is_user_alive(pAttacker))
        return;
    
    new szName[32];
    get_user_name(pAttacker, szName, charsmax(szName));
    
    new Float:vecOrigin[3];

    // Check if the attacker is a zombie before awarding bonus
    if (zp_get_user_zombie(pAttacker))
    {
        new iBonus = get_pcvar_num(cvar_tripmine_bonus);

        zp_set_user_ammo_packs(pAttacker, zp_get_user_ammo_packs(pAttacker) + iBonus);
        // Optional: Modified message to show the bonus amount and indicate a zombie got it.
        client_printcolor(0, "!y[!gRE44!y] !g%s (Zombie) !yhas won !g%d !yAmmoPacks for destroying a !gLasermine!y!", szName, iBonus);
    }

    entity_get_vector(this, EV_VEC_origin, vecOrigin);

    // Create enhanced explosion with effects
    CreateEnhancedExplosion(vecOrigin, 110, entity_get_int(this, m_pOwner));
    ApplyKickback(vecOrigin, KICKBACK_RADIUS, KICKBACK_STRENGTH, KICKBACK_UP_LIFT, entity_get_int(this, m_pOwner));

    // Play random explosion sound
    new iRandom = random(3);
    switch(iRandom)
    {
    case 0: emit_sound(this, CHAN_AUTO, "weapons/explode3.wav", VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
    case 1: emit_sound(this, CHAN_AUTO, "weapons/explode4.wav", VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
    case 2: emit_sound(this, CHAN_AUTO, "weapons/explode5.wav", VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
    }
}

ExplosionCreate(const Float:vecOrigin[3], iMagnitude, pAttacker = 0, bool:bDoDamage = true)
{
    new szMagnitude[11];

    new pExplosion = create_entity("env_explosion");

    formatex(szMagnitude, charsmax(szMagnitude), "%3d", iMagnitude);

    entity_set_origin(pExplosion, vecOrigin);
    entity_set_int(pExplosion, EV_INT_iuser1, pAttacker);
    entity_set_string(pExplosion, EV_SZ_classname, "zp_tripmine_exp");

    if (!bDoDamage)
        entity_set_int(pExplosion, EV_INT_spawnflags, entity_get_int(pExplosion, EV_INT_spawnflags) | SF_ENVEXPLOSION_NODAMAGE);

    DispatchKeyValue(pExplosion, "iMagnitude", szMagnitude);
    DispatchSpawn(pExplosion);

    force_use(pExplosion, pExplosion);
}

CreateEnhancedExplosion(const Float:vecOrigin[3], iMagnitude, pAttacker = 0)
{
    // Create the main explosion
    ExplosionCreate(vecOrigin, iMagnitude, pAttacker, true);
    
    // Fix: Cast vecOrigin to proper type for message_begin
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY, _, 0);
    write_byte(TE_SMOKE);
    engfunc(EngFunc_WriteCoord, vecOrigin[0]);
    engfunc(EngFunc_WriteCoord, vecOrigin[1]);
    engfunc(EngFunc_WriteCoord, vecOrigin[2]);
    write_short(g_smokeSpr);
    write_byte(30); // scale
    write_byte(12); // framerate
    message_end();
    
    // Sparks effect
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY, _, 0);
    write_byte(TE_SPARKS);
    engfunc(EngFunc_WriteCoord, vecOrigin[0]);
    engfunc(EngFunc_WriteCoord, vecOrigin[1]);
    engfunc(EngFunc_WriteCoord, vecOrigin[2]);
    message_end();
    
    // Light effect
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY, _, 0);
    write_byte(TE_DLIGHT);
    engfunc(EngFunc_WriteCoord, vecOrigin[0]);
    engfunc(EngFunc_WriteCoord, vecOrigin[1]);
    engfunc(EngFunc_WriteCoord, vecOrigin[2]);
    write_byte(20); // radius
    write_byte(255); // red
    write_byte(100); // green
    write_byte(0);   // blue
    write_byte(8);   // life
    write_byte(60);  // decay rate
    message_end();
}

public Tripmine_Think(this)
{
    static Float:flGameTime;

    flGameTime = get_gametime();
    
    if (entity_get_int(this, EV_INT_renderfx) == kRenderFxGlowShell)
    {
        static pBeam, Array:hDmgTime, Float:vecEnd[3], Float:vecSrc[3];

        pBeam = entity_get_int(this, m_pBeam);
        hDmgTime = Array:entity_get_int(this, m_rgpDmgTime);

        entity_get_vector(this, EV_VEC_origin, vecSrc);
        entity_get_vector(this, m_vecEnd, vecEnd);

        if (entity_get_float(this, m_flPowerUp) == 1.0)
        {
            static Float:vecAngles[3], Float:vecDir[3];

            entity_get_vector(this, EV_VEC_angles, vecAngles);
            entity_get_vector(this, EV_VEC_origin, vecSrc);

            MakeAimVectors(vecAngles);

            global_get(glb_v_forward, vecDir);
            xs_vec_mul_scalar(vecDir, 2048.0, vecDir);
            xs_vec_add(vecSrc, vecDir, vecEnd);
            
            entity_set_int(pBeam, EV_INT_effects, entity_get_int(pBeam, EV_INT_effects) & ~EF_NODRAW);

            Beam_PointEntInit(pBeam, vecEnd, this);

            entity_set_int(this, EV_INT_solid, SOLID_BBOX);
            entity_set_float(this, EV_FL_takedamage, DAMAGE_YES);
            entity_set_vector(this, m_vecEnd, vecEnd);
            entity_set_float(this, m_flPowerUp, 0.0);

            emit_sound(this, CHAN_VOICE, "weapons/mine_activate.wav", 0.5, ATTN_NORM, 0, 75);
        }
        
        engfunc(EngFunc_TraceLine, vecSrc, vecEnd, IGNORE_MONSTERS, this, 0);

        static Float:flFraction;

        get_tr2(0, TR_flFraction, flFraction);

        if (flFraction < 1.0)
        {
            get_tr2(0, TR_vecEndPos, vecEnd);

            entity_set_vector(pBeam, EV_VEC_origin, vecEnd);

            Beam_RelinkBeam(pBeam);
        }

        static Float:vecAbsMin[3], Float:vecAbsMax[3];

        vecAbsMin[0] = floatmin(vecEnd[0], vecSrc[0]);
        vecAbsMin[1] = floatmin(vecEnd[1], vecSrc[1]);
        vecAbsMin[2] = floatmin(vecEnd[2], vecSrc[2]);

        vecAbsMax[0] = floatmax(vecEnd[0], vecSrc[0]);
        vecAbsMax[1] = floatmax(vecEnd[1], vecSrc[1]);
        vecAbsMax[2] = floatmax(vecEnd[2], vecSrc[2]);

        static i, Float:flLastDamageTime, rgpPlayers[MAXPLAYERS], iPlayersCount, pPlayer, pOwner;

        iPlayersCount = 0;
        pOwner = entity_get_int(this, m_pOwner);

        PlayersInBox(rgpPlayers, iPlayersCount, vecAbsMin, vecAbsMax);
        for (i = 0; i < iPlayersCount; i++)
        {
            pPlayer = rgpPlayers[i];

            if (!zp_get_user_zombie(pPlayer))
                continue;

            // NEW: Skip damage if player is the owner of this lasermine
            if (pPlayer == pOwner)
                continue;

            flLastDamageTime = ArrayGetCell(hDmgTime, pPlayer);

            if (flGameTime - flLastDamageTime < 1.0)
                continue;

            ArraySetCell(hDmgTime, pPlayer, flGameTime);

            entity_get_vector(pPlayer, EV_VEC_origin, vecSrc);

            // Create a temporary weapon entity to simulate weapon damage
            new iWeapon = create_entity("weapon_knife");
            if (is_valid_ent(iWeapon)) {
                entity_set_edict(iWeapon, EV_ENT_owner, pOwner);
                ExecuteHam(Ham_TakeDamage, pPlayer, iWeapon, pOwner, 70.0, DMG_BULLET);
                remove_entity(iWeapon);
            } else {
                ExecuteHam(Ham_TakeDamage, pPlayer, this, pOwner, 70.0, DMG_BULLET);
            }
            emit_sound(pPlayer, CHAN_BODY, "debris/beamstart9.wav", VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
        }

        if (flGameTime - entity_get_float(this, m_flSparks) >= 1.0)
        {
            engfunc(EngFunc_MessageBegin, MSG_BROADCAST, SVC_TEMPENTITY, vecEnd, 0);
            {
                write_byte(TE_SPARKS);
                engfunc(EngFunc_WriteCoord, vecEnd[0]);
                engfunc(EngFunc_WriteCoord, vecEnd[1]);
                engfunc(EngFunc_WriteCoord, vecEnd[2]);
            }
            message_end();

            entity_set_float(this, m_flSparks, flGameTime);
        }
    }
    else
        Tripmine_RelinkTripmine(this);

    entity_set_float(this, EV_FL_nextthink, flGameTime + 0.023);
}

// Function to start showing ghost
Tripmine_StartGhost(pPlayer)
{
    if (g_bGhostActive[pPlayer])
        return; // Ghost already active
        
    g_bGhostActive[pPlayer] = true;
    
    // Create a ghost tripmine
    new pGhost = Tripmine_Spawn(pPlayer);
    Tripmine_RelinkTripmine(pGhost);
    
    // Set a repeating task to update ghost position
    set_task(0.1, "TaskUpdateGhost", pPlayer + 1000, _, _, "b");
}

// Function to stop showing ghost
Tripmine_StopGhost(pPlayer)
{
    if (!g_bGhostActive[pPlayer])
        return; // Ghost not active
        
    g_bGhostActive[pPlayer] = false;
    
    // Remove the ghost entity
    new pTripmine = -1;
    while ((pTripmine = find_ent_by_class(pTripmine, "zp_tripmine")))
    {
        if (entity_get_int(pTripmine, m_pOwner) != pPlayer)
            continue;
            
        if (entity_get_int(pTripmine, EV_INT_rendermode) == kRenderTransAdd)
        {
            remove_entity(pTripmine);
            break;
        }
    }
    
    // Remove the update task
    remove_task(pPlayer + 1000);
}

// Task to continuously update ghost position
public TaskUpdateGhost(iTaskId)
{
    new pPlayer = iTaskId - 1000;
    
    if (!is_user_alive(pPlayer) || !g_bGhostActive[pPlayer] || !g_iTripmine[pPlayer])
    {
        Tripmine_StopGhost(pPlayer);
        return;
    }
    
    // Find the ghost tripmine
    new pTripmine = -1;
    while ((pTripmine = find_ent_by_class(pTripmine, "zp_tripmine")))
    {
        if (entity_get_int(pTripmine, m_pOwner) != pPlayer)
            continue;
            
        if (entity_get_int(pTripmine, EV_INT_rendermode) == kRenderTransAdd)
        {
            Tripmine_RelinkTripmine(pTripmine);
            break;
        }
    }
}

Tripmine_RelinkTripmine(this)
{
    static hTr, pOwner, pBeam, pHit, Float:vecPlaneNormal[3], Float:vecSrc[3], Float:vecEnd[3];

    pOwner = entity_get_int(this, m_pOwner);
    pBeam = entity_get_int(this, m_pBeam);

    GetGunPosition(pOwner, vecSrc);
    GetAimPosition(pOwner, 128, vecEnd);

    hTr = create_tr2();

    engfunc(EngFunc_TraceLine, vecSrc, vecEnd, DONT_IGNORE_MONSTERS, pOwner, hTr);

    static iBody, Float:flVecColor[3], Float:flFraction, Float:vecAngles[3], Float:vecVelocity[3];

    get_tr2(hTr, TR_flFraction, flFraction);
    pHit = max(get_tr2(hTr, TR_pHit), 0);

    velocity_by_aim(pOwner, 128, vecVelocity);
    xs_vec_neg(vecVelocity, vecVelocity);
    vector_to_angle(vecVelocity, vecAngles);

    g_bCantPlant[pOwner] = true;
    iBody = 11;
    xs_vec_set(flVecColor, 150.0, 0.0, 0.0);

    if (flFraction < 1.0)
    {
        get_tr2(hTr, TR_vecPlaneNormal, vecPlaneNormal);
        get_tr2(hTr, TR_vecEndPos, vecEnd);

        xs_vec_mul_scalar(vecPlaneNormal, 8.0, vecPlaneNormal);
        xs_vec_add(vecEnd, vecPlaneNormal, vecEnd);
        
        if (!pHit || (is_valid_ent(pHit) && entity_get_int(pHit, EV_INT_solid) != SOLID_NOT))
        {
           vector_to_angle(vecPlaneNormal, vecAngles);

           g_bCantPlant[pOwner] = false;
           iBody = 15;
           xs_vec_set(flVecColor, 0.0, 150.0, 0.0);
        }
    }

    entity_set_vector(pBeam, EV_VEC_rendercolor, flVecColor);

    entity_set_vector(this, EV_VEC_angles, vecAngles);
    entity_set_int(this, EV_INT_body, iBody);
    entity_set_origin(this, vecEnd);

    free_tr2(hTr);
}

Tripmine_Kill(pOwner)
{
    new pTripmine = -1;
    new bool:bIsConnected = bool:(is_user_connected(pOwner));

    while ((pTripmine = find_ent_by_class(pTripmine, "zp_tripmine")))
    {
        if (entity_get_int(pTripmine, m_pOwner) != pOwner)
            continue;

        if (!bIsConnected) 
            entity_set_int(pTripmine, m_pOwner, pTripmine);

        if (entity_get_int(pTripmine, EV_INT_rendermode) != kRenderTransAdd)
            continue;

        remove_entity(pTripmine);
        break;
    }

    remove_task(pOwner+TASK_SETLASER);
    remove_task(pOwner+TASK_DELLASER);
    remove_task(pOwner+TASK_IDLE);

    if (bIsConnected)
        BarTime(pOwner, 0);
}

Tripmine_Render(this)
{
    new Float:vecColor[3];

    new iPercent = floatround((entity_get_float(this, EV_FL_health) / entity_get_float(this, EV_FL_max_health)) * 100.0); 
    vecColor[0] = float(clamp(255 - iPercent * 3, 0, 255));
    vecColor[1] = float(clamp(3 * iPercent, 0, 255));

    entity_set_int(this, EV_INT_body, 1);
    entity_set_int(this, EV_INT_renderfx, kRenderFxGlowShell);
    entity_set_vector(this, EV_VEC_rendercolor, vecColor);
    entity_set_float(this, EV_FL_renderamt, 25.0);
}

PlayersInBox(rgpPlayers[MAXPLAYERS], &iPlayersCount, const Float:vecMins[3], const Float:vecMaxs[3])
{
    static i, _rgpPlayers[MAXPLAYERS], Float:vecAbsMin[3], Float:vecAbsMax[3], _iPlayersCount, pPlayer;

    _iPlayersCount = 0;

    get_players(_rgpPlayers, _iPlayersCount, "a");

    for (i = 0; i < _iPlayersCount; i++)
    {
        pPlayer = _rgpPlayers[i];

        entity_get_vector(pPlayer, EV_VEC_absmin, vecAbsMin);
        entity_get_vector(pPlayer, EV_VEC_absmax, vecAbsMax);

        if (vecMins[0] > vecAbsMax[0] || vecMins[1] > vecAbsMax[1] || vecMins[2] > vecAbsMax[2] || 
            vecMaxs[0] < vecAbsMin[0] || vecMaxs[1] < vecAbsMin[1] || vecMaxs[2] < vecAbsMin[2])
            continue;

        rgpPlayers[iPlayersCount] = pPlayer;
        iPlayersCount++;
    }
}

Beam_BeamCreate(const szSpriteName[], Float:flWidth)
{
    new pBeam = create_entity("env_beam");

    Beam_BeamInit(pBeam, szSpriteName, flWidth);
    return pBeam;
}

Beam_BeamInit(this, const szSpriteName[], Float:flWidth)
{
    entity_set_int(this, EV_INT_flags, entity_get_int(this, EV_INT_flags) | FL_CUSTOMENTITY);
    entity_set_vector(this, EV_VEC_rendercolor, Float:{255.0, 255.0, 255.0});
    entity_set_float(this, EV_FL_renderamt, 255.0);
    entity_set_int(this, EV_INT_body, 0);
    entity_set_float(this, EV_FL_frame, 0.0);
    entity_set_float(this, EV_FL_animtime, 0.0);
    entity_set_model(this, szSpriteName);
    entity_set_float(this, EV_FL_scale, flWidth);

    entity_set_int(this, EV_INT_skin, 0);
    entity_set_int(this, EV_INT_sequence, 0);
    entity_set_int(this, EV_INT_rendermode, 0);
}

Beam_EntsInit(this, pStartEnt, pEndEnt)
{
    entity_set_int(this, EV_INT_rendermode, (entity_get_int(this, EV_INT_rendermode) & 0xF0) | (BEAM_ENTS & 0x0F));

    entity_set_int(this, EV_INT_sequence, (pStartEnt & 0x0FFF) | ((entity_get_int(this, EV_INT_sequence) & 0xF000) << 12));
    entity_set_edict(this, EV_ENT_owner, pStartEnt);

    entity_set_int(this, EV_INT_skin, (pEndEnt & 0x0FFF) | ((entity_get_int(this, EV_INT_skin) & 0xF000) << 12));
    entity_set_edict(this, EV_ENT_aiment, pEndEnt);

    entity_set_int(this, EV_INT_sequence, (entity_get_int(this, EV_INT_sequence) & 0x0FFF) | ((0 & 0xF) << 12));

    entity_set_int(this, EV_INT_skin, (entity_get_int(this, EV_INT_skin) & 0x0FFF) | ((0 & 0xF) << 12));

    Beam_RelinkBeam(this);
}

Beam_PointEntInit(this, const Float:vecStart[3], pEndEnt)
{
    entity_set_int(this, EV_INT_rendermode, (entity_get_int(this, EV_INT_rendermode) & 0xF0) | (BEAM_ENTPOINT & 0x0F));
    entity_set_vector(this, EV_VEC_origin, vecStart);
    entity_set_int(this, EV_INT_skin, (pEndEnt & 0x0FFF) | ((entity_get_int(this, EV_INT_skin) & 0xF000) << 12));
    entity_set_edict(this, EV_ENT_aiment, pEndEnt);
    entity_set_int(this, EV_INT_sequence, (entity_get_int(this, EV_INT_sequence) & 0x0FFF) | ((0 & 0xF) << 12));
    entity_set_int(this, EV_INT_skin, (entity_get_int(this, EV_INT_skin) & 0x0FFF) | ((0 & 0xF) << 12));

    Beam_RelinkBeam(this);
}

Beam_RelinkBeam(this)
{
    new Float:vecStartPos[3], Float:vecOrigin[3], Float:vecEndPos[3], Float:vecMins[3], Float:vecMaxs[3];

    Beam_GetStartPos(this, vecStartPos);
    Beam_GetEndPos(this, vecEndPos);

    vecMins[0] = floatmin(vecStartPos[0], vecEndPos[0]);
    vecMins[1] = floatmin(vecStartPos[1], vecEndPos[1]);
    vecMins[2] = floatmin(vecStartPos[2], vecEndPos[2]);

    vecMaxs[0] = floatmax(vecStartPos[0], vecEndPos[0]);
    vecMaxs[1] = floatmax(vecStartPos[1], vecEndPos[1]);
    vecMaxs[2] = floatmax(vecStartPos[2], vecEndPos[2]);

    entity_get_vector(this, EV_VEC_origin, vecOrigin);

    xs_vec_sub(vecMins, vecOrigin, vecMins);
    xs_vec_sub(vecMaxs, vecOrigin, vecMaxs);

    entity_set_vector(this, EV_VEC_mins, vecMins);
    entity_set_vector(this, EV_VEC_maxs, vecMaxs);

    entity_set_size(this, vecMins, vecMaxs);
    entity_set_origin(this, vecOrigin);
}

Beam_GetStartPos(this, Float:vecDest[3])
{
    if ((entity_get_int(this, EV_INT_rendermode) & 0x0F) == BEAM_ENTS)
    {
        new pEnt = (entity_get_int(this, EV_INT_sequence) & 0xFFF);
        entity_get_vector(pEnt, EV_VEC_origin, vecDest);
        return;
    }
    
    entity_get_vector(this, EV_VEC_origin, vecDest);
}

Beam_GetEndPos(this, Float:vecDest[3])
{
    new iBeamType = (entity_get_int(this, EV_INT_rendermode) & 0x0F);

    if (iBeamType == BEAM_HOSE || iBeamType == BEAM_POINTS)
    {
        entity_get_vector(this, EV_VEC_angles, vecDest);
        return;
    }

    new pEnt = max((entity_get_int(this, EV_INT_skin) & 0xFFF), 0);

    if (pEnt)
    {
        entity_get_vector(pEnt, EV_VEC_origin, vecDest);
        return;
    }

    entity_get_vector(this, EV_VEC_angles, vecDest);
}

GetAimPosition(this, iDistance, Float:vecDest[3])
{
    static Float:vecVelocity[3], Float:vecSrc[3];

    GetGunPosition(this, vecSrc);

    velocity_by_aim(this, iDistance, vecVelocity);
    xs_vec_add(vecSrc, vecVelocity, vecDest);
}

GetGunPosition(this, Float:vecDest[3])
{
    static Float:vecViewOfs[3], Float:vecSrc[3];

    entity_get_vector(this, EV_VEC_view_ofs, vecViewOfs);
    entity_get_vector(this, EV_VEC_origin, vecSrc);

    xs_vec_add(vecSrc, vecViewOfs, vecDest);
}

BarTime(this, iTime)
{
    message_begin(MSG_ONE, g_iMsgBarTime, .player = this)
    {
        write_short(iTime);
    }
    message_end();
}

MakeAimVectors(const Float:vecAngles[3])
{
    new Float:vecTmpAngles[3];

    xs_vec_set(vecTmpAngles, vecAngles[0], vecAngles[1], vecAngles[2]);
    vecTmpAngles[0] = -vecTmpAngles[0];

    engfunc(EngFunc_MakeVectors, vecTmpAngles);
}

FClassnameIs(this, szClassName[])
{
    new _szClassName[32];

    if (!is_valid_ent(this))
        return 0;

    entity_get_string(this, EV_SZ_classname, _szClassName, charsmax(_szClassName));

    if (equali(szClassName, _szClassName))
        return 1;

    return 0;
}

public showMenuLasermine(id)
{
    new szMenu[128];
    formatex(szMenu, charsmax(szMenu), "\yLasermine Menu");
    
    new menuid = menu_create(szMenu, "menuLasermine");
    menu_additem(menuid, "Plant a Lasermine");
    menu_additem(menuid, "Remove a Lasermine");
    menu_display(id, menuid, 0);
}

public menuLasermine(id, menuid, item)
{
    if (!is_user_alive(id))
        return PLUGIN_HANDLED;

    if (zp_get_user_zombie(id))
        return PLUGIN_HANDLED;

    switch(item)
    {
        case MENU_EXIT:
        {
            menu_destroy(menuid);
            return PLUGIN_HANDLED;
        }
        case 0:
        {
            if (!g_iTripmine[id])
            {
                client_printcolor(id, "!y[!gRE44!y] You do not have any more !gLasermines!y!");
                showMenuLasermine(id);
                return PLUGIN_HANDLED;
            }

            if (g_iTripmine[id])
            {
                CmdSetLaser(id);
            }

            showMenuLasermine(id);
        }
        case 1:
        {
            CmdDelLaser(id);
            showMenuLasermine(id);
        }
    }

    return PLUGIN_HANDLED;
}

stock print_colored(const index, const input [ ], const any:...) 
{  
    new message[191] 
    vformat(message, 190, input, 3) 
    replace_all(message, 190, "!y", "^1") 
    replace_all(message, 190, "!t", "^3") 
    replace_all(message, 190, "!g", "^4") 

    if(index) 
    { 
        //print to single person 
        message_begin(MSG_ONE, g_iMsgSayTxt, _, index) 
        write_byte(index) 
        write_string(message) 
        message_end() 
    } 
    else 
    { 
        //print to all players 
        new players[32], count, i, id 
        get_players(players, count, "ch") 
        for( i = 0; i < count; i ++ ) 
        { 
            id = players[i] 
            if(!is_user_connected(id)) continue; 

            message_begin(MSG_ONE_UNRELIABLE, g_iMsgSayTxt, _, id) 
            write_byte(id) 
            write_string(message) 
            message_end() 
        } 
    } 
} 

public Tripmine_ShowInfo_Post(Float:flVecStart[3], Float:flVecEnd[3], Conditions, id, Trace)
{
    // Ensure the player looking is connected and alive
    if (!is_user_connected(id) || !is_user_alive(id))
        return FMRES_IGNORED;

    static iHit;
    iHit = get_tr2(Trace, TR_pHit);

    // Check if we hit a valid entity
    if (pev_valid(iHit))
    {
        if (pev(iHit, pev_deadflag) == DEAD_NO)
        {
            new szClassName[32];
            pev(iHit, pev_classname, szClassName, charsmax(szClassName));

            // If we're looking at a tripmine
            if (equali(szClassName, "zp_tripmine"))
            {
                new iOwner;
                new Float:flHealth;
                new szOwnerName[32];
                new szHudMessage[128];

                // Get tripmine info
                iOwner = entity_get_int(iHit, EV_INT_iuser1);
                flHealth = entity_get_float(iHit, EV_FL_health);

                // Get owner name
                if (is_user_connected(iOwner))
                {
                    get_user_name(iOwner, szOwnerName, charsmax(szOwnerName));
                }
                else
                {
                    formatex(szOwnerName, charsmax(szOwnerName), "Disconnected");
                }

                // Format and show the HUD message
                format(szHudMessage, charsmax(szHudMessage), "Owner: %s^nHP: %d", 
                       szOwnerName, floatround(flHealth));

                set_hudmessage(0, 255, 0, -1.0, 0.55, 0, 0.0, 0.5, 0.1, 0.1, .channel = 1);
                show_hudmessage(id, szHudMessage);
                g_bShowingHUD[id] = true;
                
                return FMRES_IGNORED;
            }
        }
    }
    
    // If we reach here, we're not looking at a tripmine, so clear any existing HUD
    ClearTripmineHUD(id);
    
    return FMRES_IGNORED;
}

stock client_printcolor(const id,const input[], any:...)
{
    new msg[191], players[32], count = 1; vformat(msg,190,input,3);
    replace_all(msg,190,"!g","^4");    // green
    replace_all(msg,190,"!y","^1");    // normal
    replace_all(msg,190,"!t","^3");    // team
    
    if (id) players[0] = id; else get_players(players,count,"ch");
    
    for (new i=0;i<count;i++)
    {
        if (is_user_connected(players[i]))
        {
            message_begin(MSG_ONE_UNRELIABLE,get_user_msgid("SayText"),_,players[i]);
            write_byte(players[i]);
            write_string(msg);
            message_end();
        }
    }
}

// ------------------------------------------------------------------------------------
// --- NEW FUNCTION: ApplyKickback ---
// This function will push players away from the explosion origin.
// ------------------------------------------------------------------------------------
stock ApplyKickback(const Float:vecExplosionOrigin[3], Float:flRadius, Float:flStrength, Float:flUpLift, iMineOwner)
{
    // Get all connected players (excluding HLTV)
    new rgPlayers[MAXPLAYERS], iNumPlayers;
    get_players(rgPlayers, iNumPlayers, "ch"); 

    for (new i = 0; i < iNumPlayers; i++)
    {
        new id = rgPlayers[i];

        // Ensure the player is alive
        if (!is_user_alive(id))
            continue;

        // Optional: Prevent the mine owner from being kicked back by their own mine
        // if (id == iMineOwner)
        //    continue;

        // Get the player's current position
        new Float:vecPlayerOrigin[3];
        entity_get_vector(id, EV_VEC_origin, vecPlayerOrigin);

        // Calculate the distance from the explosion to the player
        new Float:flDistance = vector_distance(vecExplosionOrigin, vecPlayerOrigin);

        // Check if the player is within the kickback radius
        if (flDistance <= flRadius && flDistance > 0.0) // flDistance > 0.0 to avoid division by zero if player is at exact explosion spot
        {
            new Float:vecDirToPlayer[3];
            // Calculate direction vector from explosion to player
            xs_vec_sub(vecPlayerOrigin, vecExplosionOrigin, vecDirToPlayer); 

            // Normalize the direction vector (make its length 1.0)
            // vector_normalize() could also be used if available and preferred, but manual normalization is fine.
            new Float:flVecLength = vector_length(vecDirToPlayer);
            if (flVecLength == 0.0) continue; // Should be caught by flDistance > 0.0, but as a safeguard
            
            xs_vec_div_scalar(vecDirToPlayer, flVecLength, vecDirToPlayer); // vecDirToPlayer is now normalized

            // Calculate the kickback velocity vector
            new Float:vecKickVelocity[3];
            xs_vec_mul_scalar(vecDirToPlayer, flStrength, vecKickVelocity); 

            // Add the upward lift component
            vecKickVelocity[2] += flUpLift;

            // Get the player's current velocity
            new Float:vecCurrentVelocity[3];
            entity_get_vector(id, EV_VEC_velocity, vecCurrentVelocity);
            
            // Add the kickback velocity to the player's current velocity
            // This makes the kickback an impulse, respecting existing momentum.
            xs_vec_add(vecCurrentVelocity, vecKickVelocity, vecCurrentVelocity); 
            
            // Apply the new velocity to the player
            set_pev(id, pev_velocity, vecCurrentVelocity);
        }
    }
}