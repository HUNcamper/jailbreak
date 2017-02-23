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
#define SOUND_9SEC			"vo/announcer_ends_9sec.mp3"
#define SOUND_8SEC			"vo/announcer_ends_8sec.mp3"
#define SOUND_7SEC			"vo/announcer_ends_7sec.mp3"
#define SOUND_6SEC			"vo/announcer_ends_6sec.mp3"
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
Handle g_jbSetupTime;
Handle g_jbExecCommands;

// Global variables
bool isLRActive;
float LRtime;
float timerTime;
//char LRtext[32];

// Entity variables (they store the entity ID, not the entity itself)
new ent_stalemate, ent_normaltimer;

// HUD elements
Handle hudLRTimer;
Handle hudTimer;

// Client Arrays
Handle jbHUD[MAXPLAYERS + 1]; // Each player's HUD timer

// Timers
Handle globalTimer;

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
	g_jbSetupTime = CreateConVar("jb_timer_setup", "10", "Setup timer (in seconds)");
	g_jbExecCommands = CreateConVar("jb_commands_after_setup", "sm_say setup ended!", "Commands to execute after setup time ended");
	
	// V A R I A B L E S //
	isLRActive = false;
	LRtime = GetConVarFloat(g_lrTime);
	
	// A D M I N   C O M M A N D S //
	RegAdminCmd("sm_forcestalemate", Command_JB_ForceStaleMate, ADMFLAG_ROOT, "sm_forcestalemate");
	
	// H O O K S //
	HookEvent("teamplay_round_start", teamplay_round_start);
	HookEvent("teamplay_setup_finished", teamplay_setup_finished);
	HookEvent("player_death", Player_Death);
	
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
	
	globalTimer = CreateTimer(1.0, UpdateTimers, _, TIMER_REPEAT);
	
	Precache();
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
	
	for (new i = 1; KvizExists(kv, ":nth-child(%i)", i); i++)
	{
		decl String:map[32], Float:ctime, Float:csetuptime, Float:clrtime;
		
		KvizGetStringExact(kv, map, sizeof(map), ":nth-child(%i):key", i);
		if(StrEqual(map, currmap, false))
		{
			if(!KvizGetFloatExact(kv, ctime, ":nth-child(%i).roundtime", i)) ctime=GetConVarFloat(g_jbTime);
			if(!KvizGetFloatExact(kv, csetuptime, ":nth-child(%i).setuptime", i)) ctime=GetConVarFloat(g_jbSetupTime);
			if(!KvizGetFloatExact(kv, clrtime, ":nth-child(%i).lrtime", i)) ctime=GetConVarFloat(g_lrTime);
			PrintToChatAll("found and loaded");
			break;
		}
	}
	
	KvizClose(kv);
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
public Action:DrawHud(Handle:timer, any:client)
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
	jbHUD[client] = CreateTimer(1.0, DrawHud, client);
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
}

/////////////////////////
// S E T U P   E N D S //
/////////////////////////
//
// - When the setup ends, exec the set commands
//
public teamplay_setup_finished(Handle:event, const String:name[], bool:dontBroadcast)
{
	char buffer[32][128]; char current[256];
	GetConVarString(g_jbExecCommands, current, sizeof(current));
	ExplodeString(current, ";", buffer, sizeof(buffer), sizeof(buffer[]));
	
	for (int i = 0; i < sizeof(buffer); i++)
		ServerCommand(buffer[i]);
}

//////////////////////////////
// P L A Y E R  K I L L E D //
//////////////////////////////
// -
// - Triggers when a player is killed
// -
public Player_Death(Handle:event, const String:name[], bool:dontBroadcast)
{
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

PlaySoundToAll(String:sound)
{
	EmitSoundToClient(client, SOUND_FAILED, client, _, _, _, 1.0);
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
		else
			PrintToServer("[JAILBREAK] Created stalemate entity");
	}
}

// The code below is PROBABLY not needed.
//
///////////////////////////
// K I L L   T I M E R S //
///////////////////////////
// -
// - Kill all timer entities, if they already exist on the map, then add the custom ones.
// -
/*
public KillTimerEnts()
{
	// Entity list to be removed
	new String:ents[2][32];
	ents[0] = "game_round_win";
	ents[1] = "team_round_timer";
	
	char cls[32];
	
	// For debugging just remove the // before the lines
	// Variables for debugging
	//int checked = 0;
	//int deleted = 0;
	
	// Roll through all the entities on the map
	for(int i = 0; i <= GetMaxEntities() ; i++)
	{
		// Not valid, don't continue
		if(!IsValidEntity(i))
			continue;
		
		// Store classname in "cls"
		GetEntityClassname(i, cls, sizeof(cls));
		
		for (int b = 0; b < sizeof(ents); b++)
		{
			//checked++;
			
			// If classname equals to one in the list
			if(StrEqual(cls, ents[b], false))
			{
				RemoveEdict(i);
				//deleted++;
			}
		}
	}
	
	//PrintToChatAll("Checked: %i, deleted: %i", checked, deleted);
	//PrintToChatAll("Creating map timer and winround entities");
	
	
	// Stalemate entity, for triggering on round end
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
		else
			PrintToServer("[JAILBREAK] Created stalemate entity");
	}
	
	ent_normaltimer = CreateEntityByName("team_round_timer");
	char jbtime[32];
	char setuptime[32];
	GetConVarString(g_jbTime, jbtime, sizeof(jbtime));
	GetConVarString(g_jbSetupTime, setuptime, sizeof(setuptime));
	
	if (IsValidEntity(ent_normaltimer))
	{
		DispatchKeyValue(ent_normaltimer, "targetname", "timer_nobomb");
		DispatchKeyValue(ent_normaltimer, "StartDisabled", "0");
		DispatchKeyValue(ent_normaltimer, "start_paused", "0");
		DispatchKeyValue(ent_normaltimer, "show_time_remaining", "1");
		DispatchKeyValue(ent_normaltimer, "show_in_hud", "1");
		DispatchKeyValue(ent_normaltimer, "reset_time", "1");
		DispatchKeyValue(ent_normaltimer, "max_length", "121");
		DispatchKeyValue(ent_normaltimer, "auto_countdown", "1");
		DispatchKeyValue(ent_normaltimer, "timer_length", jbtime);
		DispatchKeyValue(ent_normaltimer, "setup_length", setuptime);
		DispatchSpawn(ent_normaltimer);
		HookSingleEntityOutput(ent_normaltimer, "OnFinished", Hook_Timeout, true);
		PrintToServer("[JAILBREAK] Created nobomb timer entity");
		AcceptEntityInput(ent_normaltimer, "Enable");
	}
	else
		PrintToServer("[JAILBREAK] Failed to create nobomb timer entity");
}
*/

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
	if(IsValidEntity(ent_stalemate))
	{
		AcceptEntityInput(ent_stalemate, "RoundWin");
		ReplyToCommand(client, "[JAILBREAK] Successfully forced stalemate");
	}
	else
		ReplyToCommand(client, "[JAILBREAK] Could not find stalemate entity");
	
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
	PrecacheSound(SOUND_9SEC, true);
	PrecacheSound(SOUND_8SEC, true);
	PrecacheSound(SOUND_7SEC, true);
	PrecacheSound(SOUND_6SEC, true);
	PrecacheSound(SOUND_5SEC, true);
	PrecacheSound(SOUND_4SEC, true);
	PrecacheSound(SOUND_3SEC, true);
	PrecacheSound(SOUND_2SEC, true);
	PrecacheSound(SOUND_1SEC, true);
}