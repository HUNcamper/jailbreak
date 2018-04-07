 //////////////////////////////////////////////////
//       _       _ _ ____                 _     //
//      | |     (_) |  _ \               | |    //
//      | | __ _ _| | |_) |_ __ ___  __ _| | __ //
//  _   | |/ _` | | |  _ <| '__/ _ \/ _` | |/ / //
// | |__| | (_| | | | |_) | | |  __/ (_| |   <  //
//  \____/ \__,_|_|_|____/|_|__\___|\__,_|_|\_\ //
// |  ____|         |__   __|  ____|__ \        //
// | |__ ___  _ __     | |  | |__     ) |       //
// |  __/ _ \| '__|    | |  |  __|   / /        //
// | | | (_) | |       | |  | |     / /_        //
// |_|  \___/|_|       |_|  |_|    |____|       //
//////////////////////////////////////////////////
// Written by HUNcamper
//
// Jailbreak tools

#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "HUNcamper"
#define PLUGIN_VERSION "1.0.0"

// Constant variables
#define TF_TEAM_BLU			3
#define TF_TEAM_RED			2

#define SOUND_10SEC			"vo/announcer_ends_10sec.mp3"
#define SOUND_5SEC			"vo/announcer_ends_5sec.mp3"
#define SOUND_4SEC			"vo/announcer_ends_4sec.mp3"
#define SOUND_3SEC			"vo/announcer_ends_3sec.mp3"
#define SOUND_2SEC			"vo/announcer_ends_2sec.mp3"
#define SOUND_1SEC			"vo/announcer_ends_1sec.mp3"

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <kvizzle>
#include <sdkhooks>
#include <smlib>

// Convars
Handle g_jbTime;
Handle g_lrTime;
Handle g_jbExecCommands;
Handle g_jbIsEnabled;
Handle g_jbSoulRemove;
Handle g_jbTeamBalance;
Handle g_jbAutoBalance;
Handle g_jbAmmoRemove;
Handle g_jbCrits;
Handle g_jbDroppedStrip;

// Global variables
bool isLRActive;
float LRtime;
float timerTime;
bool gameEnd;
bool roundGoing;
bool lateLoaded;

// Player variables
bool isStripped[MAXPLAYERS + 1];

// Entity variables (they store the entity ID, not the entity itself)
new ent_stalemate;

// HUD elements
Handle hudLRTimer;
Handle hudTimer; 

public Plugin myinfo = 
{
	name = "Jailbreak Timer", 
	author = PLUGIN_AUTHOR, 
	description = "Jailbreak and LR timer", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/HUNcamper/"
};

/////////////////////////////
// P L U G I N   S T A R T //
/////////////////////////////
//
// - Ask the server to load the plugin
//
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	lateLoaded = late;
	if (GetEngineVersion() != Engine_TF2) // If game isn't TF2
	{
		Format(error, err_max, "This Jailbreak plugin is only working with Team Fortress 2."); // Error
		return APLRes_Failure; // Don't load the plugin
	}
	return APLRes_Success; // Load the plugin
}

/////////////////////////////
// P L U G I N   S T A R T //
/////////////////////////////
//
// - Triggers when the plugin loads
//
public void OnPluginStart()
{
	// C O N V A R S //
	g_jbTime = CreateConVar("jb_timer", "600", "Jailbreak timer time (in seconds)");
	g_lrTime = CreateConVar("jb_timer_lr", "120", "Jailbreak LR timer time (in seconds)");
	g_jbExecCommands = CreateConVar("jb_commands_after_setup", "sm_say setup ended!", "Commands to execute after setup time ended");
	g_jbIsEnabled = CreateConVar("jb_enabled", "0", "Is the plugin enabled");
	g_jbSoulRemove = CreateConVar("jb_remove_souls", "1", "Should the plugin remove the flying souls (only in halloween mode)?");
	g_jbAmmoRemove = CreateConVar("jb_remove_ammodrops", "1", "Should the plugin remove the ammo packs which are dropped upon death?");
	g_jbTeamBalance = CreateConVar("jb_balance", "1", "Should the plugin balance the teams with the 1:3 ratio? (disallow reds from joining blue)");
	g_jbAutoBalance = CreateConVar("jb_autobalance", "0", "Should the plugin autobalance the teams at the end of every round with the 1:3 ratio?");
	g_jbCrits = CreateConVar("jb_crits", "1", "Should the plugin modify crits to be 100%?");
	g_jbDroppedStrip = CreateConVar("jb_strip_from_dropped", "1", "Should the plugin strip the ammo from dropped weapons?");
	
	// V A R I A B L E S //
	isLRActive = false;
	LRtime = GetConVarFloat(g_lrTime);
	gameEnd = false;
	roundGoing = false;
	//nextRoundBalance = false; // unused
	
	// A D M I N   C O M M A N D S //
	RegAdminCmd("sm_forcestalemate", Command_JB_ForceStaleMate, ADMFLAG_ROOT, "sm_forcestalemate");
	RegAdminCmd("sm_stripammo", Command_JB_StripAmmo, ADMFLAG_ROOT, "sm_stripammo <Player>");
	RegAdminCmd("sm_reloadjbconfig", Command_JB_ReloadConfig, ADMFLAG_ROOT, "sm_reloadjbconfig");
	
	// C O M M A N D S //
	RegConsoleCmd("jointeam", Command_Jointeam);
	
	// H O O K S //
	HookEvent("teamplay_round_start", teamplay_round_start);
	HookEvent("arena_round_start", arena_round_start);
	HookEvent("player_death", Player_Death);
	HookEvent("player_spawn", player_spawn);
	HookEvent("teamplay_round_stalemate", EndGame_StaleMate);
	HookEvent("teamplay_round_win", EndGame_Win);
	HookEvent("post_inventory_application", event_PlayerResupply);
	
	// H U D   E L E M E N T S //
	hudLRTimer = CreateHudSynchronizer();
	hudTimer = CreateHudSynchronizer();
	
	// O T H E R //
	LoadTranslations("common.phrases"); // Load common translation file
	
	//for (int i = 1; i <= MaxClients; i++)
	//{
	//	OnClientPostAdminCheck(i);
	//}
	
	for (int iClient = 1; iClient <= MaxClients; iClient++) {
        if (IsClientConnected(iClient) && IsClientInGame(iClient)) {
            OnClientPutInServer(iClient);
        }
        
        isStripped[iClient] = false;
    }
	
	PrintToChatAll("\x05JailBreak Plugin\x01 loaded, restarting game");
	ServerCommand("mp_restartgame 1");
	
	CreateTimer(1.0, UpdateTimers, _, TIMER_REPEAT);
	
	Precache();
	
	reloadConfig();
}

public void OnClientPutInServer(int client) 
{ 
    SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
}

public Action OnWeaponCanUse(int client, int weapon)  
{
	if (GetConVarBool(g_jbIsEnabled))
	{
		if(roundGoing && GetConVarBool(g_jbDroppedStrip))
		{
			DataPack pack;
			CreateDataTimer(0.1, OnWeaponCanUseTimed, pack);
			pack.WriteCell(client);
			pack.WriteCell(weapon);
		}
	}
	return Plugin_Continue;
}

public Action OnWeaponCanUseTimed(Handle timer, Handle pack)
{
	char buffer[64];
	
	ResetPack(pack);
	int client = ReadPackCell(pack);
	int weapon = ReadPackCell(pack);
	int slot = GetSlotFromPlayerWeapon(client, weapon);
	
	if(slot != -1)
	{
		GetEntityClassname(weapon, buffer, sizeof(buffer));
		//PrintToChatAll("%N HAS PICKED UP WEAPON: %i, AT SLOT: %i, CLASSNAME: %s", client, weapon, slot, buffer);
		
		StripAmmo(client, slot);
	}
	else
	{
		PrintToServer("[JAILBREAK] %N has picked up a weapon to an invalid slot", client);
	}
	
	return Plugin_Continue;
}

public OnEntityCreated(entity, const String:classname[])
{
    if(StrContains(classname[1], "item_ammopack", false) != -1)
    {
        SDKHook(entity,    SDKHook_StartTouch,     Ammo_StartTouch);
        //SDKHook(entity,    SDKHook_Touch,             Touch);
    }
}

public OnConfigsExecuted()
{
	/******************
	* On late load   *
	******************/
	if (lateLoaded)
	{
		new ent = -1;
		
		//Ehh you need to add code so it can also hook the other powerups, just using
		//item_healthkit_full as a demonstration
		while ((ent = FindEntityByClassname(ent, "item_ammopack_*")) != -1)
		{
			decl String:classname[64];
			GetEntityClassname(ent, classname, sizeof(classname));
			//PrintToChatAll("%s", classname);
			SDKHook(ent, SDKHook_StartTouch, Ammo_StartTouch);
			//SDKHook(ent, SDKHook_Touch,             Touch);
		}
		
		lateLoaded = false;
	}
}

public Ammo_StartTouch(entity, client)
{
	decl String:classname[64];
	GetEdictClassname(GetPlayerWeaponSlot(client, 0), classname, sizeof(classname));
	
	//int offset = Client_GetWeaponsOffset(client) + 4; // secondary weapon offset
	//int weapon = GetEntDataEnt2(client, offset);
	new secondary = GetPlayerWeaponSlot(client, 1);
	TFClassType class = TF2_GetPlayerClass(client);
	bool isOk = false;
	
	// Check if the user is with a class that has buggy weapons
	if(isStripped[client] && (class == TFClass_Sniper || class == TFClass_Heavy || class == TFClass_Scout))
	{
		// Check if the user has those weapons
		//new secondary = GetPlayerWeaponSlot(client, 1);
		char name[64];
		GetEdictClassname(secondary, name, sizeof(name));
		
		// Scout
		if		(StrEqual(name, "tf_weapon_jar"))				isOk = true;
		else if (StrEqual(name, "tf_weapon_jar_milk"))			isOk = true;
		else if (StrEqual(name, "tf_weapon_lunchbox_drink"))	isOk = true;
		else if (StrEqual(name, "tf_weapon_cleaver"))			isOk = true;
		
		// Heavy
		else if (StrEqual(name, "tf_weapon_lunchbox"))			isOk = true;
	}
	else if (isStripped[client] && class == TFClass_DemoMan)
	{
		// Enable demo shield
		SetEntPropFloat(client, Prop_Send, "m_flChargeMeter", 100.0);
	}
	
	if (isOk)
	{
		// Set secondary ammo to 1
		Client_SetWeaponPlayerAmmoEx(client, secondary, 1, 1);
		
		EmitSoundToClient(client, "player/recharged.wav", client, _, _, _, 1.0);
		//PrintToChat(client, "Your secondary has been recharged.");
	}
	
	isStripped[client] = false;
}

/////////////////////////////////
//P L A Y E R   R E S U P P L Y//
/////////////////////////////////
public event_PlayerResupply(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	isStripped[client] = false;
}

///////////////////////////////
// C R I T   M O D I F I E R //
///////////////////////////////
public Action:TF2_CalcIsAttackCritical(client, weapon, String:weaponname[], &bool:result)
{
	if (!GetConVarBool(g_jbCrits))
	{
		return Plugin_Continue;	
	}
	else
	{
		result = true;
		return Plugin_Handled;
	}
}

///////////////////////////////
// C O N F I G   R E L O A D //
///////////////////////////////
// -
// - Reload the map config for time
// -
public reloadConfig()
{
	// load config file
	decl String:config[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, config, PLATFORM_MAX_PATH, "configs/jb_maps.cfg");
	
	char currmap[32];
	GetCurrentMap(currmap, sizeof(currmap));
	
	new Handle:kv = KvizCreateFromFile("maps", config);
	
	if (kv != INVALID_HANDLE)
	{
		for (new i = 1; KvizExists(kv, ":nth-child(%i)", i); i++)
		{
			decl String:map[32], Float:ctime, String:caftersetup[256], Float:clrtime;
			int cenabled, cbalance, cautobalance, csouls, cammo;
			
			KvizGetStringExact(kv, map, sizeof(map), ":nth-child(%i):key", i);
			if (StrEqual(map, currmap, false))
			{
				if (KvizGetFloatExact(kv, ctime, ":nth-child(%i).roundtime", i)) SetConVarFloat(g_jbTime, ctime);
				if (KvizGetFloatExact(kv, clrtime, ":nth-child(%i).lrtime", i)) SetConVarFloat(g_lrTime, clrtime);
				if (KvizGetStringExact(kv, caftersetup, sizeof(caftersetup), ":nth-child(%i).aftersetup", i)) SetConVarString(g_jbExecCommands, caftersetup);
				if (KvizGetNumExact(kv, cenabled, ":nth-child(%i).enabled", i)) SetConVarInt(g_jbIsEnabled, cenabled);
				if (KvizGetNumExact(kv, cbalance, ":nth-child(%i).balance", i))	SetConVarInt(g_jbTeamBalance, cbalance);
				if (KvizGetNumExact(kv, cautobalance, ":nth-child(%i).autobalance", i))	SetConVarInt(g_jbAutoBalance, cautobalance);
				if (KvizGetNumExact(kv, csouls, ":nth-child(%i).removesouls", i)) SetConVarInt(g_jbSoulRemove, csouls);
				if (KvizGetNumExact(kv, cammo, ":nth-child(%i).removeammo", i))	SetConVarInt(g_jbAmmoRemove, cammo);
				PrintToServer("[JAILBREAK] Map config present and loaded.");
				break;
			}
		}
		
		KvizClose(kv);
	}
	else
	{
		PrintToServer("[JAILBREAK] NOTE There is no map config present!");
	}
}

////////////////////////////////////
// C L I E N T  C O N N E C T E D //
////////////////////////////////////
//
// - Check if someone connected
//
//public OnClientPostAdminCheck(client)
//{
	
//}

//////////////////////////////////////////
// C L I E N T  D I S C O N N E C T E D //
//////////////////////////////////////////
//
// - Check if someone disconnected
//
public void OnClientDisconnect(int client)
{
	if (GetConVarBool(g_jbIsEnabled))
		CreateTimer(0.5, timer_teamcheck);
	
	
}

/////////////////////////////////////////
// C M D :   R E L O A D   C O N F I G //
/////////////////////////////////////////
//
// - Reload map config
//
public Action:Command_JB_ReloadConfig(client, args)
{
	reloadConfig();
	return Plugin_Handled;
}

///////////////////////////////////
// C M D :   S T R I P   A M M O //
///////////////////////////////////
//
// - Strip ammo by command
//
public Action:Command_JB_StripAmmo(client, args)
{
	if (GetConVarBool(g_jbIsEnabled))
	{
		if (args != 1)
		{
			ReplyToCommand(client, "Usage: sm_stripammo <Player>");
			return Plugin_Handled;
		}
		
		decl String:buffer[64];
		decl String:target_name[MAX_NAME_LENGTH];
		decl target_list[MAXPLAYERS];
		decl target_count;
		decl bool:tn_is_ml;
		
		//Get target
		GetCmdArg(1, buffer, sizeof(buffer));
		
		if ((target_count = ProcessTargetString(
					buffer, 
					client, 
					target_list, 
					MAXPLAYERS, 
					COMMAND_FILTER_ALIVE, 
					target_name, 
					sizeof(target_name), 
					tn_is_ml)) <= 0)
		{
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		
		// Strip ammo
		for (new i = 0; i < target_count; i++)
		{
			if(IsValidClient(target_list[i]))
			{
				StripAmmo(target_list[i]);
			}
		}
	} else {
		ReplyToCommand(client, "[JAILBREAK] The jailbreak plugin is not active.");
	}
	
	return Plugin_Handled;
}

///////////////////////////
// R O U N D   S T A R T //
///////////////////////////
//
// - Triggers when a round starts
//
public teamplay_round_start(Handle:event, const String:name[], bool:dontBroadcast)
{
	isLRActive = false;
	LRtime = GetConVarFloat(g_lrTime);
	gameEnd = false;
	roundGoing = false;
	//KillTimerEnts();
	CreateStaleMate();
	reloadConfig();
	
	timerTime = GetConVarFloat(g_jbTime);
	
	if (GetConVarBool(g_jbIsEnabled))
	{
		
		
		for (int i = 0; i <= MaxClients; i++)
		{
			isStripped[i] = false;
			if (IsValidClient(i) && GetClientTeam(i) == TF_TEAM_RED)
			{
				StripAmmo(i);
				isStripped[i] = true;
			}
		}
	}
	
	new ent = -1;
	
	while ((ent = FindEntityByClassname(ent, "item_ammopack_*")) != -1)
	{
		decl String:classname[64];
		GetEntityClassname(ent, classname, sizeof(classname));
		//PrintToChatAll("hooked %s", classname);
		SDKHook(ent, SDKHook_StartTouch, Ammo_StartTouch);
		//SDKHook(ent, SDKHook_Touch,             Touch);
	}
}

/////////////////////////////
// R O U N D   B E G I N S //
/////////////////////////////
//
// - When the round starts, exec the set commands
//
public arena_round_start(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetConVarBool(g_jbIsEnabled))
	{
		char buffer[32][128]; char current[256];
		GetConVarString(g_jbExecCommands, current, sizeof(current));
		ExplodeString(current, ";", buffer, sizeof(buffer), sizeof(buffer[]));
		
		for (int i = 0; i < sizeof(buffer); i++)
		ServerCommand(buffer[i]);
		
		roundGoing = true;
	}
}

/////////////////////////////
// P L A Y E R   S P A W N //
/////////////////////////////
//
// - When a player spawns
//
public player_spawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetConVarBool(g_jbIsEnabled))
	{
		new client = GetClientOfUserId(GetEventInt(event, "userid")); // Get client
		if (GetClientTeam(client) == TF_TEAM_RED)
			StripAmmo(client);
	}
}

///////////////////////////
// P L A Y E R   T E A M //
///////////////////////////
//
// - When a player switches teams
//
//public Action player_team(Handle:event, const String:name[], bool:dontBroadcast)
//{
	
public Action:Command_Jointeam(client, args)
{
	if (GetConVarBool(g_jbIsEnabled) && GetConVarBool(g_jbTeamBalance))
	{
		
		decl String:buffer[10], newteam, oldteam;
		GetCmdArg(1,buffer,sizeof(buffer));
		StripQuotes(buffer);
		TrimString(buffer);
		
		if(strlen(buffer) == 0) return Plugin_Handled; // If nothing was given, break the command
		else if (StrEqual(buffer, "blue", false)) newteam = TF_TEAM_BLU;
		else if (StrEqual(buffer, "spectator", false)) return Plugin_Continue;
		else newteam = TF_TEAM_RED; // Anything else seems to drop the player to red???
		
		oldteam = GetClientTeam(client);
		
		if (newteam == oldteam)return Plugin_Handled;
		
		bool allow = false;
		
		if(IsValidClient(client, false))
		{
			new red = RoundToFloor(GetTeamClientCount(TF_TEAM_RED) / 3.0), 
			blue = GetTeamClientCount(TF_TEAM_BLU), 
			redminus = RoundToFloor((GetTeamClientCount(TF_TEAM_RED)-1.0) / 3.0);
			//PrintToChatAll("%f > %i", GetTeamClientCount(TF_TEAM_RED) / 3.0 , GetTeamClientCount(TF_TEAM_BLU));
			if(newteam == TF_TEAM_BLU)
			{
				if(oldteam == TF_TEAM_RED)
				{
					if(redminus > blue)
						allow = true;
					else if(blue == 0)
						allow = true;
				}
				else
				{
					if(red > blue)
						allow = true;
					else if(blue == 0)
						allow = true;
				}
			}
			else
			{
				allow = true;
			}
		}
		
		if(!allow)
		{
			//TF2_ChangeClientTeam(client, TFTeam_Red);
			PrintCenterText(client, "Not enough REDs to join BLU");
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

///////////////////////////
// E N D G A M E _ W I N //
///////////////////////////
//
// - When the game ends with one team winning
//
public EndGame_Win(Handle:event, const String:name[], bool:dontBroadcast)
{
	gameEnd = true;
	roundGoing = false;
	
	BalanceTeams();
}

///////////////////////////////////////
// E N D G A M E _ S T A L E M A T E //
///////////////////////////////////////
//
// - When the game ends with stalemate
//
public EndGame_StaleMate(Handle:event, const String:name[], bool:dontBroadcast)
{
	gameEnd = true;
	roundGoing = false;
	
	BalanceTeams();
}

///////////////////////////////
// B A L A N C E   T E A M S //
///////////////////////////////
//
// - Balance the teams with the 1:3 ratio
//
public BalanceTeams()
{
	if(GetConVarBool(g_jbIsEnabled))
	{
		// If the balance is enabled (, and a balance was set for the next round) <- not used anymore
		if(GetConVarBool(g_jbTeamBalance) && GetConVarBool(g_jbAutoBalance)) //&& nextRoundBalance)
		{
			while(true)
			{
				new red = RoundToFloor(GetTeamClientCount(TF_TEAM_RED) / 3.0), 
				redminus = RoundToFloor((GetTeamClientCount(TF_TEAM_RED)-1.0) / 3.0),
				blue = GetTeamClientCount(TF_TEAM_BLU);
				//PrintToChatAll("%f > %i", red, blue);
				new reds[32], blus[32], a, b;
				
				a = 0;
				b = 0;
				
				for (int i = 1; i < MaxClients; i++)
				{
					if (IsValidClient(i, false))
					{
						if (GetClientTeam(i) == TF_TEAM_RED)
						{
							reds[a] = i;
							a++;
						}
						else if (GetClientTeam(i) == TF_TEAM_BLU)
						{
							blus[b] = i;
							b++;
						}
					}
				}
				
				if(redminus > blue)
				{
					//int substraction = red - blue;
					//for (int i = 0; i < substraction; i++)
					//{
					PrintToServer("Autobalancing %N", reds[a - 1]);
					PrintToChat(reds[a-1], "[JAILBREAK] You have been auto balanced.");
					TF2_ChangeClientTeam(reds[a-1], TFTeam_Blue);
					a--;
					//}
				}
				else if(blue > red)
				{
					//int substraction = blue - red;
					//for (int i = 0; i < substraction; i++)
					//{
					PrintToServer("Autobalancing %N", blus[b - 1]);
					PrintToChat(blus[b-1], "[JAILBREAK] You have been auto balanced.");
					TF2_ChangeClientTeam(blus[b-1], TFTeam_Red);
					b--;
					//}
				}
				else
				{
					PrintToServer("DONE BALANCING");
					// Done
					return;
				}
			}
		}
	}
}

/////////////////////////
// S T R I P   A M M O //
/////////////////////////
// -
// - Strip all ammo from a player
// -
stock StripAmmo(int client, int slot=-1)
{
	if (GetConVarBool(g_jbIsEnabled))
	{
		int offset = Client_GetWeaponsOffset(client) - 4;
		
		for (int i = 0; i < 2; i++)
		{
			offset += 4;
	
			int weapon = GetEntDataEnt2(client, offset);
	
			if (!IsValidEntity(weapon) || i == TFWeaponSlot_Melee)
			{
				continue;
			}
	
			int clip = GetEntProp(weapon, Prop_Data, "m_iClip1");
			if (clip != -1)
			{
				SetEntProp(weapon, Prop_Data, "m_iClip1", 0);
			}
	
			clip = GetEntProp(weapon, Prop_Data, "m_iClip2");
			if (clip != -1)
			{
				SetEntProp(weapon, Prop_Data, "m_iClip2", 0);
			}
			
			// Disable demo shield
			SetEntPropFloat(client, Prop_Send, "m_flChargeMeter", 0.0);

			Client_SetWeaponPlayerAmmoEx(client, weapon, 0, 0);
			
		}
		
		isStripped[client] = true;
		
		// OLD METHOD
		/*
		new primary = GetPlayerWeaponSlot(client, 0);
		new secondary = GetPlayerWeaponSlot(client, 1);
		new melee = GetPlayerWeaponSlot(client, 2);
		
		if (!IsValidEntity(primary))
		{
			//PrintToServer("[JAILBREAK] WARNING Invalid primary weapon slot: %i", primary);
		}
		else if(slot == 0 || slot == -1)
		{
			char name[64];
			GetEdictClassname(primary, name, sizeof(name));
			//PrintToChatAll("primary: %s", name);
			new iOffset = GetEntProp(primary, Prop_Send, "m_iPrimaryAmmoType", 1) * 4;
			new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
			SetEntData(client, iAmmoTable + iOffset, 0, 4, true);
			
			// Don't strip clip from a weapon that doesn't have a clip!
			// THE WIDOWMAKER IS NOT WORKING. As the default engineer shotgun and the widowmaker share the same entity,
			// it'd leave the default shotgun have a clip, but stripping it would make the widowmaker unusable.
			if (!StrEqual(name, "tf_weapon_sniperrifle") && !StrEqual(name, "tf_weapon_flamethrower") && !StrEqual(name, "tf_weapon_minigun"))
			{
				new iAmmoClip = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				SetEntData(primary, iAmmoClip, 0, 4, true);
				//PrintToServer("[JAILBREAK] Successfully stripped ammo from primary");
			}
		}
		
		if (!IsValidEntity(secondary))
		{
			//PrintToServer("[JAILBREAK] WARNING Invalid secondary weapon slot: %i", secondary);
		}
		else if(slot == 1 || slot == -1)
		{
			char name[64];
			GetEdictClassname(secondary, name, sizeof(name));
			
			//if (!StrEqual(name, "tf_weapon_jar") && !StrEqual(name, "tf_weapon_jar_milk") && !StrEqual(name, "tf_weapon_cleaver"))
			//{
				new iOffset = GetEntProp(secondary, Prop_Send, "m_iPrimaryAmmoType", 1) * 4;
				new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
				SetEntData(client, iAmmoTable + iOffset, 0, 4, true);
			//}
			
			// Don't strip clip from a weapon that doesn't have a clip!
			//if (!StrEqual(name, "tf_weapon_flaregun") && !StrEqual(name, "tf_weapon_flaregun_revenge") && !StrEqual(name, "tf_weapon_jar") && !StrEqual(name, "tf_weapon_jar_milk") && !StrEqual(name, "tf_weapon_cleaver"))
			//{
				new iAmmoClip = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				SetEntData(secondary, iAmmoClip, 0, 4, true);
				//PrintToServer("[JAILBREAK] Successfully stripped ammo from secondary");
			//}
		}
		
		if (!IsValidEntity(melee))
		{
			//PrintToServer("[JAILBREAK] WARNING Invalid melee weapon slot: %i", melee);
		}
		else if(slot == 2)
		{
			char name[64];
			GetEdictClassname(melee, name, sizeof(name));
			new iOffset = GetEntProp(melee, Prop_Send, "m_iPrimaryAmmoType", 1) * 4;
			new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
			SetEntData(client, iAmmoTable + iOffset, 0, 4, true);
		}
		*/
	}
}

//////////////////////////////
// P L A Y E R  K I L L E D //
//////////////////////////////
// -
// - Triggers when a player is killed
// -
public Player_Death(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetConVarBool(g_jbIsEnabled))
	{
		CreateTimer(0.5, timer_teamcheck);
		
		if(GetConVarBool(g_jbAmmoRemove))
		{
			int victim = GetClientOfUserId(GetEventInt(event, "userid"));
			int ammopack = -1;
			
			while ((ammopack = FindEntityByClassname(ammopack, "tf_ammo_pack")) != -1)
			{
				if(GetEntPropEnt(ammopack, Prop_Send, "m_hOwnerEntity") == victim)
					AcceptEntityInput(ammopack, "Kill");
			}
		}
		
		if(GetConVarBool(g_jbSoulRemove))
		{
			int soul = -1;
			
			while ((soul = FindEntityByClassname(soul, "halloween_souls_pack")) != -1)
			{
				AcceptEntityInput(soul, "Kill");
			}
		}
	}
}

/////////////////////////////////////////
// P L A Y E R  K I L L E D  ( P R E ) //
/////////////////////////////////////////
// -
// - Triggers when a player is killed (Pre), used for stripping ammo before dying
// -
/*
public Player_Death_Pre(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetConVarBool(g_jbIsEnabled))
	{
		int victim = GetClientOfUserId(GetEventInt(event, "userid"));
		StripAmmo(victim);
	}
}
*/

//////////////////////////
// C H E C K   T E A M S//
//////////////////////////
// -
// - Check teams, and activate LR if only 1 red player is left
// -
public Action:timer_teamcheck(Handle:timer)
{
	if(roundGoing)
	{
		int red = CheckTeamNum(TF_TEAM_RED);
		if (red == 1)
		{
			isLRActive = true;
		}
	}
}

int CheckTeamNum(team)
{
	int ct = 0;
	int t = 0;
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (GetClientTeam(i) == TF_TEAM_RED)
				ct++;
			else if (GetClientTeam(i) == TF_TEAM_BLU)
				t++;
		}
	}
	
	if (team == TF_TEAM_RED)
	{
		return ct;
	}
	else if (team == TF_TEAM_BLU)
	{
		return t;
	}
	else
	{
		PrintToServer("[JAILBREAK] Invalid team: %i", team);
		return -1;
	}
}

///////////////////////////////////
// U P D A T E   L R   T I M E R //
///////////////////////////////////
//
// - Returns a time from seconds, in mm:ss format.
//
String:FormatTimer(float sec)
{
	int cTime = RoundFloat(sec);
	int cmin = cTime / 60;
	int csec = cTime % 60;
	char ctext[32];
	if (csec < 10 && cmin >= 10)
		ctext = "%i:0%i";
	else if (csec < 10 && cmin < 10)
		ctext = "0%i:0%i";
	else if (csec >= 10 && cmin < 10)
		ctext = "0%i:%i";
	else
		ctext = "%i:%i";
	
	Format(ctext, sizeof(ctext), ctext, cmin, csec);
	
	return ctext;
}

/////////////////////////////
// U P D A T E   T I M E R //
/////////////////////////////
//
// - Update the normal + lr timer (if possible), play sounds if under 10 seconds
//
public Action:UpdateTimers(Handle:timer)
{
	// Keep disabling the demo shield for stripped players
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsValidClient(i, false))
		{
			if (isStripped[i])
			{
				SetEntPropFloat(i, Prop_Send, "m_flChargeMeter", 0.0);
			}
		}
	}
	
	// If there is only 1 player, don't show the timer
	if(GetClientCount() > 1)
	{
		for (int i = 1; i < MaxClients; i++)
		{
			if (GetConVarBool(g_jbIsEnabled) && !gameEnd)
			{
				if (IsValidClient(i, false))
				{
					SetHudTextParams(-1.0, 0.20, 2.0, 0, 0, 255, 255);
					ShowSyncHudText(i, hudTimer, "%s", FormatTimer(timerTime));
					
					if (isLRActive)
					{
						SetHudTextParams(-1.0, 0.25, 2.0, 255, 0, 0, 255);
						ShowSyncHudText(i, hudLRTimer, "LR Time: %s", FormatTimer(LRtime));
					}
				}
			}
		}
	}
	if (roundGoing && GetConVarBool(g_jbIsEnabled))
	{
		if(GetClientCount() < 2) {
			roundGoing = false;
		}
		
		if (timerTime > 0.0)
		{
			if (timerTime <= 10.0)
			{
				switch (timerTime)
				{
					case 10.0:
					EmitSoundToAll(SOUND_10SEC);
					case 5.0:
					EmitSoundToAll(SOUND_5SEC);
					case 4.0:
					EmitSoundToAll(SOUND_4SEC);
					case 3.0:
					EmitSoundToAll(SOUND_3SEC);
					case 2.0:
					EmitSoundToAll(SOUND_2SEC);
					case 1.0:
					EmitSoundToAll(SOUND_1SEC);
				}
			}
			timerTime--;
		}
		else
			StaleMate();
		
		if (isLRActive && LRtime > 0.0)
			LRtime--;
	}
}


/////////////////////////////////////
// C R E A T E   S T A L E M A T E //
/////////////////////////////////////
// -
// - Create the stalemate entity, for triggering the stalemate
// -
public CreateStaleMate()
{
	ent_stalemate = CreateEntityByName("game_round_win");
	
	if (IsValidEntity(ent_stalemate))
	{
		DispatchKeyValue(ent_stalemate, "force_map_reset", "1");
		DispatchKeyValue(ent_stalemate, "targetname", "win_blue");
		DispatchKeyValue(ent_stalemate, "teamnum", "0");
		SetVariantInt(0);
		AcceptEntityInput(ent_stalemate, "SetTeam");
		if (!DispatchSpawn(ent_stalemate))
			PrintToServer("[JAILBREAK] ENTITY ERROR Failed to dispatch stalemate entity");
	}
}

///////////////////////////////////////
// S T A L E M A T E   T R I G G E R //
///////////////////////////////////////
// -
// - Trigger the stalemate entity, making the game end.
// -
public StaleMate()
{
	if (IsValidEntity(ent_stalemate))
		AcceptEntityInput(ent_stalemate, "RoundWin");
	else
		PrintToServer("[JAILBREAK] Tried to call stalemate, but the entity doesn't exist...");
}

///////////////////////////////////
// F O R C E   S T A L E M A T E //
///////////////////////////////////
// -
// - Force stalemate
// -
public Action:Command_JB_ForceStaleMate(client, args)
{
	if (GetConVarBool(g_jbIsEnabled))
	{
		if (IsValidEntity(ent_stalemate))
		{
			AcceptEntityInput(ent_stalemate, "RoundWin");
			ReplyToCommand(client, "[JAILBREAK] Successfully forced stalemate");
		}
		else
			ReplyToCommand(client, "[JAILBREAK] Could not find stalemate entity");
	} else {
		ReplyToCommand(client, "[JAILBREAK] The jailbreak plugin is not active.");
	}
	return Plugin_Handled;
}

///////////////////////////////////
// I S   V A L I D   C L I E N T //
///////////////////////////////////
// -
// - Check if a client is valid, ingame, or optionally alive.
// -
stock bool:IsValidClient(client, bool:bCheckAlive = true)
{
	if (client < 1 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (IsClientSourceTV(client) || IsClientReplay(client))return false;
	if (bCheckAlive)return IsPlayerAlive(client);
	return true;
}

/////////////////////
// P R E C A C H E //
/////////////////////
// -
// - Precache assets
// -
Precache()
{
	// S O U N D S //
	PrecacheSound(SOUND_10SEC, true);
	PrecacheSound(SOUND_5SEC, true);
	PrecacheSound(SOUND_4SEC, true);
	PrecacheSound(SOUND_3SEC, true);
	PrecacheSound(SOUND_2SEC, true);
	PrecacheSound(SOUND_1SEC, true);
} 

/////////////////
// S T O C K S //
/////////////////

stock GetSlotFromPlayerWeapon(client, weapon)
{
	for (new i = 0; i <= 5; i++)
	{
		//PrintToChatAll("Player: %N, Slot: %i, Weapon: %i == %i", client, i, GetPlayerWeaponSlot(client, i), weapon);
		if (weapon == GetPlayerWeaponSlot(client, i))
		{
			return i;
		}
	}
	return -1;
}  