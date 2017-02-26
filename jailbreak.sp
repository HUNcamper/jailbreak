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

// Global variables
bool isLRActive;
float LRtime;
float timerTime;
//char LRtext[32];

// Entity variables (they store the entity ID, not the entity itself)
new ent_stalemate;

// HUD elements
Handle hudLRTimer;
Handle hudTimer;

// Client Arrays
Handle jbHUD[MAXPLAYERS + 1]; // Each player's HUD timer

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
	if(GetEngineVersion() != Engine_TF2) // If game isn't TF2
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
	
	// V A R I A B L E S //
	isLRActive = false;
	LRtime = GetConVarFloat(g_lrTime);
	
	// A D M I N   C O M M A N D S //
	RegAdminCmd("sm_forcestalemate", Command_JB_ForceStaleMate, ADMFLAG_ROOT, "sm_forcestalemate");
	RegAdminCmd("sm_stripammo", Command_JB_StripAmmo, ADMFLAG_ROOT, "sm_stripammo <Player>");
	RegAdminCmd("sm_reloadjbconfig", Command_JB_ReloadConfig, ADMFLAG_ROOT, "sm_reloadjbconfig");
	
	// H O O K S //
	HookEvent("teamplay_round_start", teamplay_round_start);
	HookEvent("arena_round_start", arena_round_start);
	HookEvent("player_death", Player_Death);
	HookEvent("player_spawn", player_spawn); 
	
	// H U D   E L E M E N T S //
	hudLRTimer = CreateHudSynchronizer();
	hudTimer = CreateHudSynchronizer();
	
	// O T H E R //
	LoadTranslations("common.phrases"); // Load common translation file
	
	for(int i = 1; i <= MaxClients; i++)
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
	
	if(kv != INVALID_HANDLE)
	{
		for (new i = 1; KvizExists(kv, ":nth-child(%i)", i); i++)
		{
			decl String:map[32], Float:ctime, String:caftersetup[256], Float:clrtime;
			int cenabled;
			
			KvizGetStringExact(kv, map, sizeof(map), ":nth-child(%i):key", i);
			if(StrEqual(map, currmap, false))
			{
				if(KvizGetFloatExact(kv, ctime, ":nth-child(%i).roundtime", i)) SetConVarFloat(g_jbTime, ctime);
				if(KvizGetFloatExact(kv, clrtime, ":nth-child(%i).lrtime", i)) SetConVarFloat(g_lrTime, clrtime);
				if(KvizGetStringExact(kv, caftersetup, sizeof(caftersetup), ":nth-child(%i).aftersetup", i)) SetConVarString(g_jbExecCommands, caftersetup);
				if(KvizGetNumExact(kv, cenabled, ":nth-child(%i).enabled", i)) SetConVarInt(g_jbIsEnabled, cenabled);
				PrintToServer("[JAILBREAK] Map config present and loaded.");
				break;
			}
		}
		
		KvizClose(kv);
	}
	else
	{
		PrintToServer("[JAILBREAK] There is no map config present!");
	}
}

////////////////////////////////////
// C L I E N T  C O N N E C T E D //
////////////////////////////////////
public OnClientPostAdminCheck(client)
{
	if(IsValidClient(client, false) && client != 0)
		jbHUD[client] = CreateTimer(5.0, DrawHud, client); // Create a HUD timer for the player
}

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
	jbHUD[client] = CreateTimer(1.0, DrawHud, client);
}

/////////////////////////////
// D E L E T E   S O U L S //
/////////////////////////////
//
// - Delete the souls when killed
//
public void OnEntityCreated(int iEnt,char classname[32])
{
	if(GetConVarBool(g_jbIsEnabled))
	{
		if(GetConVarBool(g_jbSoulRemove))
		{
		    if(IsValidEntity(iEnt) && StrEqual(classname,"halloween_souls_pack"))
		    {
		        AcceptEntityInput(iEnt,"Kill");
		    }
	   	}
   	}
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
	if(GetConVarBool(g_jbIsEnabled))
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
			StripAmmo(target_list[i]);
		}
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
	//KillTimerEnts();
	CreateStaleMate();
		
	timerTime = GetConVarFloat(g_jbTime);
	
	if(GetConVarBool(g_jbIsEnabled))
	{
		for (int i = 0; i <= MaxClients; i++)
		{
			if(IsValidClient(i) && GetClientTeam(i) == TF_TEAM_RED)
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
	if(GetConVarBool(g_jbIsEnabled))
	{
		char buffer[32][128]; char current[256];
		GetConVarString(g_jbExecCommands, current, sizeof(current));
		ExplodeString(current, ";", buffer, sizeof(buffer), sizeof(buffer[]));
		
		for (int i = 0; i < sizeof(buffer); i++)
			ServerCommand(buffer[i]);
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
	if(GetConVarBool(g_jbIsEnabled))
	{
		new client = GetClientOfUserId(GetEventInt(event, "userid")); // Get client
		if(GetClientTeam(client) == TF_TEAM_RED)
	    StripAmmo(client);
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
	if(GetConVarBool(g_jbIsEnabled))
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
			new iOffset = GetEntProp(primary, Prop_Send, "m_iPrimaryAmmoType", 1)*4;
			new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
			SetEntData(client, iAmmoTable+iOffset, 0, 4, true);
			
			// Don't strip clip from a weapon that doesn't have a clip!
			if(!StrEqual(name, "tf_weapon_sniperrifle") && !StrEqual(name, "tf_weapon_flamethrower") && !StrEqual(name, "tf_weapon_minigun"))
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
			new iOffset = GetEntProp(secondary, Prop_Send, "m_iPrimaryAmmoType", 1)*4;
			new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
			SetEntData(client, iAmmoTable+iOffset, 0, 4, true);
			
			// Don't strip clip from a weapon that doesn't have a clip!
			if(!StrEqual(name, "tf_weapon_flaregun") && !StrEqual(name, "tf_weapon_flaregun_revenge"))
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
			new iOffset = GetEntProp(melee, Prop_Send, "m_iPrimaryAmmoType", 1)*4;
			new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
			SetEntData(client, iAmmoTable+iOffset, 0, 4, true);
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
	if(GetConVarBool(g_jbIsEnabled))
		CreateTimer(0.5, timer_teamcheck);
}

//////////////////////////
// C H E C K   T E A M S//
//////////////////////////
// -
// - Check teams, and activate LR if only 1 red player is left
// -
public Action:timer_teamcheck(Handle:timer)
{
	int red = CheckTeamNum(TF_TEAM_RED);
	PrintToChatAll("RED: %i", red);
	if(red == 1)
	{
		isLRActive = true;
		//CreateTimer(1.0, updateLR);
	}
}

int CheckTeamNum(team)
{
	int ct = 0;
	int t = 0;
	for (int i = 1; i < MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			if(GetClientTeam(i) == TF_TEAM_RED)
				ct++;
			else if(GetClientTeam(i) == TF_TEAM_BLU)
				t++;
		}
	}
	
	if(team == TF_TEAM_RED)
	{
		return ct;
	}
	else if(team == TF_TEAM_BLU)
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
// - Return a time from seconds, in mm:ss format.
//
String:FormatTimer(float sec)
{
	int cTime = RoundFloat(sec);
	int cmin = cTime / 60;
	int csec = cTime % 60;
	char ctext[32];
	if(csec < 10 && cmin >= 10)
		ctext = "%i:0%i";
	else if(csec < 10 && cmin < 10)
		ctext = "0%i:0%i";
	else if(csec >= 10 && cmin < 10)
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
	if(timerTime > 0.0)
	{
		if(timerTime <= 10.0)
		{
			switch(timerTime)
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
	
	if(isLRActive && LRtime > 0.0)
		LRtime--;
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
	if(IsValidEntity(ent_stalemate))
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
	if(GetConVarBool(g_jbIsEnabled))
	{
		if(IsValidEntity(ent_stalemate))
		{
			AcceptEntityInput(ent_stalemate, "RoundWin");
			ReplyToCommand(client, "[JAILBREAK] Successfully forced stalemate");
		}
		else
			ReplyToCommand(client, "[JAILBREAK] Could not find stalemate entity");
	}
	return Plugin_Handled;
}

///////////////////////////////////
// I S   V A L I D   C L I E N T //
///////////////////////////////////
// -
// - Check if a client is valid, ingame, or optionally alive.
// -
stock bool:IsValidClient(client, bool:bCheckAlive=true)
{
	if(client < 1 || client > MaxClients) return false;
	if(!IsClientInGame(client)) return false;
	if(IsClientSourceTV(client) || IsClientReplay(client)) return false;
	if(bCheckAlive) return IsPlayerAlive(client);
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