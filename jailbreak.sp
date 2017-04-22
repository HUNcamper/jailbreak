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
//#include <sdkhooks>

// Convars
Handle g_jbTime;
Handle g_lrTime;
Handle g_jbExecCommands;
Handle g_jbIsEnabled;
Handle g_jbSoulRemove;
Handle g_jbTeamBalance;
Handle g_jbAutoBalance;
Handle g_jbAmmoRemove;

// Global variables
bool isLRActive;
float LRtime;
float timerTime;
bool gameEnd;
bool roundGoing;
//bool nextRoundBalance; // unused
//char LRtext[32];

// Entity variables (they store the entity ID, not the entity itself)
new ent_stalemate;

// HUD elements
Handle hudLRTimer;
Handle hudTimer;

// Client Arrays
//Handle jbHUD[MAXPLAYERS + 1]; // Each player's HUD timer

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
	//HookEvent("player_team", player_team, EventHookMode_Pre);
	HookEvent("teamplay_round_stalemate", EndGame_StaleMate);
	HookEvent("teamplay_round_win", EndGame_Win);
	
	// H U D   E L E M E N T S //
	hudLRTimer = CreateHudSynchronizer();
	hudTimer = CreateHudSynchronizer();
	
	// O T H E R //
	LoadTranslations("common.phrases"); // Load common translation file
	
	for (int i = 1; i <= MaxClients; i++)
	{
		OnClientPostAdminCheck(i);
	}
	
	PrintToChatAll("\x05JailBreak Plugin\x01 loaded, restarting game");
	ServerCommand("mp_restartgame 1");
	
	CreateTimer(1.0, UpdateTimers, _, TIMER_REPEAT);
	
	Precache();
	
	reloadConfig();
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
public OnClientPostAdminCheck(client)
{
	//if(IsValidClient(client, false) && client != 0)
	//jbHUD[client] = CreateTimer(5.0, DrawHud, client); // Create a HUD timer for the player
}

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

/*
////////////////////
// D R A W  H U D //
////////////////////
//
// - Draw the timer hud
//
public Action:DrawHud(Handle:timer, any:client)
{
	
	if(GetConVarBool(g_jbIsEnabled))
	{
		if(IsValidClient(client))
		{
			SetHudTextParams(-1.0, 0.10, 2.0, 0, 0, 255, 255);
			ShowSyncHudText(client, hudTimer, "%s", FormatTimer(timerTime));
			
			if(isLRActive)
			{
				SetHudTextParams(-1.0, 0.15, 2.0, 255, 0, 0, 255);
				ShowSyncHudText(client, hudLRTimer, "LR timer: %s", FormatTimer(LRtime));
			}
		}
	}
	
	//jbHUD[client] = CreateTimer(1.0, DrawHud, client);
}
*/

///////////////////////////////////////////////////
// D E L E T E   S O U L S / A M M O   P A C K S //
///////////////////////////////////////////////////
//
// - Delete the souls or ammo packs when killed
//
/*
public void OnEntityCreated(int iEnt, char classname[32])
{
	if (GetConVarBool(g_jbIsEnabled) && (GetConVarBool(g_jbSoulRemove) || GetConVarBool(g_jbAmmoRemove)))
	{
		if (IsValidEntity(iEnt))
		{
			if (GetConVarBool(g_jbSoulRemove) && StrEqual(classname, "halloween_souls_pack"))
			{
				AcceptEntityInput(iEnt, "Kill");
				PrintToChatAll("%s", classname);
			} 
			else if(GetConVarBool(g_jbAmmoRemove) && StrEqual(classname, "tf_ammo_pack"))
			{
				AcceptEntityInput(iEnt, "Kill");
				PrintToChatAll("%s", classname);
			} 
		}
	}
}
*/

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
			if (IsValidClient(i) && GetClientTeam(i) == TF_TEAM_RED)
			{
				StripAmmo(i);
			}
		}
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
		// old stuff, for event
		//new client = GetClientOfUserId(GetEventInt(event, "userid"));
		//new oldteam = GetEventInt(event, "oldteam");
		//new newteam = GetEventInt(event, "team");
		
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
				int substraction = red - blue;
				for (int i = 0; i < substraction; i++)
				{
					PrintToChat(reds[a-1], "[JAILBREAK] You have been auto balanced.");
					TF2_ChangeClientTeam(reds[a-1], TFTeam_Blue);
					a--;
				}
			}
			else if(blue > red)
			{
				int substraction = blue - red;
				for (int i = 0; i < substraction; i++)
				{
					PrintToChat(blus[b-1], "[JAILBREAK] You have been auto balanced.");
					TF2_ChangeClientTeam(blus[b-1], TFTeam_Red);
					b--;
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
public StripAmmo(int client)
{
	if (GetConVarBool(g_jbIsEnabled))
	{
		new primary = GetPlayerWeaponSlot(client, 0);
		new secondary = GetPlayerWeaponSlot(client, 1);
		new melee = GetPlayerWeaponSlot(client, 2);
		
		if (!IsValidEntity(primary))
		{
			PrintToServer("[JAILBREAK] WARNING Invalid primary weapon slot: %i", primary);
		}
		else
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
			}
		}
		
		if (!IsValidEntity(secondary))
		{
			PrintToServer("[JAILBREAK] WARNING Invalid secondary weapon slot: %i", secondary);
		}
		else
		{
			char name[64];
			GetEdictClassname(secondary, name, sizeof(name));
			//PrintToChatAll("secondary: %s", name);
			new iOffset = GetEntProp(secondary, Prop_Send, "m_iPrimaryAmmoType", 1) * 4;
			new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
			SetEntData(client, iAmmoTable + iOffset, 0, 4, true);
			
			// Don't strip clip from a weapon that doesn't have a clip!
			if (!StrEqual(name, "tf_weapon_flaregun") && !StrEqual(name, "tf_weapon_flaregun_revenge"))
			{
				new iAmmoClip = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				SetEntData(secondary, iAmmoClip, 0, 4, true);
			}
		}
		
		if (!IsValidEntity(melee))
		{
			PrintToServer("[JAILBREAK] WARNING Invalid melee weapon slot: %i", melee);
		}
		else
		{
			char name[64];
			GetEdictClassname(melee, name, sizeof(name));
			//PrintToChatAll("melee: %s", name);
			new iOffset = GetEntProp(melee, Prop_Send, "m_iPrimaryAmmoType", 1) * 4;
			new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
			SetEntData(client, iAmmoTable + iOffset, 0, 4, true);
		}
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
		int ammopack = -1;
		int soul = -1;
		int victim = GetClientOfUserId(GetEventInt(event, "userid"));
		
		if(GetConVarBool(g_jbAmmoRemove))
		{
		    while ((ammopack = FindEntityByClassname(ammopack, "tf_ammo_pack")) != -1)
		    {
				if(GetEntPropEnt(ammopack, Prop_Send, "m_hOwnerEntity") == victim)
					AcceptEntityInput(ammopack, "Kill");
		    }
		}
		
		if(GetConVarBool(g_jbSoulRemove))
		{
		    while ((soul = FindEntityByClassname(soul, "halloween_souls_pack")) != -1)
		    {
				AcceptEntityInput(soul, "Kill");
		    }
		}
	}
}

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
		//PrintToChatAll("RED: %i", red);
		if (red == 1)
		{
			isLRActive = true;
			//CreateTimer(1.0, updateLR);
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
	for (int i = 1; i < MaxClients; i++)
	{
		if (GetConVarBool(g_jbIsEnabled) && !gameEnd)
		{
			if (IsValidClient(i, false))
			{
				SetHudTextParams(-1.0, 0.15, 2.0, 0, 0, 255, 255);
				ShowSyncHudText(i, hudTimer, "%s", FormatTimer(timerTime));
				
				if (isLRActive)
				{
					SetHudTextParams(-1.0, 0.20, 2.0, 255, 0, 0, 255);
					ShowSyncHudText(i, hudLRTimer, "LR Time: %s", FormatTimer(LRtime));
				}
			}
		}
	}
	if (roundGoing && GetConVarBool(g_jbIsEnabled))
	{
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
		//else
		//PrintToServer("[JAILBREAK] Created stalemate entity");
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