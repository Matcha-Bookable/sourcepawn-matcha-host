#include <sourcemod>
#include <morecolors>
#include <sdktools>
#include <f2stocks>

public Plugin myinfo = 
{
    name = "Matcha Bookable Host",
    author = "avan",
    description = "Host tools for Matcha Bookable",
    version = "1.0",
    url = "https://discord.gg/8ysCuREbWQ"
};

char g_charHost[MAX_AUTHID_LENGTH] = ""; // For storing the host's SteamID
char g_charHostName[MAX_NAME_LENGTH]; // For storing the host's name

ArrayList g_arrayBanlist; // Storing the list of banned players in the bookable

public void OnPluginStart() {
    RegConsoleCmd("sm_host", Command_Host, "Allow host to access the host tool");

    g_arrayBanlist = new ArrayList(ByteCountToCells(MAX_AUTHID_LENGTH));
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

	menu.SetTitle("Matcha Host Tools");

    menu.AddItem("0", "Transfer host"); // Transfer the host to another user
    menu.AddItem("1", "Ban user"); // Ban user from joining this bookable
    menu.AddItem("2", "Kick user"); // Kick user from the bookable
    // menu.AddItem("3", "Change map"); // Change map
    // menu.AddItem("4", "Change config"); // Change config
    // menu.AddItem("5", "Unban user"); // Unban user (will probably not implement)
    // menu.AddItem("6", "Cancel vote"); // Cancel vote

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
				case(1): Tools_BanUser(client);
				case(2): Tools_KickUser(client);
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

/*
    ----------------- MENU TOOLS -----------------
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
                KickClient(target, "You have been banned by the host.");
                MC_PrintToChatAll("{green}[Matcha]{default} %s has been banned from this bookable by the host.", targetName);
            }
        }
        case(MenuAction_End):
		{
			delete menu;
		}
    }

	return 0;
}

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
                KickClient(target, "You have been kicked by the host.");
            }
        }
        case(MenuAction_End):
		{
			delete menu;
		}
    }

	return 0;
}
