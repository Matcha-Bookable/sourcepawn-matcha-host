#include <sourcemod>
#include <morecolors>
#include <sdktools>
#include <f2stocks>

public Plugin myinfo = 
{
    name = "Matcha Bookable Host",
    author = "avan",
    description = "Host tools for Matcha Bookable",
    version = "1.1.0",
    url = "https://discord.gg/8ysCuREbWQ"
};

char g_charHost[MAX_AUTHID_LENGTH] = ""; // For storing the host's SteamID
char g_charHostName[MAX_NAME_LENGTH]; // For storing the host's name

#define MAX_CONFIGS 32
#define CONFIG_LEAGUE 0
#define CONFIG_NAME 1 
#define CONFIG_PATH 2

bool g_boolConfigCD = false; // Cooldown tracking
char g_charConfigs[MAX_CONFIGS][3][128]; // [config_index][league/name/path][string]
int g_iConfigCount = 0; // Track number of configs loaded

ArrayList g_arrayBanlist; // Storing the list of banned players in the bookable

public void OnPluginStart() {
    RegConsoleCmd("sm_host", Command_Host, "Allow host to access the host tool");

    g_arrayBanlist = new ArrayList(ByteCountToCells(MAX_AUTHID_LENGTH));
    
    // Initialize config counter
    g_iConfigCount = 0;
    
    ParseKV(); // Configs
}

public void OnMapStart() {
    g_boolConfigCD = false; // timer doesn't carry over
}

void ParseKV() {
    char path[128] = "cfg/comp/config.txt";
    if (!FileExists(path)) {
        SetFailState("Configuration file %s cannot be found.", path);
        return;
    }

    // KeyValues Creation
    KeyValues kv = new KeyValues("Server Configs");

    if (!kv.ImportFromFile(path)) {
        SetFailState("Configuration file %s cannot be parsed.", path);
        delete kv;
        return;
    }

    // Navigate to first league section
    if (kv.GotoFirstSubKey()) {
        do {
            char leagueName[64];
            kv.GetSectionName(leagueName, sizeof(leagueName));
            
            // Navigate to config sections within this league
            if (kv.GotoFirstSubKey()) {
                do {
                    char configName[64];
                    char configPath[128];
                    
                    kv.GetSectionName(configName, sizeof(configName));
                    kv.GetString("path", configPath, sizeof(configPath));
                    
                    if (g_iConfigCount < MAX_CONFIGS) {
                        strcopy(g_charConfigs[g_iConfigCount][CONFIG_LEAGUE], 128, leagueName);
                        strcopy(g_charConfigs[g_iConfigCount][CONFIG_NAME], 128, configName);
                        strcopy(g_charConfigs[g_iConfigCount][CONFIG_PATH], 128, configPath);
                        g_iConfigCount++;
                    }
                    
                } while (kv.GotoNextKey());
                kv.GoBack();
            }
            
        } while (kv.GotoNextKey());
    }
    
    delete kv;
}

public void OnClientAuthorized(int client, const char[] auth) {
    // Cannot kick the player from this event, mp_tournament_restart triggers for some reason (???)
}

public void OnClientPutInServer(int client) {
    // Make sure its a real player
    if (!IsRealPlayer(client) && !IsRealPlayer2(client)) {
        return;
    }

    if (StrEqual(g_charHost, "")) { // initial host
        GetClientAuthId(client, AuthId_Steam2, g_charHost, sizeof(g_charHost));
        GetClientName(client, g_charHostName, sizeof(g_charHostName));
        CreateTimer(5.0, Timer_HostIntroduction, client);
    }

    char auth[MAX_AUTHID_LENGTH];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));

    // loop through arraylist
    for (int i = 0; i < g_arrayBanlist.Length; i++) {
        char bannedSteam[MAX_AUTHID_LENGTH];
        g_arrayBanlist.GetString(i, bannedSteam, sizeof(bannedSteam));

        if (StrEqual(auth, bannedSteam)) { // if the user is banned
            KickClient(client, "You are banned from this bookable server");
            break;
        }
    }
}

public void Timer_HostIntroduction(Handle timer, int client) {
    MC_PrintToChat(client, "{red}[Matcha]{default} You are the host, you may use !host to access the host panel.");
}

public Action Command_Host(int client, int args) {
    if (!IsRealPlayer(client) && !IsRealPlayer2(client)) { // Make sure the client is legit
        ReplyToCommand(client, "[SM] Unknown client");
        return Plugin_Handled;
    } 

    char auth[MAX_AUTHID_LENGTH];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));

    if (!StrEqual(auth, g_charHost)) { // if not the host
        ReplyToCommand(client, "[SM] %s is the current host of the bookable.", g_charHostName);
        return Plugin_Handled;
    }

    ShowHostMenu(client);

    return Plugin_Handled;
}

public void ShowHostMenu(int client)
{
	Menu menu = new Menu(MenuHandler_MainMenu);
    menu.Pagination = false;

	menu.SetTitle("--- Matcha Host (%s) ---", g_charHostName);

    menu.AddItem("0", "Transfer host"); // Transfer the host to another user
    menu.AddItem("", "", ITEMDRAW_SPACER);
    menu.AddItem("2", "Change map"); // Change map
    menu.AddItem("3", "Change config"); // Change config
    menu.AddItem("4", "Cancel vote"); // Cancel vote (likely to be replaced with ping test in the future)
    menu.AddItem("", "", ITEMDRAW_SPACER);
    menu.AddItem("6", "Kick user"); // Kick user from the bookable
    menu.AddItem("7", "Ban user"); // Ban user from joining this bookable

	menu.ExitButton = true;

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MainMenu(Menu menu, MenuAction action, int client, int selection)
{
	switch(action) {
		case(MenuAction_Select):
		{
			switch(selection)
			{
				case(0): Tools_TransferHost(client);
                
                case(2): Tools_ChangeMap(client);
                case(3): Tools_ChangeConfig(client);
                case(4): Tools_CancelVote(client);

				case(6): Tools_KickUser(client);
                case(7): Tools_BanUser(client);
			}
		}
		case(MenuAction_End):
		{
			delete menu;
		}
	}
    return 0;
}

/*
    ----------------- STOCKS -----------------
*/
void AddPlayersToMenu(Menu menu, ArrayList excludedClients) {
    char clientNameBuffer[32]; // limits to 32 for the menu size
    char clientBuffer[3]; // shouldnt exceed 3 digits
    for (int client = 1; client <= MaxClients; client++) {
        // Check if client is in excludedClients
        bool excluded = false;
        for (int i = 0; i < excludedClients.Length; i++) {
            if (client == excludedClients.Get(i)) {
                excluded = true;
                break;
            }
        }

        if (excluded) continue; // skip
        if (!IsRealPlayer2(client)) continue;

        GetClientName(client, clientNameBuffer, sizeof(clientNameBuffer));
        IntToString(client, clientBuffer, sizeof(clientBuffer));
        menu.AddItem(clientBuffer, clientNameBuffer);
    }  
}

void ReadFullMaplist(ArrayList buffer, const char[] path) {
    File maplist = OpenFile(path, "rt");
    char line[1024];
    while (maplist.ReadLine(line, sizeof(line))) {
        // Remove trailing newline and carriage return
        int len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r')) {
            line[--len] = '\0';
        }
        buffer.PushString(line);
    }
    maplist.Close();
}

void AddMapsToMenu(Menu menu, ArrayList Maps) {
    char mapName[64];
    for (int i = 0; i < Maps.Length; i++) {
        Maps.GetString(i, mapName, sizeof(mapName));
        menu.AddItem(mapName, mapName);
    }
}

void AddLeaguesToMenu(Menu menu) {
    char currentLeague[64];
    char lastLeague[64] = "";
    char indexStr[8];
    int uniqueIndex = 0;
    
    for (int i = 0; i < g_iConfigCount; i++) {
        strcopy(currentLeague, sizeof(currentLeague), g_charConfigs[i][CONFIG_LEAGUE]);
        
        if (!StrEqual(currentLeague, lastLeague)) {
            IntToString(i, indexStr, sizeof(indexStr));
            menu.AddItem(indexStr, currentLeague);
            strcopy(lastLeague, sizeof(lastLeague), currentLeague);
            uniqueIndex++;
        }
    }
}

void AddLeagueConfigToMenu(Menu menu, const char[] selectedLeague) {
    char indexStr[8];
    for (int i = 0; i < g_iConfigCount; i++) {
        if (StrEqual(g_charConfigs[i][CONFIG_LEAGUE], selectedLeague)) {
            IntToString(i, indexStr, sizeof(indexStr));
            menu.AddItem(indexStr, g_charConfigs[i][CONFIG_NAME]);
        }
    }
}


/*
    ----------------------------------------------
    ----------------- MENU TOOLS -----------------
    ----------------------------------------------
*/

/*
    ------------------ TRANSFER HOST ------------------
*/
void Tools_TransferHost(int client) {
    Menu menu = new Menu(MenuHandler_Host);
    menu.SetTitle("Transfer the host to:");
    menu.ExitBackButton = true;

    ArrayList whitelisted = new ArrayList(); 
    whitelisted.Push(client); // exclude the host
    AddPlayersToMenu(menu, whitelisted);
    delete whitelisted; // garbage collection

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Host(Menu menu, MenuAction action, int client, int selection)
{
    switch(action) {
        case(MenuAction_Select):
        {
            char info[32], name[32];
            int target;

            menu.GetItem(selection, info, sizeof(info), _, name, sizeof(name));
            target = StringToInt(info);

            if (target == 0) { // target no longer exist
                MC_PrintToChat(client, "{red}[Matcha]{default} Target is not available");
            }
            else {
                char original[MAX_NAME_LENGTH];
                strcopy(original, sizeof(original), g_charHostName);

                GetClientAuthId(target, AuthId_Steam2, g_charHost, sizeof(g_charHost));
                GetClientName(target, g_charHostName, sizeof(g_charHostName));

                MC_PrintToChatAll("{green}[Matcha]{default} %s has transferred the host to %s", original, g_charHostName); // Global ACK

                MC_PrintToChat(target, "{red}[Matcha]{default} You are the new host, use !host to access the panel."); // TARGET ACK
                MC_PrintToChat(client, "{red}[Matcha]{default} Transferred successfully!"); // ACK
            }
        }
        case(MenuAction_Cancel):
		{
            switch(selection) {
                case(MenuCancel_ExitBack):
                {
                    ShowHostMenu(client);
                    delete menu;
                }
                default:
                {
                    delete menu;
                }
            }
		}
    }

	return 0;
}

/*
    ------------------ BAN USER ------------------
*/

void Tools_BanUser(int client) {
    Menu menu = new Menu(MenuHandler_Ban);
    menu.SetTitle("Ban player:");
    menu.ExitBackButton = true;

    ArrayList whitelisted = new ArrayList(); 
    whitelisted.Push(client); // exclude the host
    AddPlayersToMenu(menu, whitelisted);
    delete whitelisted; // garbage collection

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Ban(Menu menu, MenuAction action, int client, int selection)
{
    switch(action) {
        case(MenuAction_Select):
        {
            char info[32], name[32];
            int target;

            menu.GetItem(selection, info, sizeof(info), _, name, sizeof(name));
            target = StringToInt(info);

            if (target == 0) { // target no longer exist
                MC_PrintToChat(client, "{red}[Matcha]{default} Target is not available");
            }
            else {
                char bannedSteam[MAX_AUTHID_LENGTH];
                GetClientAuthId(target, AuthId_Steam2, bannedSteam, sizeof(bannedSteam));
                
                char targetName[MAX_NAME_LENGTH];
                GetClientName(target, targetName, sizeof(targetName));

                g_arrayBanlist.PushString(bannedSteam); // push to array
                KickClient(target, "You have been banned by the host (%s).", g_charHostName);
                MC_PrintToChatAll("{green}[Matcha]{default} %s has been banned from this bookable by the host (%s).", targetName, g_charHostName);
            }
        }
        case(MenuAction_Cancel):
		{
            switch(selection) {
                case(MenuCancel_ExitBack):
                {
                    ShowHostMenu(client);
                    delete menu;
                }
                default:
                {
                    delete menu;
                }
            }
		}
    }

	return 0;
}

/*
    ------------------ KICK USER ------------------
*/

void Tools_KickUser(int client) {
    Menu menu = new Menu(MenuHandler_Kick);
    menu.SetTitle("Kick player:");
    menu.ExitBackButton = true;

    ArrayList whitelisted = new ArrayList(); 
    whitelisted.Push(client); // exclude the host
    AddPlayersToMenu(menu, whitelisted);
    delete whitelisted; // garbage collection

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Kick(Menu menu, MenuAction action, int client, int selection)
{
    switch(action) {
        case(MenuAction_Select):
        {
            char info[32], name[32];
            int target;

            menu.GetItem(selection, info, sizeof(info), _, name, sizeof(name));
            target = StringToInt(info);

            if (target == 0) { // target no longer exist
                MC_PrintToChat(client, "{red}[Matcha]{default} Target is not available");
            }
            else {
                KickClient(target, "You have been kicked by the host (%s).", g_charHostName);
            }
        }
        case(MenuAction_Cancel):
		{
            switch(selection) {
                case(MenuCancel_ExitBack):
                {
                    ShowHostMenu(client);
                    delete menu;
                }
                default:
                {
                    delete menu;
                }
            }
		}
    }

	return 0;
}

/*
    ------------------ CHANGE MAP ------------------
*/

void Tools_ChangeMap(int client) {
    ArrayList MapList = new ArrayList();
    MapList = CreateArray(MAX_NAME_LENGTH);
    ReadFullMaplist(MapList, "cfg/comp/maps.txt");

    Menu menu = new Menu(MenuHandler_ChangeMap);
    menu.SetTitle("Change map:");
    menu.ExitBackButton = true;

    AddMapsToMenu(menu, MapList);
    menu.Display(client, MENU_TIME_FOREVER);

    delete MapList; // garbage collection
}

public int MenuHandler_ChangeMap(Menu menu, MenuAction action, int client, int selection)
{
    switch(action) {
        case(MenuAction_Select):
        {
            char info[32], name[32];
            menu.GetItem(selection, info, sizeof(info), _, name, sizeof(name));

            MC_PrintToChatAll("{green}[Matcha]{default} %s has changed the map to %s", g_charHostName, name);
            ServerCommand("changelevel %s", name);
        }
        case(MenuAction_Cancel):
		{
            switch(selection) {
                case(MenuCancel_ExitBack):
                {
                    ShowHostMenu(client);
                    delete menu;
                }
                default:
                {
                    delete menu;
                }
            }
		}
    }

	return 0;
}

/*
    ------------------ CHANGE CONFIG ------------------
*/

void Tools_ChangeConfig(int client) {
    Menu menu = new Menu(MenuHandler_ChangeConfig);
    menu.SetTitle("Change config:");
    menu.ExitBackButton = true;

    AddLeaguesToMenu(menu);
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ChangeConfig(Menu menu, MenuAction action, int client, int selection)
{
    switch(action) {
        case(MenuAction_Select):
        {
            char info[8];
            menu.GetItem(selection, info, sizeof(info));

            int leagueFirstIndex = StringToInt(info);
            char selectedLeague[128];
            strcopy(selectedLeague, sizeof(selectedLeague), g_charConfigs[leagueFirstIndex][CONFIG_LEAGUE]);
            
            // Config menu
            Tools_ShowLeagueConfigs(client, selectedLeague);
        }
        case(MenuAction_Cancel):
		{
            switch(selection) {
                case(MenuCancel_ExitBack):
                {
                    ShowHostMenu(client);
                    delete menu;
                }
                default:
                {
                    delete menu;
                }
            }
		}
    }

	return 0;
}

void Tools_ShowLeagueConfigs(int client, const char[] leagueName) {
    Menu menu = new Menu(MenuHandler_LeagueConfigs);
    
    char title[128];
    Format(title, sizeof(title), "%s configs:", leagueName);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    AddLeagueConfigToMenu(menu, leagueName);
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_LeagueConfigs(Menu menu, MenuAction action, int client, int selection)
{
    switch(action) {
        case(MenuAction_Select):
        {
            if (!g_boolConfigCD) {
                g_boolConfigCD = true;
                
                char info[32], name[64];
                menu.GetItem(selection, info, sizeof(info), _, name, sizeof(name));
                
                int configIndex = StringToInt(info);
                char configPath[128];
                
                strcopy(configPath, sizeof(configPath), g_charConfigs[configIndex][CONFIG_PATH]);
                
                MC_PrintToChatAll("{green}[Matcha]{default} %s changed the config to {aqua}%s", g_charHostName, name);

                // Its better to have a delay to alert config changes
                DataPack pack = new DataPack();
                pack.WriteString(configPath);
                pack.Reset();
                CreateTimer(3.5, Timer_ChangeConfig, pack, TIMER_FLAG_NO_MAPCHANGE);
            }
            else {
                PrintToChat(client, "{red}[Matcha]{default} A config change is being performed.");
            }
        }
        case(MenuAction_Cancel):
        {
            switch(selection) {
                case(MenuCancel_ExitBack):
                {
                    Tools_ChangeConfig(client); // Go back to league selection
                    delete menu;
                }
                default:
                {
                    delete menu;
                }
            }
        }
    }

    return 0;
}

public Action Timer_ChangeConfig(Handle timer, DataPack pack) {
    char configPath[128];
    pack.Reset();
    pack.ReadString(configPath, sizeof(configPath));
    delete pack;
    
    ServerCommand("sm_execcfg %s", configPath);

    g_boolConfigCD = false;
    return Plugin_Stop;
}

/*
    ------------------ CANCEL VOTE ------------------
*/

void Tools_CancelVote(int client) {
    if (IsVoteInProgress()) {
        MC_PrintToChatAll("{green}[Matcha]{default} %s has cancelled the vote.", g_charHostName);
        CancelVote();
    }
    else {
        MC_PrintToChat(client, "{red}[Matcha]{default} There are no on-going votes.");
    }
}