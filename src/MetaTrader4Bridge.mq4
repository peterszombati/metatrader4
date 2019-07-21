#property copyright "Copyright 2019, Peter Szombati"
#property version	"1.0"
#property strict

// Required: MQL-ZMQ from https://github.com/dingmaotu/mql-zmq
#include <Zmq/Zmq.mqh>

extern string PROJECT_NAME = "MetaTrader 4 Bridge";
extern string ZEROMQ_PROTOCOL = "tcp";
extern string HOSTNAME = "*";
extern string APIKEY = "CHANGEME";
extern int REP_PORT = 5555;
extern int PUSH_PORT = 5556;

// ZeroMQ Context
Context context(PROJECT_NAME);
// ZMQ_REP SOCKET
Socket repSocket(context, ZMQ_REP);
// ZMQ_PUSH SOCKET
Socket pushSocket(context, ZMQ_PUSH);
// VARIABLES FOR LATER
uchar mdata[];
ZmqMsg request;
bool runningTests;
// UPDATE VARIABLES
int lastUpdateSeconds;
string lastUpdateAccount;
string lastUpdateOrders;
string lastUpdateRates[];
// REQUEST TYPES
int REQUEST_PING = 1;
int REQUEST_TRADE_OPEN = 11;
int REQUEST_TRADE_MODIFY = 12;
int REQUEST_TRADE_DELETE = 13;
int REQUEST_DELETE_ALL_PENDING_ORDERS = 21;
int REQUEST_CLOSE_MARKET_ORDER = 22;
int REQUEST_CLOSE_ALL_MARKET_ORDERS = 23;
int REQUEST_RATES = 31;
int REQUEST_ACCOUNT = 41;
int REQUEST_ORDERS = 51;
int REQUEST_SUBSCRIBE_PRICES = 61;
int REQUEST_SUBSCRIBE_ACCOUNT = 62;
int REQUEST_SUBSCRIBE_ORDERS = 63;
int REQUEST_UNSUBSCRIBE_PRICES = 64;
int REQUEST_UNSUBSCRIBE_ACCOUNT = 65;
int REQUEST_UNSUBSCRIBE_ORDERS = 66;
int REQUEST_CHART = 71;

// RESPONSE STATUSES
int RESPONSE_OK = 0;
int RESPONSE_FAILED = 1;

// UNIT TYPES
int UNIT_CONTRACTS = 0;
int UNIT_CURRENCY = 1;

// SUBSCRIBE
bool subscribe_orders = false;
bool subscribe_account = false;
string subscribe_prices[];

// Expert initialization function.
int OnInit() {
	// Perform core system check.
	Sleep(100);
	if (!RunTests()) {
		Sleep(1000);
		if (!RunTests()) {
			return(INIT_FAILED);
		}
	}

	EventSetMillisecondTimer(1);  // Set Millisecond Timer to get client socket input

	PrintFormat("[REP] Binding MT4 Server to Socket on Port %d.", REP_PORT);
	PrintFormat("[PUSH] Binding MT4 Server to Socket on Port %d.", PUSH_PORT);

	repSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, REP_PORT));
	pushSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));

	// Maximum amount of time in milliseconds that the thread will try to send messages
	// after its socket has been closed (the default value of -1 means to linger forever):

	repSocket.setLinger(1000);  // 1000 milliseconds

	/*	If we initiate socket.send() without having a corresponding socket draining the queue,
		we'll eat up memory as the socket just keeps enqueueing messages.
		So how many messages do we want ZeroMQ to buffer in RAM before blocking the socket?	  */

	repSocket.setSendHighWaterMark(10);  // 10 messages only.

	return(INIT_SUCCEEDED);
}

// Expert deinitialization function.
void OnDeinit(const int reason) {
	PrintFormat("[REP] Unbinding MT4 Server from Socket on Port %d.", REP_PORT);
	repSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, REP_PORT));

	PrintFormat("[PUSH] Unbinding MT4 Server from Socket on Port %d.", PUSH_PORT);
	pushSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));
}

// Expert timer function.
void OnTimer() {
	// Get client's response, but don't wait.
	repSocket.recv(request, true);

	// Send response to the client.
	ZmqMsg reply = MessageHandler(request);
	repSocket.send(reply);

	// Send periodical updates to connected sockets.
	SendUpdateMessage(pushSocket);
}

// Send Status Update data to the Client.
void SendUpdateMessage(Socket &pSocket) {
	int seconds = TimeSeconds(TimeCurrent());

	// Update every second.
	if (lastUpdateSeconds != seconds) {
		lastUpdateSeconds = seconds;

		if (subscribe_account) {
			string accountInfoString = GetAccountInfoString();
			if (lastUpdateAccount != accountInfoString) {
				lastUpdateAccount = accountInfoString;
				InformPullClient("STREAM", pSocket, "ACCOUNT", accountInfoString);
			}
		}

		if (subscribe_orders) {
			string ordersInfoString = GetAccountOrdersString();
			if (lastUpdateOrders != ordersInfoString) {
				lastUpdateOrders = ordersInfoString;
				InformPullClient("STREAM", pSocket, "ORDERS", ordersInfoString);
			}
		}

		if (ArraySize(subscribe_prices) > 0) {
			string changes[];
			for(int i = 0; i < ArraySize(subscribe_prices); i++) {
				string rateString = GetRatesString(subscribe_prices[i]);
				if (rateString != lastUpdateRates[i]) {
					ArrayPush(changes, rateString);
					lastUpdateRates[i] = rateString;
				}
			}
			string json = "[";
			for(int i = 0; i < ArraySize(changes); i++) {
				json += changes[i] + ",";
			}
			if (json != "[") {
				json = StringSubstr(json, 0, StringLen(json) - 1);
				json += "]";
				InformPullClient("STREAM", pSocket, "PRICES", StringFormat("%d|%s", RESPONSE_OK, json));
			}
		}
	}
}

// Handle request message.
ZmqMsg MessageHandler(ZmqMsg &rRequest) {
	// Output object.
	ZmqMsg reply;

	// Message components for later.
	string components[];

	if (request.size() > 0) {
		// Get data from request.
		ArrayResize(mdata, request.size());
		request.getData(mdata);
		string dataStr = CharArrayToString(mdata);

		// Process data.
		ParseZmqMessage(dataStr, components);

		// Interpret data.
		InterpretZmqMessage(&pushSocket, components);

		// Construct response.
		string id = components[1];
		ZmqMsg ret(id);
		reply = ret;
	}

	return(reply);
}

// Parse Zmq Message received from the client.
// A message should be a string with values separated by pipe sign.
// Example: 2|31|EURUSD
void ParseZmqMessage(string& message, string& retArray[]) {
	PrintFormat("Parsing: %s", message);
	string sep = "|";
	ushort u_sep = StringGetCharacter(sep, 0);
	StringSplit(message, u_sep, retArray);
}

// Send a message to the client.
void InformPullClient(string type, Socket& pSocket, string message_id, string message) {
	string response = StringFormat("%s|%s|%s", type, message_id, message);
	PrintFormat("Response: %s", response);
	ZmqMsg pushReply(response);
	pSocket.send(pushReply, true);
}

// Checks whether the program is operational.
int RunTests() {
	int testsNotPassed = 0;

	runningTests = true;

	///Checking for Permission to Perform Automated Trading for this program
	if (!MQLInfoInteger(MQL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_DLLS_ALLOWED))
		testsNotPassed += 2;

	// Checking if trading is allowed for any Expert Advisors/scripts for the current account
	if (!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
		testsNotPassed += 4;

	// Checking if trading is allowed for the current account
	if (!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
		testsNotPassed += 8;

	// Should NOT ALLOW open price modification for market orders and pending orders out of freeze level range.
	if (HasValidFreezeAndStopLevels("USDJPY", OP_BUY, Bid - 0.1, Bid, Bid - 0.3, Bid + 0.3) != -1 ||
		HasValidFreezeAndStopLevels("USDJPY", OP_SELL, Ask + 0.1, Ask, Ask + 0.3, Ask - 0.3) != -1 ||
		HasValidFreezeAndStopLevels("USDJPY", OP_BUYLIMIT, Bid - 0.1, Bid, Bid - 0.3, Bid + 0.3) != -2 ||
		HasValidFreezeAndStopLevels("USDJPY", OP_SELLLIMIT, Ask + 0.1, Ask, Ask + 0.3, Ask - 0.3) != -2 ||
		HasValidFreezeAndStopLevels("USDJPY", OP_BUYSTOP, Ask - 0.1, Ask + 0.1, Ask + 0.3, Ask + 0.3) != -2 ||
		HasValidFreezeAndStopLevels("USDJPY", OP_SELLSTOP, Bid + 0.1, Bid - 0.1, Bid - 0.3, Bid - 0.5) != -2)
		testsNotPassed += 16;

	// Should NOT ALLOW stop loss modification for market orders out of freeze range.
	if (HasValidFreezeAndStopLevels("USDJPY", OP_BUY, 0, Bid, Bid - 0.1, 0) != -3 ||
		HasValidFreezeAndStopLevels("USDJPY", OP_SELL, Ask, Ask, Ask + 0.1, 0)!= -3)
		testsNotPassed += 32;

	// Should NOT ALLOW take profit modification for market orders out of freeze range.
	if (HasValidFreezeAndStopLevels("USDJPY", OP_BUY, 0, Bid, 0, Bid + 0.1) != -4 ||
		HasValidFreezeAndStopLevels("USDJPY", OP_SELL, Ask, Ask, 0, Ask - 0.1)!= -4)
		testsNotPassed += 64;

	// Should ALLOW open price modification for pending orders.
	if (HasValidFreezeAndStopLevels("USDJPY", OP_BUYLIMIT, Bid - 0.5, Bid - 0.25, Bid - 0.6, Bid + 0.6) != 1 ||
		HasValidFreezeAndStopLevels("USDJPY", OP_SELLLIMIT, Ask + 0.5, Ask + 0.25, Ask + 0.6, Ask - 0.6) != 1 ||
		HasValidFreezeAndStopLevels("USDJPY", OP_BUYSTOP, Ask, Ask + 0.50, Ask + 0.25, Ask + 0.75) != 1 ||
		HasValidFreezeAndStopLevels("USDJPY", OP_SELLSTOP, Bid, Bid - 0.50, Bid - 0.25, Bid - 0.75) != 1)
		testsNotPassed += 128;

	// Should calculate correct prices.
	if (CalculateAndNormalizePrice("0", OP_BUY) != Ask ||
		CalculateAndNormalizePrice(DoubleToStr(Ask), OP_BUYLIMIT) != Ask ||
		CalculateAndNormalizePrice("-15", OP_SELLLIMIT) != Bid - 15 ||
		CalculateAndNormalizePrice("+10", OP_BUYLIMIT) != Ask + 10 ||
		CalculateAndNormalizePrice("%+10", OP_BUYLIMIT) != NormalizeDouble(Ask * 1.1, Digits) ||
		CalculateAndNormalizePrice("%-15", OP_BUYLIMIT) != NormalizeDouble(Ask * 0.85, Digits))
		testsNotPassed += 256;

	runningTests = false;

	if (testsNotPassed) {
		PrintFormat("Tests didn't pass with %d!", testsNotPassed);
		return false;
	}

	return true;
}

// Check order against exchange freeze and stop levels.
//  1 - trade has valid open price and SL/TP.
// -1 - open price modification is not allowed.
// -2 - open price is out of freeze level range.
// -3 - stop loss is out of freeze level range.
// -4 - take profit is out of freeze level range.
// -5 - open price is out of stop level range.
// -6 - stop loss is out of stop level range.
// -7 - take profit is out of stop level range.
int HasValidFreezeAndStopLevels(string symbol, int cmd, double openPrice,
	double price, double stoploss, double takeprofit) {

	double FreezeLevel = runningTests ? 0.2 : MarketInfo(symbol, MODE_FREEZELEVEL);
	double StopLevel = runningTests ? 0.2 : MarketInfo(symbol, MODE_STOPLEVEL);

	if (openPrice != price) { // Check open price modification
		if (openPrice && (cmd == OP_BUY || cmd == OP_SELL)) { // Check if market order
			return(-1);
		} else if ( // Check freeze level
			(cmd == OP_BUYLIMIT && Ask - price <= FreezeLevel) ||
			(cmd == OP_SELLLIMIT && price - Bid <= FreezeLevel) ||
			(cmd == OP_BUYSTOP && price - Ask <= FreezeLevel) ||
			(cmd == OP_SELLSTOP && Bid - price <= FreezeLevel)
		) {
			return(-2);
		} else if ( // Check stop level
			(cmd == OP_BUYLIMIT && Ask - price < StopLevel) ||
			(cmd == OP_SELLLIMIT && price - Bid < StopLevel) ||
			(cmd == OP_BUYSTOP && price - Ask < StopLevel) ||
			(cmd == OP_SELLSTOP && Bid - price < StopLevel)
		) {
			return(-5);
		}
	}

	if (stoploss) { // Check stop loss
		if ( // Check freeze level
			(cmd == OP_BUY && Bid - stoploss <= FreezeLevel) ||
			(cmd == OP_SELL && stoploss - Ask <= FreezeLevel)
		) {
			return(-3);
		} else if ( // Check stop level
			(cmd == OP_BUY && Bid - stoploss < StopLevel) ||
			(cmd == OP_SELL && stoploss - Ask < StopLevel) ||
			(cmd == OP_BUYLIMIT && price - stoploss < StopLevel) ||
			(cmd == OP_SELLLIMIT && stoploss - price < StopLevel) ||
			(cmd == OP_BUYSTOP && price - stoploss < StopLevel) ||
			(cmd == OP_SELLSTOP && stoploss - price < StopLevel)
		) {
			return(-6);
		}
	}

	if (takeprofit) { // Check take profit
		if ( // Check freeze level
			(cmd == OP_BUY && takeprofit - Bid <= FreezeLevel) ||
			(cmd == OP_SELL && Ask - takeprofit <= FreezeLevel)
		) {
			return(-4);
		} else if ( // Check stop level
			(cmd == OP_BUY && takeprofit - Bid < StopLevel) ||
			(cmd == OP_SELL && Ask - takeprofit < StopLevel) ||
			(cmd == OP_BUYLIMIT && takeprofit - price < StopLevel) ||
			(cmd == OP_SELLLIMIT && price - takeprofit < StopLevel) ||
			(cmd == OP_BUYSTOP && takeprofit - price < StopLevel) ||
			(cmd == OP_SELLSTOP && price - takeprofit < StopLevel)
		) {
			return(-7);
		}
	}

	return 1;
}

// Apply optional modifier and normalize the price.
// Possible modifiers are:
//  - - reduce base or market price by given value
//  + - increase base or market price by given value
//  % - percentage multiplier of base or market price
double CalculateAndNormalizePrice(string basePrice, int cmd) {
	RefreshRates();

	double price;
	double marketPrice = cmd % 2 == 1 ? Bid : Ask;

	if (cmd != -1 && (cmd < 2 || basePrice == "0")) { // Use market price
		price = marketPrice;
	} else if (cmd == -1 && basePrice == "0") { // Use empty value
		price = 0;
	} else {
		string modifier = StringSubstr(basePrice, 0, 1);
		if (modifier == "-") { // Undercut modifier
			price = marketPrice + StrToDouble(basePrice);
		} else if (modifier == "+") { // Overcut modifier
			price = marketPrice + StrToDouble(StringSubstr(basePrice, 1));
		} else if (modifier == "%") { // Percentage modifier
			price = marketPrice * (1 + (StrToDouble(StringSubstr(basePrice, 1))) / 100);
		} else { // Apply no modifier
			price = StrToDouble(basePrice);
		}

		price = NormalizeDouble(price, Digits);
	}

	return price;
}

// Check the trade context status. Return codes:
//  1 - trade context is free, trade allowed.
//  0 - trade context was busy, but became free. Trade is allowed
//      only after the market info has been refreshed.
// -1 - trade context is busy, waiting interrupted by the user
//      (expert was removed from the chart, terminal was shut down,
//      the chart period and/or symbol was changed, etc.).
// -2 - trade context is busy, waiting limit is reached (waitFor).
int IsAllowedToTrade(int waitFor = 15) {
	// check whether the trade context is free
	if (!IsTradeAllowed()) {
		int StartWaitingTime = (int)GetTickCount();

		// infinite loop
		while (true) {
			// if the expert was terminated by the user, stop operation
			if (IsStopped()) {
				Alert("The expert was terminated by the user!");
				return -1;
			}
			// if the waiting time exceeds the time specified in the
			// MaxWaiting_sec variable, stop operation, as well
			if ((int)GetTickCount() - StartWaitingTime > waitFor * 1000) {
				Alert(StringFormat("The waiting limit exceeded (%d seconds)!", waitFor));
				return -2;
			}
			// if the trade context has become free,
			if (IsTradeAllowed()) {
				return 0;
			}
			// if no loop breaking condition has been met, "wait" for 0.1
			// second and then restart checking
			Sleep(100);
		}
	} else {
		return 1;
	}
}

// Interpret Zmq Message validate it and perform an action.
void InterpretZmqMessage(Socket& pSocket, string& compArray[]) {
	// Pull data string.
	string response = "";

	// Message id and type of a message.
	string apiKey = compArray[0];
	string id = compArray[1];
	int type = (int)compArray[2];

	if (apiKey != APIKEY) {
		response = StringFormat("%d|%s", RESPONSE_FAILED, getErrorReasonJson("Invalid API key"));
	} else if (type == REQUEST_PING) {
		response = StringFormat("%d|%d", RESPONSE_OK, TimeLocal());
	} else if (type == REQUEST_TRADE_OPEN) {
		if (ArraySize(compArray) != 13) {
			response = StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(4050));
		} else {
			string symbol = compArray[3];
			int operation = (int)compArray[4];
			double volume = (double)compArray[5];
			string basePrice = compArray[6];
			int slippage = (int)compArray[7];
			string baseStoploss = compArray[8];
			string baseTakeprofit = compArray[9];
			string comment = compArray[10];
			int magicnumber = (int)compArray[11];
			int unit = (int)compArray[12];

			response = OpenOrder(symbol, operation, volume, basePrice, slippage, baseStoploss, baseTakeprofit, comment, magicnumber, unit);
		}
	} else if (type == REQUEST_TRADE_MODIFY) {
		if (ArraySize(compArray) != 7) {
			response = StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(4050));
		} else {
			int ticket = (int)compArray[3];
			string basePrice = compArray[4];
			string baseStoploss = compArray[5];
			string baseTakeprofit = compArray[6];

			response = ModifyOrder(ticket, basePrice, baseStoploss, baseTakeprofit);
		}
	} else if (type == REQUEST_TRADE_DELETE) {
		if (ArraySize(compArray) != 4) {
			response = StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(4050));
		} else {
			int ticket = (int)compArray[3];
			response = DeletePendingOrder(ticket);
		}
	} else if (type == REQUEST_RATES) {
		if (ArraySize(compArray) != 4) {
			response = StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(4050));
		} else {
			string symbol = compArray[3];
			response = GetRatesString(symbol);
		}
	} else if (type == REQUEST_ACCOUNT) {
		response = GetAccountInfoString();
	} else if (type == REQUEST_ORDERS) {
		response = GetAccountOrdersString();
	} else if (type == REQUEST_DELETE_ALL_PENDING_ORDERS) {
		if (ArraySize(compArray) != 4) {
			response = StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(4050));
		} else {
			string symbol = compArray[3];
			response = DeleteAllPendingOrders(symbol);
		}
	} else if (type == REQUEST_CLOSE_MARKET_ORDER) {
		if (ArraySize(compArray) != 4) {
			response = StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(4050));
		} else {
			int ticket = (int)compArray[3];
			response = CloseMarketOrder(ticket);
		}
	} else if (type == REQUEST_CLOSE_ALL_MARKET_ORDERS) {
		if (ArraySize(compArray) != 4) {
			response = StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(4050));
		} else {
			string symbol = compArray[3];
			response = CloseAllMarketOrders(symbol);
		}
	} else if (type == REQUEST_SUBSCRIBE_ACCOUNT) {
		subscribe_account = true;
		response = StringFormat("%d|%s", RESPONSE_OK, "{\"status\":true}");
	} else if (type == REQUEST_SUBSCRIBE_ORDERS) {
		subscribe_orders = true;
		response = StringFormat("%d|%s", RESPONSE_OK, "{\"status\":true}");
	} else if (type == REQUEST_SUBSCRIBE_PRICES) {
		string symbols[];
		string sep = ",";
		ushort u_sep = StringGetCharacter(sep, 0);
    	StringSplit(compArray[3], u_sep, symbols);
		for (int i = 0; i < ArraySize(symbols); i++) {
			bool found = false;
			for (int i2 = 0; i2 < ArraySize(subscribe_prices); i2++) {
				if (symbols[i] == subscribe_prices[i2]) {
					found = true;
					break;
				}
			}
			if (found == false) {
				ArrayPush(subscribe_prices, symbols[i]);
				ArrayPush(lastUpdateRates, "");
			}
		}
		response = StringFormat("%d|%s", RESPONSE_OK, "{\"status\":true}");
	} else if (type == REQUEST_UNSUBSCRIBE_ACCOUNT) {
		subscribe_account = false;
		response = StringFormat("%d|%s", RESPONSE_OK, "{\"status\":true}");
    } else if (type == REQUEST_UNSUBSCRIBE_ORDERS) {
		subscribe_orders = false;
		response = StringFormat("%d|%s", RESPONSE_OK, "{\"status\":true}");
	} else if (type == REQUEST_UNSUBSCRIBE_PRICES) {
		string symbols[];
		string sep = ",";
		ushort u_sep = StringGetCharacter(sep, 0);
    	StringSplit(compArray[3], u_sep, symbols);
		for (int i = 0; i < ArraySize(symbols); i++) {
			for (int i2 = 0; i2 < ArraySize(subscribe_prices); i2++) {
				if (symbols[i] == subscribe_prices[i2]) {
					RemoveIndexFromArray(subscribe_prices,i2);
					RemoveIndexFromArray(lastUpdateRates,i2);
					break;
				}
			}
		}
		string status = "true";
		for (int i = 0; i < ArraySize(symbols); i++) {
        	for (int i2 = 0; i2 < ArraySize(subscribe_prices); i2++) {
        		if (symbols[i] == subscribe_prices[i2]) {
        			status = "false";
        			break;
        		}
        	}
        }
		response = StringFormat("%d|%s", RESPONSE_OK, "{\"status\":" + status + "}");
	} else if (type == REQUEST_CHART) {
		bool opened = ChartOpen(compArray[3], 1) != 0;
		if (opened) {
			Sleep(100);
			MqlRates rates[];
			ArrayCopyRates(rates, compArray[3], 1);
			closeAllChart();
			string json = ratesToJson(rates);
			response = StringFormat("%d|%s", RESPONSE_OK, json);
		} else {
			response = StringFormat("%d|%s", RESPONSE_FAILED, "{\"error\":\"ChartOpen failed\"}");
		}
	} else {
		response = StringFormat("%d|%s", RESPONSE_FAILED, "{\"error\":\"invalid type\"}");
	}

	// Send a response.
	InformPullClient("RESPONSE", pSocket, id, response);
}

// Open an order.
// Input:	SYMBOL|OPERATION|VOLUME|BASE_PRICE|SLIPPAGE|
//				 BASE_STOPLOSS|BASE_TAKEPROFIT|COMMENT|MAGIC_NUMBER|
//				 UNIT
// Example: USDJPY|2|1|108.848|0|0|0|some text|123|0
// Output:  TICKET
// Example: 140602286
string OpenOrder(string symbol, int cmd, double volume, string basePrice, int slippage, string baseStoploss,
	string baseTakeprofit, string comment, int magicnumber, int unit) {
	while(true) {
		double price = CalculateAndNormalizePrice(basePrice, cmd);
		double stoploss = CalculateAndNormalizePrice(baseStoploss, -1);
		double takeprofit = CalculateAndNormalizePrice(baseTakeprofit, -1);

		if (unit == UNIT_CURRENCY) {
			volume /= price;
		}

		if (HasValidFreezeAndStopLevels(symbol, cmd, 0, price, stoploss, takeprofit) < 0) {
			return StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(130)); // Invalid stops
		} else if (volume < MarketInfo(symbol, MODE_MINLOT) || volume > MarketInfo(symbol, MODE_MAXLOT)) {
			return StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(131)); // Volume below min or above max
		} else if (cmd < 2 && (AccountFreeMarginCheck(symbol, cmd, volume) <= 0 || GetLastError() == 134)) {
			return StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(134)); // Free margin is insufficient
		} else if (IsAllowedToTrade() < 0) {
			return StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(146)); // Trader context is busy
		}

		int ticket = OrderSend(symbol, cmd, volume, price, slippage, stoploss, takeprofit, comment, magicnumber, 0, clrGreen);

		if (ticket > 0) {
			string json = "{\"ticket\":\"" + IntegerToString(ticket) + "\"}";
			return StringFormat("%d|%s", RESPONSE_OK, json);
		} else {
			int error = GetLastError();

			switch(error) {								 // Overcomable errors
				case 4:										// Trade server is busy. Retrying...
					Sleep(2000);							 // Try again
					continue;								 // At the next iteration
				case 135:									 // The price has changed. Retrying...
					RefreshRates();						 // Update data
					continue;								 // At the next iteration
				case 136:									 // No prices. Waiting for a new tick...
					while(RefreshRates() == false)	 // Up to a new tick
						Sleep(1);							 // Cycle delay
					continue;								 // At the next iteration
				case 137:									 // Broker is busy. Retrying...
					Sleep(2000);							 // Try again
					continue;								 // At the next iteration
				case 146:									 // Trading subsystem is busy. Retrying...
					Sleep(500);							  // Try again
					RefreshRates();						 // Update data
					continue;								 // At the next iteration
				default:
					Alert(StringFormat("OpenOrder error: %d", error));
					return(StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(error)));
			}
		}
	}
}

string ModifyOrder(int ticket, string basePrice, string baseStoploss, string baseTakeprofit) {
	bool success;

	while(true) {
		if (OrderSelect(ticket, SELECT_BY_TICKET) == false) {
			success = false;
		} else {
			double openPrice = OrderOpenPrice();
			double price;

			if (OrderType() < 2) {
				price = openPrice;
			} else {
				price = CalculateAndNormalizePrice(basePrice, -1);
			}

			double stoploss = CalculateAndNormalizePrice(baseStoploss, -1);
			double takeprofit = CalculateAndNormalizePrice(baseTakeprofit, -1);

			if (HasValidFreezeAndStopLevels(OrderSymbol(), OrderType(), openPrice, price, stoploss, takeprofit) < 0) {
				return StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(130)); // Invalid stops
			} else if (IsAllowedToTrade() < 0) {
				return StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(146)); // Trader context is busy
			}

			success = OrderModify(ticket, price, stoploss, takeprofit, 0, clrGreen);
		}

		if (success) {
			string json = "{\"ticket\":\"" + IntegerToString(ticket) + "\"}";
			return(StringFormat("%d|%s", RESPONSE_OK, json));
		} else {
			int error = GetLastError();

			switch(error) { // Overcomable errors
				case 4:             // Trade server is busy. Retrying...
					Sleep(2000);    // Try again
					continue;		// At the next iteration
				case 137:			// Broker is busy. Retrying...
					Sleep(2000);	// Try again
					continue;		// At the next iteration
				case 146:			// Trading subsystem is busy. Retrying...
					Sleep(500);		// Try again
					continue;		// At the next iteration
				default:
					Alert(StringFormat("ModifyOrder error: %d", error));
					return StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(error));
			}
		}
	}
}

string DeletePendingOrder(int ticket) {
	bool success;

	while(true) {
		if (OrderSelect(ticket, SELECT_BY_TICKET) == false) {
			success = false;
		} else {
			if (IsAllowedToTrade() < 0) {
				return StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(146)); // Trader context is busy
			}

			success = OrderDelete(ticket, CLR_NONE);
		}

		if (success) {
			string json = "{\"ticket\":\"" + IntegerToString(ticket) + "\"}";
			return StringFormat("%d|%s", RESPONSE_OK, json);
		} else {
			int error = GetLastError();

			switch(error) { // Overcomable errors
				case 4:             // Trade server is busy. Retrying...
					Sleep(2000);    // Try again
					continue;       // At the next iteration
				case 137:           // Broker is busy. Retrying...
					Sleep(2000);    // Try again
					continue;       // At the next iteration
				case 146:           // Trading subsystem is busy. Retrying...
					Sleep(500);     // Try again
					continue;       // At the next iteration
				default:
					Alert(StringFormat("DeletePendingOrder error: %d", error));
					return StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(error));
			}
		}
	}
}

string DeleteAllPendingOrders(string symbol) {
	int deletedCount = 0;

	for (int i = OrdersTotal() - 1; i >= 0; i--) {
		bool found = OrderSelect(i, SELECT_BY_POS);

		// Order not found or Symbol is not ours.
		if (!found || OrderSymbol() != symbol) continue;

		// Select only pending orders.
		if (OrderType() > 1) {
			string response = DeletePendingOrder(OrderTicket());

			if (StringFind(response, (string)RESPONSE_OK) == 0) {
				deletedCount++;
			}
		}
	}

	string json = "{\"deleted_count\":"+IntegerToString(deletedCount)+"}";
	return StringFormat("%d|%s", RESPONSE_OK, json);
}

string CloseMarketOrder(int ticket) {
	PrintFormat("ORDER CLOSE #%d", ticket);

	bool success;

	while(true) {
		if (OrderSelect(ticket, SELECT_BY_TICKET) == false) {
			success = false;
		} else {
			double price = 0;

			switch(OrderType()) { // By order type
				case 0: // Order Buy
					price = Bid;
					break;
				case 1: // Order Sell
					price = Ask;
					break;
				}

			if (IsAllowedToTrade() < 0) {
            	return StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(146)); // Trader context is busy
			}

			success = OrderClose(ticket, OrderLots(), price, 2, clrRed);
		}

		if (success) {
			string json = "{\"ticket\":\"" + IntegerToString(ticket) + "\"}";
			return StringFormat("%d|%s", RESPONSE_OK, json);
		} else {
			int error = GetLastError();
			switch(error) { // Overcomable errors
				case 129: // Wrong price
				case 135:  // The price has changed. Retrying...
					RefreshRates(); // Update data
					continue; // At the next iteration
				case 136: // No prices. Waiting for a new tick...
				while(RefreshRates() == false) // To the new tick
					Sleep(1); // Cycle sleep
					continue; // At the next iteration
				case 146: // Trading subsystem is busy. Retrying...
					Sleep(500); // Try again
					RefreshRates(); // Update data
					continue; // At the next iteration
				default:
					Alert(StringFormat("CloseMarketOrder error: %d", error));
					return StringFormat("%d|%s", RESPONSE_FAILED, getErrorJson(error));
			}
		}
	}
}

string CloseAllMarketOrders(string symbol) {
	int closedCount = 0;

	for (int i = OrdersTotal() - 1; i >= 0; i--) {
		bool found = OrderSelect(i, SELECT_BY_POS);

		// Order not found or Symbol is not ours.
		if (!found || OrderSymbol() != symbol) continue;

		// Select only market orders.
		if (OrderType() < 2) {
			string response = CloseMarketOrder(OrderTicket());

			if (StringFind(response, (string)RESPONSE_OK) == 0) {
				closedCount++;
			}
		}
	}
	string json = "{\"closed_count\":" + IntegerToString(closedCount) + "}";
	return StringFormat("%d|%s", RESPONSE_OK, json);
}

string GetRatesString(string symbol) {
	return "{" +
          		"\"bid\":" + DoubleToString(MarketInfo(symbol, MODE_BID)) + ","
          		"\"ask\":" + DoubleToString(MarketInfo(symbol, MODE_ASK)) + ","
          		"\"symbol\":" + "\"" + symbol + "\"}";
}

string GetAccountInfoString() {
	string json = "{" +
		"\"currency\":\"" + AccountInfoString(ACCOUNT_CURRENCY) + "\"," +
		"\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "," +
		"\"profit\":" + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + "," +
		"\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "," +
		"\"margin\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN), 2) + "," +
		"\"margin_free\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + "," +
		"\"margin_level\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2) + "," +
		"\"margin_call_level\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL), 2) + "," +
		"\"margin_stop_out_level\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_SO), 2) + "," +
		"\"leverage\":" + IntegerToString(AccountLeverage())
	+ "}";
	return StringFormat("%d|%s", RESPONSE_OK, json);
}

string GetAccountOrdersString() {
	string json = "[";
	int ordersCount = OrdersTotal();

	for (int i = 0; i < ordersCount; i++) {
		if (OrderSelect(i, SELECT_BY_POS) == false) continue;
		string orderComment = OrderComment();
		StringReplace(orderComment,"\"","");
		json += "{" +
			"\"order\":" + IntegerToString(OrderTicket()) + "," +
			"\"open_time\":\"" + TimeToString(OrderOpenTime()) + "\"," +
			"\"type\":" + IntegerToString(OrderType()) + "," +
			"\"volume\":" + DoubleToString(OrderLots(), 2) + "," +
			"\"symbol\":\"" + OrderSymbol() + "\"," +
			"\"price\":" + DoubleToString(OrderOpenPrice(), 5) + "," +
			"\"sl\":" + DoubleToString(OrderStopLoss(), 5) + "," +
			"\"tp\":" + DoubleToString(OrderTakeProfit(), 5) + "," +
			"\"commission\":" + DoubleToString(OrderCommission(), 2) + "," +
			"\"swap\":" + DoubleToString(OrderSwap(), 2) + "," +
			"\"profit\":" + DoubleToString(OrderProfit(), 2) + "," +
			"\"comment\":\"" + orderComment + "\"},";
	}

	if (json != "["){
		json = StringSubstr(json, 0, StringLen(json) - 1);
	}
	json += "]";

	return StringFormat("%d|%s", RESPONSE_OK, json);
}

string getErrorReasonJson(string reason) {
	return "{\"error\":"+ reason+"}";
}

string getErrorJson(int code) {
	return "{\"error\":"+IntegerToString(code)+"}";
}

void RemoveIndexFromArray(string &MyArray[], int index) {
   MyArray[index] = MyArray[ArraySize(MyArray) - 1];
   ArrayResize(MyArray, ArraySize(MyArray) - 1);
}

void ArrayPush(string & array[], string dataToPush) {
    int count = ArrayResize(array, ArraySize(array) + 1);
    array[ArraySize(array) - 1] = dataToPush;
}

void closeAllChart() {
	long currChart,prevChart=ChartFirst();
	int i=0,limit=100;
	while(i<limit) {
		currChart=ChartNext(prevChart);
        if(currChart<0) break;
        ChartClose(currChart);
        prevChart=currChart;
        i++;
	}
}

string rateToJson(MqlRates &rate) {
	datetime time = rate.time;
	double open = rate.open;
	double close = rate.close;
	double low = rate.low;
	double high = rate.high;
	long tick_volume = rate.tick_volume;
	return "{\"time\":\"" + TimeToStr(time) + "\"," +
		"\"open\":" + DoubleToString(open) + "," +
		"\"low\":" + DoubleToString(low) + "," +
		"\"high\":" + DoubleToString(high) + "," +
		"\"close\":" + DoubleToString(close) + "," +
		"\"volume\":" + IntegerToString(tick_volume) + "}";
}

string ratesToJson(MqlRates & rates[]) {
	string json = "[";
	int size = ArraySize(rates);
	int end = 29;
	if (size < 30) {
		end = size - 1;
	}
	for (int i = end; i >= 0; i--) {
		json += rateToJson(rates[i]);
		if (i != 0) {
			json += ",";
		}
	}
	json += "]";
	return json;
}
