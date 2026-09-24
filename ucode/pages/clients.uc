'use strict';

import { ROW_H_ROOT } from '../lib/theme.uc';
import { IMAGE_COMPUTER, IMAGE_CONSOLE, IMAGE_DEVICE, IMAGE_JACK_SM,
	 IMAGE_PHONE, IMAGE_PRINTER, IMAGE_TV } from '../lib/assets.uc';
import { list_new, signal_level } from '../lib/widget.uc';
import { key_of } from '../lib/layout.uc';
import { rows_new } from '../lib/component/rows.uc';

const TYPE_ICONS = {
	computer: IMAGE_COMPUTER,
	phone: IMAGE_PHONE,
	tv: IMAGE_TV,
	console: IMAGE_CONSOLE,
	printer: IMAGE_PRINTER,
	device: IMAGE_DEVICE
};

let state, activity, open;
let list;

/*
 * Every client, not only the associated ones. state.stations is what the radios
 * can see, which on a router is a minority of what is connected - upstream
 * listed those alone because the dhcpsnoop it was written against only knew
 * about WiFi. state.clients is every neighbour on the LAN bridges, from the
 * ARP table by way of the JSON API, so the wired machines are already there.
 *
 * A station is then decoration: its band and its signal, and the icon that says
 * which way a client reached the router.
 */
function stations_by_mac() {
	let out = {};

	for (let station in state.stations)
		out[station.mac] = station;

	return out;
}

/* Sortable: octets padded so .9 comes before .10, absent addresses last. */
function address_key(ip) {
	let parts = split(ip ?? '', '.');

	if (length(parts) != 4)
		return 'zzzz';

	return sprintf('%03d%03d%03d%03d', +parts[0], +parts[1], +parts[2],
		       +parts[3]);
}

function clients_list() {
	let stations = stations_by_mac();
	let out = [];

	for (let mac, record in state.clients)
		push(out, { mac, ip: record.ip, hostname: record.hostname,
			    type: record.type, station: stations[mac] });

	/* Associated but not in the ARP table yet: just joined, or holds no
	   address of ours. It is still a client and the page should say so. */
	for (let mac, station in stations)
		if (!state.clients[mac])
			push(out, { mac, station });

	return sort(out, function(a, b) {
		let ka = address_key(a.ip), kb = address_key(b.ip);

		if (ka != kb)
			return ka < kb ? -1 : 1;

		return a.mac < b.mac ? -1 : 1;
	});
}

function label_of(client) {
	if (client.hostname)
		return client.hostname;

	return uc(substr(client.mac, 9));
}

function icon_of(client) {
	/* Wired says more than the type does, and the type is a guess: nothing
	   here sees a DHCP vendor class, so every client arrives as generic. */
	if (!client.station)
		return IMAGE_JACK_SM;

	return TYPE_ICONS[client.type] ?? IMAGE_DEVICE;
}

function secondary_of(client) {
	if (client.station?.band)
		return client.ip ? sprintf('%s · %s', client.ip, client.station.band)
				 : client.station.band;

	return client.ip;
}

/* No signal in the key: it crosses a threshold at tick rate, and rebuilding
   for it would throw the scroll position back to the top. Set in place. */
function key_client(client) {
	return sprintf('%s|%s|%s', client.mac, label_of(client),
		       secondary_of(client) ?? '');
}

function tap_handler(mac) {
	return function() {
		activity();
		open('client', { mac });
	};
}

function row_of(client) {
	let row = {
		icon: icon_of(client),
		label: label_of(client),
		secondary: secondary_of(client),
		accessory: 'chevron',
		on_tap: tap_handler(client.mac)
	};

	if (client.station)
		row.signal = signal_level(client.station.signal);

	return row;
}

function page_update(source) {
	let clients = clients_list();

	if (list.set(key_of(clients, key_client), clients, row_of))
		return;

	for (let i = 0; i < length(list.rows); i++)
		if (list.rows[i].signal)
			list.rows[i].signal.set(signal_level(clients[i].station?.signal));
}

function page_build(parent, ctx) {
	state = ctx.state;
	activity = ctx.activity;
	open = ctx.open;

	let scroll = list_new(parent, { title: 'Clients', activity });

	list = rows_new(scroll, { empty: 'No clients', h: ROW_H_ROOT,
				  large: true, activity });
}

return {
	needs: [ 'wireless', 'stations', 'clients' ],
	build: page_build,
	enter: page_update,
	update: page_update
};
