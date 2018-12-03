/*
	SourcePawn is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	SourceMod is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	Pawn and SMALL are Copyright (C) 1997-2008 ITB CompuPhase.
	Source is Copyright (C) Valve Corporation.
	All trademarks are property of their respective owners.
	This program is free software: you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the
	Free Software Foundation, either version 3 of the License, or (at your
	option) any later version.
	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	General Public License for more details.
	You should have received a copy of the GNU General Public License along
	with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
#pragma semicolon 1
 
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>

new Handle:hCvarDmgThreshold;
new Handle:hCvarAnnounce;
new Handle:hCvarHunterClawDamage;
new Handle:hCvarSkipGetUpAnimation;
new Handle:g_hGameMode;
new CvarDmgThreshold;
new CvarAnnounce;
new CvarHunterClawDamage;
new CvarSkipGetUpAnimation;
new String:CvarGameMode[20];
new bool:haspounced[MAXPLAYERS + 1] = {false};
new pouncedvictim[MAXPLAYERS + 1] = {0};
new     bool:           bLateLoad                                               = false;

public APLRes:AskPluginLoad2( Handle:plugin, bool:late, String:error[], errMax)
{
    bLateLoad = late;
    return APLRes_Success;
}

public Plugin:myinfo =
{
	name = "1vHunters",
	author = "Harry Potter",
	description = "Hunter pounce survivors and die ,set hunter scratch damage, no getup animation",
	version = "1.5",
	url = "https://github.com/Attano/Equilibrium"
};

public OnPluginStart()
{     
	g_hGameMode = FindConVar("mp_gamemode");
	GetConVarString(g_hGameMode,CvarGameMode,sizeof(CvarGameMode));

	hCvarDmgThreshold = CreateConVar("sm_1v1_dmgthreshold", "24", "Amount of damage done (at once) before SI suicides. -1:Disable", FCVAR_PLUGIN, true, -1.0);
	hCvarAnnounce = CreateConVar("sm_1v1_dmgannounce", "1", "Announce SI Health Left before SI suicides.", FCVAR_PLUGIN, true, 0.0);
	hCvarHunterClawDamage = CreateConVar("sm_hunter_claw_dmg", "-1", "Hunter claw Dmg. -1:Default value dmg", FCVAR_PLUGIN, true, -1.0);
	hCvarSkipGetUpAnimation = CreateConVar("sm_hunter_skip_getup", "1", "Skip Survivor Get Up Animation", FCVAR_PLUGIN, true, 0.0);
	
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("lunge_pounce", PlayerLunge_Pounce_Event);
	HookEvent("round_start", event_RoundStart, EventHookMode_PostNoCopy);//每回合開始就發生的event
	HookEvent("player_spawn",		Event_PlayerSpawn,	EventHookMode_PostNoCopy);
	HookEvent("player_death",		Event_PlayerDeath,	EventHookMode_PostNoCopy);
	HookEvent("pounce_stopped", PlayerLunge_Pounce_Stop_Event);
	
	CvarDmgThreshold = GetConVarInt(hCvarDmgThreshold);
	CvarAnnounce = GetConVarInt(hCvarAnnounce);
	CvarHunterClawDamage = GetConVarInt(hCvarHunterClawDamage);
	CvarSkipGetUpAnimation = GetConVarInt(hCvarSkipGetUpAnimation);
	
	HookConVarChange(hCvarDmgThreshold, ConVarChange_hCvarDmgThreshold);
	HookConVarChange(hCvarAnnounce, ConVarChange_hCvarAnnounce);
	HookConVarChange(hCvarHunterClawDamage, ConVarChange_hHunterClawDamage);
	HookConVarChange(hCvarSkipGetUpAnimation,ConVarChange_hCvarSkipGetUpAnimation);
	
    // hook when loading late
	if(bLateLoad){
		for (new i = 1; i < MaxClients + 1; i++) {
			if (IsClientAndInGame(i)) {
                SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
            }
        }
    }
}
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if(!IsClientAndInGame(attacker)||!IsClientAndInGame(client)) return;
	if(GetClientTeam(attacker) == 3 && GetZombieClass(attacker) == 3 && IsPlayerAlive(attacker) && GetClientTeam(client) == 2)
	{
		new remaining_health = GetClientHealth(attacker);
		if(CvarAnnounce == 1)
		{
			CPrintToChat(client,"[{olive}TS 1vHunter{default}] {red}%N{default} had {green}%d{default} health remaining!", attacker, remaining_health);
			if(!IsFakeClient(attacker))
				CPrintToChat(attacker,"[{olive}TS 1vHunter{default}] You have {green}%d{default} health remaining!",remaining_health);
		}
		ForcePlayerSuicide(attacker);
		if (remaining_health == 1 && CvarAnnounce == 1)
		{
			CPrintToChat(client, "[{olive}TS 1vHunter{default}] You don't have to be mad...");
		}
	}
}
public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(IsClientAndInGame(client)&&GetClientTeam(client) == 3 && GetZombieClass(client) == 3)
		haspounced[client] = false;
}

public Action:PlayerLunge_Pounce_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	if(IsClientAndInGame(client)&&GetClientTeam(client) == 3 && GetZombieClass(client) == 3)
	{
		haspounced[client] = true;
		pouncedvictim[client] = victim;
	}
}

public Action:PlayerLunge_Pounce_Stop_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	if(IsClientAndInGame(victim)&&GetClientTeam(victim) == 2)
	{
		for (new i = 1; i <= MaxClients; i++) //clear 
		{
			if(pouncedvictim[i] == victim)
			{
				haspounced[i] = false;
				pouncedvictim[i] = 0;
				break;
			}
		}
	}
}


public Action:event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	for (new i = 1; i <= MaxClients; i++) //clear 
	{
		haspounced[i] = false;
		pouncedvictim[i] = 0;
	}
}
public Action:Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsClientAndInGame(attacker)||!haspounced[attacker] || !IsClientAndInGame(victim) || CvarDmgThreshold < 0)
		return;

	new damage = GetEventInt(event, "dmg_health");
	new zombie_class = GetZombieClass(attacker);

	if (GetClientTeam(victim) == 2 && GetClientTeam(attacker) == 3 && zombie_class == 3 && damage >= CvarDmgThreshold)
	{
		new remaining_health = GetClientHealth(attacker);
		if(CvarAnnounce == 1)
		{
			CPrintToChat(victim,"[{olive}TS 1vHunter{default}] {red}%N{default} had {green}%d{default} health remaining!", attacker, remaining_health);
			if(!IsFakeClient(attacker))
				CPrintToChat(attacker,"[{olive}TS 1vHunter{default}] You have {green}%d{default} health remaining!", remaining_health);
		}

		ForcePlayerSuicide(attacker);    
		haspounced[attacker] = false;
		if(CvarSkipGetUpAnimation == 1)
			CreateTimer(0.04, CancelGetup, victim,_);
		
		if (remaining_health == 1&&CvarAnnounce == 1)
		{
			CPrintToChat(victim, "[{olive}TS 1vHunter{default}] You don't have to be mad...");
		}
	}
}

stock GetZombieClass(client) return GetEntProp(client, Prop_Send, "m_zombieClass");

stock bool:IsClientAndInGame(index)
{
	if (index > 0 && index < MaxClients)
	{
		return IsClientInGame(index);
	}
	return false;
}

public ConVarChange_hCvarDmgThreshold(Handle:convar, const String:oldValue[], const String:newValue[])
{	
	if (!StrEqual(oldValue, newValue))
		CvarDmgThreshold = StringToInt(newValue);
}

public ConVarChange_hCvarAnnounce(Handle:convar, const String:oldValue[], const String:newValue[])
{	
	if (!StrEqual(oldValue, newValue))
		CvarAnnounce = StringToInt(newValue);
}
public ConVarChange_hHunterClawDamage(Handle:convar, const String:oldValue[], const String:newValue[])
{	
	if (!StrEqual(oldValue, newValue))
		CvarHunterClawDamage = StringToInt(newValue);
}
public ConVarChange_hCvarSkipGetUpAnimation(Handle:convar, const String:oldValue[], const String:newValue[])
{	
	if (!StrEqual(oldValue, newValue))
		CvarSkipGetUpAnimation = StringToInt(newValue);
}


public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
	if(!IsValidEdict(victim) || !IsValidEdict(attacker) || !IsValidEdict(inflictor) || !IsValidEdict(damagetype)) { return Plugin_Continue; }
	
	if(!IsClientAndInGame(victim) || !IsClientAndInGame(attacker) || damage == 0.0 || CvarHunterClawDamage < 0) { return Plugin_Continue; }
	
	//decl String:sClassname[64];
	//GetEntityClassname(inflictor, sClassname, 64);
	decl String:sdamagetype[64];
	GetEdictClassname( damagetype, sdamagetype, sizeof( sdamagetype ) ) ;
	//PrintToChatAll("victim: %d,attacker:%d ,sClassname is %s, damage is %f, sdamagetype is %s",victim,attacker,sClassname,damage,sdamagetype);
	if (GetClientTeam(attacker) == 3 && GetClientTeam(victim) == 2)
	{
		if(StrEqual(CvarGameMode,"coop")||StrEqual(CvarGameMode,"survival"))
		{
			if(GetZombieClass(attacker) == 3 && !haspounced[attacker])
			{
				damage = float(CvarHunterClawDamage);
				return Plugin_Changed;
			}
		}
		else if(StrEqual(CvarGameMode,"versus"))
		{
			if(GetZombieClass(attacker) == 3 && !haspounced[attacker] && StrEqual(sdamagetype, "trigger_once"))
			{
				damage = float(CvarHunterClawDamage);
				return Plugin_Changed;
			}
		}
	}
	return Plugin_Continue;
}

public OnClientPostAdminCheck(client)
{
    // hook bots spawning
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public OnClientDisconnect(client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action:CancelGetup(Handle:timer, any:client) {
    if (!IsClientConnected(client) || !IsClientInGame(client) || GetClientTeam(client) != 2) return Plugin_Stop;

    SetEntPropFloat(client, Prop_Send, "m_flCycle", 1000.0); // Jumps to frame 1000 in the animation, effectively skipping it.
    return Plugin_Continue;
}