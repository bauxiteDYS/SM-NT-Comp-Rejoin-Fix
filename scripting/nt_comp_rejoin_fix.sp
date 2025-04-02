#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <neotokyo>
#include <nt_competitive/nt_competitive_natives>

// A player can drop a weapon such as an AA, rejoin as support to give themselves AA when it should not be possible for support to get AA themselves
// or they can rejoin again and get AA to have two AAs for the team where otherwise not possible if other teammates dont' have 20 xp or arent assault
// how to fix? 
// I think it's best to lock players into their class if they drop a wep during respawn period, and rejoin, and also drop their weapons before they rejoin
// when they rejoin, strip them of (all) their weps

#define DEBUG false

Handle g_respawnPeriodTimer;
bool g_respawnPeriod;

StringMap g_dropTrie = null;
char g_steamID[32+1][32];
int g_ogClass[32+1];
int g_weps[32+1][4];
// primary, secondary, melee, grenade, 0123

void ResetWeps()
{
	g_dropTrie.Clear();
	
	for(int client = 1; client <= 32; client++)
	{
		g_ogClass[client] = 0;
		
		for(int b = 0; b <= 3; b++)
		{
			g_weps[client][b] = -1;
		}
	}
}

public Plugin myinfo = {
    name = "NT Comp rejoin fix",
    author = "bauxite",
    description = "Fix comp exploits related to re-joining in spawn period",
    version = "0.1.1",
    url = ""
};

public void OnPluginStart()
{
	HookEvent("game_round_start", OnRoundStartPost, EventHookMode_Post);
	HookEvent("player_spawn", OnPlayerSpawnPost, EventHookMode_Post);
	
	AddCommandListener(OnClass, "setclass");
	
	g_dropTrie = new StringMap();
	
	ResetWeps();
}

public void OnMapStart()
{
	ResetWeps();
	
	//late load
}

public void OnClientAuthorized(int client, const char[] auth)
{
	#if DEBUG
	PrintToServer("[rf] OnClientAuthorized");
	#endif
	
	if(IsFakeClient(client))
	{
		return;
	}
	
	if(!GetClientAuthId(client, AuthId_SteamID64, g_steamID[client], sizeof(g_steamID[])))
	{
		PrintToServer("[rf] Error getting SteamID on connect");
	}
	
	int oClass;
	
	if(!g_dropTrie.GetValue(g_steamID[client], oClass))
	{
		#if DEBUG
		PrintToServer("[rf] client key not found on authorize");
		#endif
		
		g_ogClass[client] = 0;
	}
	else
	{
		g_ogClass[client] = oClass;
	}
}

public void OnClientPutInServer(int client)
{
	#if DEBUG
	PrintToServer("[rf] On ClientPutInServer");
	#endif
	
	if(IsFakeClient(client))
	{
		return;
	}
	
	SDKHook(client, SDKHook_WeaponDrop, OnWeaponDrop);
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
}

public void OnClientDisconnect(int client)
{
	if(IsPlayerAlive(client))
	{
		#if DEBUG
		PrintToServer("[rf] Player alive on DC");
		#endif
	}
	else
	{
		#if DEBUG
		PrintToServer("[rf] Player dead on DC");
		#endif
		
		return;
	}
	
	if(!g_respawnPeriod)
	{
		#if DEBUG
		PrintToServer("[rf] Player DC outside respawn period");
		#endif
		
		return; 
	}
	
	// we might wanna drop their weapons still?
	
	if(g_ogClass[client] <= 0)
	{
		#if DEBUG
		PrintToServer("[rf] player hadn't dropped any weapons on DC, ignoring");
		#endif
		
		return;
	}
	
	float clientOrigin[3];
	GetClientAbsOrigin(client, clientOrigin);
	
	int wepsSize = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	
	for (int i = 0; i < wepsSize; i++)
	{
		int wep = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		int slot = GetWeaponSlot(wep);
		
		if (slot == SLOT_PRIMARY || slot == SLOT_SECONDARY || slot == SLOT_GRENADE)
		{
			#if DEBUG
			PrintToServer("[rf] FORCE drop weapon: %d", wep);
			#endif
			
			SDKHooks_DropWeapon(client, wep, clientOrigin, NULL_VECTOR, true);
		}
	}
}

public void OnClientDisconnect_Post(int client)
{
	g_steamID[client][0] = '\0';
	
	g_ogClass[client] = 0;
	
	for(int i = 0; i <= 3; i++)
	{
		g_weps[client][i] = -1;
	}
}

public void OnWeaponEquipPost(int client, int weapon)
{
	#if DEBUG
	PrintToServer("[rf] 1 wep equip");
	#endif
	
	if(!g_respawnPeriod)
	{
		return;
	}
	
	int GameState = GameRules_GetProp("m_iGameState");
	
	if(GameState == GAMESTATE_ROUND_OVER || GameState == GAMESTATE_WAITING_FOR_PLAYERS)
	{
		return;
	}
	
	if(!IsValidEdict(weapon) || !IsPlayerAlive(client))
	{
		return;
	}
	
	if(g_steamID[client][0] == '\0')
	{
		PrintToServer("[rf] Error getting steam id when pickup");
	}
	
	int slot = GetWeaponSlot(weapon);
	
	if(slot == -1)
	{
		return;
	}
	
	char className[32];
	
	if(!GetEntityClassname(weapon, className, sizeof(className)))
	{
		return;
	}
	
	#if DEBUG 
	PrintToServer("[rf] 2 wep equip, picked up %d", weapon);
	#endif
	
	int wepRef = EntIndexToEntRef(weapon);
	
	if(g_weps[client][slot] == wepRef)
	{
		g_weps[client][slot] = -1;
	}
	
	bool dropped;
	
	for(int i = 0; i <= 1; i++)
	{
		if(g_weps[client][i] != -1)
		{
			dropped = true;
		}
	}
	
	if(!dropped) // check if the key is even in trie
	{
		g_ogClass[client] = 0;
		g_dropTrie.SetValue(g_steamID[client], 0);
	}
}

public Action OnWeaponDrop(int client, int weapon)
{
	#if DEBUG
	PrintToServer("[rf] Weapon Drop");
	#endif
	
	if(!g_respawnPeriod)
	{
		return Plugin_Continue;
	}
	
	int GameState = GameRules_GetProp("m_iGameState");
	
	if(GameState == GAMESTATE_ROUND_OVER || GameState == GAMESTATE_WAITING_FOR_PLAYERS)
	{
		return Plugin_Continue;
	}
	
	if(!IsValidEdict(weapon) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}
	
	if(g_steamID[client][0] == '\0')
	{
		PrintToServer("[rf] Error getting steam id when drop");
	}
	
	int slot = GetWeaponSlot(weapon);
	
	if(slot == -1)
	{
		return Plugin_Continue;
	}
	
	// already checked by slot if no classname will return -1 slot
	// but we need to check if the primary wep is ghost again

	char wepName[32];
	
	GetEntityClassname(weapon, wepName, sizeof(wepName));

	if(StrEqual(wepName, "weapon_ghost", false))
	{
		return Plugin_Continue;
	}
	
	if(g_weps[client][slot] != -1)
	{
		// client has already dropped a wep from this slot before
		// and we've recorded the ref of that weapon
		return Plugin_Continue;
	}
	
	// input client class if they dropped primary or secondary (nade?) weapon, track weps in an array
	// if they pick up all same weapons clear the trie with class 0
	
	g_weps[client][slot] = EntIndexToEntRef(weapon);
	
	int class = GetPlayerClass(client);
	g_ogClass[client] = class;
	
	g_dropTrie.SetValue(g_steamID[client], class);
	
	return Plugin_Continue;
}

public void OnRoundStartPost(Event event, const char[] name, bool dontBroadcast)
{
	#if DEBUG
	PrintToServer("[rf] Round Start Event");
	#endif
	
	ResetWeps();
	
	g_respawnPeriod = true;
	
	if(IsValidHandle(g_respawnPeriodTimer))
	{
		#if DEBUG
		PrintToServer("[rf] closing timer");
		#endif
		
		CloseHandle(g_respawnPeriodTimer);
	}
	
	#if DEBUG
	PrintToServer("[rf] creating timer");
	#endif
	
	g_respawnPeriodTimer = CreateTimer(33.0, ResetRespawnPeriodTimer, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action ResetRespawnPeriodTimer(Handle timer)
{
	#if DEBUG
	PrintToServer("[rf] On Reset Timer");
	#endif
	
	g_respawnPeriod = false;
	return Plugin_Stop;
}

public Action OnClass(int client, const char[] command, int argc)
{
	if(!g_respawnPeriod)
	{
		return Plugin_Continue;
	}
	
	if(argc != 1 || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}
	
	int iClass = GetCmdArgInt(1);
	
	if(g_ogClass[client] <= 0)
	{
		return Plugin_Continue;
	}
	
	if(iClass != g_ogClass[client])
	{
		FakeClientCommandEx(client, "setclass %d", g_ogClass[client]);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public void OnPlayerSpawnPost(Event event, const char[] name, bool dontBroadcast)
{
	#if DEBUG
	PrintToServer("[rf] On Player Spawn");
	#endif
	
	int dc = g_dropTrie.Size;
	
	if(dc == 0)
	{
		return;
	}
	
	#if DEBUG
	PrintToServer("[rf] drop count on spawn was %d", dc);
	#endif
	
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	
	if(g_ogClass[client] > 0)
	{
		RequestFrame(StripWeapons, userid);
	}
}

void StripWeapons(int userid)
{
	int client = GetClientOfUserId(userid);
	
	if(client <= 0 || !IsClientInGame(client) || GetClientTeam(client) <= TEAM_SPECTATOR)
	{
		return;
	}
	
	StripPlayerWeapons(client, true);
	
	#if DEBUG
	PrintToServer("[rf] Stripping weapons");
	PrintToChatAll("[rf] Stripping weapons of %N", client);
	#endif
}
