import {MetaTrader4} from "./MetaTrader4";

const MetaTrader = new MetaTrader4({
	apiKey:"CHANGEME",
	reqUrl: "tcp://127.0.0.1:5555",
	pullUrl: "tcp://127.0.0.1:5556"});

MetaTrader.onConnect(() => {
	console.log("Connected");
	MetaTrader.getAccountInfo().then((account) => {
		console.log(account);
	});
	MetaTrader.getLastCandles("EURGBP").then((candles) => {
		console.log(candles);
	});
});

MetaTrader.connect();
