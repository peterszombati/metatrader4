// See: https://docs.mql4.com/constants/tradingconstants/orderproperties
export enum OP {
	BUY = 0,
	SELL = 1,
	BUYLIMIT = 2,
	SELLLIMIT = 3,
	BUYSTOP = 4,
	SELLSTOP = 5,
}

// Identificators for internal unit types.
export const UNIT_CONTRACTS = 0;
export const UNIT_CURRENCY = 1;

// Identificators for internal request operations.
export enum REQUEST {
	PING = 1,
	TRADE_OPEN = 11,
	TRADE_MODIFY = 12,
	TRADE_DELETE = 13,
	DELETE_ALL_PENDING_ORDERS = 21,
	CLOSE_MARKET_ORDER = 22,
	CLOSE_ALL_MARKET_ORDERS = 23,
	RATES = 31,
	ACCOUNT = 41,
	ORDERS = 51,
	SUBSCRIBE_PRICES = 61,
	SUBSCRIBE_ACCOUNT = 62,
	SUBSCRIBE_ORDERS = 63,
	UNSUBSCRIBE_PRICES = 64,
	UNSUBSCRIBE_ACCOUNT = 65,
	UNSUBSCRIBE_ORDERS = 66,
	CHART = 71,
}

// Identificators for internal response operations.
export enum RESPONSE {
	OK = 0,
	FAILED = 1
}
