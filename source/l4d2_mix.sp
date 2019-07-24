#include <sourcemod>
#include <sdktools_sound>

#define MAX_STR_LEN 30
#define MIN_MIX_START_COUNT 2

#define COND_HAS_ALREADY_VOTED 0
#define COND_NEED_MORE_VOTES 1
#define COND_START_MIX 2
#define COND_START_MIX_ADMIN 3

#define STATE_FIRST_CAPT 0
#define STATE_SECOND_CAPT 1
#define STATE_NO_MIX 2
#define STATE_PICK_TEAMS 3

enum L4D2Team                                                                   
{                                                                               
    L4D2Team_None = 0,                                                          
    L4D2Team_Spectator,                                                         
    L4D2Team_Survivor,                                                          
    L4D2Team_Infected                                                           
}

new currentState = STATE_NO_MIX;
new Menu:mixMenu;
new StringMap:hVoteResultsTrie;
new mixCallsCount = 0;
char currentMaxVotedCaptAuthId[MAX_STR_LEN];
char survCaptainAuthId[MAX_STR_LEN];
char infCaptainAuthId[MAX_STR_LEN];
new maxVoteCount = 0;
new pickCount = 0;
new selectedPattern = 0;
new L4D2Team:pickerSide = L4D2Team_Survivor;
new L4D2Team:patterns[3][6] = 
{
	{
		L4D2Team_Survivor,
		L4D2Team_Infected,
		L4D2Team_Survivor,
		L4D2Team_Infected,
		L4D2Team_Infected,
		L4D2Team_Survivor
	},
	{
		L4D2Team_Survivor,
		L4D2Team_Infected,
		L4D2Team_Infected,
		L4D2Team_Survivor,
		L4D2Team_Survivor,
		L4D2Team_Infected
	},
	{
		L4D2Team_Survivor,
		L4D2Team_Infected,
		L4D2Team_Survivor,
		L4D2Team_Infected,
		L4D2Team_Survivor,
		L4D2Team_Infected
	}
};
new bool:isMixAllowed = false;
new Handle:mixStartedForward;
new Handle:mixStoppedForward;

public Plugin myinfo =
{
    name = "L4D2 Mix Manager",
    author = "Luckylock",
    description = "Provides ability to pick captains and teams through menus",
    version = "1",
    url = "https://github.com/LuckyServ/"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_mix", Cmd_MixStart, "Mix command with pattern (optional))");
    RegAdminCmd("sm_stopmix", Cmd_MixStop, ADMFLAG_CHANGEMAP, "Mix command");
    hVoteResultsTrie = CreateTrie();
    mixStartedForward = CreateGlobalForward("OnMixStarted", ET_Event);
    mixStoppedForward = CreateGlobalForward("OnMixStopped", ET_Event);
    PrecacheSound("buttons/blip1.wav");
}

public void OnMapStart()
{
    isMixAllowed = true;
}

public void OnRoundIsLive() {
    isMixAllowed = false;
    StopMix();
}

public void StartMix()
{
    EmitSoundToAll("buttons/blip1.wav"); 
    Call_StartForward(mixStartedForward);
    Call_Finish();
}

public void StopMix()
{
    currentState = STATE_NO_MIX;
    Call_StartForward(mixStoppedForward);
    Call_Finish();
}

public Action Cmd_MixStop(int client, int args) {
    if (currentState != STATE_NO_MIX) {
        StopMix();
        PrintToChatAll("\x04Mix Manager: \x01Stopped by admin \x03%N\x01.", client);
    } else {
        PrintToChat(client, "\x04Mix Manager: \x01Not currently started.");
    }
}

public Action Cmd_MixStart(int client, int args)
{
    if (currentState != STATE_NO_MIX) {
        PrintToChat(client, "\x04Mix Manager: \x01Already started.");
        return Plugin_Handled;
    } else if (!isMixAllowed) {
        PrintToChat(client, "\x04Mix Manager: \x01Not allowed on live round.");
        return Plugin_Handled;
    }

    if(args > 1) 
    {
        PrintToChat(client,"\x04Mix Manager: \x01Invalid arguments count.");
        return Plugin_Handled;
    }
	if(args == 1)
	{
		decl String:arg[32];
		GetCmdArg(1, arg, sizeof(arg));    
		
		if(StrEqual(arg, "help"))
		{
			PrintToChat(client,"\x04Mix Manager: \x01Use !mix #pattern. Options: 1: ABABBA 2: ABBAAB 3: ABABAB");
			return Plugin_Handled;
		}		

		selectedPattern = StringToInt(arg);
		selectedPattern = (selectedPattern > 0 && selectedPattern <= sizeof(patterns)) ? selectedPattern - 1 : 0;
	}	

    new mixConditions;
    mixConditions = GetMixConditionsAfterVote(client);

    if (mixConditions == COND_START_MIX || mixConditions == COND_START_MIX_ADMIN) {
        if (mixConditions == COND_START_MIX_ADMIN) {
            PrintToChatAll("\x04Mix Manager: \x01Started by admin \x03%N\x01.", client);
        } else {
            PrintToChatAll("\x04Mix Manager: \x03%N \x01has voted to start a Mix.", client);
            PrintToChatAll("\x04Mix Manager: \x01Started by vote.");
        }

        currentState = STATE_FIRST_CAPT;
        StartMix();
        SwapAllPlayersToSpec();

        // Initialise values
        mixCallsCount = 0;
        ClearTrie(hVoteResultsTrie);
        maxVoteCount = 0;
        strcopy(currentMaxVotedCaptAuthId, MAX_STR_LEN, " ");
        pickCount = 0;

        if (Menu_Initialise()) {
            Menu_AddAllSpectators();
            Menu_DisplayToAllSpecs();
        }

        CreateTimer(8.0, Menu_StateHandler, _, TIMER_REPEAT); 

    } else if (mixConditions == COND_NEED_MORE_VOTES) {
        PrintToChatAll("\x04Mix Manager: \x03%N \x01has voted to start a Mix. (\x05%d \x01more to start)", client, MIN_MIX_START_COUNT - mixCallsCount);

    } else if (mixConditions == COND_HAS_ALREADY_VOTED) {
        PrintToChat(client, "\x04Mix Manager: \x01You already voted to start a Mix.");

    }

    return Plugin_Handled;
}

public int GetMixConditionsAfterVote(int client)
{
    new bool:dummy = false;
    new bool:hasVoted = false;
    char clientAuthId[MAX_STR_LEN];
    GetClientAuthId(client, AuthId_SteamID64, clientAuthId, MAX_STR_LEN);
    hasVoted = GetTrieValue(hVoteResultsTrie, clientAuthId, dummy)

    if (GetAdminFlag(GetUserAdmin(client), Admin_Changemap)) {
        return COND_START_MIX_ADMIN;

    } else if (hasVoted){
        return COND_HAS_ALREADY_VOTED;

    } else if (++mixCallsCount >= MIN_MIX_START_COUNT) {
        return COND_START_MIX; 

    } else {
        SetTrieValue(hVoteResultsTrie, clientAuthId, true);
        return COND_NEED_MORE_VOTES;

    }
}

public bool Menu_Initialise()
{
    if (currentState == STATE_NO_MIX) return false;

    mixMenu = new Menu(Menu_MixHandler, MENU_ACTIONS_ALL);
    mixMenu.ExitButton = false;

    switch(currentState) {
        case STATE_FIRST_CAPT: {
            mixMenu.SetTitle("Mix Manager - Pick first captain");
            return true;
        }

        case STATE_SECOND_CAPT: {
            mixMenu.SetTitle("Mix Manager - Pick second captain");
            return true;
        }

        case STATE_PICK_TEAMS: {
            mixMenu.SetTitle("Mix Manager - Pick team member(s)");
            return true;
        }
    }

    CloseHandle(mixMenu);
    return false;
}

public void Menu_AddAllSpectators()
{
    char clientName[MAX_STR_LEN];
    char clientId[MAX_STR_LEN];

    mixMenu.RemoveAllItems();

    for (new client = 1; client <= MaxClients; ++client) {
        if (IsClientSpec(client)) {
            GetClientAuthId(client, AuthId_SteamID64, clientId, MAX_STR_LEN);
            GetClientName(client, clientName, MAX_STR_LEN);
            mixMenu.AddItem(clientId, clientName);
        }  
    }
}

public void Menu_AddTestSubjects()
{
    mixMenu.AddItem("test", "test");
}

public void Menu_DisplayToAllSpecs()
{
    for (new client = 1; client <= MaxClients; ++client) {
        if (IsClientSpec(client)) {
            mixMenu.Display(client, 7);
        }
    }
}

public int Menu_MixHandler(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select) {
        if (currentState == STATE_FIRST_CAPT || currentState == STATE_SECOND_CAPT) {
            char authId[MAX_STR_LEN];
            menu.GetItem(param2, authId, MAX_STR_LEN);

            new voteCount = 0;

            if (!GetTrieValue(hVoteResultsTrie, authId, voteCount)) {
                voteCount = 0;
            }

            SetTrieValue(hVoteResultsTrie, authId, ++voteCount, true);

            if (voteCount >= maxVoteCount) {
                strcopy(currentMaxVotedCaptAuthId, MAX_STR_LEN, authId);
                maxVoteCount = voteCount;
            }

        } else if (currentState == STATE_PICK_TEAMS) {
            char authId[MAX_STR_LEN]; 
            menu.GetItem(param2, authId, MAX_STR_LEN);
            new L4D2Team:team = GetClientTeamEx(param1);

            if (team == L4D2Team_Spectator) {
                PrintToChatAll("\x04Mix Manager: \x01Captain \x03%N \x01found in the wrong team, aborting...", param1);
                StopMix();

            } else {
                if (SwapPlayerToTeam(authId, team, 0)) {
                    CreateTimer(0.5, Menu_StateHandler);
                } else {
                    PrintToChatAll("\x04Mix Manager: \x01The team member who was picked was not found, aborting...", param1);
                    StopMix();
                    
                }
            }
        }
    }

    return 0;
}

public Action Menu_StateHandler(Handle timer, Handle hndl)
{
    switch(currentState) {
        case STATE_FIRST_CAPT: {
            new numVotes = 0;
            GetTrieValue(hVoteResultsTrie, currentMaxVotedCaptAuthId, numVotes);
            ClearTrie(hVoteResultsTrie);

            if (SwapPlayerToTeam(currentMaxVotedCaptAuthId, L4D2Team_Survivor, numVotes)) {
                strcopy(survCaptainAuthId, MAX_STR_LEN, currentMaxVotedCaptAuthId);
                currentState = STATE_SECOND_CAPT;
                maxVoteCount = 0;

                if (Menu_Initialise()) {					
                    Menu_AddAllSpectators();
                    Menu_DisplayToAllSpecs();
                }
            } else {
                PrintToChatAll("\x04Mix Manager: \x01Failed to find first captain with at least 1 vote from spectators, aborting...");
                StopMix();
            }

            strcopy(currentMaxVotedCaptAuthId, MAX_STR_LEN, " ");
        }

        case STATE_SECOND_CAPT: {
            new numVotes = 0;
            GetTrieValue(hVoteResultsTrie, currentMaxVotedCaptAuthId, numVotes);
            ClearTrie(hVoteResultsTrie);
			
            if (SwapPlayerToTeam(currentMaxVotedCaptAuthId, L4D2Team_Infected, numVotes)) {
                strcopy(infCaptainAuthId, MAX_STR_LEN, currentMaxVotedCaptAuthId);
                currentState = STATE_PICK_TEAMS;
				
				//Randomly decide which captain picks first (0 = stay as it is, 1 = swap captains)
				if(GetRandomInt(0,1) == 1)
				{				 
					char buff[MAX_STR_LEN];
					strcopy(buff, MAX_STR_LEN, survCaptainAuthId);
					strcopy(survCaptainAuthId, MAX_STR_LEN, infCaptainAuthId);
					strcopy(infCaptainAuthId, MAX_STR_LEN, buff);

					ChangeClientTeamEx(GetClientFromAuthId(infCaptainAuthId), L4D2Team_Survivor);
					ChangeClientTeamEx(GetClientFromAuthId(buff), L4D2Team_Infected);					
				}
				
                CreateTimer(0.5, Menu_StateHandler); 

            } else {
                PrintToChatAll("\x04Mix Manager: \x01Failed to find second captain with at least 1 vote from spectators, aborting...");
                StopMix();
            }

            strcopy(currentMaxVotedCaptAuthId, MAX_STR_LEN, " ");
        }

        case STATE_PICK_TEAMS: {
            Menu_TeamPickHandler();
        }
    }

    if (currentState == STATE_NO_MIX || currentState == STATE_PICK_TEAMS) {
        return Plugin_Stop; 
    } else {
        return Plugin_Handled;
    }
}

public void Menu_TeamPickHandler()
{
    if (currentState == STATE_PICK_TEAMS) {
        if (pickCount > 5) {
            PrintToChatAll("\x04Mix Manager: \x01 Teams are picked.");
            StopMix();
        } 
		
		pickerSide = patterns[selectedPattern][pickCount];

        if (Menu_Initialise()) {
            Menu_AddAllSpectators();
            new captain;

            if (pickerSide == L4D2Team_Survivor) {
               captain = GetClientFromAuthId(survCaptainAuthId); 
            } else {
               captain = GetClientFromAuthId(infCaptainAuthId); 
            }

            if (captain > 0) {
                if (GetSpectatorsCount() > 0) {
					pickCount++; 
                    mixMenu.Display(captain, MENU_TIME_FOREVER); 
                } else {
                    PrintToChatAll("\x04Mix Manager: \x01No more spectators to choose from, aborting...");
                    StopMix();
                }
            } else {
                PrintToChatAll("\x04Mix Manager: \x01Failed to find the captain, aborting...");
                StopMix();
            }			
        }
    }
}

public void SwapAllPlayersToSpec()
{
    for (new client = 1; client <= MaxClients; ++client) {
        if (IsClientInGame(client) && !IsFakeClient(client)) 
		{
            ChangeClientTeamEx(client, L4D2Team_Spectator);
        }
    }
}

public bool SwapPlayerToTeam(const char[] authId, L4D2Team:team, numVotes)
{
    new client = GetClientFromAuthId(authId);
    new bool:foundClient = client > 0;

    if (foundClient) {
        ChangeClientTeamEx(client, team);

        switch(currentState) {
            case STATE_FIRST_CAPT: {
                PrintToChatAll("\x04Mix Manager: \x01First captain is \x03%N\x01. (\x05%d \x01votes)", client, numVotes);
            }
            
            case STATE_SECOND_CAPT: {
                PrintToChatAll("\x04Mix Manager: \x01Second captain is \x03%N\x01. (\x05%d \x01votes)", client, numVotes);
            }

            case STATE_PICK_TEAMS: {
                if (pickerSide == L4D2Team_Survivor) {
                    PrintToChatAll("\x04Mix Manager: \x03%N \x01was picked (survivors).", client)
                } else {
                    PrintToChatAll("\x04Mix Manager: \x03%N \x01was picked (infected).", client)
                }
            }
        }
    }

    return foundClient;
}

public void OnClientDisconnect(client)
{
    if (currentState != STATE_NO_MIX && IsPlayerCaptain(client))
    {
        PrintToChatAll("\x04Mix Manager: \x01Captain \x03%N \x01has left the game, aborting...", client);
        StopMix();
    }
}

public bool IsPlayerCaptain(client)
{
    return GetClientFromAuthId(survCaptainAuthId) == client || GetClientFromAuthId(infCaptainAuthId) == client;
}

public int GetClientFromAuthId(const char[] authId)
{
    char clientAuthId[MAX_STR_LEN];
    new client = 0;
    new i = 0;
    
    while (client == 0 && i < MaxClients) {
        ++i;

        if (IsClientInGame(i) && !IsFakeClient(i)) 
		{
            GetClientAuthId(i, AuthId_SteamID64, clientAuthId, MAX_STR_LEN); 

            if (StrEqual(authId, clientAuthId)) {
                client = i;
            }
        }
    }

    return client;
}

public bool IsClientSpec(int client) {
    return IsClientInGame(client) && GetClientTeam(client) == 1 && !IsFakeClient(client) ;
}

public int GetSpectatorsCount()
{
    new count = 0;

    for (new client = 1; client <= MaxClients; ++client) {
        if (IsClientSpec(client)) {
            ++count;
        }
    }

    return count;
}

stock bool:ChangeClientTeamEx(client, L4D2Team:team)
{
    if (GetClientTeamEx(client) == team) {
        return true;
    }

    if (team != L4D2Team_Survivor) {
        ChangeClientTeam(client, _:team);
        return true;
    } else {
        new bot = FindSurvivorBot();

        if (bot > 0) {
            new flags = GetCommandFlags("sb_takecontrol");
            SetCommandFlags("sb_takecontrol", flags & ~FCVAR_CHEAT);
            FakeClientCommand(client, "sb_takecontrol");
            SetCommandFlags("sb_takecontrol", flags);
            return true;
        }
    }
    return false;
}

stock L4D2Team:GetClientTeamEx(client)
{
    return L4D2Team:GetClientTeam(client);
}

stock FindSurvivorBot()
{
    for (new client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client)  && GetClientTeamEx(client) == L4D2Team_Survivor && IsFakeClient(client))
        {
            return client;
        }
    }
    return -1;
}
