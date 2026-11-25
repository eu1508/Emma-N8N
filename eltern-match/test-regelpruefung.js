// Ausführen: node eltern-match/test-regelpruefung.js
const assert = require('assert');
const { pruefe, grundAdresse } = require('./regelpruefung.js');
const I = 'info@dalinowellness.de';
const f = a => ({ value: [{ address: a }], text: a });
const jetzt = new Date('2026-11-25T21:30:00Z');
const gut = '<img src="dalino-kids-logo.png"> pages/impressum-1 datenschutz-eltern-match LÖSCHEN Dein Dalino-Kids-Team Kaulbachstr. 51–53';
const mails = [
  { id: 'p1', subject: 'Eltern-Match Testprofil Juri', from: f('tester@example.org'), to: f(I), date: '2026-11-17T11:46:52Z', text: 'Formular: ELTERN-MATCH Profil\nName: Juri\nE-Mail: tippfehler@gmial.com' },
  { id: 'b1', subject: 'Delivery Status Notification (Failure)', from: f('mailer-daemon@googlemail.com'), to: f(I), date: '2026-11-18T10:21:57Z', text: 'Final-Recipient: rfc822; tippfehler@gmial.com' },
  { id: 'a1', subject: 'Eltern-Match: Wir haben jemanden für dich gefunden (EM001)', from: f(I), to: f('papa@example.org'), date: '2026-11-17T11:47:21Z', html: '<p>Hallo Papa,</p> Dein Dalino-Team Kaulbachstraße 51 · LÖSCHEN' },
  { id: 'w1', subject: 'Eltern-Match: Wir haben jemanden (EM002)', from: f(I), to: f('mama@example.org'), date: '2026-11-18T18:09:33Z', html: gut + ' Hallo Kundin, Neues aus der Dalino-Welt This email was sent automatically with n8n' },
  { id: 'p2', subject: 'Eltern-Match: neues Profil von Mareike', from: f(I), to: f(I), date: '2026-11-25T20:40:00Z', text: 'Name: Mareike\nE-Mail: mareike@example.de\nAlter der Kinder: 0–1 Jahr' },
  { id: 'p3', subject: 'Eltern-Match: neues Profil von Lena', from: f(I), to: f(I), date: '2026-11-25T20:00:00Z', text: 'Name: Lena\nE-Mail: lena@example.de' },
  { id: 'd3', subject: 'Eltern-Match: Danke für dein Profil', from: f(I), to: f('lena@example.de'), date: '2026-11-25T20:01:00Z', html: gut + ' Hallo Lena' },
];
const state = {};
const r = pruefe(mails.map(json => ({ json })), state, jetzt);
const alles = r.alarme.concat(r.warnungen).join('\n');
assert(/unzustellbar/.test(alles), 'Bounce erkannt');
assert(/Werbung ohne bestätigtes Double-Opt-in/.test(alles), 'Werbung ohne Opt-in erkannt');
assert(/n8n-Hinweis/.test(alles) && /Anrede ohne echten Namen/.test(alles), 'n8n-Footer und Hallo Kundin erkannt');
assert(/Impressum-Link fehlt/.test(alles) && /Alte Adresse/.test(alles), 'alte Vorlage erkannt');
assert(/Mareike hat nach \d+ Min\. noch keine Bestätigung/.test(alles), 'fehlende Bestätigung erkannt');
assert(!/Lena hat/.test(alles), 'bestätigtes Profil ohne Alarm');
assert(/0–1 Jahr/.test(alles), 'Altersangabe erkannt');
assert(r.testprofile.length === 1 && /Juri/.test(r.testprofile[0]), 'Testprofil erkannt');
const r2 = pruefe(mails.map(json => ({ json })), state, jetzt);
assert.strictEqual(r2.alarme.length + r2.warnungen.length, 0, 'keine doppelten Meldungen');
assert.strictEqual(grundAdresse('Max.Muster+mama@gmail.com'), 'maxmuster@gmail.com');
assert.strictEqual(pruefe([{ json: {} }], {}, jetzt).hatAlarm, false, 'leerer Lauf ohne Alarm');
console.log('Alle Tests bestanden.');
