/*
 * Remote control of the panel, for the web UI's screen page.
 *
 * The UI owns the display and the input, so anything that wants to see the
 * panel or press it has to ask this process. httpd does that over a unix
 * datagram socket, one command per message, because it links against neither
 * ubus nor LVGL and a drag sends tens of samples a second - a sendto() each,
 * no process spawned.
 *
 *   t <x> <y> <0|1>  a pointer sample, pressed or released
 *   s <path>         capture the screen to <path>
 *   w                wake the panel
 *
 * Datagrams rather than a FIFO for two reasons: each message arrives whole,
 * so a command can never be read half written, and the socket is non-blocking,
 * so the queue can be drained to the end on every wakeup. A FIFO read through
 * buffered stdio can leave a message sitting unseen until the next one arrives
 * - and a pointer release left sitting is a finger stuck down on the panel.
 *
 * The samples go to lv.pointer_send(), a second input device beside the
 * touchscreen, so LVGL turns them into taps, drags and swipes by the same
 * rules as a finger - including waking the panel, which the idle screen does
 * itself on being pressed. Waking from here instead would load the root screen
 * before the sample was delivered, and the one click would then both dismiss
 * the clock and press whatever it landed on behind it. The idle screen's own
 * handler calls lv.touch_drop(), which is what stops that for a finger.
 *
 * The capture is written under a temporary name and renamed, so httpd polling
 * for it never opens a half-written file.
 */

'use strict';

import * as lv from 'lv';
import * as uloop from 'uloop';
import * as socket from 'socket';
import { rename, unlink } from 'fs';
import { runtime_wake } from './runtime.uc';

const SOCK = '/var/run/panel_remote';

/* Longer than any command, and a datagram over it is truncated, not split. */
const MSG_MAX = 256;

let sk, watch;

function shot(path) {
	if (!path)
		return;

	let tmp = path + '.new';

	lv.refresh();

	if (!lv.screenshot(tmp)) {
		unlink(tmp);

		return;
	}

	rename(tmp, path);
}

function apply(msg) {
	let f = split(trim(msg), /\s+/);
	let down;

	switch (f[0]) {
	case 't':
		down = f[3] == '1';

		lv.pointer_send(+f[1], +f[2], down);
		break;

	case 's':
		shot(f[1]);
		break;

	case 'w':
		runtime_wake();
		break;
	}
}

export function remote_init() {
	sk = socket.create(socket.AF_UNIX, socket.SOCK_DGRAM | socket.SOCK_NONBLOCK);

	if (!sk)
		return false;

	/* Left behind by a UI that was killed rather than stopped: bind fails
	   on an existing path, and nothing else owns this one. */
	unlink(SOCK);

	if (!sk.bind({ family: socket.AF_UNIX, path: SOCK })) {
		sk.close();
		sk = null;

		return false;
	}

	watch = uloop.handle(sk, function(h, events) {
		let msg;

		/* To the end of the queue: the socket is non-blocking, so recv
		   returns null once it is empty rather than waiting. */
		while ((msg = sk.recv(MSG_MAX)) != null && length(msg))
			apply(msg);
	}, uloop.ULOOP_READ);

	return watch != null;
};
