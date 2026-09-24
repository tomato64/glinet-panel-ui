/*
 * The menu: every page as a tile, one tap away.
 *
 * The panel started as one long row of pages, swiped left and right. That is
 * fine for three, and tedious by twelve - reaching the last one meant eleven
 * swipes, and Tomato64 keeps adding pages. So this sits first in the row, and
 * tapping the idle clock lands here (view_wake() goes to the first page), the
 * way the stock firmware puts a menu behind its home screen.
 *
 * Nothing else changes: the pages are still in a row and still swipe, and the
 * menu button in the corner of each of them comes back here.
 *
 * The tiles are built from the page list the framework hands over rather than
 * a list of its own, so a page added to the panel_pages setting appears here
 * with it. A name with no entry in TITLES is shown capitalised, which is right
 * often enough - "ports", "system", "clients" - and wrong quietly rather than
 * leaving a hole.
 */

'use strict';

import * as lv from 'lv';
import { FONT_REG_13 } from '../lib/assets.uc';
import { C_RAISED, C_DOWN, C_TXT, W, BODY_Y, BODY_H,
	 GROUP_RADIUS } from '../lib/theme.uc';
import { label_new, header_new, scroll_new } from '../lib/widget.uc';
import { grid_new, cell_set } from '../lib/layout.uc';

/* Where a page's own title is not the word in the config. */
const TITLES = {
	menu:		'Menu',
	traffic:	'Traffic',
	weather:	'Weather',
	wifi:		'Wi-Fi',
	wifitoggles:	'Wi-Fi toggles',
	radio:		'Radios',
	qrcodes:	'QR codes',
	clients:	'Clients',
	interfaces:	'Interfaces',
	ports:		'Ports',
	system:		'System',
	brightness:	'Brightness',
	vpn:		'VPN',
	reboot:		'Reboot'
};

const COLS	= 3;
const PAD_X	= 10;
const GAP	= 8;
const TILE_H	= 52;

let goto_page, activity, defer;

function title_of(name) {
	return TITLES[name] ?? (uc(substr(name, 0, 1)) + substr(name, 1));
}

function tile_new(grid, name, col, row) {
	let tile = lv.obj(grid);

	tile.style({ bg_color: C_RAISED, bg_opa: lv.OPA_COVER,
		     radius: GROUP_RADIUS, border_width: 0, pad_all: 0 });
	tile.style({ bg_color: C_DOWN }, lv.STATE_PRESSED);
	tile.clickable(true);
	tile.scrollable(false);

	let text = label_new(tile, FONT_REG_13, C_TXT, title_of(name));

	text.set({ align: lv.ALIGN_CENTER });
	text.clickable(false);

	/* Deferred: this runs inside lv_timer_handler, and the jump tears the
	   page tree about while the input still holds the tile that was
	   pressed. */
	tile.on(lv.EVENT_CLICKED, function() {
		activity();

		defer(function() {
			goto_page(name);
		});
	});

	cell_set(tile, col, row);

	return tile;
}

function page_build(parent, ctx) {
	activity = ctx.activity;
	goto_page = ctx.goto;
	defer = ctx.defer;

	header_new(parent, 'Menu', false, null);

	let names = [];

	for (let name in ctx.page_names())
		if (name != 'menu')
			push(names, name);

	let rows = [];

	for (let i = 0; i < length(names); i += COLS)
		push(rows, TILE_H);

	/* The grid is as tall as its rows, inside an area that is not, so a
	   list longer than the screen scrolls rather than being cut off. */
	let area = scroll_new(parent, 0, BODY_Y, W, BODY_H);
	let grid = grid_new(area, { cols: [ '1fr', '1fr', '1fr' ], rows,
				    gap_x: GAP, gap_y: GAP,
				    x: PAD_X, y: 0,
				    w: W - 2 * PAD_X,
				    h: length(rows) * TILE_H +
				       (length(rows) - 1) * GAP });

	for (let i = 0; i < length(names); i++)
		tile_new(grid, names[i], i % COLS, int(i / COLS));
}

return {
	needs: [],
	build: page_build
};
