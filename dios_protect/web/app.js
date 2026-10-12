/* Presentation controller. All protected actions still use the existing Lua callbacks. */
(() => {
    'use strict';
    const U = window.ProtectUI, s = U.store;
    let refreshPending = false, lastTacticalState;
    U.visibility = (open, compact = s.compact) => {
        s.visible = open; s.compact = compact;
        U.$('#panel').hidden = !open; U.$('#dashboard').hidden = compact; U.$('#control-panel').hidden = !compact;
        document.body.dataset.protectOpen = open ? 'true' : 'false';
        const notifications = U.$('#notifications');
        if (open) { const root = U.$(compact ? '#control-panel' : '#dashboard'); root.insertBefore(notifications, root.lastElementChild); }
        else document.body.append(notifications);
        if (!open) { s.confirmation = null; if (!s.invitation) U.modal(null); U.$('#message').hidden = true; }
    };
    U.close = () => { U.visibility(false); U.request('close').catch(error => console.error(error)); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 600));
    const execute = async (route, data) => {
        const result = await U.request(route, data);
        if (result.error) { console.error('[dios_protect]', result.error); throw new Error(U.publicError(result.error)); }
        if (route === 'control' && ['settings', 'tactical'].includes(data.action)) U.applyAcknowledged(data, result);
        else U.setState(result);
        U.renderAll(); return result;
    };
    U.operation = async (route, data) => {
        if (s.pending || s.invitation) return;
        s.pending = true; s.pendingRoute = route; U.renderControls(); U.renderOverview();
        U.message(U.t(route === 'deploy' ? 'deploying' : 'updating'), false, true);
        try {
            if (route === 'deploy') {
                const planned = { formation: s.draft.formation, posture: s.draft.posture, settings: U.settings() };
                await execute(route, data);
                // Deployment itself still accepts only its original composition fields.
                // Apply requested live settings through the existing validated callbacks.
                try {
                    if (planned.formation !== (s.data.tactical?.formation || s.data.defaults?.formation) || planned.posture !== 'normal') {
                        await pause(); await execute('control', { action: 'tactical', formation: planned.formation, posture: planned.posture });
                    }
                    const detail = s.data.detail || {};
                    if (U.settingsFields.some(key => String(planned.settings[key]) !== String(detail[key]))) {
                        await pause(); await execute('control', planned.settings);
                    }
                } catch (error) { U.notice(U.publicError(error), 'warning'); }
                U.message(U.t('dispatched'));
            } else { await execute(route, data); U.message(U.t('updated')); }
        } catch (error) {
            U.message(error.name === 'AbortError' ? U.t('unavailable') : U.publicError(error), true);
        } finally { s.pending = false; s.pendingRoute = null; U.renderAll(); }
    };
    const apply = kind => {
        if (!s.data.active) { U.message(U.t('planned_settings')); return; }
        if (kind === 'tactical') U.operation('control', { action: 'tactical', formation: s.draft.formation, posture: s.draft.posture });
        else {
            const max = Math.max(5, Math.floor(s.data.maxSpeed || 300));
            const speed = Math.max(5, Math.min(max, Number(s.draft.speed) || 5));
            const gap = Math.max(4, Math.min(20, Number(s.draft.gap) || 4));
            if (speed !== Number(s.draft.speed)) U.notice(U.t('speed_clamped', { max }), 'warning');
            U.edit('speed', speed); U.edit('gap', gap); U.operation('control', U.settings());
        }
    };
    U.all('[data-page]').forEach(node => node.onclick = () => U.navigate(node.dataset.page, true));
    U.all('[data-go]').forEach(node => node.onclick = () => U.navigate(node.dataset.go, true));
    U.all('[data-field]').forEach(node => node.addEventListener('input', () => {
        const key = node.dataset.field, value = ['speed', 'gap'].includes(key) ? Number(node.value) : node.value;
        U.edit(key, value); U.renderControls(); U.renderSummary(); U.renderDiagrams();
    }));
    const count = U.$('#count');
    const setCount = value => {
        if (s.data.active || s.pending) return;
        s.count = Math.max(0, Math.min(s.data.maxGuards || 6, Math.round(Number(value) || 0))); U.renderAll();
    };
    count.addEventListener('input', () => setCount(count.value));
    U.$('#guard-minus').onclick = () => setCount(s.count - 1); U.$('#guard-plus').onclick = () => setCount(s.count + 1);
    U.$('#vehicle-search').addEventListener('input', U.renderVehicles);
    U.$('#vehicle-category').addEventListener('change', U.renderVehicles);
    U.$('#clear-search').onclick = () => { U.$('#vehicle-search').value = ''; U.renderVehicles(); U.$('#vehicle-search').focus(); };
    U.$('#enable').onclick = () => U.operation('deploy', { mode: s.mode, count: s.count, vehicles: [...s.chosen].map(([model, quantity]) => ({ model, quantity })) });
    U.all('[data-apply]').forEach(node => node.onclick = () => apply(node.dataset.apply));
    U.all('[data-tactical]').forEach(node => node.onclick = () => U.operation('control', { action: 'tactical', command: node.dataset.tactical }));
    U.all('[data-command]').forEach(node => node.onclick = () => U.operation('control', { action: node.dataset.command }));
    U.all('[data-dispatch-air]').forEach(node => node.onclick = async () => {
        if (s.draft.air === 'off' || !s.data.detail || s.data.detail.air === 'off') {
            U.edit('air', 'escort'); await U.operation('control', U.settings());
        } else await U.operation('control', { action: 'air' });
    });
    U.all('[data-action]').forEach(node => node.onclick = () => U.confirm(node.dataset.action));
    U.$('#refresh').onclick = () => U.operation('refresh', {});
    U.$('#close').onclick = U.close; U.$('#compact-close').onclick = U.close;
    U.$('#open-dashboard').onclick = () => { U.visibility(true, false); U.navigate('overview', true); };
    U.$('#confirm-cancel').onclick = () => { s.confirmation = null; U.modal(null); };
    U.$('#confirm-accept').onclick = () => {
        const action = s.confirmation; if (!action) return;
        s.confirmation = null; U.modal(null); U.operation('action', action);
    };
    U.$('#invite-accept').onclick = () => U.answerInvite(true); U.$('#invite-decline').onclick = () => U.answerInvite(false);
    document.addEventListener('keydown', event => {
        if (event.defaultPrevented) return;
        if (event.key === 'Escape') {
            event.preventDefault();
            if (s.invitation) { if (!s.invitation.submitting) U.answerInvite(false); return; }
            if (s.confirmation) { s.confirmation = null; U.modal(null); return; }
            const menu = U.$('.destructive-menu[open]');
            if (menu) { menu.open = false; menu.querySelector('summary').focus(); return; }
            if (document.activeElement?.tagName === 'SELECT') { document.activeElement.blur(); return; }
            if (s.visible) U.close();
        }
        if (event.key === 'Tab') {
            const root = s.invitation ? U.$('#invite-dialog') : s.confirmation ? U.$('#confirm-dialog') : s.visible ? U.$(s.compact ? '#control-panel' : '#dashboard') : null;
            if (!root) return;
            const nodes = [...root.querySelectorAll('button,input,select,summary')].filter(node => !node.disabled && node.getClientRects().length);
            if (!nodes.length) { event.preventDefault(); return; }
            const first = nodes[0], last = nodes.at(-1);
            if (!nodes.includes(document.activeElement) || event.shiftKey && document.activeElement === first) { event.preventDefault(); (event.shiftKey ? last : first).focus(); }
            else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
        }
        if (['ArrowLeft', 'ArrowRight'].includes(event.key) && document.activeElement?.matches('[data-posture],[data-formation]')) {
            const nodes = [...document.activeElement.parentElement.querySelectorAll('button')];
            const index = nodes.indexOf(document.activeElement), next = nodes[(index + (event.key === 'ArrowRight' ? 1 : nodes.length - 1)) % nodes.length];
            event.preventDefault(); next.focus(); next.click();
        }
    });
    const live = payload => {
        if (!payload || typeof payload !== 'object') return;
        s.live = payload;
        s.data.active = payload.active === true; s.data.deploying = payload.deploying === true;
        if (payload.detail) s.data.detail = payload.detail;
        if (payload.tactical) s.data.tactical = payload.tactical;
        if (payload.airCooldown !== undefined) s.cooldownDeadline = performance.now() + payload.airCooldown * 1000;
        if (!payload.active) { s.data.counts = {}; s.data.detail = null; s.data.tactical = null; }
        else if (payload.counts) s.data.counts = payload.counts;
        const current = payload.tactical?.state;
        if (current && current !== lastTacticalState && lastTacticalState && current !== 'NORMAL' && current !== 'EXTRACTION') U.notice(U.t('state_' + current) + ' ? ' + U.t('description_' + current), 'tactical', undefined, current);
        lastTacticalState = current;
        U.setState({ detail: s.data.detail, tactical: s.data.tactical });
        // setState already respects dirty fields; no DOM-driven draft reconstruction.
        U.renderAll();
    };
    window.addEventListener('message', ({ data }) => {
        if (!data || typeof data !== 'object') return;
        if (data.action === 'deploymentProgress' && s.pending && s.pendingRoute === 'deploy') {
            const keys = { models: 'deploy_models', positions: 'deploy_positions', dispatch: 'deploy_dispatch', crew: 'deploy_crew' };
            if (keys[data.phase]) U.message(U.t(keys[data.phase]), false, true);
        }
        if (data.action === 'close') U.visibility(false);
        if (data.action === 'open') {
            U.setState(data.state); U.renderAll(); U.visibility(true, data.view === 'control'); U.navigate(s.page);
            U.$(s.compact ? '#compact-close' : '#close').focus();
        }
        if (data.action === 'state') { U.setState(data.state); U.renderAll(); }
        if (data.action === 'context') { s.live.context = data.context; s.data.maxSpeed = data.maxSpeed; U.renderControls(); }
        if (data.action === 'live') live(data.live);
        // Compatibility with the previous presentation-only tactical message.
        if (data.action === 'tactical') live({ ...s.live, active: s.data.active, tactical: data.tactical, airActive: data.airActive });
        if (data.action === 'invite') U.invite(data);
        if (data.action === 'inviteClose') U.hideInvitation(data.token);
        if (data.action === 'notify') U.notice(data.text, data.kind, data.title);
        if (data.action === 'reset') { s.live = {}; s.data.active = false; s.data.counts = {}; U.visibility(false); U.hideInvitation(); U.renderExtraction(); }
    });
    U.visibility(false); U.navigate('overview');
    U.request('ready').then(data => { U.setState(data); U.renderAll(); }).catch(error => console.error('[dios_protect] UI initialization', error));
    setInterval(() => {
        U.tick();
        if (s.visible) { U.renderAir(); U.renderControls(); }
    }, 500);
    setInterval(async () => {
        if (!s.visible || s.pending || refreshPending) return;
        refreshPending = true;
        try {
            const data = await U.request('refresh');
            if (data.error) { U.close(); return; }
            U.setState(data); U.renderAll();
        } catch (error) { console.error('[dios_protect] UI refresh', error); }
        finally { refreshPending = false; }
    }, 5000);
})();
