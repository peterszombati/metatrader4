export interface TradingAccount {
	currency: string,
	balance: number,
	profit: number,
	equity: number,
	margin: number,
	margin_free: number,
	margin_level: number,
	margin_call_level: number,
	margin_stop_out_level: number,
	leverage: number
}

export interface Order {
	order: number,
	open_time: string,
	type: number,
	volume: number,
	price: number,
	sl: number,
	tp: number,
	commission: number,
	swap: number,
	profit: number,
	comment: string
}
