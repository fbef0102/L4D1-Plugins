#define PLUGIN_VERSION	"2.0"

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <colors>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#include <l4d_lib>

#define debug		0

#define PRESENT			"%"

#define NULL					-1
#define BOSSES				2
#define TANK_PASS_TIME		(g_fCvarTankSelectTime + 1.0)

#define CVAR_FLAGS			FCVAR_PLUGIN|FCVAR_NOTIFY

enum DATA
{
	INDEX,
	DMG,
	WITCH = 0,
	TANK
}

public Plugin:myinfo =
{
	name = "l4d_tank_witch_damage_announce_spawnAnnouncer",
	author = "raziEiL [disawar1],l4d1 modify by Harry Potter",
	description = "Bosses dealt damage announcer and Announce in chat and via a sound when a Tank/Witch has spawned",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/raziEiL"
}

forward TP_OnTankPass(old_tank, new_tank);

static		Handle:g_hTankHealth, Handle:g_hVsBonusHealth, Handle:g_hDifficulty, Handle:g_hGameMode, bool:g_bCvarSkipBots, g_iCvarHealth[BOSSES],
			g_iDamage[MAXPLAYERS+1][MAXPLAYERS+1][BOSSES], g_iWitchIndex[MAXPLAYERS+1], g_iTotalDamage[MAXPLAYERS+1][BOSSES],
			bool:bTempBlock, g_iLastKnownTank, bool:g_bTankInGame, Handle:g_hTrine, g_iCvarFlags, g_iCvarPrivateFlags,
			bool:g_bNoHrCrown[MAXPLAYERS+1], g_iWitchCount, bool:g_bCvarRunAway, g_iWitchRef[MAXPLAYERS+1];
new control_time;
new                     g_iLastTankHealth           = 0;                // Used to award the killing blow the exact right amount of damage
new bool:g_bIsTankAlive;
new g_TankOtherDamage = 0;
new g_bCvarSurvLimit;
static bool:resuce_start = false;

public OnMapStart()
{
	PrecacheSound("ui/pickup_secret01.wav");
}

public OnPluginStart()
{
	g_hTankHealth		= FindConVar("z_tank_health");
	g_hVsBonusHealth	= FindConVar("versus_tank_bonus_health");
	g_hDifficulty		= FindConVar("z_difficulty");
	g_hGameMode			= FindConVar("mp_gamemode");

	new Handle:hCvarWitchHealth			= FindConVar("z_witch_health");
	new Handle:hCvarSurvLimit			= FindConVar("survivor_limit");

	new Handle:hCvarFlags		= CreateConVar("prodmg_announce_flags",		"3", "What stats get printed to chat. Flags: 0=disabled, 1=witch, 2=tank, 3=all", CVAR_FLAGS, true, 0.0, true, 3.0);
	new Handle:hCvarSkipBots	= CreateConVar("prodmg_ignore_bots",			"0", "If set, bots stats won't get printed to chat", CVAR_FLAGS, true, 0.0, true, 1.0);
	new Handle:hCvarPrivate		= CreateConVar("prodmg_announce_private",	"0", "If set, stats wont print to public chat. Flags (add together): 0=disabled, 1=witch, 2=tank, 3=all", CVAR_FLAGS, true, 0.0, true, 3.0);
	new Handle:hCvarRunAway		= CreateConVar("prodmg_failed_crown",		"1", "If set, witch stats at round end won't print if she isn't killed", CVAR_FLAGS, true, 0.0, true, 1.0);

	g_iCvarHealth[TANK]	= RoundFloat(FloatMul(GetConVarFloat(g_hTankHealth), IsVersusGameMode() ? GetConVarFloat(g_hVsBonusHealth) : GetCoopMultiplie()));
	g_iCvarHealth[WITCH]	= GetConVarInt(hCvarWitchHealth);
	g_bCvarSurvLimit			= GetConVarInt(hCvarSurvLimit);
	g_iCvarFlags				= GetConVarInt(hCvarFlags);
	g_bCvarSkipBots			= GetConVarBool(hCvarSkipBots);
	g_bCvarRunAway			= GetConVarBool(hCvarRunAway);

	HookConVarChange(g_hDifficulty,			OnConvarChange_TankHealth);
	HookConVarChange(g_hTankHealth,			OnConvarChange_TankHealth);
	HookConVarChange(g_hGameMode,			OnConvarChange_TankHealth);
	HookConVarChange(g_hVsBonusHealth,		OnConvarChange_TankHealth);
	HookConVarChange(hCvarWitchHealth,		OnConvarChange_WitchHealth);
	HookConVarChange(hCvarSurvLimit,		OnConvarChange_SurvLimit);
	HookConVarChange(hCvarFlags,				OnConvarChange_Flags);
	HookConVarChange(hCvarSkipBots,			OnConvarChange_SkipBots);
	HookConVarChange(hCvarPrivate,			OnConvarChange_Private);
	HookConVarChange(hCvarRunAway,			OnConvarChange_RunAway);

	HookEvent("round_start",			PD_ev_RoundStart,		EventHookMode_PostNoCopy);//每回合開始就發生的event
	HookEvent("round_end",			PD_ev_RoundEnd,			EventHookMode_PostNoCopy);
	HookEvent("tank_spawn",			PD_ev_TankSpawn,		EventHookMode_PostNoCopy);
	HookEvent("witch_spawn",			PD_ev_WitchSpawn);
	HookEvent("tank_frustrated",		PD_ev_TankFrustrated);
	HookEvent("witch_killed",			PD_ev_WitchKilled);
	HookEvent("entity_killed",		PD_ev_EntityKilled);
	HookEvent("player_hurt",			PD_ev_PlayerHurt);
	HookEvent("infected_hurt",		PD_ev_InfectedHurt);
	HookEvent("player_bot_replace",	PD_ev_PlayerBotReplace);
	HookEvent("finale_start", Event_Finale_Start);
	
	g_hTrine = CreateTrie();
	
	AutoExecConfig(true, "l4d_tank_witch_damage_announce");
	control_time=1;
}

public Action:PD_ev_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	//LogMessage("Now round_start event");
	resuce_start = false;
	g_bIsTankAlive = false;
	g_iLastTankHealth = 0;
	g_TankOtherDamage = 0;
	bTempBlock = false;
	g_bTankInGame = false;
	g_iLastKnownTank = 0;
	g_iWitchCount = 0;
	control_time = 1;
	ClearTrie(g_hTrine);

	for (new i; i <= MAXPLAYERS; i++){

		for (new elem; elem <= MAXPLAYERS; elem++){

			g_iDamage[i][elem][TANK] = 0;
			g_iDamage[i][elem][WITCH] = 0;
		}

		g_iTotalDamage[i][TANK] = 0;
		g_iTotalDamage[i][WITCH] = 0;
		g_iWitchRef[i] = INVALID_ENT_REFERENCE;
		g_iWitchIndex[i] = 0;
		g_bNoHrCrown[i] = false;
	}
}

public Action:PD_ev_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	control_time = 1;
	if (bTempBlock || !g_iCvarFlags) return;

	bTempBlock = true;
	g_bTankInGame = false;

	decl String:sName[32];

	if (g_iCvarFlags & (1 << _:TANK)){

		new iTank = IsTankInGame();
		if (iTank && !g_iTotalDamage[iTank][TANK]){

			GetClientName(iTank, sName, 32);
			if(g_bIsTankAlive&& IsClientAndInGame(iTank)&& GetClientTeam(iTank) == 3 && IsPlayerTank(iTank) ) 
			{
				CPrintToChatAll("{green}[提示] Tank {default}({red}%s{default}) had {red}%d {default}health remaining", IsFakeClient(iTank) ? "AI" : sName, g_iLastTankHealth);
				g_bIsTankAlive = false;
			}
		}
	}

	for (new i; i <= MaxClients; i++){

		if (g_iTotalDamage[i][TANK]){
			if( g_bIsTankAlive&& IsClientAndInGame(i)&& GetClientTeam(i) == 3 && IsPlayerTank(i) ){
				CPrintToChatAll("{green}[提示] Tank{default} had {red}%d {default}health remaining", g_iLastTankHealth);
				
				PrintDamage(i, true, false,0);
				//g_bIsTankAlive = false;
			}
		}
		
		if (g_iTotalDamage[i][WITCH]){

			if (g_bCvarRunAway && g_iWitchRef[i] != INVALID_ENT_REFERENCE && EntRefToEntIndex(g_iWitchRef[i]) == INVALID_ENT_REFERENCE) continue;

			//CPrintToChatAll("{green}[提示] 妹子{default} had {red}%d {default}health remaining", g_iCvarHealth[WITCH] - g_iTotalDamage[i][WITCH]);
			PrintDamage(i, false, false,5);
		}
		
	}
	g_iLastTankHealth = 0;
	g_TankOtherDamage = 0;
}
// Tank
public OnClientPutInServer(client)
{
	if (g_bTankInGame && g_iCvarFlags & (1 << _:TANK) && client){

		if (!IsFakeClient(client)){

			decl String:sName[32], String:sIndex[16];
			GetClientName(client, sName, 32);
			IntToString(client, sIndex, 16);
			SetTrieString(g_hTrine, sIndex, sName);
		}
		else
			CreateTimer(0.0, PD_t_CheckIsInf, client);
	}
}

public Action:PD_t_CheckIsInf(Handle:timer, any:client)
{
	if (IsClientInGame(client) && IsFakeClient(client)){

		decl String:sName[32];
		GetClientName(client, sName, 32);

		if (StrContains(sName, "Smoker") != -1 || StrContains(sName, "Boomer") != -1 || StrContains(sName, "Hunter") != -1) return;

		decl String:sIndex[16];
		IntToString(client, sIndex, 16);
		SetTrieString(g_hTrine, sIndex, sName);
	}
}

public Action:PD_ev_TankSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(resuce_start)
	{
		new Handle:BlockFirstTank = FindConVar("no_final_first_tank");
		if(BlockFirstTank != INVALID_HANDLE)
		{
			if(GetConVarInt(BlockFirstTank) == 1)
			{
				resuce_start = false;
				return;
			}
		}
	}
	if (!g_bIsTankAlive)
	{
		g_TankOtherDamage = 0;
		g_bIsTankAlive = true;
		PrintToChatAll("\x04[提示] Tank\x01 has spawned!");
		EmitSoundToAll("ui/pickup_secret01.wav");
	}
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	control_time = 1;
	if (!g_bTankInGame && g_iCvarFlags & (1 << _:TANK)){

		decl String:sName[32], String:sIndex[16];

		for (new i = 1; i <= MaxClients; i++){

			if (!IsClientInGame(i) || (IsFakeClient(i) && GetClientTeam(i) == 3)) continue;

			IntToString(i, sIndex, 16);
			GetClientName(i, sName, 32);
			SetTrieString(g_hTrine, sIndex, sName);

			#if debug
				LogMessage("push to trine. %s (%s)", sIndex, sName);
			#endif
		}
		g_iLastTankHealth = GetClientHealth(client);
		//LogMessage("g_iLastTankHealth is %d",g_iLastTankHealth);
	}

	g_bTankInGame = true;
}

public Action:PD_ev_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (bTempBlock || !(g_iCvarFlags & (1 << _:TANK))||!g_bIsTankAlive) return;
	
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (IsClientAndInGame(victim) && IsClientAndInGame(attacker) && GetClientTeam(attacker) == 2  && GetClientTeam(victim) == 3){
	
		if (!IsPlayerTank(victim) || g_iTotalDamage[victim][TANK] == g_iCvarHealth[TANK]) return;
		
		if (g_iLastKnownTank)
			CloneStats(victim);
			
		new iDamage = GetEventInt(event, "dmg_health");
		
		decl String:weapon[16];
		GetEventString(event, "weapon", weapon, sizeof(weapon));	
		g_iLastTankHealth = GetEventInt(event,"health");
		if (StrEqual(weapon, "hunting_rifle"))
		{
			//new newdmg = GetConVarInt(FindConVar("l4d_huntingrifle_tank_dmg"));
			new newdmg = 135;
			new originalhealth = g_iLastTankHealth + iDamage;
			if(originalhealth - newdmg <= 0)
			{
				iDamage = originalhealth;
				g_iLastTankHealth = 0;
			}
			else
			{
				iDamage = newdmg;
				g_iLastTankHealth = originalhealth - newdmg;
			}
		}
		g_iDamage[attacker][victim][TANK] += iDamage;
		g_iTotalDamage[victim][TANK] += iDamage;
		
		#if debug
			LogMessage("#1. total %d dmg %d (%N, health %d)", g_iTotalDamage[victim][TANK], iDamage, victim, GetEventInt(event, "health"));
		#endif

		CorrectDmg(attacker, victim, true);
			
		new type = GetEventInt(event,"type");
		//PrintToChatAll("GetEventInt(event,type) is %d",GetEventInt(event,"type"));
		if(type == 131072) g_iLastTankHealth = 0 ;
		//LogMessage("g_iLastTankHealth is %d ",g_iLastTankHealth);
		return;
	}
	if(IsClientAndInGame(victim)&& GetClientTeam(victim) == 3&&IsPlayerTank(victim))
	{
		new iDamage = GetEventInt(event, "dmg_health");
		new type = GetEventInt(event,"type");
		//PrintToChatAll("GetEventInt(event,type) is %d",GetEventInt(event,"type"));
		if(  iDamage<=10 && type != 8 && type != 268435464 ) return;//GetEventInt(event,"type")= 8 被火傷到 268435464:著火 131072:死亡動畫時	iDamage<=10為不明傷害
		if(type == 131072){g_iLastTankHealth = 0 ;return;}
		g_TankOtherDamage += iDamage;
		g_iLastTankHealth = GetEventInt(event,"health");
		//PrintToChatAll("g_iLastTankHealth is %d ,g_TankOtherDamage is %d",g_iLastTankHealth,g_TankOtherDamage);
		if (g_iTotalDamage[victim][true] + g_TankOtherDamage> g_iCvarHealth[true]){
			new iDiff = g_iTotalDamage[victim][true] + g_TankOtherDamage - g_iCvarHealth[true];
			g_TankOtherDamage -= iDiff;
		}
	}
}

CloneStats(client)
{
	if (client && client != g_iLastKnownTank){

		#if debug
			LogMessage("clone tank stats %N -> %N", g_iLastKnownTank, client);
		#endif

		for (new i; i <= MaxClients; i++){

			if (g_iDamage[i][g_iLastKnownTank][TANK]){

				g_iDamage[i][client][TANK] = g_iDamage[i][g_iLastKnownTank][TANK];
				g_iDamage[i][g_iLastKnownTank][TANK] = 0;
			}
		}

		g_iTotalDamage[client][TANK] = g_iTotalDamage[g_iLastKnownTank][TANK];
		g_iTotalDamage[g_iLastKnownTank][TANK] = 0;
	}
	#if debug
	else
		LogMessage("don't clone tank stats %N -> %N", g_iLastKnownTank, client);
	#endif

	g_iLastKnownTank = 0;
}

public Action:PD_ev_EntityKilled(Handle:event, const String:name[], bool:dontBroadcast)
{
	decl client;
	if (!bTempBlock && g_bTankInGame && g_iCvarFlags & (1 << _:TANK) && IsPlayerTank((client = GetEventInt(event, "entindex_killed"))))
	{
		if (g_iTotalDamage[client][TANK])
		{
			if(g_bIsTankAlive){
				PrintDamage(client, true);
				g_bIsTankAlive = false;
				g_TankOtherDamage = 0;
				g_bTankInGame = false;
			}
		}
		else //
		{
			//PrintToChatAll("\x04[提示] Tank \x01自爆了(也許卡住了).");
			//PrintDamage(client, true);
			CreateTimer(1.5, PD_t_FindAnyTank, _, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public Action:PD_t_FindAnyTank(Handle:timer, any:client)
{
	if(!IsTankInGame())
	{
		g_bIsTankAlive = false;
		g_TankOtherDamage = 0;
		g_bTankInGame = false;
	}
}

IsTankInGame(exclude = 0)
{
	for (new i = 1; i <= MaxClients; i++)
		if (exclude != i && IsClientInGame(i) && GetClientTeam(i) == 3 && IsPlayerTank(i) && IsInfectedAlive(i) && !IsIncapacitated(i))
			return i;

	return 0;
}

public Action:PD_ev_PlayerBotReplace(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (bTempBlock || g_bCvarSurvLimit==1 || !(g_iCvarFlags & (1 << _:TANK))) return;

	// tank leave?
	new client = GetClientOfUserId(GetEventInt(event, "player"));

	if (!g_iLastKnownTank && g_iTotalDamage[client][TANK]){

		#if debug
			LogMessage("tank %N leave inf team!", client);
		#endif

		g_iLastKnownTank = client;
		CloneStats(GetClientOfUserId(GetEventInt(event, "bot")));
	}
}

public Action:PD_ev_TankFrustrated(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (bTempBlock || !(g_iCvarFlags & (1 << _:TANK))) return;

	#if debug
		LogMessage("TankFrustrated fired (pass time %f sec)", TANK_PASS_TIME);
	#endif

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IsClientInGame(client)) return;

	if (g_bCvarSurvLimit!=1){
		if(GetConVarInt(FindConVar("rotoblin_enable_2v2"))==1)//rotoblin_enable_2v2=1為AI會被處死
			CreateTimer(1.0, CheckForAITank, client, TIMER_FLAG_NO_MAPCHANGE);
		g_iLastKnownTank = client;
		if(control_time == 2)
		{
			//CPrintToChatAll("{green}[提示] {red}特感隊伍{default}已經失去了兩次{green}Tank{default}控制權機會!");
			control_time=1;
			return;
		}
		//LogMessage("特感失去第%d次控制權!",control_time);	
		control_time++;
		return;
	}

	// 1v1
	CreateTimer(1.0,CheckForAITank,client);
}

public Action:CheckForAITank(Handle:timer,any:client)//passing to AI
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsValidEdict(i)&&IsPlayerTank(i))
		{
			if (IsInfected(client)&&IsFakeClient(i))//Tank is AI
			{
				g_bTankInGame = false;
					
				CPrintToChatAll("{green}[提示] Tank{default} ({red}%N{default}) 迷路失去控制權了.", client);
				CPrintToChatAll("{green}[提示]{default} He had {red}%d {default}health remaining", g_iLastTankHealth);
	
				if (g_iTotalDamage[client][TANK])//人類沒有造成任何傷害就不印
					PrintDamage(client, true, false);
				g_bIsTankAlive = false;
				g_TankOtherDamage = 0;
			}
			return Plugin_Handled;
		}
	}
	return Plugin_Handled;
}

public TP_OnTankPass(old_tank, new_tank)
{
	if (bTempBlock || !(g_iCvarFlags & (1 << _:TANK)) || g_bCvarSurvLimit==1) return;

	g_iLastKnownTank = old_tank;
}

// Witch
public Action:PD_ev_WitchSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
		for (new i = 1; i <= MaxClients; i++) 
			if (IsClientConnected(i) && IsClientInGame(i)&& !IsFakeClient(i) && (GetClientTeam(i) == 1 || GetClientTeam(i) == 3) )
				CPrintToChat(i, "{green}[提示]{red} 妹子{default} has spawned!");
		CreateTimer(0.5, PD_t_EnumThisWitch, EntIndexToEntRef(GetEventInt(event, "witchid")), TIMER_FLAG_NO_MAPCHANGE);
}

public Action:PD_t_EnumThisWitch(Handle:timer, any:entity)
{
	new ref = entity;
	if ((entity = EntRefToEntIndex(entity)) != INVALID_ENT_REFERENCE && g_iWitchCount < MAXPLAYERS){

		g_iWitchRef[g_iWitchCount] = ref;

		decl String:sWitchName[8];
		FormatEx(sWitchName, 8, "%d", g_iWitchCount++);
		DispatchKeyValue(entity, "targetname", sWitchName);
	}
}

public Action:PD_ev_InfectedHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (bTempBlock || !(g_iCvarFlags & (1 << _:WITCH))) return;

	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	decl iWitchEnt;
	if (IsWitch((iWitchEnt = GetEventInt(event, "entityid"))) && IsClientAndInGame(attacker) && GetClientTeam(attacker) == 2){

		new iIndex = GetWitchIndex(iWitchEnt);
		if (iIndex == NULL) return;

		if (!g_bNoHrCrown[iIndex] && GetEventInt(event, "amount") != 90)
			g_bNoHrCrown[iIndex] = true;

		if (g_iTotalDamage[iIndex][WITCH] == g_iCvarHealth[WITCH]) return;

		new iDamage = GetEventInt(event, "amount");

		g_iDamage[attacker][iIndex][WITCH] += iDamage;
		g_iTotalDamage[iIndex][WITCH] += iDamage;

		#if debug
			LogMessage("%d (Witch: indx %d, elem %d)", g_iTotalDamage[iIndex][WITCH], iWitchEnt, iIndex);
		#endif

		CorrectDmg(attacker, iIndex, false);
	}
}

GetWitchIndex(entity)
{
	decl String:sWitchName[8];
	GetEntPropString(entity, Prop_Data, "m_iName", sWitchName, 8);
	if (strlen(sWitchName) != 1) return -1;

	return StringToInt(sWitchName);
}
// ---

CorrectDmg(attacker, iIndex, bool:bTankBoss)
{
	if (g_iTotalDamage[iIndex][bTankBoss] + g_TankOtherDamage> g_iCvarHealth[bTankBoss]){
		new iDiff = g_iTotalDamage[iIndex][bTankBoss] + g_TankOtherDamage - g_iCvarHealth[bTankBoss];

		#if debug
			LogMessage("dmg corrected %d. total dmg %d", iDiff, g_iTotalDamage[iIndex][bTankBoss]);
		#endif

		g_iDamage[attacker][iIndex][bTankBoss] -= iDiff;
		g_iTotalDamage[iIndex][bTankBoss] -= iDiff;
	}
}

public Action:PD_ev_WitchKilled(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!(g_iCvarFlags & (1 << _:WITCH))) return;

	new iIndex = GetWitchIndex(GetEventInt(event, "witchid"));
	if (iIndex == NULL || !g_iTotalDamage[iIndex][WITCH]) return;

	//new killer = GetClientOfUserId(GetEventInt(event, "userid"));
	//if(!IsClientConnected(killer) || !IsClientInGame(killer) || GetClientTeam(killer) != 2) return;	
	//PrintDamage(iIndex, false, _, !g_bNoHrCrown[iIndex] ? 2 : GetEventInt(event, "oneshot"));
	PrintDamage(iIndex, false, _, GetEventInt(event, "oneshot"));
	g_bNoHrCrown[iIndex] = false;
}

PrintDamage(iIndex, bool:bTankBoss, bool:bLoose = false, iCrownTech = 0)
{
	decl String:tankplayerName[32];
	new bool:istankAI = false;
	if(bTankBoss)
	{
		GetClientName(iIndex,tankplayerName, 32);
		if(StrEqual(tankplayerName,"Tank"))
			istankAI =true;
	}
	
	decl iClient[MAXPLAYERS+1][BOSSES];
	new iSurvivors;
		
	for (new i = 1; i <= MaxClients; i++){

		if (!g_iDamage[i][iIndex][bTankBoss]) continue;

		if (!bTankBoss && IsClientInGame(i) || bTankBoss){

			if ((g_bCvarSkipBots && IsClientInGame(i) && !IsFakeClient(i)) || !g_bCvarSkipBots){

				iClient[iSurvivors][INDEX] = i;
				iClient[iSurvivors][DMG] = g_iDamage[i][iIndex][bTankBoss];
				iSurvivors++;
			}
		}
		// reset var
		g_iDamage[i][iIndex][bTankBoss] = 0;
	}
	if (!iSurvivors) return;

	if (iSurvivors == 1 && !bLoose){

		if (bTankBoss){
			/*
			if(istankAI)
				CPrintToChatAll("{green}[提示]{blue} %N {default}dealt {olive}%d {default}damage to {green}Tank{default} ({red}AI{default}).",iClient[0][INDEX],iClient[0][DMG]);
			else
				CPrintToChatAll("{green}[提示]{blue} %N {default}dealt {olive}%d {default}damage to {green}Tank{default} ({red}%s{default}).",iClient[0][INDEX],iClient[0][DMG],tankplayerName);
			*/
			CPrintToChatAll("{green}[提示] {blue}%N {default}dealt {olive}%d {default}damage to{green} Tank", iClient[0][INDEX], iClient[0][DMG]);
			g_bIsTankAlive = false;
		}
		else{

			if (IsIncapacitated(iClient[0][INDEX])){//只有一位玩家造成妹子傷害, 反被witch incap/秒殺(Jerkstored crown)
				//CPrintToChatAll("{green}[提示]{blue} %N {default}反被 {green}妹子 {olive}爆☆殺{default}.", iClient[0][INDEX]);
			}
			else
			{
				if( iCrownTech==1)
					CPrintToChatAll("{green}[提示]{blue} %N {default}一槍爆☆殺 {green}妹子{default}.", iClient[0][INDEX]);	
				else if (!iCrownTech)
				{
					new gun = GetPlayerWeaponSlot(iClient[0][INDEX], 0); //get the players primary weapon
					if (!IsValidEdict(gun)) return; //check for validity
					
					decl String:currentgunname[64];
					GetEdictClassname(gun, currentgunname, sizeof(currentgunname)); //get the primary weapon name
			
					if (StrEqual(currentgunname, "weapon_pumpshotgun")&&!IsIncapacitated(iClient[0][INDEX]))
						CPrintToChatAll("{green}[提示]{blue} %N {default}引秒-爆☆殺 {green}妹子{default}.", iClient[0][INDEX]);	
				}
				else if (iCrownTech == 5){//被witch incap/秒殺結束回合
					//CPrintToChatAll("{green}[提示]{blue} %N {default}反被 {green}妹子 {olive}爆☆殺 {default}結束這回合.", iClient[0][INDEX]);
				}
				else
				{/*CPrintToChatAll("{green}[提示]{blue} %N {default}打昏-爆☆殺 {green}妹子{default}.", iClient[0][INDEX]);*/}
			}
		}
	}
	else {

		new Float:fTotalDamage = float(g_iCvarHealth[bTankBoss]);

		SortCustom2D(iClient, iSurvivors, SortFuncByDamageDesc);
		
		if (!bLoose && !(g_iCvarPrivateFlags & (1 << (bTankBoss ? 1 : 0))))
			if(bTankBoss){
				CPrintToChatAll("{olive}[提示] Damage dealt to Tank ({red}%s{olive}):", ( istankAI ? "AI":tankplayerName));
				g_bIsTankAlive = false;
			}
			else
				CPrintToChatAll("{olive}[提示] Damage dealt to{red} 妹子{olive}:");

		if (bTankBoss){

			decl String:sName[48], client, bool:bInGame;

			for (new i; i < iSurvivors; i++){

				client = iClient[i][INDEX];

				if ((bInGame = IsSurvivor(client)))
					GetClientName(client, sName, 48);
				else {

					IntToString(client, sName, 48);

					if (GetTrieString(g_hTrine, sName, sName, 48))
						Format(sName, 48, "%s (left the team)", sName);
					else
						sName = "unknown";
				}
					// private
				if (g_iCvarPrivateFlags & (1 << _:TANK)){

					if (bInGame)
						PrintToChat(client, "\x03[提示] Damage dealt to Tank (\x02%d\x03):\nYou #%d: %d (%.0f%%)", g_iTotalDamage[iIndex][bTankBoss], i + 1, iClient[i][DMG], FloatMul(FloatDiv(float(iClient[i][DMG]), fTotalDamage), 100.0));
				}
				else{ // public
					CPrintToChatAll("{olive} %d {default}[{green}%.0f%%%%%{default}] -{blue} %s", iClient[i][DMG], FloatMul(FloatDiv(float(iClient[i][DMG]), fTotalDamage), 100.0),sName);
				}
			}
			if (!(g_iCvarPrivateFlags & (1 << _:TANK))&&g_TankOtherDamage){
				CPrintToChatAll("{olive} %d {default}[{green}%.0f%%%%%{default}] -{lightgreen} 來自其他傷害",g_TankOtherDamage,FloatMul(FloatDiv(float(g_TankOtherDamage), fTotalDamage), 100.0));
				g_TankOtherDamage = 0;
			}
		}
		else {

			for (new i; i < iSurvivors; i++){
			
				if (g_iCvarPrivateFlags & (1 << _:WITCH))
					PrintToChat(iClient[i][INDEX], "\x04[提示] Damage dealt to Witch (\x02%d\x03):\nYou #%d: %d (%.0f%%)", g_iTotalDamage[iIndex][bTankBoss], i + 1, iClient[i][DMG], FloatMul(FloatDiv(float(iClient[i][DMG]), fTotalDamage), 100.0));
				else{
					CPrintToChatAll("{olive} %d {default}[{green}%.0f%%%%%{default}] -{blue} %N", iClient[i][DMG], FloatMul(FloatDiv(float(iClient[i][DMG]), fTotalDamage), 100.0),iClient[i][INDEX]);
					//CPrintToChatAll("%s",PRESENT);y
					}
			}
		}
	}

	// reset var
	g_iTotalDamage[iIndex][bTankBoss] = 0;
}

public SortFuncByDamageDesc(x[], y[], const array[][], Handle:hndl)
{
	if (x[1] < y[1])
		return 1;
	else if (x[1] == y[1])
		return 0;

	return NULL;
}

Float:GetCoopMultiplie()
{
	decl String:sDifficulty[24];
	GetConVarString(g_hDifficulty, sDifficulty, 24);

	if (StrEqual(sDifficulty, "Easy"))
		return 0.75;
	else if (StrEqual(sDifficulty, "Normal"))
		return 1.0;

	return 2.0;
}

bool:IsVersusGameMode()
{
	decl String:sGameMode[12];
	GetConVarString(g_hGameMode, sGameMode, 12);
	return StrEqual(sGameMode, "versus");
}

public OnConvarChange_TankHealth(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(oldValue, newValue))
		g_iCvarHealth[TANK] = RoundFloat(FloatMul(GetConVarFloat(g_hTankHealth), IsVersusGameMode() ? GetConVarFloat(g_hVsBonusHealth) : GetCoopMultiplie()));
}

public OnConvarChange_WitchHealth(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(oldValue, newValue))
		g_iCvarHealth[WITCH] = GetConVarInt(convar);
}

public OnConvarChange_SkipBots(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(oldValue, newValue))
		g_bCvarSkipBots = GetConVarBool(convar);
}

public OnConvarChange_SurvLimit(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(oldValue, newValue))
		g_bCvarSurvLimit = GetConVarInt(convar);
}

public OnConvarChange_Flags(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(oldValue, newValue))
		g_iCvarFlags = GetConVarInt(convar);
}

public OnConvarChange_Private(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(oldValue, newValue))
		g_iCvarPrivateFlags = GetConVarInt(convar);
}

public OnConvarChange_RunAway(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(oldValue, newValue))
		g_bCvarRunAway = GetConVarBool(convar);
}

/*
public CheckSurvivorAlive()
{
	new surdead=0;
	for(new i=1; i <= MaxClients; i++){//在最後一位倖存者倒下之後到回合結束之前乃有一點時間  在這段時間 Tank可能會扣到變成0血 因此判定最後一位倖存者倒下之時停止計算g_iLastTankHealth
		if(IsClientConnected(i) && IsClientInGame(i)&& GetClientTeam(i) == 2)
			if(!IsPlayerAlive(i)||IsIncapacitated(i)||GetEntProp(i, Prop_Send, "m_isHangingFromLedge"))
				surdead++;
	}
	//PrintToChatAll("%d",surdead);
	if(surdead == g_bCvarSurvLimit)
		g_iLastTankHealth = 0;
}*/

public Action:Event_Finale_Start(Handle:event, const String:name[], bool:dontBroadcast)
{
	resuce_start = true;
}