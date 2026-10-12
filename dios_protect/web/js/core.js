/* Shared UI state and the existing bounded NUI transport. No runtime dependencies. */
(() => {
    'use strict';
    const U = window.ProtectUI = {};
    U.$ = selector => document.querySelector(selector);
    U.all = selector => [...document.querySelectorAll(selector)];
    U.el = (tag, text, cls) => {
        const node = document.createElement(tag);
        if (text !== undefined) node.textContent = String(text);
        if (cls) node.className = cls;
        return node;
    };
    U.icon = name => {
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.classList.add('icon'); svg.setAttribute('aria-hidden', 'true');
        const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
        use.setAttribute('href', `icons.svg#${name}`); svg.append(use); return svg;
    };
    U.store = {
        data: {}, fallback: {}, live: {}, page: 'overview', visible: false, compact: false,
        pending: false, draft: {}, dirty: new Set(), chosen: new Map(), count: 4, mode: '',
        initialized: false, invitation: null, confirmation: null, cooldownDeadline: 0, offers: []
    };
    U.formations = ['adaptive', 'diamond', 'box', 'column', 'close', 'loose', 'left', 'right'];
    U.settingsFields = ['speed', 'gap', 'style', 'order', 'air'];
    U.t = (key, values = {}) => {
        const s = U.store;
        const selected = s.data.translations?.[key], fallback = s.fallback[key];
        const text = typeof selected === 'string' ? selected : typeof fallback === 'string' ? fallback : '';
        return text.replace(/\{(\w+)\}/g, (_, token) => {
            const value = values[token];
            return typeof value === 'string' || typeof value === 'number' ? String(value) : '';
        });
    };
    U.label = key => U.t(key) || (typeof key === 'string' ? key : '');
    U.language = () => { try { const code = (U.store.data.locale || 'en').replace(/_/g, '-'); new Intl.NumberFormat(code); return code; } catch { return 'en'; } };
    U.number = value => new Intl.NumberFormat(U.language(), { maximumFractionDigits: 1 }).format(Number(value) || 0);
    U.total = () => [...U.store.chosen.values()].reduce((sum, n) => sum + n, 0);
    U.time = ms => {
        const seconds = Math.max(0, Math.ceil(ms / 1000));
        return `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
    };
    U.setState = incoming => {
        if (!incoming || typeof incoming !== 'object' || incoming.error) return;
        const s = U.store;
        s.data = { ...s.data, ...incoming };
        if (incoming.fallback) s.fallback = incoming.fallback;
        if (incoming.live) s.live = incoming.live;
        if (incoming.tactical) s.live.tactical = incoming.tactical;
        if (incoming.airCooldown !== undefined) s.cooldownDeadline = performance.now() + incoming.airCooldown * 1000;
        if (incoming.offers) s.offers = incoming.offers.map(offer => ({ ...offer, deadline: performance.now() + offer.remainingSeconds * 1000 }));
        const detail = incoming.detail || (incoming.active === false ? {} : s.data.detail) || {};
        const tactical = incoming.tactical || s.live.tactical || {};
        const values = {
            speed: detail.speed ?? s.data.defaults?.speed ?? 60, gap: detail.gap ?? s.data.defaults?.gap ?? 6,
            style: detail.style || 'normal', order: detail.order || 'follow', air: detail.air || 'off',
            formation: tactical.formation || s.data.defaults?.formation || 'adaptive', posture: tactical.posture || 'normal'
        };
        for (const [key, value] of Object.entries(values)) if (!s.dirty.has(key)) s.draft[key] = value;
        if (!s.initialized && incoming.maxGuards !== undefined) {
            s.count = Math.min(incoming.ui?.defaultGuards ?? 4, incoming.maxGuards); s.initialized = true;
        }
        if (incoming.maxGuards !== undefined) s.count = Math.min(s.count, incoming.maxGuards);
        if (incoming.active && incoming.mode && s.data.modes?.[incoming.mode]) s.mode = incoming.mode;
        if (incoming.modes) {
            const modes = Object.keys(incoming.modes);
            if (!modes.includes(s.mode)) s.mode = modes[0] || '';
        }
        if (incoming.vehicles) {
            const known = new Set(incoming.vehicles.map(v => v.model));
            for (const model of s.chosen.keys()) if (!known.has(model)) s.chosen.delete(model);
        }
    };
    U.edit = (field, value) => { U.store.draft[field] = value; U.store.dirty.add(field); };
    U.applyAcknowledged = (submitted, result) => {
        // A passive state message can arrive before this reply. Only the successful
        // response clears the fields actually submitted, and never newer edits.
        for (const key of Object.keys(submitted)) {
            if (key !== 'action' && String(U.store.draft[key]) === String(submitted[key])) U.store.dirty.delete(key);
        }
        U.setState(result);
    };
    U.request = async (route, data = {}) => {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), route === 'deploy' ? 210000 : 45000);
        try {
            const response = await fetch(`https://${GetParentResourceName()}/${route}`, {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data), signal: controller.signal
            });
            if (!response.ok) throw new Error(U.t('unavailable'));
            const result = await response.json();
            if (!result || typeof result !== 'object') throw new Error(U.t('unavailable'));
            return result;
        } finally { clearTimeout(timeout); }
    };
    U.settings = () => ({ action: 'settings', ...Object.fromEntries(U.settingsFields.map(key => [key, U.store.draft[key]])) });
    U.publicError = error => {
        const message = typeof error === 'string' ? error : error?.message;
        return typeof message === 'string' && !/\.lua:\d+|stack traceback|session.*token/i.test(message) ? message : U.t('unavailable');
    };
    U.translate = () => {
        const data = U.store.data;
        document.documentElement.lang = data.locale || 'en';
        U.all('[data-i18n]').forEach(node => { node.textContent = U.t(node.dataset.i18n); });
        U.all('[data-placeholder]').forEach(node => { node.placeholder = U.t(node.dataset.placeholder); });
        U.all('[data-label]').forEach(node => node.setAttribute('aria-label', U.t(node.dataset.label)));
        U.$('#brand').textContent = data.ui?.brand || 'DIOS PROTECT';
        U.$('#office').textContent = data.ui?.office || '';
        if (/^#[0-9a-f]{6}$/i.test(data.ui?.accent || '')) document.documentElement.style.setProperty('--accent', data.ui.accent);
    };
})();
