#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_NAME "Show Keys"
#define PLUGIN_AUTHOR "JoinedSenses"
#define PLUGIN_DESCRIPTION "Displays client key presses"
#define PLUGIN_VERSION "0.1.0"
#define PLUGIN_URL "https://github.com/JoinedSenses"

#include <sourcemod>
#include <clientprefs>

#define TAG "\x01[\x03SKEYS\x01] "

#define RED   0
#define GREEN 1
#define BLUE  2

#define XPOS 0
#define YPOS 1

#define XPOSDEFAULT 0.54
#define YPOSDEFAULT 0.4
#define ALLKEYS 3615
#define DEFAULTCOLOR {255, 255, 255}
#define DEFAULTPOS view_as<float>({XPOSDEFAULT, YPOSDEFAULT})

#define DEBUG 1

enum {
	Pref_R = 0,
	Pref_G,
	Pref_B,
	Pref_X,
	Pref_Y,
	Pref_Max
}

Cookie g_hCookie;

Handle g_hHudDisplayForward;
Handle g_hHudDisplayASD;
Handle g_hHudDisplayJump;
Handle g_hHudDisplayAttack;

bool g_bShowing[MAXPLAYERS+1];
bool g_bEditing[MAXPLAYERS+1];

int g_iButtons[MAXPLAYERS+1];
int g_iColor[MAXPLAYERS+1][3];

float g_fPos[MAXPLAYERS+1][2];

bool g_bLate;

public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	CreateConVar(
		"sm_showkeys_version",
		PLUGIN_VERSION,
		PLUGIN_DESCRIPTION,
		FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD
	).SetString(PLUGIN_VERSION);

	RegConsoleCmd("sm_skeys", cmdShowKeys, "Toggle showing a client's keys.");
	RegConsoleCmd("sm_skeyscolor", cmdKeyColor, "Changes the color of the text for skeys.");
	RegConsoleCmd("sm_skeyscolors", cmdKeyColor, "Changes the color of the text for skeys.");
	RegConsoleCmd("sm_skeyspos", cmdKeyPos, "Changes the location of the text for skeys.");
	RegConsoleCmd("sm_skeysloc", cmdKeyPos, "Changes the location of the text for skeys.");

#if DEBUG
	RegAdminCmd("sm_testskeys", cmdTestSkeys, ADMFLAG_ROOT);
#endif

	g_hCookie = new Cookie("skeys_prefs", "Stores client show keys preferences", CookieAccess_Private);

	g_hHudDisplayForward = CreateHudSynchronizer();
	g_hHudDisplayASD = CreateHudSynchronizer();
	g_hHudDisplayJump = CreateHudSynchronizer();
	g_hHudDisplayAttack = CreateHudSynchronizer();

	SetAllSkeysDefaults();

	if (g_bLate && g_hCookie) {
		for (int i = 1; i <= MaxClients; ++i) {
			if (IsClientInGame(i) && AreClientCookiesCached(i)) {
				OnClientCookiesCached(i);
			}
		}
	}
}

#if DEBUG
public Action cmdTestSkeys(int client, int args) {
	ReplyToCommand(
		client,
		"{%i %i %i} {%0.3f %0.3f}",
		g_iColor[0], g_iColor[1], g_iColor[2], g_fPos[0], g_fPos[1]
	);

	return Plugin_Handled;
}
#endif

public void OnClientDisconnect(int client) {
	g_bShowing[client] = false;
	g_bEditing[client] = false;
	SetSkeysDefaults(client);
}

public void OnClientCookiesCached(int client) {
	char str[64];
	g_hCookie.Get(client, str, sizeof str);

	if (str[0] == '\0') {
		return;
	}

	// r,g,b,x,y
	char buffer[Pref_Max][16];
	ExplodeString(str, ",", buffer, sizeof buffer, sizeof buffer[]);

	SetColor(client, buffer[Pref_R], buffer[Pref_G], buffer[Pref_B]);
	SetPos(client, buffer[Pref_X], buffer[Pref_Y]);
}

public Action cmdShowKeys(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	PrintToChat(
		client,
		"\x01Key display is now \x03%s\x01.",
		(g_bShowing[client] = !g_bShowing[client]) ? "enabled" : "disabled"
	);

	return Plugin_Handled;
}

public Action cmdKeyColor(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}
	
	if (args < 1) {
		PrintToChat(client, "\x03Usage\x01: sm_skeys_color <R> <G> <B>");
		return Plugin_Handled;
	}

	char red[4];
	GetCmdArg(1, red, sizeof(red));

	char green[4];
	GetCmdArg(2, green, sizeof(green));

	char blue[4];
	GetCmdArg(3, blue, sizeof(blue));

	if (!IsStringNumeric(red) || !IsStringNumeric(blue) || !IsStringNumeric(green)) {
		PrintToChat(client, TAG ... "Invalid numeric value");
		return Plugin_Handled;
	}

	SetColor(client, red, green, blue);
	SaveKeyPrefs(client);

	return Plugin_Handled;
}

public Action cmdKeyPos(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	if (IsClientObserver(client)) {
		PrintToChat(client, TAG ... "Cannot use this feature while in \x03spectate\x01.");
		return Plugin_Handled;
	}

	g_bShowing[client] = true;

	if (g_bEditing[client]) {
			g_bEditing[client] = false;
			SetEntityFlags(client, GetEntityFlags(client)&~(FL_ATCONTROLS|FL_FROZEN));
	}
	else {
		g_bEditing[client] = true;
		SetEntityFlags(client, GetEntityFlags(client)|FL_ATCONTROLS|FL_FROZEN);

		PrintToChat(
			client,
			TAG ... "Update position using\x03 mouse movement\x01.\n" ...
			TAG ... "Save with\x03 attack\x01.\n" ...
			TAG ... "Reset with\x03 jump\x01."
		);
	}

	return Plugin_Handled;
}

void SetSkeysDefaults(int client) {
	g_fPos[client] = DEFAULTPOS;
	g_iColor[client] = DEFAULTCOLOR;
}

void SetAllSkeysDefaults() {
	for (int i = 1; i <= MaxClients; ++i) {
		SetSkeysDefaults(i);
	}
}

void SaveKeyPrefs(int client) {
	if (g_hCookie == null) {
		PrintToChat(client, "Unable to save preferences at this time");
		return;
	}

	int color[3];
	color = g_iColor[client];

	float pos[2];
	pos = g_fPos[client];

	char str[64];
	FormatEx(str, sizeof str, "%i,%i,%i,%0.5f,%0.5f",
		color[RED],
		color[GREEN],
		color[BLUE],
		pos[XPOS],
		pos[YPOS]
	);

	g_hCookie.Set(client, str);
	PrintToChat(client, "\x01Your settings were \x03saved\x01.");
}

void SetColor(int client, const char[] r, const char[] g, const char[] b) {
	g_iColor[client][RED] = StringToInt(r);
	g_iColor[client][GREEN] = StringToInt(g);
	g_iColor[client][BLUE] = StringToInt(b);
}

void SetPos(int client, const char[] x, const char[] y) {
	g_fPos[client][XPOS] = StringToFloat(x);
	g_fPos[client][YPOS] = StringToFloat(y);
}

public void OnGameFrame() {
	for (int i = 1; i <= MaxClients; ++i) {
		if (IsClientInGame(i)) {
			g_iButtons[i] = GetClientButtons(i);
		}
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype,
int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (!IsClientInGame(client)
	|| !g_bShowing[client]
	|| (buttons & IN_SCORE)
	|| GetEntProp(client, Prop_Send, "m_iObserverMode") == 7) {
		return Plugin_Continue;
	}

	int clientToShow = IsClientObserver(client) ? GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") : client;
	if (clientToShow < 0 || clientToShow > MaxClients) {
		return Plugin_Continue;
	}

	bool isEditing;
	if (g_bEditing[client]) {
		isEditing = true;
		g_fPos[client][XPOS] = Clamp(g_fPos[client][XPOS] + 0.0005 * mouse[0], 0.0, 0.85);
		g_fPos[client][YPOS] = Clamp(g_fPos[client][YPOS] + 0.0005 * mouse[1], 0.0, 0.90);

		if (buttons & (IN_ATTACK|IN_ATTACK2)) {
			g_bEditing[client] = false;
			SaveKeyPrefs(client);

			CreateTimer(0.2, timerUnfreeze, GetClientUserId(client));
		}
		else if (buttons & (IN_ATTACK3|IN_JUMP)) {
			g_fPos[client] = DEFAULTPOS;
			
			g_bEditing[client] = false;
			SaveKeyPrefs(client);

			CreateTimer(0.2, timerUnfreeze, GetClientUserId(client));
		}
	}

	int
		btns = isEditing ? ALLKEYS : g_iButtons[clientToShow],
		R = g_iColor[client][RED],
		G = g_iColor[client][GREEN],
		B = g_iColor[client][BLUE];
	bool
		W = !!(btns & IN_FORWARD),
		A = !!(btns & IN_MOVELEFT),
		S = !!(btns & IN_BACK),
		D = !!(btns & IN_MOVERIGHT),
		Duck = !!(btns & IN_DUCK),
		Jump = !!(btns & IN_JUMP),
		M1 = !!(btns & IN_ATTACK),
		M2 = !!(btns & IN_ATTACK2);
	float
		X = g_fPos[client][XPOS],
		Y = g_fPos[client][YPOS];

	static const int alpha = 255;
	static const float hold = 0.3;

	SetHudTextParams(X+(W?0.047:0.052), Y, hold, R, G, B, alpha, .fadeIn=0.0, .fadeOut=0.0);
	ShowSyncHudText(client, g_hHudDisplayForward, (W?"W":"-"));

	SetHudTextParams(X+0.04-(A?0.0042:0.0)-(S?0.0015:0.0), Y+0.04, hold, R, G, B, alpha, .fadeIn=0.0, .fadeOut=0.0);
	ShowSyncHudText(client, g_hHudDisplayASD, "%c %c %c", (A?'A':'-'), (S?'S':'-'), (D?'D':'-'));

	SetHudTextParams(X+0.08, Y, hold, R, G, B, alpha, .fadeIn=0.0, .fadeOut=0.0);
	ShowSyncHudText(client, g_hHudDisplayJump, "%s\n%s", (Duck?" Duck":""), (Jump?"Jump":""));

	SetHudTextParams(X, Y, hold, R, G, B, alpha, .fadeIn=0.0, .fadeOut=0.0);
	ShowSyncHudText(client, g_hHudDisplayAttack, "%s\n%s", (M1?"M1":""), (M2?"M2":""));

	return Plugin_Continue;
}

public Action timerUnfreeze(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if (client) {
		SetEntityFlags(client, GetEntityFlags(client) & ~(FL_ATCONTROLS|FL_FROZEN));
	}
}

bool IsStringNumeric(const char[] MyString) {
	int n = 0;
	while (MyString[n] != '\0') {
		if (!IsCharNumeric(MyString[n])) {
			return false;
		}
		++n;
	}
	
	return true;
}

float Clamp(float value, float min, float max) {
	if (value > max) {
		value = max;
	}
	else if (value < min) {
		value = min;
	}

	return value;
}