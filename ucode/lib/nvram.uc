/*
 * The panel's settings, in Tomato64's nvram rather than UCI.
 *
 * Upstream keeps them in /etc/config/glinet_panel. Here /etc is a tmpfs that
 * is rebuilt every boot, so a config file has to be seeded from /usr/share on
 * the way up and is invisible to the web interface either way - which means
 * the only way to change the panel is over ssh. nvram is where the rest of
 * this firmware keeps its settings, it survives a boot, and the GUI already
 * knows how to write it.
 *
 * Every key is panel_<option>, where <option> is what the page asks for, so
 * the option names in pages and in loader.uc's requires_option carry over
 * unchanged.
 *
 * Read once into a cache: one fork of `nvram show` rather than one per key,
 * because this is read during startup by the settings, the page loader and
 * the weather source in turn.
 */

'use strict';

import { popen } from 'fs';

const PREFIX = 'panel_';

let cache;

function load() {
	let out = {};
	let proc = popen('nvram show 2>/dev/null');

	if (!proc)
		return out;

	for (let line = proc.read('line'); length(line); line = proc.read('line')) {
		let entry = trim(line);
		let eq = index(entry, '=');

		if (eq <= 0)
			continue;

		let key = substr(entry, 0, eq);

		if (substr(key, 0, length(PREFIX)) != PREFIX)
			continue;

		out[substr(key, length(PREFIX))] = substr(entry, eq + 1);
	}

	proc.close();

	return out;
}

/**
 * panel_settings - every panel_ setting, keyed without the prefix
 */
export function panel_settings() {
	cache ??= load();

	return cache;
};

/**
 * panel_get - one setting, or null when it is unset
 * @option: the name without the panel_ prefix
 */
export function panel_get(option) {
	let value = panel_settings()[option];

	return (value != null && value != '') ? value : null;
};

/**
 * panel_set - write one setting back and commit it
 * @option: the name without the panel_ prefix
 * @value: written as given
 *
 * argv rather than a command line: a value never reaches a shell, so nothing
 * here has to think about quoting it.
 *
 * Return: whether nvram took it.
 */
export function panel_set(option, value) {
	let assignment = sprintf('%s%s=%s', PREFIX, option, value);

	if (system([ 'nvram', 'set', assignment ]) != 0)
		return false;

	if (system([ 'nvram', 'commit' ]) != 0)
		return false;

	if (cache)
		cache[option] = `${value}`;

	return true;
};
