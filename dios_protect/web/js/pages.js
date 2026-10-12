(() => {
    'use strict';
    const U = window.ProtectUI, cached = new Map(), vehicleNodes = new Map();
    const textAll = (selector, text) => U.all(selector).forEach(n => { n.textContent = text; });
    const changed = (key, value) => { const signature = JSON.stringify(value); if (cached.get(key) === signature) return false; cached.set(key, signature); return true; };
    U.vehicleLabel = model => {
        const definition = U.store.data.vehicles?.find(v => v.model.toLowerCase() === String(model || '').toLowerCase());
        return definition ? U.label(definition.label) : U.label(model) || U.t('assigned_vehicle');
    };
    U.navigate = (page, focus = false) => {
        if (!['overview', 'personnel', 'motorcade', 'tactical', 'air', 'appointments'].includes(page)) return;
        U.store.page = page;
        U.all('[data-page-content]').forEach(node => { node.hidden = node.dataset.pageContent !== page; });
        U.all('[data-page]').forEach(node => node.setAttribute('aria-current', node.dataset.page === page ? 'page' : 'false'));
        if (focus) U.$('#page-' + page).focus();
    };
    U.renderSelectors = () => {
        const s = U.store;
        if (changed('formations', [s.data.locale, s.data.translations?.formation, s.data.tacticalEnabled])) {
            U.all('[data-formations]').forEach(container => {
                container.replaceChildren();
                for (const value of U.formations) {
                    const button = U.el('button', undefined, 'formation-option'); button.type = 'button'; button.dataset.formation = value;
                    const diagram = U.el('span', undefined, 'formation-mini'); U.diagram(diagram, value, 4, { mini: true });
                    button.append(diagram, U.el('span', U.t('formation_' + value)));
                    button.onclick = () => { U.edit('formation', value); U.renderControls(); U.renderDiagrams(); };
                    container.append(button);
                }
            });
            const select = U.$('#compact-formation-select'); select.replaceChildren();
            U.formations.forEach(value => select.append(new Option(U.t('formation_' + value), value)));
            U.all('[data-postures]').forEach(container => {
                container.replaceChildren();
                for (const posture of ['normal', 'alert', 'emergency']) {
                    const button = U.el('button', U.t('posture_' + posture)); button.type = 'button'; button.dataset.posture = posture;
                    button.onclick = () => { U.edit('posture', posture); U.renderControls(); };
                    container.append(button);
                }
            });
        }
        if (changed('modes', [s.data.modes, s.data.locale])) {
            const container = U.$('#guard-modes'); container.replaceChildren();
            for (const [key, definition] of Object.entries(s.data.modes || {})) {
                const button = U.el('button', undefined, 'mode-card'); button.type = 'button'; button.dataset.mode = key; button.dataset.setup = '';
                const content = U.el('div'); content.append(U.el('strong', U.t(key) || U.label(definition.label)), U.el('small', U.t(key + '_hint')));
                button.append(U.icon(({ police: 'shield', military: 'target', civilian: 'suit', casual: 'person' })[key] || 'person'), content);
                button.onclick = () => { if (!s.data.active && !s.pending) { s.mode = key; U.renderAll(); } };
                container.append(button);
            }
            if (!Object.keys(s.data.modes || {}).length) container.append(U.empty('Choose a valid guard detail.'));
        }
        U.all('[data-mode]').forEach(node => node.setAttribute('aria-pressed', String(node.dataset.mode === s.mode)));
    };
    U.renderControls = () => {
        const s = U.store, d = s.data, live = s.live;
        U.all('[data-field]').forEach(node => {
            const key = node.dataset.field;
            if (document.activeElement !== node) node.value = s.draft[key] ?? '';
            if (key === 'speed') node.max = Math.max(5, Math.floor(d.maxSpeed || 300));
        });
        U.all('[data-formation]').forEach(node => node.setAttribute('aria-pressed', String(node.dataset.formation === s.draft.formation)));
        U.all('[data-posture]').forEach(node => node.setAttribute('aria-pressed', String(node.dataset.posture === s.draft.posture)));
        U.$('#count').max = d.maxGuards || 6;
        if (document.activeElement !== U.$('#count')) U.$('#count').value = d.active ? d.counts?.foot || 0 : s.count;
        U.$('#guard-limit').textContent = U.t('maximum_agents', { max: d.maxGuards || 6 });
        U.all('[data-setup-lock]').forEach(node => { node.hidden = !d.active; });
        U.$('#enable').hidden = !!d.active;
        const tactical = d.tacticalEnabled !== false;
        U.$('#tactical-disabled').hidden = tactical;
        U.$('#tactical-content').hidden = !tactical;
        U.all('button,input,select').forEach(node => {
            if (['close', 'compact-close', 'confirm-cancel', 'invite-accept', 'invite-decline'].includes(node.id) || node.dataset.page || node.dataset.go || node.id === 'open-dashboard') return;
            let disabled = s.pending;
            if (node.hasAttribute('data-setup')) disabled ||= !!d.active;
            if (node.dataset.field || node.dataset.apply) disabled ||= !!d.deploying;
            if (node.dataset.tactical) disabled ||= !d.active || !!d.deploying || !tactical;
            if (node.dataset.formation || node.dataset.posture || node.dataset.field === 'formation') disabled ||= !tactical;
            if (node.dataset.command || node.hasAttribute('data-dispatch-air')) disabled ||= !d.active || !!d.deploying;
            if (node.dataset.action) disabled ||= !d.active && !(d.agents?.length || s.offers.length);
            if (node.dataset.action === 'off') disabled ||= !d.active;
            if (node.dataset.action === 'disband') disabled ||= !d.active || !(d.counts?.vehicles);
            if (node.dataset.command === 'driver') {
                disabled ||= !live.context?.passenger; node.title = live.context?.passenger ? '' : U.t('Sit in the passenger seat of your vehicle first.');
            }
            if (node.dataset.command === 'waypoint') {
                disabled ||= !d.detail?.driver || !live.context?.waypoint || !live.context?.chauffeurPassenger;
                node.title = live.context?.waypoint ? U.t('Board your chauffeur vehicle before starting the route.') : U.t('Set a waypoint on the map first.');
            }
            if (node.dataset.command === 'stop' || node.dataset.command === 'release') disabled ||= !d.detail?.driver;
            if (node.dataset.command === 'recallAir') disabled ||= !live.airActive;
            if (node.hasAttribute('data-dispatch-air')) disabled ||= !live.airAvailable || !!live.airActive || !!d.airDeploying || s.cooldownDeadline > performance.now();
            if (node.dataset.apply === 'settings') disabled ||= !d.active;
            if (node.id === 'guard-minus') disabled ||= s.count <= 0;
            if (node.id === 'guard-plus') disabled ||= s.count >= (d.maxGuards || 6);
            if (node.id === 'enable') disabled ||= !s.mode || (!s.count && !U.total());
            if (node.dataset.quantity) {
                const n = s.chosen.get(node.dataset.quantity) || 0;
                disabled ||= !!d.active || (node.dataset.delta === '1' && U.total() >= (d.maxVehicles || 20)) || (node.dataset.delta === '-1' && n === 0);
            }
            node.disabled = disabled;
        });
        U.$('#panel').setAttribute('aria-busy', String(s.pending));
        textAll('[data-speed-cap]', U.t('cap', { max: Math.floor(d.maxSpeed || 300) }));
    };
    U.adjustQuantity = (model, delta) => {
        const s = U.store;
        if (s.pending || s.data.active) return;
        const n = Math.max(0, (s.chosen.get(model) || 0) + delta);
        if (U.total() - (s.chosen.get(model) || 0) + n > (s.data.maxVehicles || 20)) { U.message(U.t('limit', { max: s.data.maxVehicles || 20 })); return; }
        n ? s.chosen.set(model, n) : s.chosen.delete(model);
        U.renderVehicles(); U.renderManifest(); U.renderOverview(); U.renderSummary(); U.renderControls();
    };
    U.renderVehicles = () => {
        const s = U.store, container = U.$('#vehicles');
        if (changed('catalog', [s.data.vehicles, s.data.locale])) {
            const category = U.$('#vehicle-category'), previous = category.value;
            category.replaceChildren(new Option(U.t('all'), 'all'));
            for (const value of new Set((s.data.vehicles || []).map(v => v.category))) category.append(new Option(U.label(value), value));
            category.value = [...category.options].some(o => o.value === previous) ? previous : 'all';
            container.replaceChildren(); vehicleNodes.clear();
            for (const vehicle of s.data.vehicles || []) {
                const card = U.el('article', undefined, 'vehicle-card'); card.dataset.model = vehicle.model;
                const header = U.el('div', undefined, 'vehicle-card-header'), title = U.el('div');
                title.append(U.el('strong', U.label(vehicle.label)), U.el('span', U.label(vehicle.category), 'meta'));
                header.append(U.icon('vehicle'), title);
                const footer = U.el('div', undefined, 'vehicle-card-footer'), stepper = U.el('div', undefined, 'stepper');
                const value = U.el('strong', '0');
                for (const delta of [-1, 1]) {
                    const button = U.el('button'); button.type = 'button'; button.dataset.quantity = vehicle.model; button.dataset.delta = String(delta);
                    button.setAttribute('aria-label', U.t(delta < 0 ? 'remove_vehicle' : 'add_vehicle', { label: U.label(vehicle.label) }));
                    button.append(U.icon(delta < 0 ? 'minus' : 'plus')); button.onclick = () => U.adjustQuantity(vehicle.model, delta);
                    if (delta > 0) stepper.append(value); stepper.append(button);
                }
                const remove = U.el('button', U.t('remove_selection')); remove.type = 'button'; remove.dataset.setup = '';
                remove.onclick = () => U.adjustQuantity(vehicle.model, -(s.chosen.get(vehicle.model) || 0));
                remove.setAttribute('aria-label', U.t('remove_vehicle', { label: U.label(vehicle.label) }));
                footer.append(U.el('p', U.t('vehicle_capacity', { crew: vehicle.seats, seats: vehicle.passengerCapacity ?? 0 })), stepper);
                header.append(remove);remove.className = 'remove-selection';
                card.append(header, footer); container.append(card); vehicleNodes.set(vehicle.model, { card, value, vehicle, remove });
            }
            container.append(U.empty('no_vehicles')); container.lastElementChild.id = 'catalog-empty';
        }
        const term = U.$('#vehicle-search').value.trim().toLocaleLowerCase(U.language()), category = U.$('#vehicle-category').value;
        let found = 0;
        for (const { card, value, vehicle, remove } of vehicleNodes.values()) {
            const label = `${U.label(vehicle.label)} ${vehicle.label} ${vehicle.model} ${U.label(vehicle.category)}`.toLocaleLowerCase(U.language());
            const visible = (category === 'all' || !category || category === vehicle.category) && label.includes(term);
            card.hidden = !visible; if (visible) found++;
            const n = s.data.active ? (s.live.convoy || []).filter(entry => entry.model === vehicle.model).length : s.chosen.get(vehicle.model) || 0; if (value.textContent !== U.number(n)) { value.classList.add('count-updated'); setTimeout(() => value.classList.remove('count-updated'), 180); }
            value.textContent = U.number(n); remove.hidden = !n || s.data.active; card.dataset.selected = String(n > 0);
        }
        const empty = U.$('#catalog-empty'); if (empty) empty.hidden = found > 0;
        U.$('#clear-search').hidden = !term;
        U.$('#build-availability').textContent = s.data.unavailableVehicles ? U.t('unavailable_models', { count: s.data.unavailableVehicles }) : U.t('hide_unavailable');
    };
    U.renderManifest = () => {
        const s = U.store;
        const entries = s.data.active ? s.live.convoy || [] : [...s.chosen].flatMap(([model, n]) => Array.from({ length: n }, () => ({ model, crew: s.data.vehicles?.find(v => v.model === model)?.seats || 0, role: 'planned' })));
        if (changed('manifest', [entries, s.data.active, s.data.locale])) {
            const container = U.$('#convoy-manifest'); container.replaceChildren();
            if (!entries.length) container.append(U.empty('no_motorcade'));
            entries.forEach((entry, index) => {
                const row = U.el('div', undefined, 'manifest-entry');
                const content = U.el('div'); content.append(U.el('strong', U.vehicleLabel(entry.model)), U.el('span', U.t('manifest_meta', { role: U.t('convoy_role_' + entry.role), crew: entry.crew }), 'meta'));
                if (entry.principal) content.append(U.el('span', U.t('principal_vehicle'), 'meta'));
                row.append(U.el('span', String(index + 1).padStart(2, '0'), 'manifest-number'), content, U.icon(entry.principal ? 'principal' : 'vehicle')); container.append(row);
            });
        }
        U.$('#vehicle-count').textContent = `${U.number(entries.length)} / ${U.number(s.data.maxVehicles || 20)}`;
        U.$('#convoy-mode').textContent = U.t(entries.length > (s.data.longConvoyThreshold || 5) ? 'extended' : 'standard');
    };
    U.renderDiagrams = () => {
        const s = U.store, activeCount = s.data.active ? s.data.counts?.foot || 0 : s.count;
        U.diagram(U.$('#overview-diagram'), s.data.active ? s.live.tactical?.formation || s.data.tactical?.formation || 'adaptive' : s.draft.formation, activeCount, { vehicles: s.data.active ? s.data.counts?.vehicles : U.total(), air: s.live.airActive, base: s.live.tactical?.baseFormation });
        U.diagram(U.$('#personnel-diagram'), s.draft.formation, activeCount);
        U.diagram(U.$('#tactical-diagram'), s.draft.formation, activeCount, { base: s.data.active ? s.live.tactical?.baseFormation : undefined });
    };
    U.renderOverview = () => {
        const s = U.store, d = s.data, c = d.counts || {};
        U.$('#setup-guide').hidden = !!d.active;
        const values = [[d.active ? (c.foot || 0) + (c.crew || 0) + (c.airCrew || 0) : s.count + [...s.chosen].reduce((sum, [model, n]) => sum + n * (d.vehicles?.find(v => v.model === model)?.seats || 0), 0), 'npc_agents'], [d.agents?.length || 0, 'agents'], [d.active ? c.vehicles || 0 : U.total(), 'selected'], [d.active ? c.air || 0 : 0, 'air']];
        if (changed('metrics', [values, d.locale])) U.$('#readiness-metrics').replaceChildren(...values.map(([n, key]) => U.metric(n, U.t(key))));
        U.$('#overview-formation').textContent = U.t('formation_' + (d.active ? s.live.tactical?.formation || d.tactical?.formation || 'adaptive' : s.draft.formation));
        U.$('#overview-posture').textContent = U.t('posture_' + (s.live.tactical?.posture || s.draft.posture));
        textAll('[data-principal-label]', s.live.principalVehicle?.label || U.t('no_principal_vehicle'));
        textAll('[data-driver-status]', U.t(d.detail?.driver ? d.detail.destination ? 'route_active' : s.live.driverReady ? 'driver_ready' : 'driver_pending' : 'no_driver'));
        const state = s.live.tactical?.state || d.tactical?.state || 'NORMAL';
        U.all('[data-state-chip]').forEach(node => { node.hidden = !d.active || d.tacticalEnabled === false; U.chip(node, U.t('state_' + state), state); });
        U.all('[data-state-surface]').forEach(node => { node.dataset.state = d.active ? state : ''; });
        textAll('[data-state-description]', U.t(d.active ? 'description_' + state : 'no_detail'));
        U.chip(U.$('#status'), U.t(d.deploying || s.pending && s.pendingRoute === 'deploy' ? 'status_deploying' : d.active ? 'active' : 'standby'), d.active ? 'NORMAL' : '');
        U.$('#compact-formation').textContent = U.t('formation_' + (s.live.tactical?.formation || s.draft.formation));
        const roles = d.active && Object.keys(s.live.roles || {}).length ? s.live.roles : { principal: Math.min(1, s.count), close: Math.max(0, Math.min(s.count, d.defaults?.closeGuards || 2) - 1), flank: Math.max(0, s.count - (d.defaults?.closeGuards || 2)) };
        if (changed('roles', [roles, d.locale, d.active])) {
            const container = U.$('#role-distribution'); container.replaceChildren();
            container.append(U.el('p', U.t(d.active ? 'live_distribution' : 'planned_distribution'), 'hint'));
            for (const [role, n] of Object.entries(roles)) { const row = U.el('div', undefined, 'role-row'); row.append(U.el('span', U.t('role_' + role)), U.el('strong', U.number(n))); container.append(row); }
        }
        U.renderDiagrams();
    };
    U.renderAir = () => {
        const s = U.store, live = s.live;
        const key = !live.airAvailable ? 'air_unavailable' : s.data.airDeploying ? 'status_deploying' : live.airActive ? 'airborne' : s.cooldownDeadline > performance.now() ? 'air_cooldown' : 'air_ready';
        textAll('[data-air-status]', U.t(key));
        textAll('[data-air-model]', U.label(live.airLabel || live.airModel || s.data.defaults?.airModel));
        textAll('[data-air-mission]', live.airActive ? U.t('air_' + (live.tactical?.airPosture || 'escort')) : U.t('air_mode_hint'));
        const c = s.data.counts || {};
        const crew = s.data.active && live.airActive ? c.airCrew || 0 : 0;
        if (changed('air-crew', [crew, c.airPilot, s.data.locale])) U.$('#air-crew').replaceChildren(U.metric(c.airPilot || 0, U.t('pilot')), U.metric(Math.max(0, crew - (c.airPilot || 0)), U.t('crew_agents')));
    };
    U.renderAppointments = () => {
        const s = U.store, agents = s.data.agents || [], candidates = s.data.nearby || [];
        if (changed('appointments', [agents, candidates, s.data.locale])) {
            for (const [id, entries] of [['agents', agents], ['nearby', candidates]]) {
                const container = U.$('#' + id); container.replaceChildren();
                if (!entries.length) container.append(U.empty(id === 'agents' ? 'no_agents' : 'no_nearby'));
                for (const person of entries) {
                    const row = U.el('div', undefined, 'entity-row'), info = U.el('div');
                    info.append(U.el('strong', person.name));
                    info.append(U.el('span', id === 'agents' ? U.t(person.onDuty ? 'on_duty' : 'off_duty') : U.t('candidate_distance', { distance: U.number(person.distance) }), 'meta'));
                    const button = U.el('button', U.t(id === 'agents' ? 'dismiss' : person.pending ? 'offer_pending' : 'offer')); button.type = 'button';
                    button.onclick = () => id === 'agents' ? U.confirm('dismiss', person.citizenid) : U.operation('action', { action: 'invite', target: person.id });
                    button.disabled = !!person.pending; button.dataset.appointment = ''; button.dataset.ineligible = person.pending ? 'true' : 'false';
                    row.append(info, button); container.append(row);
                }
            }
        }
        if (changed('offers', [s.offers.map(o => o.name), s.data.locale])) {
            const container = U.$('#pending-offers'); container.replaceChildren();
            if (!s.offers.length) container.append(U.empty('no_pending_offers'));
            s.offers.forEach((offer, i) => {
                const row = U.el('div', undefined, 'entity-row'); row.append(U.el('strong', offer.name));
                const time = U.el('span', '', 'meta'); time.dataset.offerIndex = String(i); row.append(time); container.append(row);
            });
        }
        U.all('[data-offer-index]').forEach(node => { node.dataset.offerDeadline = String(s.offers[Number(node.dataset.offerIndex)]?.deadline || 0); });
        U.$('#nearby-heading').textContent = U.t('nearby', { range: s.data.inviteRange || 25 });
    };
    U.renderSummary = () => {
        const s = U.store, c = s.data.counts || {};
        U.$('#deployment-summary').textContent = U.t('deployment_counts', { guards: U.number(s.data.active ? c.foot || 0 : s.count), vehicles: U.number(s.data.active ? c.vehicles || 0 : U.total()), agents: U.number(s.data.agents?.length || 0) });
        U.$('#draft-summary').textContent = U.t('deployment_plan', { mode: U.t(s.data.active ? s.data.mode || s.mode : s.mode) || U.label(s.data.modes?.[s.mode]?.label), formation: U.t('formation_' + (s.data.active ? s.live.tactical?.formation || s.data.tactical?.formation || 'adaptive' : s.draft.formation)), air: U.t(s.data.active ? s.data.detail?.air || 'off' : s.draft.air) });
        U.$('#capacity-fill').style.width = `${Math.min(100, (s.data.active ? c.vehicles || 0 : U.total()) / (s.data.maxVehicles || 20) * 100)}%`;
    };
    U.renderExtraction = () => {
        const s = U.store, ex = s.live.extraction, state = s.live.tactical?.state;
        const visible = !!s.data.active && state === 'EXTRACTION' && !ex?.boarded;
        U.$('#extraction-hud').hidden = !visible; document.body.dataset.protectHud = visible ? 'true' : 'false';
        const label = ex ? U.vehicleLabel(ex.model) : U.t('extraction_selecting');
        U.$('#hud-instruction').textContent = U.t(ex ? 'proceed_vehicle' : 'extraction_selecting');
        U.$('#hud-vehicle').textContent = label;
        U.$('#hud-distance').textContent = ex?.distance !== undefined ? U.t('distance_metres', { distance: U.number(ex.distance) }) : '';
        U.$('#hud-driver').textContent = U.t(ex?.ready ? 'driver_ready' : 'driver_pending');
        U.all('[data-extraction-card]').forEach(node => { node.dataset.state = state || ''; });
        textAll('[data-extraction-status]', ex ? U.t('extraction_status', { vehicle: label, driver: U.t(ex.ready ? 'driver_ready' : 'driver_pending') }) : U.t('extraction_hint'));
    };
    U.renderAll = () => {
        U.translate(); U.renderSelectors(); U.renderVehicles(); U.renderManifest(); U.renderOverview();
        U.renderAir(); U.renderAppointments(); U.renderSummary(); U.renderControls(); U.renderExtraction(); U.tick();
        U.renderConfirmationCounts();
        U.all('[data-appointment]').forEach(node => { node.disabled = U.store.pending || node.dataset.ineligible === 'true'; });
    };
})();
