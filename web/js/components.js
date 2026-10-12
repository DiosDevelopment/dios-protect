(() => {
    'use strict';
    const U = window.ProtectUI, diagrams = new WeakMap(), toasts = new Map();
    let restoreFocus = null, messageTimer;
    U.offset = (formation, slot, count, scale = 1) => {
        const spacing = (formation === 'loose' ? 68 : formation === 'close' ? 32 : 48) * scale;
        if (formation === 'column') return [(slot % 2 === 0 ? .35 : -.35) * spacing, slot * spacing * .65];
        if (formation === 'left' || formation === 'right') return [(formation === 'left' ? -1 : 1) * spacing, (slot - (count + 1) / 2) * spacing];
        if (formation === 'box') {
            const ring = 1 + Math.floor((slot - 1) / 4);
            return [(slot % 2 === 0 ? 1 : -1) * spacing * ring, ((slot - 1) % 4 < 2 ? -1 : 1) * spacing * ring];
        }
        const points = [[0, -1], [-1, 0], [1, 0], [0, 1]], point = points[(slot - 1) % 4], ring = 1 + Math.floor((slot - 1) / 4);
        return point.map(n => n * spacing * ring);
    };
    U.diagram = (node, formation, count, options = {}) => {
        let record = diagrams.get(node);
        if (!record) {
            const principal = U.el('span', undefined, 'formation-principal'); principal.append(U.icon('principal'));
            const auto = U.el('span', undefined, 'diagram-auto');
            const air = U.el('span', undefined, 'diagram-air'); air.append(U.icon('air'));
            const lead = U.el('span', undefined, 'diagram-vehicle lead'); lead.append(U.icon('vehicle'));
            const follow = U.el('span', undefined, 'diagram-vehicle follow'); follow.append(U.icon('vehicle'));
            node.append(principal, auto, air, lead, follow);
            record = { dots: [], auto, air, lead, follow }; diagrams.set(node, record);
        }
        count = Math.max(0, Math.min(12, Number(count) || 0));
        while (record.dots.length < count) { const dot = U.el('i', undefined, 'formation-dot'); record.dots.push(dot); node.append(dot); }
        // Retain existing dots so CSS interpolates their position instead of replacing the diagram.
        const base = formation === 'adaptive' ? options.base || 'diamond' : formation;
        const points = Array.from({ length: count }, (_, i) => U.offset(base, i + 1, count));
        const maxX = Math.max(1, ...points.map(([x]) => Math.abs(x))), maxY = Math.max(1, ...points.map(([, y]) => Math.abs(y)));
        const scale = options.mini ? .18 : Math.min(1, 100 / maxX, 88 / maxY);
        record.dots.forEach((dot, i) => {
            dot.hidden = i >= count;
            const [x, y] = U.offset(base, i + 1, count, scale);
            dot.style.transform = `translate(${x}px, ${y}px)`;
        });
        record.auto.hidden = formation !== 'adaptive' || options.mini;
        record.auto.textContent = U.t('automatic_formation');
        record.air.hidden = !options.air; record.lead.hidden = !options.vehicles; record.follow.hidden = !(options.vehicles > 1);
        node.dataset.formation = formation; node.dataset.count = String(count);
        node.setAttribute('aria-label', U.t('diagram_label', { formation: U.t('formation_' + formation), count }));
    };
    U.chip = (node, label, state) => { node.textContent = label; node.dataset.state = state || ''; };
    U.metric = (value, label) => {
        const node = U.el('div', undefined, 'metric'); node.append(U.el('strong', U.number(value), 'metric-value'), U.el('span', label)); return node;
    };
    U.empty = key => U.el('p', U.t(key), 'empty');
    U.notice = (text, kind = 'inform', title, state) => {
        if (typeof text !== 'string' || !text.trim()) return;
        const key = `${kind}:${text}`;
        if (toasts.has(key)) return;
        const node = U.el('section', undefined, 'toast'); node.dataset.kind = kind; if (state) node.dataset.state = state;
        node.append(U.el('strong', title || U.store.data.ui?.brand || 'DIOS PROTECT'), U.el('p', text));
        const container = U.$('#notifications'); container.append(node); toasts.set(key, node);
        while (toasts.size > 4) { const first = toasts.keys().next().value; toasts.get(first).remove(); toasts.delete(first); }
        document.body.dataset.protectNotify = 'true';
        const duration = kind === 'error' || kind === 'warning' ? 5000 : kind === 'success' || kind === 'tactical' ? 4000 : 3000;
        setTimeout(() => { if (toasts.get(key) === node) toasts.delete(key); node.remove(); document.body.dataset.protectNotify = toasts.size ? 'true' : 'false'; }, duration);
    };
    U.clearNotices = () => { toasts.clear(); U.$('#notifications').replaceChildren(); document.body.dataset.protectNotify = 'false'; };
    U.message = (text, error = false, persist = false) => {
        clearTimeout(messageTimer); const node = U.$('#message');
        node.textContent = text; node.dataset.kind = error ? 'error' : 'inform'; node.hidden = !text;
        if (!persist) messageTimer = setTimeout(() => { node.hidden = true; }, error ? 7000 : 4000);
    };
    U.modal = type => {
        const s = U.store;
        if (type && U.$('#modal-layer').hidden) restoreFocus = document.activeElement;
        U.$('#confirm-dialog').hidden = type !== 'confirm'; U.$('#invite-dialog').hidden = type !== 'invite';
        U.$('#modal-layer').hidden = !type; document.body.dataset.protectModal = type ? 'true' : 'false';
        if (type) U.$(type === 'invite' ? '#invite-decline' : '#confirm-cancel').focus();
        else if (restoreFocus?.isConnected && s.visible) restoreFocus.focus();
    };
    U.confirm = (action, target) => {
        if (U.store.pending || U.store.invitation) return;
        const keys = { off: ['confirm_standdown', 'standdown_effect'], disband: ['confirm_disband', 'disband_effect'], dismissAll: ['confirm_dismiss_all', 'dismiss_all_effect'], dismiss: ['confirm_dismiss', 'dismiss_effect'] };
        const [title, description] = keys[action];
        U.store.confirmation = { action, target };
        U.$('#confirm-title').textContent = U.t(title); U.$('#confirm-text').textContent = U.t(description);
        U.renderConfirmationCounts(); U.modal('confirm');
    };
    U.renderConfirmationCounts = () => {
        const action = U.store.confirmation?.action;
        if (!action) return;
        const c = U.store.data.counts || {}, container = U.$('#confirm-counts'); container.replaceChildren();
        const rows = action === 'dismiss' ? [] : action === 'disband' ? [[(c.crew || 0), 'crew_agents'], [c.vehicles || 0, 'selected']] : [[(c.foot || 0) + (c.crew || 0) + (c.airCrew || 0), 'npc_agents'], [c.vehicles || 0, 'selected'], [c.air || 0, 'air']];
        if (action === 'dismissAll') rows.push([U.store.data.agents?.length || 0, 'agents']);
        for (const [value, label] of rows) { const row = U.el('div', undefined, 'role-row'); row.append(U.el('span', U.t(label)), U.el('strong', U.number(value))); container.append(row); }
    };
    U.hideInvitation = token => {
        const s = U.store;
        if (token && s.invitation?.token !== token) return;
        s.invitation = null; U.modal(s.confirmation ? 'confirm' : null);
    };
    U.invite = data => {
        if (typeof data.token !== 'string') return;
        const s = U.store;
        s.confirmation = null;
        if (data.translations) s.data.translations = data.translations;
        if (data.locale) s.data.locale = data.locale;
        const duration = Math.max(0, Number(data.remainingMs) || 0);
        s.invitation = { token: data.token, deadline: performance.now() + duration, duration, submitting: false };
        U.translate(); U.$('#invite-title').textContent = data.title; U.$('#invite-text').textContent = data.text;
        U.$('#invite-accept').textContent = data.accept; U.$('#invite-decline').textContent = data.decline;
        U.$('#invite-accept').disabled = false; U.$('#invite-decline').disabled = false;
        U.modal('invite'); U.tick();
    };
    U.answerInvite = async accepted => {
        const record = U.store.invitation;
        if (!record || record.submitting) return;
        if (record.deadline <= performance.now()) accepted = false;
        record.submitting = true; U.$('#invite-accept').disabled = true; U.$('#invite-decline').disabled = true;
        try {
            const response = await U.request('inviteAnswer', { token: record.token, accepted });
            if (response.error) throw new Error(response.error);
            U.hideInvitation(record.token);
        } catch (error) {
            if (U.store.invitation === record && record.deadline > performance.now()) {
                record.submitting = false; U.$('#invite-accept').disabled = false; U.$('#invite-decline').disabled = false;
                U.notice(U.publicError(error), 'error');
            } else U.hideInvitation(record.token);
        }
    };
    U.tick = () => {
        const invite = U.store.invitation;
        if (invite) {
            const left = Math.max(0, invite.deadline - performance.now());
            U.$('#invite-countdown').textContent = U.time(left);
            U.$('#invite-progress').style.width = `${invite.duration ? left / invite.duration * 100 : 0}%`;
            if (!left) { if (!invite.submitting) U.answerInvite(false); U.hideInvitation(invite.token); }
        }
        U.all('[data-offer-deadline]').forEach(node => { node.textContent = U.time(Number(node.dataset.offerDeadline) - performance.now()); });
        const left = Math.max(0, U.store.cooldownDeadline - performance.now());
        U.all('[data-air-cooldown]').forEach(node => { node.textContent = left ? U.t('available_in', { time: U.time(left) }) : ''; });
    };
})();
