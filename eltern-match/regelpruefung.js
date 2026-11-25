// Eltern-Match Wächter: Regelprüfung
// Läuft im n8n-Code-Node "Regelprüfung" (Modus: Run Once for All Items).
// Eingabe: bis zu 100 Gmail-Nachrichten aus info@dalinowellness.de (Gmail-Node, Simplify AUS).
// Ausgabe: genau 1 Item mit { alarme, warnungen, testprofile, statistik, telegramText, hatAlarm }.
// Bereits gemeldete Funde merkt sich der Workflow (Static Data), damit Emma nicht doppelt alarmiert wird.

const KONFIG = {
  absender: 'info@dalinowellness.de',
  // Pflichtbestandteile jeder Mail an Eltern
  pflicht: [
    { muster: /pages\/impressum/i, text: 'Impressum-Link fehlt' },
    { muster: /datenschutz-eltern-match/i, text: 'Datenschutz-Link fehlt' },
    { muster: /LÖSCHEN/, text: 'Hinweis „LÖSCHEN“ (Widerruf) fehlt' },
    { muster: /dalino-kids-logo|dalino-logo/i, text: 'Logo fehlt (alte Vorlage?)' },
    { muster: /Dalino-Kids-Team/, text: 'Gruß „Dein Dalino-Kids-Team“ fehlt (alte Vorlage?)' },
  ],
  // Darf in keiner Mail an Eltern stehen
  verboten: [
    { muster: /sent automatically with/i, text: 'n8n-Hinweis „This email was sent automatically with n8n“' },
    { muster: /Hallo\s+(Kundin|Kunde|undefined|null)\b|Hallo\s*,\s*<|Hallo\s*,\s*$/im, text: 'Anrede ohne echten Namen („Hallo Kundin“ o. Ä.)' },
    { muster: /\{\{|\}\}|\$json|undefined|NaN|\[object Object\]/, text: 'Platzhalter/Technikfehler im Text ({{ }}, undefined …)' },
    { muster: /Kaulbachstra(ß|ss)e 51(?!\s*[–-])/, text: 'Alte Adresse „Kaulbachstraße 51“ statt „Kaulbachstr. 51–53“' },
  ],
  werbeblock: /Neues aus der Dalino-Welt|Dalino Longevity ansehen|Mehr zu HBOT/i,
  // Testprofile, die nie an echte Eltern gematcht werden dürfen
  testMuster: [/\btest/i, /rueb\.eu/i, /irniarueb/i, /irinarueb/i, /ruebeu@/i, /\+mama@/i, /\[TEST\]/i, /Testprofil/i, /Testkopie/i],
  bestaetigungMinuten: 30,   // so schnell muss „Danke für dein Profil“ / „Danke, wir haben deine Antwort“ raus
  stilleStunden: 24,         // Profile kommen rein, aber 24 h keine Mail raus = Störung
};

function adresse(feld) {
  if (!feld) return '';
  if (typeof feld === 'string') { const m = feld.match(/[\w.+-]+@[\w.-]+\.\w+/); return m ? m[0].toLowerCase() : ''; }
  if (feld.value && feld.value[0]) return String(feld.value[0].address || '').toLowerCase();
  if (feld.text) return adresse(feld.text);
  return '';
}
function alleAdressen(feld) {
  if (!feld) return [];
  if (feld.value) return feld.value.map(v => String(v.address || '').toLowerCase()).filter(Boolean);
  const s = typeof feld === 'string' ? feld : (feld.text || '');
  return (s.match(/[\w.+-]+@[\w.-]+\.\w+/g) || []).map(a => a.toLowerCase());
}
// Gmail schickt von „name+alias@gmail.com“ immer ab „name@gmail.com“ – für den Abgleich normalisieren.
function grundAdresse(a) {
  a = (a || '').toLowerCase();
  const [lokal, domain] = a.split('@');
  if (!domain) return a;
  let l = lokal.replace(/\+.*$/, '');
  if (/^(gmail|googlemail)\.com$/.test(domain)) l = l.replace(/\./g, '');
  return l + '@' + domain;
}
function gueltigeAdresse(a) { return /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test(a || ''); }
function feldAusFormular(text, name) {
  const m = (text || '').match(new RegExp('^\\s*(?:\\d+\\.\\s*)?' + name + ':\\s*(.+)$', 'im'));
  return m ? m[1].trim() : '';
}

function pruefe(nachrichten, state, jetzt) {
  state.gemeldet = state.gemeldet || {};
  const alarme = [], warnungen = [], testMap = {};
  const neu = (schluessel) => { if (state.gemeldet[schluessel]) return false; state.gemeldet[schluessel] = jetzt.toISOString(); return true; };

  const mails = nachrichten.filter(n => (n.json || n).id).map(n => {
    const j = n.json || n;
    const html = j.html || j.textAsHtml || '';
    const text = j.text || '';
    const von = adresse(j.from);
    return {
      id: j.id, betreff: j.subject || '', von, an: alleAdressen(j.to),
      datum: new Date(j.date || (j.internalDate ? Number(j.internalDate) : jetzt)),
      inhalt: html + '\n' + text, text: text || html.replace(/<[^>]+>/g, ' '), labels: j.labelIds || [],
    };
  });

  const ausgehend = mails.filter(m => m.von === KONFIG.absender && !m.an.every(a => a === KONFIG.absender));
  const intern = mails.filter(m => m.von === KONFIG.absender && m.an.every(a => a === KONFIG.absender));
  const bounces = mails.filter(m => /mailer-daemon|postmaster/i.test(m.von) || /Delivery Status Notification|Undeliverable|Unzustellbar|nicht zugestellt/i.test(m.betreff));
  const formulare = mails.filter(m => /ELTERN-MATCH Profil|neues Profil von/i.test(m.inhalt + m.betreff) && !bounces.includes(m));
  const antworten = mails.filter(m => m.von !== KONFIG.absender && /Eltern-Match\s+(JA|SCHREIBEN|NEIN)\b/i.test(m.betreff));
  const optins = mails.filter(m => m.von !== KONFIG.absender && /NEUIGKEITEN JA/i.test(m.betreff));
  const optouts = mails.filter(m => m.von !== KONFIG.absender && /KEINE WERBUNG/i.test(m.betreff + ' ' + m.text.slice(0, 200)));
  const loeschen = mails.filter(m => m.von !== KONFIG.absender && /\bLÖSCHEN\b/.test(m.betreff + ' ' + m.text.slice(0, 200)));

  // Opt-in-Liste pflegen (Double-Opt-in bestätigt = Antwort NEUIGKEITEN JA, Abmeldung = KEINE WERBUNG)
  state.optin = state.optin || {};
  optins.forEach(m => { state.optin[grundAdresse(m.von)] = m.datum.toISOString(); });
  optouts.forEach(m => { delete state.optin[grundAdresse(m.von)]; });

  // Profile aus Formular-Mails
  const profile = formulare.map(m => {
    const mail = feldAusFormular(m.text, 'E-Mail') || (m.text.match(/[\w.+-]+@[\w.-]+\.\w+/g) || []).find(a => a.toLowerCase() !== KONFIG.absender) || '';
    return { mail: (mail.match(/[\w.+-]+@[\w.-]+\.\w+/) || [mail])[0].toLowerCase(), roh: mail, name: feldAusFormular(m.text, 'Name'), alter: feldAusFormular(m.text, '(?:Alter der Kinder)'), m };
  });
  state.profile = state.profile || {};
  profile.forEach(p => { if (p.mail) state.profile[grundAdresse(p.mail)] = { name: p.name, seit: p.m.datum.toISOString() }; });
  loeschen.forEach(m => { delete state.profile[grundAdresse(m.von)]; });

  // 1) RECHT: Pflichtangaben, Werbung nur mit bestätigtem Opt-in
  ausgehend.forEach(m => {
    const fehlt = KONFIG.pflicht.filter(r => !r.muster.test(m.inhalt)).map(r => r.text);
    const verstoss = KONFIG.verboten.filter(r => r.muster.test(m.inhalt)).map(r => r.text);
    const empfaenger = m.an.filter(a => a !== KONFIG.absender);
    const werbungOhneOptin = KONFIG.werbeblock.test(m.inhalt) && empfaenger.some(a => !state.optin[grundAdresse(a)]);
    if (werbungOhneOptin && neu('werbung:' + m.id)) alarme.push(`⚖️ Werbung ohne bestätigtes Double-Opt-in an ${empfaenger.join(', ')} („${m.betreff}“)`);
    if (fehlt.length && neu('pflicht:' + m.id)) warnungen.push(`📄 „${m.betreff}“ an ${empfaenger.join(', ')}: ${fehlt.join('; ')}`);
    if (verstoss.length && neu('qualitaet:' + m.id)) warnungen.push(`✏️ „${m.betreff}“ an ${empfaenger.join(', ')}: ${verstoss.join('; ')}`);
  });

  // 2) STÖRUNG: unzustellbare Mails
  bounces.forEach(m => {
    const ziel = (m.text.match(/(?:Final-Recipient:\s*rfc822;\s*|nicht an\s+|delivered to\s+)([\w.+-]+@[\w.-]+\.\w+)/i) || [])[1] || 'unbekannt';
    if (neu('bounce:' + m.id)) alarme.push(`📭 Mail an ${ziel} ist unzustellbar. Profil prüfen (Tippfehler?) – solange hängt das Match.`);
  });

  // 3) PROFILE: Adresse, Bestätigung, Testprofile, Altersangaben
  profile.forEach(p => {
    if (!gueltigeAdresse(p.mail) || /https?:\/\//i.test(p.roh)) {
      if (neu('adresse:' + p.m.id)) alarme.push(`📧 Profil „${p.name || '?'}“ hat keine gültige E-Mail-Adresse: ${p.roh || '(leer)'}`);
    }
    const istTest = KONFIG.testMuster.some(r => r.test(p.mail) || r.test(p.name) || r.test(p.m.betreff));
    if (istTest) testMap[grundAdresse(p.mail)] = `${p.name || '?'} <${p.mail}>`;
    const bestaetigt = ausgehend.some(o => o.an.some(a => grundAdresse(a) === grundAdresse(p.mail)) && /Danke für dein Profil/i.test(o.betreff) && o.datum >= p.m.datum);
    const alterMin = (jetzt - p.m.datum) / 60000;
    if (!istTest && !bestaetigt && alterMin > KONFIG.bestaetigungMinuten && neu('bestaetigung:' + p.m.id)) {
      alarme.push(`⏱️ ${p.name || p.mail} hat nach ${Math.round(alterMin)} Min. noch keine Bestätigung „Danke für dein Profil“ bekommen.`);
    }
    if (/0–1 Jahr|0-1 Jahr/.test(p.alter) && neu('alter:' + p.m.id)) {
      warnungen.push(`🧮 ${p.name || p.mail}: Altersangabe „0–1 Jahr“ (neues Formular). Ältere Profile haben „unter 1 Jahr“ – prüfen, ob das Matching beide als gleich erkennt.`);
    }
  });
  // Testprofile aus dem Gedächtnis (auch ältere Läufe)
  Object.entries(state.profile).forEach(([mail, info]) => {
    if (KONFIG.testMuster.some(r => r.test(mail) || r.test(info.name || ''))) {
      if (!testMap[mail]) testMap[mail] = `${info.name || '?'} <${mail}>`;
    }
  });
  const testprofile = Object.values(testMap);
  Object.entries(testMap).forEach(([k, t]) => { if (neu('test:' + k)) alarme.push(`🧪 Testprofil noch aktiv: ${t} – bitte in der Match-Datenbank löschen, damit es niemand Echtes als Match bekommt.`); });

  // 4) ANTWORTEN: JA/SCHREIBEN/NEIN müssen bestätigt werden
  antworten.forEach(a => {
    const ok = ausgehend.some(o => o.an.some(x => grundAdresse(x) === grundAdresse(a.von)) && /Danke, wir haben deine Antwort|stellen euch|Vorstellung/i.test(o.betreff + o.text.slice(0, 300)) && o.datum >= a.datum);
    const min = (jetzt - a.datum) / 60000;
    if (!ok && min > KONFIG.bestaetigungMinuten && neu('antwort:' + a.id)) warnungen.push(`⏱️ Antwort „${a.betreff}“ von ${a.von} ist seit ${Math.round(min)} Min. unbestätigt.`);
  });

  // 5) DOUBLE-OPT-IN: Bestätigung muss einem Profil zugeordnet werden können
  optins.forEach(o => {
    if (!state.profile[grundAdresse(o.von)] && neu('optin:' + o.id)) warnungen.push(`📬 „NEUIGKEITEN JA“ von ${o.von} passt zu keinem bekannten Profil (anderer Absender als im Formular?).`);
  });

  // 6) STILLE: Profile kommen rein, aber nichts geht raus = Workflow steht
  const letzteAusgehend = ausgehend.reduce((t, m) => Math.max(t, m.datum.getTime()), 0);
  const letztesProfil = profile.reduce((t, p) => Math.max(t, p.m.datum.getTime()), 0);
  if (letztesProfil && letztesProfil > letzteAusgehend && (jetzt - letztesProfil) / 3600000 > KONFIG.stilleStunden && neu('stille:' + new Date(letztesProfil).toISOString())) {
    alarme.push(`🚨 Seit über ${KONFIG.stilleStunden} Std. kam ein Profil rein, aber der Eltern-Match-Workflow hat keine einzige Mail verschickt. Läuft n8n?`);
  }

  // Gedächtnis klein halten (älter als 60 Tage vergessen)
  for (const [k, t] of Object.entries(state.gemeldet)) if (jetzt - new Date(t) > 60 * 864e5) delete state.gemeldet[k];

  const statistik = { geprueft: mails.length, ausgehend: ausgehend.length, intern: intern.length, profile: profile.length, antworten: antworten.length, bounces: bounces.length, optins: optins.length, aktiveProfile: Object.keys(state.profile).length, bestaetigteOptins: Object.keys(state.optin).length };
  state.letzterLauf = { zeit: jetzt.toISOString(), statistik, alarme: alarme.length, warnungen: warnungen.length };

  const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  let telegramText = '';
  if (alarme.length || warnungen.length) {
    telegramText = `<b>Eltern-Match Wächter</b> – ${alarme.length} Störung(en), ${warnungen.length} Hinweis(e)\n`;
    if (alarme.length) telegramText += '\n<b>Sofort ansehen:</b>\n' + alarme.map(esc).join('\n') + '\n';
    if (warnungen.length) telegramText += '\n<b>Qualität/Recht:</b>\n' + warnungen.slice(0, 15).map(esc).join('\n') + (warnungen.length > 15 ? `\n… und ${warnungen.length - 15} weitere` : '') + '\n';
    telegramText += `\n<i>${statistik.geprueft} Mails geprüft (Paket à 100)</i>`;
  }
  return { alarme, warnungen, testprofile, statistik, telegramText, hatAlarm: alarme.length + warnungen.length > 0 };
}

// --- n8n ---
if (typeof $input !== 'undefined') {
  return [{ json: pruefe($input.all(), $getWorkflowStaticData('global'), new Date()) }];
}
module.exports = { pruefe, grundAdresse };
