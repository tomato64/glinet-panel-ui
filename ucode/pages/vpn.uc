/*
 * The tunnels this firmware can run, and a way to bring one up or take it down.
 *
 * Tomato64 has OpenVPN clients and servers and WireGuard interfaces, all of
 * them configured from the web interface and none of them reachable from the
 * panel until now. What a panel is good for is the part you want without a
 * browser: is the tunnel up, and put it back if it is not.
 *
 * Starting and stopping goes through rc's own service table - `service
 * vpnclient1 start` - which is what the web interface calls too, so there is
 * one path into it rather than two. The API hands over the service name with
 * each tunnel, so nothing here has to know how the firmware spells them.
 */

'use strict';

import * as lv from 'lv';
import { ROW_H_ROOT, C_OK, C_TXT_DIM } from '../lib/theme.uc';
import { list_new, dialog_new } from '../lib/widget.uc';
import { key_of } from '../lib/layout.uc';
import { rows_new } from '../lib/component/rows.uc';

let state, activity, defer;
let parent_obj, dialog;
let list;

function tunnels() {
	let out = [];

	/* A tunnel that is neither running nor set to start is one the user has
	   never configured, and listing a dozen of those buries the two that
	   matter. */
	for (let entry in state.vpn)
		if (entry.up || entry.enabled)
			push(out, entry);

	return out;
}

function state_of(tunnel) {
	if (tunnel.up)
		return 'Up';

	return tunnel.enabled ? 'Down' : 'Off';
}

function dialog_close() {
	activity();

	if (!dialog)
		return;

	/* A button must not delete the dialog it is part of from its own
	   handler: the indev still holds the pressed object. */
	let doomed = dialog;

	dialog = null;

	defer(function() {
		doomed.close();
	});
}

function service_run(tunnel) {
	let action = tunnel.up ? 'stop' : 'start';

	if (system([ 'service', tunnel.service, action ]) != 0)
		warn(sprintf('panel: service %s %s failed\n', tunnel.service, action));
}

function dialog_open(tunnel) {
	activity();

	if (dialog)
		return;

	let down = tunnel.up;

	dialog = dialog_new(parent_obj, {
		title: down ? 'Disconnect?' : 'Connect?',
		body: down ? sprintf('%s will be taken down.', tunnel.name)
			   : sprintf('%s will be brought up.', tunnel.name),
		confirm: down ? 'Disconnect' : 'Connect',
		activity,
		on_cancel: dialog_close,
		on_confirm: function() {
			dialog_close();
			service_run(tunnel);
		}
	});
}

function tap_handler(tunnel) {
	return function() {
		dialog_open(tunnel);
	};
}

function key_tunnel(tunnel) {
	return sprintf('%s|%s', tunnel.service, state_of(tunnel));
}

function row_of(tunnel) {
	return {
		dot: tunnel.up,
		label: tunnel.name,
		value: state_of(tunnel),
		value_colour: tunnel.up ? C_OK : C_TXT_DIM,
		on_tap: tap_handler(tunnel)
	};
}

function page_update(source) {
	let list_of = tunnels();

	list.set(key_of(list_of, key_tunnel), list_of, row_of);
}

function page_build(parent, ctx) {
	state = ctx.state;
	activity = ctx.activity;
	defer = ctx.defer;
	parent_obj = parent;

	let scroll = list_new(parent, { title: 'VPN', activity });

	list = rows_new(scroll, { empty: 'No tunnels', h: ROW_H_ROOT,
				  large: true, activity });
}

function page_leave() {
	dialog_close();
}

return {
	needs: [ 'vpn' ],
	build: page_build,
	enter: page_update,
	update: page_update,
	leave: page_leave
};
