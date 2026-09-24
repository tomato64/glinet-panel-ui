/*
 * Tomato64 boot splash for the GL-BE14000 front panel.
 *
 * Started by panel_boot from set_devs_be14000 as soon as the panel driver is
 * loaded. Shows Tux full screen while a tomato travels along the bottom to
 * mark how far the boot has got, then hands the display to the UI.
 *
 * The milestones are observed, not scheduled: each is something the boot
 * really passes, read from the system, so the tomato only moves when
 * something happened. They can complete out of order - an unplugged WAN never
 * gets a default route - so the tomato goes to the furthest one reached.
 *
 * The handover follows upstream boot.uc's protocol, which panel.uc already
 * speaks. This applet drops DRM master but stays alive, so its frame stays on
 * the plane and the panel never goes dark; it starts panel_ui with
 * GLINET_PANEL_BOOT_PID pointing at its pidfile; panel.uc draws and commits
 * its own first frame and only then sends this applet SIGTERM. Exiting any
 * earlier would destroy a framebuffer still on the plane, and the kernel
 * answers that by disabling the CRTC.
 *
 * The UI is started when httpd answers, because that is what the UI reads
 * from, not when the WAN is up: a router with no WAN must still get its UI.
 */

'use strict';

import * as lv from 'lv';
import * as uloop from 'uloop';
import { readfile, open } from 'fs';
import { api_get } from './lib/api.uc';

const W = 320;
const H = 240;

const ART = '/usr/share/glinet-panel-ui/tux.png';
const MARKER = '/usr/share/glinet-panel-ui/tomato.png';
const PIDFILE = '/var/run/panel_boot.pid';

/* Must match gen-splash.py: the marker is composited onto this colour,
   because lv.image_load() drops alpha. */
const BAND = 0xd1f1e9;
const BAND_H = 22;

const TRACK = 0xa9cfc6;
const FILL = 0xd7263d;
const TRACK_H = 2;
const TRACK_X = 12;
const TRACK_W = W - 2 * TRACK_X;
const MARKER_SIZE = 18;

const TRACK_Y = H - BAND_H / 2;

const FRAME_MS = 33;
const POLL_MS = 500;

/* Handover no sooner than this, so a fast boot still shows the splash, and
   no later than that, so a boot where httpd never answers still gets a UI. */
const MIN_MS = 1500;
const MAX_MS = 120000;

let target = 0.05;
let shown = 0.0;
let started;
let handed = false;
let released = false;

let marker, fill;
let timers = {};

/* Debugging aid: a path prefix to screenshot the first and the last frame to,
   since this applet publishes no lvgl ubus object to ask it with. */
const SHOT = getenv('PANEL_BOOT_SHOT');

/* Set by panel_boot for a panel_boot=trace boot: each step is written and
   synced before the next, so after a reset the last line names the call that
   never returned. */
const TRACE = getenv('PANEL_BOOT_TRACE');

/* Set by panel_boot for a diagnostic boot. Markers go to the kernel log at
   KERN_EMERG, which reaches the console and so the ramoops copy of it that
   survives a reset - a persistent trace with no disk I/O to perturb timing.
   It has to be EMERG: rc sets console_loglevel to 1 from nvram partway
   through the boot, so anything lower is filtered out after about 9s. */
const KMSG = getenv('PANEL_BOOT_KMSG');

function trace(msg) {
	if (KMSG) {
		let k = open('/dev/kmsg', 'w');

		if (k) {
			k.write(`<0>panel_boot: ${msg}\n`);
			k.close();
		}
	}

	if (!TRACE)
		return;

	let f = open(TRACE, 'a');

	if (f) {
		f.write(sprintf('%s %s\n',
			split(readfile('/proc/uptime') ?? '', ' ')[0], msg));
		f.close();
	}

	system('sync');
}

function now_ms() {
	let t = clock(true);

	return t[0] * 1000 + t[1] / 1000000;
}

function operstate(dev) {
	return trim(readfile(`/sys/class/net/${dev}/operstate`) ?? '');
}

function lan_up() {
	return operstate('br0') == 'up';
}

function wifi_up() {
	let names = readfile('/proc/net/dev') ?? '';

	for (let line in split(names, '\n')) {
		let m = match(line, /^\s*(phy[0-9]+-ap[0-9]+):/);

		if (m && operstate(m[1]) == 'up')
			return true;
	}

	return false;
}

/* A default route, whatever the WAN interface is called. */
function wan_routed() {
	for (let line in split(readfile('/proc/net/route') ?? '', '\n')) {
		let f = split(trim(line), /\s+/);

		if (length(f) > 2 && f[1] == '00000000')
			return true;
	}

	return false;
}

/* Only worth asking once the LAN is up: httpd listens on its address. */
function ui_ready() {
	return lan_up() && api_get('ping') != null;
}

/* Declared after the functions it names: ucode binds a function declaration
   where it appears, so naming one earlier would capture null. */
const MILESTONES = [
	{ at: 0.30, passed: lan_up },
	{ at: 0.55, passed: wifi_up },
	{ at: 0.75, passed: wan_routed },
	{ at: 0.95, passed: ui_ready }
];

function build() {
	let screen = lv.screen();

	screen.style({ bg_color: BAND, bg_opa: lv.OPA_COVER, border_width: 0,
		       pad_all: 0 });
	screen.scrollbar(lv.SCROLLBAR_OFF);
	screen.scrollable(false);

	let art = lv.image(screen);

	art.src(lv.image_load(ART));
	art.set({ x: 0, y: 0 });

	let band = lv.obj(screen);

	band.style({ bg_color: BAND, bg_opa: lv.OPA_COVER, border_width: 0,
		     radius: 0, pad_all: 0 });
	band.scrollable(false);
	band.clickable(false);
	band.set({ x: 0, y: H - BAND_H, w: W, h: BAND_H });

	let track = lv.obj(screen);

	track.style({ bg_color: TRACK, bg_opa: lv.OPA_COVER, border_width: 0,
		      radius: TRACK_H, pad_all: 0 });
	track.scrollable(false);
	track.clickable(false);
	track.set({ x: TRACK_X, y: TRACK_Y - TRACK_H / 2, w: TRACK_W, h: TRACK_H });

	fill = lv.obj(screen);
	fill.style({ bg_color: FILL, bg_opa: lv.OPA_COVER, border_width: 0,
		     radius: TRACK_H, pad_all: 0 });
	fill.scrollable(false);
	fill.clickable(false);

	marker = lv.image(screen);
	marker.src(lv.image_load(MARKER));
}

function place() {
	let span = TRACK_W - MARKER_SIZE;
	let x = TRACK_X + int(shown * span);

	marker.set({ x, y: TRACK_Y - MARKER_SIZE / 2 });
	fill.set({ x: TRACK_X, y: TRACK_Y - TRACK_H / 2,
		   w: x - TRACK_X + MARKER_SIZE / 2, h: TRACK_H });
}

function handover() {
	trace('handover');

	if (SHOT)
		lv.screenshot(SHOT + '-end.png');

	released = true;

	lv.drm_drop_master();

	system(`setsid sh -c 'GLINET_PANEL_BOOT_PID=${PIDFILE} exec panel_ui' ` +
	       '< /dev/null > /dev/null 2>&1 &');
}

function lv_tick() {
	if (released)
		return;

	let delay = lv.timer_handler();

	timers.lv.set(delay < 5 ? 5 : (delay > 200 ? 200 : delay));
}

function frame() {
	if (released)
		return;

	/* Ease towards the target rather than jumping to it. */
	shown += (target - shown) * 0.15;

	if (target - shown < 0.002)
		shown = target;

	place();

	/* Hand over once the tomato has actually reached the end. */
	if (handed && shown >= 1.0) {
		handover();

		return;
	}

	timers.frame.set(FRAME_MS);
}

function poll() {
	if (handed)
		return;

	for (let m in MILESTONES)
		if (m.at > target && m.passed()) {
			target = m.at;
			trace(sprintf('milestone %.2f', target));
		}

	let elapsed = now_ms() - started;

	if ((target >= 0.95 && elapsed >= MIN_MS) || elapsed >= MAX_MS) {
		handed = true;
		target = 1.0;

		return;
	}

	timers.poll.set(POLL_MS);
}

trace('applet start');
trace('lv.init');

if (!lv.init())
	die('cannot initialise LVGL');

trace('lv.init ok; display_drm');

if (!lv.display_drm(getenv('PANEL_DRM_DEVICE') ?? '/dev/dri/card0', -1))
	die('cannot open the DRM display');

trace('display_drm ok; build');

build();

trace('build ok');

started = now_ms();

uloop.init();

timers.lv = uloop.timer(-1, lv_tick);
timers.frame = uloop.timer(-1, frame);
timers.poll = uloop.timer(-1, poll);

place();

trace('first refresh');
lv.refresh();
trace('first refresh ok - panel drawn');

if (SHOT)
	lv.screenshot(SHOT + '-start.png');

timers.lv.set(5);
timers.frame.set(FRAME_MS);
timers.poll.set(POLL_MS);

/* Kept for anything else that wants the display: drop master, stay alive. */
uloop.signal('SIGUSR1', function() {
	released = true;
	lv.drm_drop_master();
});

/* panel.uc's boot_applet_retire(), once its own frame is on the plane. */
uloop.signal('SIGTERM', function() {
	uloop.end();
});

uloop.run();
