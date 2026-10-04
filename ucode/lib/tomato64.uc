/*
 * Tomato64 data sources for the front-panel UI.
 *
 * lib/sampler.uc was written for OpenWrt, and five of its sources do not
 * exist here. Everything else it reads - nl80211, hostapd and netifd's
 * network.wireless over ubus, the /etc/config/wireless netifd is fed from,
 * /proc and /sys - is present on Tomato64 and is left alone. These are the
 * five, each returning the shape the pages already consume:
 *
 *   wan_device()  ubus network.interface.wan  - /etc/config/network is empty,
 *                 netifd only drives WiFi here, so there is no wan interface
 *   interfaces()  ubus network.interface dump - same reason
 *   sysinfo()     ubus system info            - that object is procd's, and
 *                 Tomato64 does not run procd
 *   clients()     ubus dhcpsnoop + /tmp/dhcp.leases - neither exists; the
 *                 Tomato dnsmasq lease file is transient in any case
 *   ports()       /etc/board.json             - present, but written by the
 *                 WiFi stack with a wlan section only, no network section
 *
 * All of it comes through the httpd JSON API (lib/api.uc) rather than nvram,
 * for which ucode has no binding.
 */

'use strict';

import { api_get } from './api.uc';

function mask_len(mask) {
	let bits = 0;

	for (let octet in split(mask ?? '', '.'))
		for (let v = +octet; v; v = (v << 1) & 0xff)
			bits++;

	return bits;
}

function ipv4(address, mask) {
	return address ? [ { address, mask: mask_len(mask) } ] : [];
}

export function wan_device() {
	return api_get('wan')?.wan?.iface;
};

/*
 * netifd's "interface dump" shape, which pages/interfaces.uc and
 * subpages/interface.uc read: up, device, l3_device, uptime, ipv4-address as
 * [{ address, mask }] with the mask as a prefix length, and dns-server.
 */
export function interfaces() {
	let wan = api_get('wan')?.wan;
	let lan = api_get('lan')?.lan ?? [];
	let out = {};

	if (wan)
		out.wan = {
			up: !!wan.up,
			proto: wan.proto,
			device: wan.iface,
			l3_device: wan.iface,
			uptime: wan.uptime,
			'ipv4-address': wan.up ? ipv4(wan.ipaddr, wan.netmask) : [],
			'dns-server': wan.dns ?? []
		};

	/*
	 * One entry per LAN bridge. The names match what the web interface
	 * calls them - LAN for br0, then LAN1 and up - because the pages
	 * upper-case the key, and somebody reading the panel should see the
	 * same name they configured the bridge under.
	 */
	for (let bridge in lan) {
		let key = bridge.index ? sprintf('lan%d', bridge.index) : 'lan';

		out[key] = {
			up: !!bridge.up,
			device: bridge.ifname,
			l3_device: bridge.ifname,
			'ipv4-address': ipv4(bridge.ipaddr, bridge.netmask)
		};
	}

	return out;
};

/* Percentages, as sampler.uc's state.mem and state.flash hold them. */
export function sysinfo() {
	let s = api_get('system')?.system;
	let out = {};

	if (s?.mem_total_kb > 0)
		out.mem = int(s.mem_used_kb * 100 / s.mem_total_kb);

	if (s?.flash_total_kb > 0)
		out.flash = int(s.flash_used_kb * 100 / s.flash_total_kb);

	return out;
};

/*
 * mac -> { ip, hostname }, keyed by lower-case MAC as sampler.uc keys it.
 * No DHCP vendor class comes through, so client_type() in the sampler files
 * every client as a generic device.
 */
export function clients() {
	let out = {};

	for (let c in api_get('clients')?.clients?.list ?? [])
		out[lc(c.mac)] = {
			ip: c.ip,
			hostname: length(c.hostname) ? c.hostname : null
		};

	return out;
};

/*
 * The tunnels this firmware can run, up or down, as the API reports them:
 * { kind, service, index, name, enabled, up }. The service name is rc's, so a
 * page that offers to connect one has the argument for `service <name> start`
 * without having to know how the firmware spells it.
 */
export function vpn() {
	return api_get('vpn')?.vpn ?? [];
};

/*
 * The chassis ports, named and ordered by the API: the WAN and the LAN
 * bridge's members in ethN order, carrying whatever the Port Labels page calls
 * them. The naming lives there rather than here so that the panel and the web
 * interface never disagree about which socket is which.
 *
 * The role travels with each port, so pages/ports.uc can draw an SFP cage for
 * the fibre socket without having to recognise it by name - which stops being
 * possible the moment somebody labels it something of their own.
 */
export function ports() {
	let out = [];

	for (let port in api_get('ports')?.ports ?? [])
		push(out, { name: port.name, device: port.device,
			    role: port.role });

	return out;
};
