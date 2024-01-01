import {RESPONSE} from "./Enum";
import {Listener} from "./Listener";
const zmq = require("zeromq/v5-compat")
import * as url from 'url';

export interface ResponeMessage {
	type: string,
	id: string,
	err: any,
	json: any
}

export class MetaTrader4Connection extends Listener {
	private reqSocket = zmq.socket('req');
	private pullSocket = zmq.socket('pull');
	private requestId = 1;
	private requestQueueValue = 5;
	private requestTimeoutValue = 15000;
	private apiKey: string | null = null;
	private reqUrl: string | null = null;
	private pullUrl: string | null = null;
	private requests: { reqId: number, reject: any, resolve: any, timeout: any }[] = [];

	constructor({apiKey = "CHANGEME", reqUrl, pullUrl}: {apiKey: string, reqUrl: string, pullUrl: string}) {
		super();
		this.apiKey = apiKey;
		this.reqUrl = reqUrl;
		this.pullUrl = pullUrl;
	}

	public connect() {
		const { reqUrl, pullUrl } = this;
		if (!reqUrl || !url.parse(reqUrl).hostname) {
			throw new Error("reqUrl invalid.")
		} else if (!pullUrl || !url.parse(pullUrl).hostname) {
			throw new Error("pullUrl invalid.")
		}

		this.checkConnection(this.reqSocket, reqUrl);
		this.checkConnection(this.pullSocket, pullUrl);
		this.reqSocket.monitor().connect(reqUrl);
		this.pullSocket.monitor().connect(pullUrl);
		this.reqSocket.on('message', (msg: any) => {
			const message = this.parseMessage(msg);
			this.callListener("onReqMessage", [message]);
		});
		this.pullSocket.on('message', (msg: any) => {
			const message = this.parseMessage(msg);
			if (message.type === "RESPONSE") {
				const i = this.requests.findIndex(r => r.reqId === parseInt(message.id), 10);
				if (message.err == null) {
					this.requests[i].resolve(message.json);
					this.requests.splice(i, 1);
				} else {
					this.reject(parseInt(message.id, 10), message.err);
				}
			} else if (message.type === "STREAM") {
				this.callListener(message.id, [message.json]);
			}
			this.callListener("onPullMessage", [message]);
		});

		this.reqSocket.on('connect', () => this.reqConnected = true);
		this.pullSocket.on('connect', () => this.pullConnected = true);
		this.reqSocket.on('disconnect', () => this.reqConnected = false);
		this.pullSocket.on('disconnect', () => this.pullConnected = false);
	}

	private _reqConnected: boolean = false;
	private _pullConnected: boolean = false;

	private set reqConnected(value: boolean) {
		if (value === true && !this._reqConnected && this._pullConnected) {
			this._reqConnected = value;
			this.callListener("onConnect", []);
		} else if (value === false && this._reqConnected && this._pullConnected) {
			this._reqConnected = value;
			this.callListener("onDisconnect", []);
		} else {
			this._reqConnected = value;
		}
	}

	private get reqConnected() {
		return this._reqConnected;
	}

	private set pullConnected(value: boolean) {
		if (value === true && this._reqConnected && !this._pullConnected) {
			this._pullConnected = value;
			this.callListener("onConnect", []);
		} else if (value === false && this._reqConnected && this._pullConnected) {
			this._pullConnected = value;
			this.callListener("onDisconnect", []);
		} else {
			this._pullConnected = value;
		}
	}

	private get pullConnected() {
		return this._pullConnected;
	}

	public onConnect(callback: () => void) {
		this.addListener("onConnect", callback);
	}

	public onDisconnect(callback: () => void) {
		this.addListener("onDisconnect", callback);
	}

	public checkConnection(socket: any, url: string) {
		let reqDelayedConnects = 0;

		function performCheck() {
			reqDelayedConnects++;
			if (reqDelayedConnects === 2) {
				socket.removeListener('connect', connectCallback);
				socket.removeListener('connect_delay', performCheck);
				console.warn(`METATRADER4 cannot connect with ${url}.`)
			}
		}

		function connectCallback() {
			socket.removeListener('connect_delay', performCheck);
		}

		socket.once('connect', connectCallback);
		socket.on('connect_delay', performCheck);
	}

	public onReqMessage(callback: (message: any) => void) {
		this.addListener("onReqMessage", callback);
	}

	public onPullMessage(callback: (message: any) => void) {
		this.addListener("onPullMessage", callback);
	}

	private parseMessage(message: any): ResponeMessage {
		const split = message.toString().split('|');
		const type = split.shift();
		const id = split.shift();
		const status = +split[0];
		let err, msg;
		if (status === RESPONSE.OK) {
			err = null;
			msg = split.length === 2 && split[1] === "" ? true : split;
			if (msg !== true) {
				msg.shift();
			}
		} else if (status === RESPONSE.FAILED) {
			err = split[2];
			msg = null;
		}
		try {
			const json = JSON.parse(msg);
			return {type, id, err, json};
		} catch (e) {
			return {type, id, err, json: msg };
		}
	}

	private requestCheckConnections(fn: any) {
		if (!this.reqConnected) {
			fn(new Error("ZMQ REQ connection is closed."));
			return false
		} else if (!this.pullConnected) {
			fn(new Error("ZMQ PULL connection is closed."));
			return false
		} else {
			return true
		}
	}

	private isWaitingForResponse(reqId: number) {
		return this.requests.findIndex(r => r.reqId === reqId) === -1;
	}

	private reject(reqId: number, e: any) {
		const i = this.requests.findIndex(r => r.reqId === reqId);
		if (i !== -1){
			this.requests[i].reject(e);
			this.requests.splice(i, 1);
		}
	}

	public request(...args: (string | number)[]): Promise<any> {
		return new Promise((resolve, reject) => {
			const reqId = this.requestId;
			this.requestId += 1;
			if (this.requestCheckConnections(reject))
				setTimeout(() => {
					const timeout = setTimeout(() => {
						this.reject(reqId, new Error("ZMQ Request timeout."));
					}, this.requestTimeoutValue);
					this.requests.push({reqId, resolve, reject, timeout});
					if (args.some(arg => typeof(arg) === 'string' && arg.includes("|"))) {
						console.warn(`${reqId}|${args.join("|")}\n`);
					}
					this.reqSocket.send(`${this.apiKey}|${reqId}|${args.join("|")}`);
				}, this.requestQueueValue);
		})
	}

}
