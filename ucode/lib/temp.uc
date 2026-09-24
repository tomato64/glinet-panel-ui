/*
 * Celsius or Fahrenheit, from the panel_temp_unit setting.
 *
 * Two readings on this panel are temperatures and they arrive by different
 * routes: the SoC's, which the kernel reports in millidegrees Celsius and
 * nothing else, and the weather, which the forecast service will return in
 * either unit if asked. So the conversion lives here and the weather source
 * asks for the right one rather than converting twice.
 *
 * Read once: a unit is not something that changes while the panel is running.
 */

'use strict';

import { panel_get } from './nvram.uc';

const FAHRENHEIT = 'f';

let unit;

/**
 * temp_unit - 'f' or 'c'
 */
export function temp_unit() {
	unit ??= (lc(panel_get('temp_unit') ?? '') == FAHRENHEIT) ? FAHRENHEIT : 'c';

	return unit;
};

/**
 * temp_from_c - a Celsius reading in the configured unit
 * @celsius: the reading, or null
 *
 * Return: the converted reading, or null.
 */
export function temp_from_c(celsius) {
	if (celsius == null)
		return null;

	return temp_unit() == FAHRENHEIT ? (celsius * 9 / 5) + 32 : celsius;
};

/**
 * temp_mark - the degree sign with its letter, for a reading that stands alone
 */
export function temp_mark() {
	return temp_unit() == FAHRENHEIT ? '°F' : '°C';
};
