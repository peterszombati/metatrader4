## Connection between MetaTrader4 and NodeJS

### Sources

`#1` https://github.com/dingmaotu/mql4-lib

`#2` https://github.com/dingmaotu/mql-zmq

### 1. Compile MetaTrader4Bridge.mq4

1. Download https://github.com/dingmaotu/mql4-lib/archive/master.zip
2. Unzip to: `<MetaTrader Data>\MQL4\Include\Mql\<mql4-lib content>`
3. Download https://github.com/dingmaotu/mql-zmq/archive/master.zip
4. Unzip to: `<MetaTrader Data>\MQL4\<mql-zmq content>`
5. Move from: `<MetaTrader Data>\MQL4\Library\MT4\<content>` to
`<MetaTrader Data>\MQL4\Libraries\<content>`
6. Delete: `<MetaTrader Data>\MQL4\Library`
7. Download https://raw.githubusercontent.com/peterszombati/metatrader4/master/src/MetaTrader4Bridge.mq4
8. Move to: `<MetaTrader Data>\MQL4\Experts\MetaTrader4Bridge.mq4`
9. Compile `MetaTrader4Bridge.mq4` expert

### Example usage
```ts
import MetaTrader4 from "metatrader4";

const mt4 = new MetaTrader4({
	apiKey: "CHANGEME",
	reqUrl: "tcp://127.0.0.1:5555",
	pullUrl: "tcp://127.0.0.1:5556"
});

mt4.onConnect(() => {
	console.log("Connected");
	mt4.getAccountInfo().then((account) => {
		console.log(account);
	});
	mt4.getLastCandles("EURUSD").then((candles) => {
		console.log(candles);
	});
});

mt4.connect();
```
### node-mt4-zmq-bridge project has deficiency

This project has deficiency: https://github.com/bonnevoyager/node-mt4-zmq-bridge so I developed it and published this new repository.
