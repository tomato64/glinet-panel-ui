/*
 * Tomato64 JSON API client for the front-panel UI.
 *
 * Fetches /api/v1/<path> from httpd and returns the decoded object, or null.
 * This is the panel's only route to nvram-backed data: ucode has no nvram
 * binding here, and the sampler's upstream sources (ubus network.interface.*,
 * ubus dhcpsnoop, uci wireless) do not exist on Tomato64.
 *
 * Three facts about httpd shape this file:
 *
 * - It binds to lan_ipaddr, not 0.0.0.0, so 127.0.0.1 does not connect.
 *   The address and port are read from nvram like any other client would.
 *
 * - It authenticates with HTTP Basic against http_username/http_passwd, and
 *   substitutes root/admin when either is empty. The panel authenticates the
 *   same way rather than through any bypass, so it adds no new access path.
 *   A 401 re-reads the credentials once, which is what makes a password
 *   change in the GUI take effect without restarting the panel.
 *
 * - It answers HTTP/1.0 and closes, so a response is read to EOF with no
 *   chunked decoding and no keep-alive.
 *
 * Calls block. Everything is local and small, but /wireless spawns iwinfo and
 * iw per radio, so both connect and receive are bounded to keep a slow answer
 * from stalling the uloop that drives the display and the touchscreen.
 */

'use strict';

import * as socket from 'socket';
import { popen } from 'fs';

const TIMEOUT_MS = 2000;

let cfg = null;

function nvram_get(key) {
	let p = popen(`nvram get ${key}`, 'r');

	if (!p)
		return '';

	let v = p.read('all') ?? '';

	p.close();

	return trim(v);
}

function config_load() {
	let user = nvram_get('http_username');
	let pass = nvram_get('http_passwd');

	cfg = {
		host: nvram_get('lan_ipaddr') || '192.168.1.1',
		port: +(nvram_get('http_lanport') || '80'),
		auth: b64enc(`${length(user) ? user : 'root'}:${length(pass) ? pass : 'admin'}`)
	};
}

function fetch(path) {
	let s = socket.connect(cfg.host, cfg.port, null, TIMEOUT_MS);

	if (!s)
		return { status: 0 };

	s.setopt(socket.SOL_SOCKET, socket.SO_RCVTIMEO,
		 { sec: TIMEOUT_MS / 1000, usec: 0 });

	s.send(`GET /api/v1/${path} HTTP/1.0\r\n` +
	       `Host: ${cfg.host}\r\n` +
	       `Authorization: Basic ${cfg.auth}\r\n` +
	       `Connection: close\r\n\r\n`);

	let buf = '';

	for (;;) {
		let chunk = s.recv(4096);

		if (chunk == null || !length(chunk))
			break;

		buf += chunk;
	}

	s.close();

	let sep = index(buf, '\r\n\r\n');

	if (sep < 0)
		return { status: 0 };

	let m = match(substr(buf, 0, sep), /^HTTP\/[0-9.]+ ([0-9]+)/);

	return { status: m ? +m[1] : 0, body: substr(buf, sep + 4) };
}

export function api_get(path) {
	if (!cfg)
		config_load();

	let r = fetch(path);

	if (r.status == 401) {
		config_load();
		r = fetch(path);
	}

	if (r.status != 200)
		return null;

	try {
		return json(r.body);
	}
	catch (e) {
		return null;
	}
};
