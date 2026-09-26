/* OpenJooki web UI — local management page for a Jooki v2.
   Talks to the Jooki only (MQTT over WebSocket on port 8000 + HTTP /upload).
   No tracker, no cloud, no external resource. */
(function () {
  'use strict';

  var CFG = window.OJ_CONFIG || {};
  var VERSION = '1.3.0';

  /* ------------------------------------------------------------------ i18n */
  var T = {
    fr: {
      playlists: 'Playlists', tokens: 'Jetons', library: 'Bibliothèque', settings: 'Réglages',
      connecting: 'Connexion au Jooki…', connected: 'Connecté', offline: 'Hors ligne',
      offline_long: 'Le Jooki ne répond pas. Vérifie qu\'il est allumé et sur le même Wi-Fi. Nouvelle tentative automatique…',
      retry: 'Réessayer',
      new_playlist: 'Nouvelle playlist', create: 'Créer', cancel: 'Annuler', save: 'Enregistrer', close: 'Fermer',
      name: 'Nom', playlist_name_ph: 'Ex. : Comptines du soir',
      n_tracks: function (n) { return n + (n > 1 ? ' pistes' : ' piste'); },
      audiobook: 'Livre audio', audiobook_help: 'Reprend toujours là où on s\'était arrêté, sans lecture aléatoire.',
      no_token: 'Aucun jeton', choose_token: 'Choisir le personnage', token_for: 'Personnage qui lance cette playlist',
      token_help: 'Tous les jetons d\'un même personnage lancent cette playlist (par exemple tous les dragons noirs).',
      used_by: function (t) { return 'déjà sur « ' + t + ' »'; },
      token_moved: function (t) { return 'Ce personnage lançait « ' + t + ' ». Il lancera désormais cette playlist.'; },
      play: 'Lire', pause: 'Pause', next: 'Suivant', prev: 'Précédent',
      add_files: 'Ajouter des fichiers', from_library: 'Depuis la bibliothèque', web_radio: 'Radio web',
      delete_playlist: 'Supprimer la playlist',
      delete_playlist_q: function (t) { return 'Supprimer « ' + t + ' » ?'; },
      delete_playlist_text: 'La playlist est supprimée. Ses morceaux restent sur le Jooki (dans « Non utilisées »).',
      delete: 'Supprimer', rename: 'Renommer',
      empty_playlist: 'Cette playlist est vide.', empty_playlist_hint: 'Ajoute des fichiers depuis ton téléphone ou ton ordinateur, ou des morceaux déjà présents sur le Jooki.',
      drop_here: 'Glisse des fichiers audio ici', removed_from: 'Retiré de la playlist', undo: 'Annuler',
      playlist_missing: 'Cette playlist n\'existe plus.', back: 'Retour',
      no_playlists: 'Aucune playlist pour l\'instant.',
      unused_banner: function (n) { return n + (n > 1 ? ' morceaux ne sont' : ' morceau n\'est') + ' dans aucune playlist.'; },
      see: 'Voir',
      all: 'Tous', unused: 'Non utilisés', search: 'Rechercher', in_playlists: 'Dans : ', in_none: 'Dans aucune playlist',
      add_to: 'Ajouter à…', selected: function (n) { return n + (n > 1 ? ' sélectionnés' : ' sélectionné'); },
      delete_forever: 'Supprimer du Jooki',
      delete_forever_q: function (n) { return 'Supprimer définitivement ' + n + (n > 1 ? ' morceaux' : ' morceau') + ' ?'; },
      delete_forever_text: 'Les fichiers seront effacés du Jooki. Cette action est irréversible.',
      deleted: 'Supprimé', choose_playlist: 'Choisir une playlist', added: function (n) { return n + (n > 1 ? ' morceaux ajoutés' : ' morceau ajouté'); },
      already_in: 'déjà dedans', add: 'Ajouter', add_n: function (n) { return 'Ajouter ' + n; },
      library_empty: 'Aucun morceau sur le Jooki.', unused_empty: 'Tous les morceaux sont dans une playlist.',
      radio: 'Radio', radio_title: 'Ajouter une radio web', radio_name: 'Nom de la radio', radio_url: 'Adresse du flux (http:// ou https://)',
      radio_url_bad: 'L\'adresse doit commencer par http:// ou https://',
      tokens_intro: 'Chaque personnage lance une playlist. Tous les jetons d\'un même personnage (par exemple tous tes dragons noirs) font exactement la même chose.',
      tokens_hint: 'Pose un jeton sur le Jooki pour le faire apparaître ici.',
      launches: 'Lance', none_dash: '— Aucune playlist —',
      token_n: function (n) { return 'Jeton ' + n; }, token_name_ph: 'Surnom (facultatif)',
      seen_n: function (n) { return 'posé ' + n + ' fois'; }, on_jooki: 'Sur le Jooki',
      forget: 'Oublier', forget_q: 'Oublier ce jeton ?',
      forget_text: 'Il disparaît de la liste et réapparaîtra la prochaine fois qu\'il sera posé. La playlist du personnage ne change pas.',
      saved: 'Enregistré', no_tokens: 'Aucun jeton connu pour l\'instant.',
      other_chars: 'Personnages sans jeton connu',
      device: 'Appareil', device_name: 'Nom', battery: 'Batterie', charging: 'en charge', plugged: 'branché',
      wifi: 'Wi-Fi', ip: 'Adresse IP', storage: 'Stockage', free: 'libres', version: 'Version',
      playback: 'Lecture', toy_safe: 'Volume limité (mode enfant)', shuffle: 'Aléatoire', repeat: 'Répéter',
      language: 'Langue', power_off: 'Éteindre le Jooki', power_off_q: 'Éteindre le Jooki ?',
      power_off_text: 'Il faudra appuyer sur son bouton pour le rallumer.', power_off_done: 'Le Jooki s\'éteint…',
      nothing_playing: 'Rien en lecture', nothing_hint: 'Pose un jeton ou choisis une playlist',
      live: 'En direct', volume: 'Volume',
      uploading: 'Envoi', processing: 'Analyse sur le Jooki…', done: 'Ajouté', queued: 'En attente',
      up_too_small: 'Fichier vide ou trop petit', up_no_space: 'Plus assez de place sur le Jooki',
      up_net: 'Échec de l\'envoi (connexion perdue ?)', up_type: 'Ce fichier n\'est pas un format audio reconnu',
      up_fail: 'Le Jooki n\'a pas pu ajouter ce fichier', up_timeout: 'Pas de réponse du Jooki',
      uploads_running: 'Des envois sont en cours. Quitter la page les interrompra.',
      clear_done: 'Masquer les envois terminés',
      up_retrying: function (n, m) { return 'Connexion perdue, nouvel essai (' + n + '/' + m + ')…'; }, up_retry: 'Réessayer',
      wifi_good: 'Signal bon', wifi_fair: 'Signal moyen', wifi_weak: 'Signal faible',
      wifi_drops: function (n) { return n + (n > 1 ? ' coupures' : ' coupure') + ' depuis le démarrage'; },
      wifi_advice: 'Rapprochez le Jooki d\'une borne Wi-Fi. La musique marche sans Wi-Fi : seuls cette page et les envois en ont besoin.',
      err_readonly: 'Action impossible sur les morceaux non utilisés.',
      err_internal: 'Le Jooki a rencontré une erreur. Réessaie.',
      err_empty_title: 'Le nom ne peut pas être vide.',
      err_radio: 'Adresse de radio invalide.',
      err_gone: 'Cet élément n\'existe plus.',
      err_generic: 'Le Jooki a refusé l\'action.',
      err_unknown_char: 'Personnage inconnu.',
      duration_total: function (s) { return s; },
      mute_unsupported: '',
      files_hint: 'MP3, M4A, OGG, FLAC, WAV…',
      open_player: 'Ouvrir le lecteur',
      web_page: 'page', upd_check: 'Rechercher une mise à jour', upd_checking: 'Recherche…',
      upd_uptodate: 'Ton Jooki est à jour.', upd_offline: 'Impossible de joindre GitHub (le Jooki a-t-il Internet ?).',
      upd_available: function (v) { return 'Nouvelle version ' + v + ' disponible'; }, upd_now: 'Mettre à jour maintenant',
      upd_q: function (v) { return 'Mettre à jour vers OpenJooki ' + v + ' ?'; },
      upd_text: 'Le Jooki télécharge la nouvelle version et redémarre tout seul : jusqu\'à 10 minutes. Garde-le branché. Ta musique et tes jetons sont conservés, et il revient tout seul à l\'ancienne version si quelque chose se passe mal.',
      upd_running: 'Mise à jour en cours…', upd_keep: 'Garde le Jooki branché. Cette page se reconnecte toute seule.',
      upd_rebooting: 'Le Jooki redémarre sur la nouvelle version…', upd_done: function (v) { return 'Jooki mis à jour : OpenJooki ' + v; },
      upd_failed: 'La mise à jour n\'a pas pu se faire. Ton Jooki n\'a pas changé.', upd_banner: function (v) { return 'Mise à jour ' + v + ' disponible'; },
      upd_see: 'Voir',
      bedtime: 'Heure du coucher', sleep_timer: 'Minuterie', sleep_off: 'Arrêt',
      sleep_min: function (n) { return n + ' min'; }, sleep_track: 'Fin du chapitre',
      sleep_left: function (s) { return 'Arrêt dans ' + s; }, sleep_at_end: 'Arrêt à la fin de ce morceau',
      sleep_auto: 'automatique (mode nuit)', sleep_cancel: 'Annuler la minuterie',
      night_mode: 'Mode nuit', night_help: 'Pendant ces heures, chaque écoute s\'arrête toute seule, le volume est limité et les lumières sont tamisées.',
      night_from: 'De', night_to: 'À', night_timer: 'Minuterie automatique', night_timer_none: 'Aucune',
      night_maxvol: 'Volume maximum', night_nolimit: 'pas de limite', night_dim: 'Lumières tamisées',
      night_now: 'Mode nuit en ce moment', night_next: function (h) { return 'Commence à ' + h; },
      night_clock: 'L\'heure du Jooki vient d\'Internet (heure d\'été comprise).',
      resume_at: function (c, s) { return 'Reprendra au chapitre ' + c + (s ? ' · ' + s : ''); },
      resume_restart: 'Recommencer au début', resume_done: 'Reprendra au chapitre 1',
      sort_tracks: 'Remettre dans l\'ordre (1, 2, 3…)', sorted: 'Pistes remises dans l\'ordre'
    },
    en: {
      playlists: 'Playlists', tokens: 'Tokens', library: 'Library', settings: 'Settings',
      connecting: 'Connecting to the Jooki…', connected: 'Connected', offline: 'Offline',
      offline_long: 'The Jooki is not answering. Check it is on and on the same Wi-Fi. Retrying automatically…',
      retry: 'Retry',
      new_playlist: 'New playlist', create: 'Create', cancel: 'Cancel', save: 'Save', close: 'Close',
      name: 'Name', playlist_name_ph: 'E.g. Bedtime songs',
      n_tracks: function (n) { return n + (n === 1 ? ' track' : ' tracks'); },
      audiobook: 'Audiobook', audiobook_help: 'Always resumes where it stopped, never shuffled.',
      no_token: 'No token', choose_token: 'Choose the character', token_for: 'Character that starts this playlist',
      token_help: 'Every token of the same character starts this playlist (e.g. all black dragons).',
      used_by: function (t) { return 'on “' + t + '”'; },
      token_moved: function (t) { return 'This character used to start “' + t + '”. It will now start this playlist.'; },
      play: 'Play', pause: 'Pause', next: 'Next', prev: 'Previous',
      add_files: 'Add files', from_library: 'From the library', web_radio: 'Web radio',
      delete_playlist: 'Delete playlist',
      delete_playlist_q: function (t) { return 'Delete “' + t + '”?'; },
      delete_playlist_text: 'The playlist is deleted. Its tracks stay on the Jooki (under “Unused”).',
      delete: 'Delete', rename: 'Rename',
      empty_playlist: 'This playlist is empty.', empty_playlist_hint: 'Add files from your phone or computer, or tracks already on the Jooki.',
      drop_here: 'Drop audio files here', removed_from: 'Removed from the playlist', undo: 'Undo',
      playlist_missing: 'This playlist no longer exists.', back: 'Back',
      no_playlists: 'No playlist yet.',
      unused_banner: function (n) { return n + (n === 1 ? ' track is' : ' tracks are') + ' in no playlist.'; },
      see: 'Show',
      all: 'All', unused: 'Unused', search: 'Search', in_playlists: 'In: ', in_none: 'In no playlist',
      add_to: 'Add to…', selected: function (n) { return n + ' selected'; },
      delete_forever: 'Delete from Jooki',
      delete_forever_q: function (n) { return 'Permanently delete ' + n + (n === 1 ? ' track' : ' tracks') + '?'; },
      delete_forever_text: 'The files will be erased from the Jooki. This cannot be undone.',
      deleted: 'Deleted', choose_playlist: 'Choose a playlist', added: function (n) { return n + (n === 1 ? ' track added' : ' tracks added'); },
      already_in: 'already in', add: 'Add', add_n: function (n) { return 'Add ' + n; },
      library_empty: 'No track on the Jooki.', unused_empty: 'Every track is in a playlist.',
      radio: 'Radio', radio_title: 'Add a web radio', radio_name: 'Radio name', radio_url: 'Stream address (http:// or https://)',
      radio_url_bad: 'The address must start with http:// or https://',
      tokens_intro: 'Each character starts one playlist. All tokens of the same character (e.g. all your black dragons) do exactly the same thing.',
      tokens_hint: 'Put a token on the Jooki to see it here.',
      launches: 'Starts', none_dash: '— No playlist —',
      token_n: function (n) { return 'Token ' + n; }, token_name_ph: 'Nickname (optional)',
      seen_n: function (n) { return 'used ' + n + (n === 1 ? ' time' : ' times'); }, on_jooki: 'On the Jooki',
      forget: 'Forget', forget_q: 'Forget this token?',
      forget_text: 'It leaves the list and comes back next time it is used. The character\'s playlist does not change.',
      saved: 'Saved', no_tokens: 'No known token yet.',
      other_chars: 'Characters without a known token',
      device: 'Device', device_name: 'Name', battery: 'Battery', charging: 'charging', plugged: 'plugged in',
      wifi: 'Wi-Fi', ip: 'IP address', storage: 'Storage', free: 'free', version: 'Version',
      playback: 'Playback', toy_safe: 'Limited volume (kids mode)', shuffle: 'Shuffle', repeat: 'Repeat',
      language: 'Language', power_off: 'Turn off the Jooki', power_off_q: 'Turn off the Jooki?',
      power_off_text: 'You will need to press its button to turn it back on.', power_off_done: 'The Jooki is turning off…',
      nothing_playing: 'Nothing playing', nothing_hint: 'Put a token or pick a playlist',
      live: 'Live', volume: 'Volume',
      uploading: 'Uploading', processing: 'Processing on the Jooki…', done: 'Added', queued: 'Waiting',
      up_too_small: 'Empty or too small file', up_no_space: 'Not enough space left on the Jooki',
      up_net: 'Upload failed (connection lost?)', up_type: 'This file is not a supported audio format',
      up_fail: 'The Jooki could not add this file', up_timeout: 'No answer from the Jooki',
      uploads_running: 'Uploads are in progress. Leaving the page will stop them.',
      clear_done: 'Hide finished uploads',
      up_retrying: function (n, m) { return 'Connection lost, retrying (' + n + '/' + m + ')…'; }, up_retry: 'Retry',
      wifi_good: 'Good signal', wifi_fair: 'Fair signal', wifi_weak: 'Weak signal',
      wifi_drops: function (n) { return n + (n === 1 ? ' drop' : ' drops') + ' since start-up'; },
      wifi_advice: 'Move the Jooki closer to a Wi-Fi access point. Music works without Wi-Fi: only this page and uploads need it.',
      err_readonly: 'Not possible on unused tracks.',
      err_internal: 'The Jooki hit an error. Please retry.',
      err_empty_title: 'The name cannot be empty.',
      err_radio: 'Invalid radio address.',
      err_gone: 'This item no longer exists.',
      err_generic: 'The Jooki refused the action.',
      err_unknown_char: 'Unknown character.',
      duration_total: function (s) { return s; },
      mute_unsupported: '',
      files_hint: 'MP3, M4A, OGG, FLAC, WAV…',
      open_player: 'Open the player',
      web_page: 'page', upd_check: 'Check for updates', upd_checking: 'Checking…',
      upd_uptodate: 'Your Jooki is up to date.', upd_offline: 'Cannot reach GitHub (is the Jooki online?).',
      upd_available: function (v) { return 'New version ' + v + ' available'; }, upd_now: 'Update now',
      upd_q: function (v) { return 'Update to OpenJooki ' + v + '?'; },
      upd_text: 'The Jooki downloads the new version and restarts on its own: up to 10 minutes. Keep it plugged in. Your music and tokens are kept, and it goes back to the previous version by itself if anything goes wrong.',
      upd_running: 'Updating…', upd_keep: 'Keep the Jooki plugged in. This page reconnects by itself.',
      upd_rebooting: 'The Jooki is restarting on the new version…', upd_done: function (v) { return 'Jooki updated: OpenJooki ' + v; },
      upd_failed: 'The update could not be done. Your Jooki has not changed.', upd_banner: function (v) { return 'Update ' + v + ' available'; },
      upd_see: 'Show',
      bedtime: 'Bedtime', sleep_timer: 'Sleep timer', sleep_off: 'Off',
      sleep_min: function (n) { return n + ' min'; }, sleep_track: 'End of chapter',
      sleep_left: function (s) { return 'Stops in ' + s; }, sleep_at_end: 'Stops at the end of this track',
      sleep_auto: 'automatic (night mode)', sleep_cancel: 'Cancel the timer',
      night_mode: 'Night mode', night_help: 'During these hours, every listen stops by itself, the volume is limited and the lights are dimmed.',
      night_from: 'From', night_to: 'To', night_timer: 'Automatic timer', night_timer_none: 'None',
      night_maxvol: 'Maximum volume', night_nolimit: 'no limit', night_dim: 'Dimmed lights',
      night_now: 'Night mode right now', night_next: function (h) { return 'Starts at ' + h; },
      night_clock: 'The Jooki gets its time from the Internet (summer time included).',
      resume_at: function (c, s) { return 'Will resume at chapter ' + c + (s ? ' · ' + s : ''); },
      resume_restart: 'Start again from the beginning', resume_done: 'Will resume at chapter 1',
      sort_tracks: 'Put back in order (1, 2, 3…)', sorted: 'Tracks put back in order'
    }
  };
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  var lang = lsGet('oj.lang') || ((navigator.language || 'fr').slice(0, 2) === 'fr' ? 'fr' : 'en');
  if (!T[lang]) lang = 'fr';
  function t(k) {
    var v = T[lang][k];
    if (v === undefined) v = T.fr[k];
    if (typeof v === 'function') return v.apply(null, Array.prototype.slice.call(arguments, 1));
    return v === undefined ? k : v;
  }

  /* ------------------------------------------------------------------ characters */
  var MEDIA = '/static/media/';
  var CHARS = [
    ['Jooki.Dragon', 'Dragon', 'Dragon', 'dragon.cffed3d7.png'],
    ['Jooki.Fox', 'Renard', 'Fox', 'fox.ac721aec.png'],
    ['Jooki.Ghost', 'Fantôme', 'Ghost', 'ghost.c2a43882.png'],
    ['Jooki.Knight', 'Chevalier', 'Knight', 'knight.dc50962b.png'],
    ['Jooki.Whale', 'Baleine', 'Whale', 'whale.da72da11.png'],
    ['Jooki.Black.Dragon', 'Dragon noir', 'Black dragon', 'dragon-black.27a71b2c.png'],
    ['Jooki.Black.Fox', 'Renard noir', 'Black fox', 'fox-black.7d23b82c.png'],
    ['Jooki.Black.Knight', 'Chevalier noir', 'Black knight', 'knight-black.d995170a.png'],
    ['Jooki.Black.Whale', 'Baleine noire', 'Black whale', 'whale-black.74e936a9.png'],
    ['Jooki.White.Dragon', 'Dragon blanc', 'White dragon', 'dragon-white.921a8110.png'],
    ['Jooki.White.Fox', 'Renard blanc', 'White fox', 'fox-white.8f5e5c27.png'],
    ['Jooki.White.Knight', 'Chevalier blanc', 'White knight', 'knight-white.b0dd9a37.png'],
    ['Jooki.White.Whale', 'Baleine blanche', 'White whale', 'whale-white.218d88b9.png'],
    ['G2.Orange', 'Jeton orange', 'Orange token', '#f28b24'],
    ['G2.DarkBlue', 'Jeton bleu foncé', 'Dark blue token', '#23408e'],
    ['G2.Turquoise', 'Jeton turquoise', 'Turquoise token', '#22b2ad'],
    ['G2.Yellow', 'Jeton jaune', 'Yellow token', '#f4c21b'],
    ['G2.Red', 'Jeton rouge', 'Red token', '#d7362c'],
    ['G2.Purple', 'Jeton violet', 'Purple token', '#7c4db4'],
    ['G2.Green', 'Jeton vert', 'Green token', '#3ba555'],
    ['G2.Pink', 'Jeton rose', 'Pink token', '#ec6ea6'],
    ['Jooki.Flat', 'Jeton plat', 'Flat token', 'flat.5534d75d.png'],
    ['Jooki.ThankYou', 'Jeton Merci', 'Thank-you token', 'flat.5534d75d.png']
  ];
  var CHAR = {};
  CHARS.forEach(function (c, i) { CHAR[c[0]] = { id: c[0], fr: c[1], en: c[2], art: c[3], order: i }; });
  function charInfo(id) {
    if (CHAR[id]) return CHAR[id];
    return { id: id, fr: id || '?', en: id || '?', art: null, order: 999 };
  }
  function charName(id) { var c = charInfo(id); return c[lang] || c.fr; }
  function isUserChar(id) { return !!id && id.indexOf('sys.') !== 0 && id.indexOf('test.') !== 0; }

  /* ------------------------------------------------------------------ helpers */
  function h(tag, attrs) {
    var el = document.createElement(tag);
    if (attrs) {
      for (var k in attrs) {
        var v = attrs[k];
        if (v === null || v === undefined || v === false) continue;
        if (k === 'class') el.className = v;
        else if (k === 'text') el.textContent = v;
        else if (k === 'html') el.innerHTML = v; // only used with static SVG icons
        else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
        else if (k === 'value') el.value = v;
        else if (k === 'checked') el.checked = !!v;
        else if (k === 'style') el.setAttribute('style', v);
        else el.setAttribute(k, v === true ? '' : v);
      }
    }
    for (var i = 2; i < arguments.length; i++) add(el, arguments[i]);
    return el;
  }
  function add(el, c) {
    if (c === null || c === undefined || c === false) return;
    if (Array.isArray(c)) { c.forEach(function (x) { add(el, x); }); return; }
    el.appendChild(typeof c === 'object' ? c : document.createTextNode(String(c)));
  }
  var ICONS = {
    list: '<path d="M4 6h16M4 12h16M4 18h10"/>',
    token: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/>',
    lib: '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    play: '<path d="M7 4.5v15l13-7.5z" fill="currentColor" stroke="none"/>',
    pause: '<path d="M7 4h4v16H7zM14 4h4v16h-4z" fill="currentColor" stroke="none"/>',
    next: '<path d="M5 5l10 7-10 7zM18 5v14" fill="currentColor"/>',
    prev: '<path d="M19 5L9 12l10 7zM6 5v14" fill="currentColor"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    upload: '<path d="M12 16V4M6 10l6-6 6 6M4 20h16"/>',
    radio: '<circle cx="12" cy="12" r="2"/><path d="M16.2 7.8a6 6 0 0 1 0 8.4M7.8 16.2a6 6 0 0 1 0-8.4M19 5a10 10 0 0 1 0 14M5 19A10 10 0 0 1 5 5"/>',
    trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
    x: '<path d="M6 6l12 12M18 6L6 18"/>',
    grip: '<path d="M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01" stroke-width="3"/>',
    edit: '<path d="M4 20h4L19 9l-4-4L4 16z"/>',
    back: '<path d="M15 5l-7 7 7 7"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
    check: '<path d="M5 12l5 5 9-10"/>',
    book: '<path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z"/><path d="M4 19V5"/>',
    shuffle: '<path d="M16 3h5v5M4 20L21 3M21 16v5h-5M15 15l6 6M4 4l5 5"/>',
    repeat: '<path d="M17 1l4 4-4 4"/><path d="M3 11V9a4 4 0 0 1 4-4h14M7 23l-4-4 4-4"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>',
    vol: '<path d="M11 5L6 9H2v6h4l5 4z"/><path d="M15.5 8.5a5 5 0 0 1 0 7M19 5a10 10 0 0 1 0 14"/>',
    power: '<path d="M12 2v10M18.4 6.6a9 9 0 1 1-12.8 0"/>',
    note: '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
    link0: '<path d="M8 12h8"/>',
    moon: '<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5z"/>',
    sort: '<path d="M4 6h9M4 12h7M4 18h5M17 4v16M14 17l3 3 3-3"/>'
  };
  function icon(name) {
    var s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('fill', 'none');
    s.setAttribute('stroke', 'currentColor');
    s.setAttribute('stroke-width', '2');
    s.setAttribute('stroke-linecap', 'round');
    s.setAttribute('stroke-linejoin', 'round');
    s.setAttribute('aria-hidden', 'true');
    s.innerHTML = ICONS[name] || '';
    return s;
  }
  function fmtTime(sec) {
    sec = Math.max(0, Math.round(Number(sec) || 0));
    var hh = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    if (hh) return hh + ':' + (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
    return m + ':' + (s < 10 ? '0' : '') + s;
  }
  function fmtTotal(sec) {
    sec = Math.round(Number(sec) || 0);
    var hh = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
    if (hh) return hh + ' h ' + (m < 10 ? '0' : '') + m;
    return m + ' min';
  }
  function fmtBytes(b) {
    b = Number(b) || 0;
    var u = lang === 'fr' ? ['o', 'Ko', 'Mo', 'Go'] : ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    while (b >= 1000 && i < u.length - 1) { b /= 1000; i++; }
    return (i ? b.toFixed(b < 10 ? 1 : 0) : b) + ' ' + u[i];
  }
  function obj(x) { return x && typeof x === 'object' && !Array.isArray(x) ? x : {}; }
  function arr(x) { return Array.isArray(x) ? x : []; }
  function cleanTitle(s) { return String(s || '').replace(/\.(mp3|m4a|mp4|aac|ogg|oga|flac|wav|wma)$/i, ''); }
  function collator() { try { return new Intl.Collator(lang, { numeric: true, sensitivity: 'base' }); } catch (e) { return { compare: function (a, b) { return a < b ? -1 : a > b ? 1 : 0; } }; } }

  /* ------------------------------------------------------------------ state */
  var S = { db: { playlists: {}, tracks: {}, tokens: {} }, audio: { config: {}, playback: {}, nowPlaying: {} }, nfc: {}, device: {}, power: {}, wifi: {}, userMessages: [], bedtime: {} };
  var gotState = false;
  function normalize() {
    S.db = obj(S.db);
    S.db.playlists = obj(S.db.playlists);
    S.db.tracks = obj(S.db.tracks);
    S.db.tokens = obj(S.db.tokens);
    delete S.db.tokens._;
    S.audio = obj(S.audio);
    S.audio.config = obj(S.audio.config);
    S.audio.playback = obj(S.audio.playback);
    S.audio.nowPlaying = obj(S.audio.nowPlaying);
    S.nfc = obj(S.nfc); S.device = obj(S.device); S.power = obj(S.power); S.wifi = obj(S.wifi);
    S.userMessages = arr(S.userMessages);
    S.net = obj(S.net);
    S.bedtime = obj(S.bedtime);
    S.bedtime.cfg = obj(S.bedtime.cfg);
    S.bedtime.resume = obj(S.bedtime.resume);
  }
  function mergeState(p) {
    if (!p || typeof p !== 'object') return;
    Object.keys(p).forEach(function (k) {
      if (k === 'audio' && p.audio && typeof p.audio === 'object' && !Array.isArray(p.audio)) {
        S.audio = obj(S.audio);
        Object.keys(p.audio).forEach(function (s) { S.audio[s] = p.audio[s]; });
        if (p.audio.playback) posStamp = Date.now();
      } else if (k === 'bedtime') {
        S.bedtime = p.bedtime;
        sleepStamp = Date.now();
      } else {
        S[k] = p[k];
      }
    });
    if (p.db) gotState = true;
    normalize();
  }
  var posStamp = Date.now(), sleepStamp = Date.now();
  function pls() { return S.db.playlists; }
  function userPlaylists() {
    var c = collator();
    return Object.keys(pls()).filter(function (id) { return id !== 'TRASH' && id !== 'system'; })
      .map(function (id) { return Object.assign({ id: id }, pls()[id]); })
      .sort(function (a, b) { return c.compare(a.title || '', b.title || ''); });
  }
  function trackTitle(id) { var tr = S.db.tracks[id]; if (!tr) return '?'; return cleanTitle(tr.title || tr.userFilename || id); }
  function trackSub(tr) {
    if (!tr) return '';
    if (tr.isUrl) return t('radio') + ' · ' + (tr.filename || '');
    var bits = [];
    if (tr.artist && tr.artist !== 'unknown') bits.push(tr.artist);
    if (tr.album && tr.album !== 'unknown') bits.push(tr.album);
    if (tr.duration) bits.push(fmtTime(tr.duration));
    return bits.join(' · ');
  }
  function playlistOfChar(starId) {
    var list = userPlaylists();
    for (var i = 0; i < list.length; i++) if (list[i].star === starId) return list[i];
    return null;
  }
  function unusedIds() { var tr = pls().TRASH; return tr ? arr(tr.tracks).filter(function (x) { return S.db.tracks[x]; }) : []; }

  /* ------------------------------------------------------------------ MQTT connection */
  var client = null, online = false, everOnline = false, retryDelay = 1000, retryTimer = null, lastCmd = 0;
  var wsHost = location.hostname || '127.0.0.1';
  function connect() {
    clearTimeout(retryTimer);
    if (client) { try { client.onclose = function () {}; client.close(); } catch (e) {} }
    var url = 'ws://' + (wsHost.indexOf(':') >= 0 ? '[' + wsHost + ']' : wsHost) + ':' + (CFG.wsPort || 8000) + '/mqtt';
    client = new window.MiniMqtt(url, { username: CFG.mqttUser, password: CFG.mqttPass, keepalive: 20 });
    client.onconnect = function () {
      online = true; everOnline = true; retryDelay = 1000;
      client.subscribe('/j/web/output/#');
      send('GET_STATE', {});
      render();
    };
    client.onmessage = onMessage;
    client.onclose = function () {
      var was = online;
      online = false;
      uploads.forEach(function (u) { if (u.status === 'processing') u.lost = true; });
      if (was || !everOnline) render();
      retryTimer = setTimeout(connect, retryDelay);
      retryDelay = Math.min(retryDelay * 1.6, 8000);
    };
    client.connect();
  }
  function send(type, payload) {
    lastCmd = Date.now();
    if (!client || !online) { toast(t('offline'), 'error'); return false; }
    return client.publish('/j/web/input/' + type, JSON.stringify(payload || {}));
  }
  var waiters = [], autoChecked = false;
  function onMessage(topic, text) {
    var data;
    try { data = JSON.parse(text); } catch (e) { return; }
    if (topic === '/j/web/output/state') {
      var posOnly = data && Object.keys(data).length === 1 && data.audio && Object.keys(data.audio).length === 1 && data.audio.playback &&
        obj(data.audio.playback).state === S.audio.playback.state;
      mergeState(data);
      if (posOnly) return;
      waiters = waiters.filter(function (w) { return !w(data); });
      if (!autoChecked && S.device.openjooki) { autoChecked = true; setTimeout(checkUpdate, 1500); }
      syncClock();
      handleUserMessages();
      scheduleRender();
    } else if (topic === '/j/web/output/error') {
      if (Date.now() - lastCmd < 4000) toast(errorText(data && data.msg), 'error');
    }
  }
  function errorText(msg) {
    msg = String(msg || '');
    if (msg === 'TRASH_READONLY') return t('err_readonly');
    if (msg === 'ERR_INTERNAL') return t('err_internal');
    if (msg === 'empty title') return t('err_empty_title');
    if (msg === 'invalid stream url') return t('err_radio');
    if (msg === 'invalid token type') return t('err_unknown_char');
    if (/does not exist|invalid:|nil playlistId|unknown token/.test(msg)) return t('err_gone');
    return t('err_generic');
  }
  var seenMsg = {};
  function handleUserMessages() {
    S.userMessages.forEach(function (m) {
      if (!m || seenMsg[m.id]) return;
      seenMsg[m.id] = true;
      var type = String(m.messageType || '');
      var ex = obj(m.extra);
      var mine = uploads.some(function (u) { return u.name === ex.filename && (u.status === 'processing' || u.status === 'uploading'); });
      if (type.indexOf('UPLOAD_FAIL') === 0) {
        uploads.forEach(function (u) {
          if (u.name === ex.filename && u.status === 'processing') { u.failType = type; }
        });
        if (!mine && ex.filename) toast(t(type === 'UPLOAD_FAIL_TYPE' ? 'up_type' : 'up_fail') + ' : ' + ex.filename, 'error');
      }
      if (client && online) client.publish('/j/web/input/MESSAGE_DISMISS', JSON.stringify({ id: m.id }));
    });
  }

  /* ------------------------------------------------------------------ toasts & modals */
  var toastBox;
  function toast(text, kind, action) {
    if (!toastBox) return;
    var el = h('div', { class: 'toast' + (kind === 'error' ? ' error' : ''), role: 'status' }, h('span', { class: 'grow' }, text));
    if (action) el.appendChild(h('button', { onclick: function () { action.fn(); el.remove(); } }, action.label));
    toastBox.appendChild(el);
    setTimeout(function () { el.remove(); }, action ? 6000 : 3500);
  }
  var modal = null; // {render: fn -> element, onclose}
  function openModal(m) { modal = m; renderModal(); }
  function closeModal() { var m = modal; modal = null; renderModal(); if (m && m.onclose) m.onclose(); }
  var modalRoot;
  function renderModal() {
    if (!modalRoot) return;
    var keep = captureFocus(modalRoot);
    modalRoot.innerHTML = '';
    if (!modal) { document.body.style.overflow = ''; return; }
    document.body.style.overflow = 'hidden';
    var sheet = h('div', { class: 'sheet', role: 'dialog', 'aria-modal': 'true' }, modal.render());
    var ov = h('div', { class: 'overlay', onclick: function (e) { if (e.target === ov) closeModal(); } }, sheet);
    modalRoot.appendChild(ov);
    restoreFocus(modalRoot, keep, modal.autofocus);
  }
  function confirmBox(title, text, okLabel, danger) {
    return new Promise(function (resolve) {
      var done = false;
      function fin(v) { if (done) return; done = true; modal = null; renderModal(); resolve(v); }
      openModal({
        onclose: function () { fin(false); },
        render: function () {
          return [h('h3', null, title), text ? h('p', { class: 'muted' }, text) : null,
            h('div', { class: 'foot' },
              h('button', { class: 'btn', onclick: function () { fin(false); } }, t('cancel')),
              h('button', { class: 'btn ' + (danger ? 'danger solid' : 'primary'), 'data-k': 'ok', onclick: function () { fin(true); } }, okLabel))];
        },
        autofocus: 'ok'
      });
    });
  }
  function captureFocus(root) {
    var a = document.activeElement;
    if (!a || !root.contains(a) || !a.getAttribute('data-k')) return null;
    return { k: a.getAttribute('data-k'), s: a.selectionStart, e: a.selectionEnd };
  }
  function restoreFocus(root, keep, auto) {
    var k = keep ? keep.k : auto;
    if (!k) return;
    var el = root.querySelector('[data-k="' + k + '"]');
    if (!el) return;
    el.focus({ preventScroll: true });
    if (keep && keep.s !== undefined && keep.s !== null && el.setSelectionRange) { try { el.setSelectionRange(keep.s, keep.e); } catch (e) {} }
  }

  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && modal) closeModal(); });

  /* ------------------------------------------------------------------ uploads */
  var uploads = [], upBusy = false, upSeq = 0;
  var AUDIO_EXT = /\.(mp3|m4a|mp4|aac|ogg|oga|flac|wav|wma|m4b)$/i;
  function enqueue(files, playlistId) {
    var free = S.device.diskUsage && Number(S.device.diskUsage.available) ? Number(S.device.diskUsage.available) * 1024 : null;
    var reserved = 0;
    Array.prototype.forEach.call(files, function (f) {
      var u = { key: ++upSeq, file: f, name: f.name, size: f.size, playlistId: playlistId || null, status: 'queued', progress: 0, error: null };
      if (f.size <= 5000) { u.status = 'error'; u.error = t('up_too_small'); }
      else if (!AUDIO_EXT.test(f.name) && !(f.type && f.type.indexOf('audio/') === 0)) { u.status = 'error'; u.error = t('up_type'); }
      else if (free !== null && reserved + f.size + 10e6 > free) { u.status = 'error'; u.error = t('up_no_space'); }
      else reserved += f.size;
      uploads.push(u);
    });
    render();
    pump();
  }
  // A weak Wi-Fi drops connections: a failed or stalled transfer is retried on its own
  // (after the Jooki is back), and a lost answer is checked again after reconnecting.
  var UP_TRIES = 4, UP_STALL_MS = 30000, UP_DELAYS = [3000, 8000, 20000];
  function pump() {
    if (upBusy) return;
    var now = Date.now();
    var u = uploads.filter(function (x) { return x.status === 'queued' && !(x.retryAt > now); })[0];
    if (!u) {
      var next = uploads.filter(function (x) { return x.status === 'queued'; }).map(function (x) { return x.retryAt; })[0];
      if (next) setTimeout(pump, Math.max(200, next - now));
      return;
    }
    if (!online) { setTimeout(pump, 1500); return; }
    upBusy = true;
    u.status = 'uploading'; u.progress = 0; u.tries = (u.tries || 0) + 1; u.note = null;
    var uid = String(Math.floor(Math.random() * 9e6) + 1e6);
    var fd = new FormData();
    fd.append(uid, u.file, u.name);
    var xhr = new XMLHttpRequest();
    var lastMove = Date.now(), ended = false;
    var stall = setInterval(function () { if (Date.now() - lastMove > UP_STALL_MS) { xhr.abort(); } }, 2000);
    function netFail(why) {
      if (ended) return; ended = true; clearInterval(stall);
      retryOrFail(u, why);
    }
    xhr.open('POST', '/upload');
    xhr.upload.onprogress = function (e) { lastMove = Date.now(); if (e.lengthComputable) { u.progress = e.loaded / e.total; updateUploadRow(u); } };
    xhr.onerror = xhr.ontimeout = xhr.onabort = function () { netFail(t('up_net')); };
    xhr.onload = function () {
      if (ended) return; ended = true; clearInterval(stall);
      if (xhr.status !== 200) { retryOrFail(u, t('up_net') + ' (' + xhr.status + ')'); return; }
      u.progress = 1;
      u.status = 'processing';
      render();
      var beforePl = u.playlistId && pls()[u.playlistId] ? arr(pls()[u.playlistId].tracks).length : -1;
      var beforeLib = Object.keys(S.db.tracks).length;
      var p = { uploadId: uid, filename: u.name };
      if (u.playlistId) p.playlistId = u.playlistId;
      var resent = false;
      u.lost = false;
      var timer = setTimeout(function () { finishUp(u, 'error', t('up_timeout')); }, 240000);
      function added() {
        if (u.playlistId) return pls()[u.playlistId] && arr(pls()[u.playlistId].tracks).length > beforePl;
        return Object.keys(S.db.tracks).length > beforeLib;
      }
      waiters.push(function (partial) {
        if (u.status !== 'processing') return true;
        if (partial.audio) {                 // full state after a reconnection: did the Jooki get it?
          if (!u.lost) return false;
          u.lost = false;
          if (added()) { clearTimeout(timer); finishUp(u, 'done'); return true; }
          if (!resent) { resent = true; send('PLAYLIST_ADD_UPLOAD', p); }
          return false;
        }
        if (!(partial.db && partial.device)) return false; // end of an upload request
        clearTimeout(timer);
        if (u.failType) { finishUp(u, 'error', t(u.failType === 'UPLOAD_FAIL_TYPE' ? 'up_type' : 'up_fail')); return true; }
        if (u.playlistId && pls()[u.playlistId] && arr(pls()[u.playlistId].tracks).length <= beforePl) {
          if (resent && !u.failType) { finishUp(u, 'done'); return true; } // first request had worked
          finishUp(u, 'error', t('up_fail')); return true;
        }
        finishUp(u, 'done');
        return true;
      });
      if (!send('PLAYLIST_ADD_UPLOAD', p)) u.lost = true;
    };
    xhr.send(fd);
    render();
  }
  function retryOrFail(u, why) {
    upBusy = false;
    if (u.tries < UP_TRIES && u.file) {
      u.status = 'queued'; u.progress = 0;
      u.retryAt = Date.now() + UP_DELAYS[Math.min(u.tries - 1, UP_DELAYS.length - 1)];
      u.note = t('up_retrying', u.tries + 1, UP_TRIES);
      render(); setTimeout(pump, 50);
      return;
    }
    u.status = 'error'; u.error = why; u.canRetry = !!u.file;
    render(); setTimeout(pump, 50);
  }
  function retryUpload(u) { u.status = 'queued'; u.tries = 0; u.retryAt = 0; u.error = null; u.canRetry = false; render(); pump(); }
  function finishUp(u, status, err) {
    if (u.status === 'done' || u.status === 'error') return;
    u.status = status; u.error = err || null; u.file = null; u.note = null;
    upBusy = false;
    render();
    setTimeout(pump, 50);
  }
  function uploadsActive() { return uploads.some(function (u) { return u.status === 'queued' || u.status === 'uploading' || u.status === 'processing'; }); }
  window.addEventListener('beforeunload', function (e) { if (uploadsActive()) { e.preventDefault(); e.returnValue = t('uploads_running'); return e.returnValue; } });
  function updateUploadRow(u) {
    var el = document.querySelector('[data-up="' + u.key + '"] .bar > i');
    if (el) el.style.width = Math.round(u.progress * 100) + '%';
    var st = document.querySelector('[data-up="' + u.key + '"] .st');
    if (st) st.textContent = t('uploading') + ' ' + Math.round(u.progress * 100) + ' %';
  }
  function uploadsBlock(playlistId) {
    var list = uploads.filter(function (u) { return u.playlistId === (playlistId || null); });
    if (!list.length) return null;
    var anyDone = list.some(function (u) { return u.status === 'done' || u.status === 'error'; });
    return h('div', { class: 'card uploads' },
      list.map(function (u) {
        var st = u.status === 'queued' ? (u.note || t('queued')) : u.status === 'uploading' ? t('uploading') + ' ' + Math.round(u.progress * 100) + ' %'
          : u.status === 'processing' ? t('processing') : u.status === 'done' ? t('done') : u.error;
        return h('div', { class: 'up ' + u.status, 'data-up': u.key },
          h('div', { class: 'row' }, h('div', { class: 'grow ellipsis' }, u.name), h('span', { class: 'small muted' }, fmtBytes(u.size))),
          h('div', { class: 'bar' }, h('i', { style: 'width:' + (u.status === 'done' || u.status === 'processing' ? 100 : Math.round(u.progress * 100)) + '%' })),
          h('div', { class: 'st row' }, h('span', { class: 'grow' }, st),
            u.status === 'error' && u.canRetry ? h('button', { class: 'btn ghost', 'data-k': 'upretry-' + u.key, onclick: function () { retryUpload(u); } }, t('up_retry')) : null));
      }),
      anyDone && !uploadsActive() ? h('div', { class: 'up' }, h('button', { class: 'btn ghost block', onclick: function () {
        uploads = uploads.filter(function (u) { return u.playlistId !== (playlistId || null) || (u.status !== 'done' && u.status !== 'error'); }); render();
      } }, t('clear_done'))) : null);
  }
  function fileButton(label, playlistId, primary) {
    var inp = h('input', { type: 'file', multiple: true, accept: 'audio/*,.mp3,.m4a,.m4b,.aac,.ogg,.oga,.flac,.wav,.wma', class: 'sr', 'aria-hidden': 'true', tabindex: '-1',
      onchange: function () { if (inp.files && inp.files.length) enqueue(inp.files, playlistId); inp.value = ''; } });
    return h('label', { class: 'btn' + (primary ? ' primary' : ''), tabindex: '0', role: 'button',
      onkeydown: function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); inp.click(); } } }, icon('upload'), label, inp);
  }
  function dropZone(playlistId) {
    var z = h('div', { class: 'drop' }, t('drop_here'), h('div', { class: 'small' }, t('files_hint')));
    z.addEventListener('dragover', function (e) { e.preventDefault(); z.classList.add('over'); });
    z.addEventListener('dragleave', function () { z.classList.remove('over'); });
    z.addEventListener('drop', function (e) { e.preventDefault(); z.classList.remove('over'); if (e.dataTransfer && e.dataTransfer.files.length) enqueue(e.dataTransfer.files, playlistId); });
    return z;
  }
  var canHover = window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)').matches;

  /* ------------------------------------------------------------------ token visuals */
  function tokVisual(starId, cls, live) {
    var c = charInfo(starId);
    var el = h('div', { class: 'tok ' + (cls || '') + (live ? ' live' : ''), title: charName(starId) });
    if (!starId) { el.className += ' none'; el.appendChild(icon('token')); return el; }
    if (c.art && c.art.charAt(0) === '#') el.appendChild(h('div', { class: 'disc', style: 'background:' + c.art }));
    else if (c.art) {
      var img = h('img', { src: MEDIA + c.art, alt: '' });
      img.onerror = function () { img.replaceWith(h('span', { class: 'letter' }, (charName(starId) || '?').charAt(0))); };
      el.appendChild(img);
    } else el.appendChild(h('span', { class: 'letter' }, (charName(starId) || '?').charAt(0)));
    return el;
  }

  /* ------------------------------------------------------------------ routing */
  function route() {
    var hs = (location.hash || '#/').replace(/^#/, '');
    var parts = hs.split('/').filter(Boolean).map(function (x) { try { return decodeURIComponent(x); } catch (e) { return x; } });
    return { name: parts[0] || 'playlists', arg: parts[1] || null };
  }
  function go(hash) { if (location.hash !== hash) location.hash = hash; else render(); }
  window.addEventListener('hashchange', function () { ui.sel = {}; ui.search = ''; ui.editTitle = null; window.scrollTo(0, 0); render(); });

  /* ------------------------------------------------------------------ UI state */
  var ui = { search: '', sel: {}, editTitle: null, dragging: false, libTab: 'all' };

  /* ------------------------------------------------------------------ views */
  function viewPlaylists() {
    var list = userPlaylists();
    var np = S.audio.nowPlaying;
    var un = unusedIds().length;
    var cards = list.map(function (p) {
      var n = arr(p.tracks).length;
      var card = h('div', { class: 'card pl' + (np.playlistId === p.id ? ' active' : ''), role: 'link', tabindex: '0', 'data-pl': p.id,
        onclick: function () { go('#/p/' + encodeURIComponent(p.id)); },
        onkeydown: function (e) { if (e.key === 'Enter') go('#/p/' + encodeURIComponent(p.id)); } },
        h('div', { class: 'ph' }, tokVisual(p.star, 'sm', S.nfc.starId && S.nfc.starId === p.star)),
        h('div', { class: 'name' }, p.title || '—'),
        h('div', { class: 'meta' }, t('n_tracks', n) + (p.audiobook ? ' · ' + t('audiobook') : '')),
        n ? h('button', { class: 'icon-btn accent play', 'aria-label': t('play') + ' ' + (p.title || ''), onclick: function (e) {
          e.stopPropagation(); send('PLAYLIST_PLAY', { playlistId: p.id }); } }, icon('play')) : null);
      return card;
    });
    cards.push(h('button', { class: 'card pl newpl', onclick: newPlaylistModal, 'data-k': 'newpl' }, icon('plus'), t('new_playlist')));
    return [
      updateAvailable() && upd.state === 'checked' ? h('div', { class: 'banner row', 'data-k': 'updbanner' }, h('span', { class: 'grow' }, t('upd_banner', upd.latest)),
        h('a', { href: '#/settings' }, t('upd_see'))) : null,
      un ? h('div', { class: 'banner row' }, h('span', { class: 'grow' }, t('unused_banner', un)),
        h('a', { href: '#/library/unused' }, t('see'))) : null,
      list.length ? null : h('div', { class: 'empty' }, h('div', { class: 'big' }, '🎵'), t('no_playlists')),
      h('div', { class: 'plgrid' }, cards)
    ];
  }

  function newPlaylistModal(prefillTracks) {
    var name = '';
    function create() {
      var v = name.trim();
      if (!v) return;
      var before = Object.keys(pls());
      closeModal();
      waiters.push(function (partial) {
        if (!partial.db) return false;
        var fresh = Object.keys(pls()).filter(function (k) { return before.indexOf(k) < 0 && k !== 'TRASH'; })[0];
        if (!fresh) return false;
        if (Array.isArray(prefillTracks) && prefillTracks.length) {
          send('PLAYLIST_UPDATE', { playlist: { id: fresh, tracks: prefillTracks } });
          toast(t('added', prefillTracks.length));
        } else go('#/p/' + encodeURIComponent(fresh));
        return true;
      });
      send('PLAYLIST_NEW', { title: v, audiobook: false });
    }
    openModal({
      autofocus: 'plname',
      render: function () {
        return [h('h3', null, t('new_playlist')),
          h('label', { class: 'field' }, h('span', null, t('name')),
            h('input', { class: 'input', 'data-k': 'plname', maxlength: '100', placeholder: t('playlist_name_ph'), value: name,
              oninput: function (e) { name = e.target.value; var b = document.querySelector('[data-k="plcreate"]'); if (b) b.disabled = !name.trim(); },
              onkeydown: function (e) { if (e.key === 'Enter') create(); } })),
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
            h('button', { class: 'btn primary', 'data-k': 'plcreate', disabled: !name.trim(), onclick: create }, t('create')))];
      }
    });
  }

  function charPickerModal(p) {
    var chosen = p.star || null;
    var seen = {};
    Object.keys(S.db.tokens).forEach(function (k) { var s = S.db.tokens[k] && S.db.tokens[k].starId; if (isUserChar(s)) seen[s] = true; });
    function opt(id) {
      var other = id ? playlistOfChar(id) : null;
      if (other && other.id === p.id) other = null;
      return h('button', { class: 'charopt' + (chosen === id ? ' sel' : ''), 'data-char': id || 'none', 'aria-pressed': chosen === id ? 'true' : 'false',
        onclick: function () { chosen = id; renderModal(); } },
        tokVisual(id, 'sm'), h('div', null, id ? charName(id) : t('no_token')), other ? h('div', { class: 'taken' }, t('used_by', other.title || '—')) : null);
    }
    var ids = CHARS.map(function (c) { return c[0]; }).filter(function (id) { return id !== 'Jooki.ThankYou'; });
    Object.keys(seen).forEach(function (s) { if (ids.indexOf(s) < 0) ids.push(s); });
    ids.sort(function (a, b) { return (seen[b] ? 1 : 0) - (seen[a] ? 1 : 0) || charInfo(a).order - charInfo(b).order; });
    openModal({
      render: function () {
        var other = chosen ? playlistOfChar(chosen) : null;
        if (other && other.id === p.id) other = null;
        return [h('h3', null, t('token_for')), h('p', { class: 'small muted' }, t('token_help')),
          h('div', { class: 'chargrid' }, opt(null), ids.map(opt)),
          other ? h('div', { class: 'banner', style: 'margin-top:12px' }, t('token_moved', other.title || '—')) : null,
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
            h('button', { class: 'btn primary', 'data-k': 'charsave', onclick: function () {
              if ((chosen || null) !== (p.star || null)) send('PLAYLIST_UPDATE', { playlist: { id: p.id, star: chosen || false } });
              closeModal();
            } }, t('save')))];
      }
    });
  }

  function viewPlaylist(id) {
    if (id === 'TRASH') { setTimeout(function () { go('#/library/unused'); }, 0); return []; }
    var p = pls()[id];
    if (!p) return h('div', { class: 'empty' }, h('p', null, t('playlist_missing')), h('a', { class: 'btn', href: '#/' }, t('back')));
    p = Object.assign({ id: id }, p);
    var tracks = arr(p.tracks);
    var np = S.audio.nowPlaying;
    var total = tracks.reduce(function (s, x) { var tr = S.db.tracks[x]; return s + (tr && !tr.isUrl ? Number(tr.duration) || 0 : 0); }, 0);
    var editing = ui.editTitle !== null;
    function saveTitle() {
      var v = (ui.editTitle || '').trim();
      if (!v) { toast(t('err_empty_title'), 'error'); return; }
      if (v !== p.title) send('PLAYLIST_UPDATE', { playlist: { id: id, title: v } });
      ui.editTitle = null; render();
    }
    var head = h('div', { class: 'card plhead' },
      h('button', { class: 'tokbtn', 'aria-label': t('choose_token'), onclick: function () { charPickerModal(p); }, 'data-k': 'tokbtn' },
        tokVisual(p.star, '', S.nfc.starId && S.nfc.starId === p.star)),
      h('div', { class: 'grow' },
        editing ? h('div', { class: 'edit-title' },
          h('input', { class: 'input', 'data-k': 'title', maxlength: '100', value: ui.editTitle, 'aria-label': t('name'),
            oninput: function (e) { ui.editTitle = e.target.value; },
            onkeydown: function (e) { if (e.key === 'Enter') saveTitle(); if (e.key === 'Escape') { e.stopPropagation(); ui.editTitle = null; render(); } } }),
          h('button', { class: 'icon-btn', 'aria-label': t('save'), onclick: saveTitle }, icon('check')),
          h('button', { class: 'icon-btn', 'aria-label': t('cancel'), onclick: function () { ui.editTitle = null; render(); } }, icon('x')))
          : h('h2', { class: 'row' }, h('span', { class: 'grow' }, p.title || '—'),
            h('button', { class: 'icon-btn', 'aria-label': t('rename'), 'data-k': 'renamebtn', onclick: function () { ui.editTitle = p.title || ''; render(); setTimeout(function () {
              var el = document.querySelector('[data-k="title"]'); if (el) { el.focus(); el.select(); } }, 0); } }, icon('edit'))),
        h('div', { class: 'small muted' }, (p.star ? charName(p.star) : t('no_token')) + ' · ' + t('n_tracks', tracks.length) + (total ? ' · ' + fmtTotal(total) : ''))));
    var actions = h('div', { class: 'actions' },
      tracks.length ? h('button', { class: 'btn primary', onclick: function () { send('PLAYLIST_PLAY', { playlistId: id }); } }, icon('play'), t('play')) : null,
      fileButton(t('add_files'), id, !tracks.length),
      h('button', { class: 'btn', onclick: function () { libraryPickerModal(p); } }, icon('lib'), t('from_library')),
      h('button', { class: 'btn', onclick: function () { radioModal(p); } }, icon('radio'), t('web_radio')));
    var list;
    if (!tracks.length) {
      list = h('div', { class: 'card empty' }, h('div', { class: 'big' }, '🎶'), h('div', null, t('empty_playlist')), h('div', { class: 'small' }, t('empty_playlist_hint')));
    } else {
      list = h('ul', { class: 'card list', 'data-list': 'tracks' }, tracks.map(function (tid, i) {
        var tr = S.db.tracks[tid];
        var playing = np.playlistId === id && np.trackIndex === i + 1;
        return h('li', { class: 'clickable' + (playing ? ' playing' : ''), 'data-i': i, 'data-track': tid,
          onclick: function (e) { if (e.target.closest('button,.handle')) return; send('PLAYLIST_PLAY', { playlistId: id, trackIndex: i + 1 }); } },
          h('span', { class: 'handle', 'aria-hidden': 'true', onpointerdown: function (e) { startDrag(e, id); } }, icon('grip')),
          h('span', { class: 'num' }, playing ? '♪' : String(i + 1)),
          h('div', { class: 'grow' }, h('div', { class: 'title ellipsis' }, trackTitle(tid)), h('div', { class: 'sub ellipsis' }, trackSub(tr))),
          h('button', { class: 'icon-btn', 'aria-label': t('removed_from') + ' : ' + trackTitle(tid), 'data-remove': i, onclick: function () {
            var old = tracks.slice();
            var nt = tracks.slice(); nt.splice(i, 1);
            optimisticTracks(id, nt);
            send('PLAYLIST_UPDATE', { playlist: { id: id, tracks: nt } });
            toast(t('removed_from'), null, { label: t('undo'), fn: function () { optimisticTracks(id, old); send('PLAYLIST_UPDATE', { playlist: { id: id, tracks: old } }); } });
          } }, icon('x')));
      }));
    }
    var rs = p.audiobook ? S.bedtime.resume[id] : null;
    var ri = rs ? tracks.indexOf(rs.id) : -1;
    var sorted = sortedTracks(tracks);
    var unsorted = tracks.length > 1 && sorted.join('|') !== tracks.join('|');
    var more = h('div', { class: 'card', style: 'margin-top:16px' },
      h('label', { class: 'switch' }, h('div', null, h('div', null, t('audiobook')), h('div', { class: 'small muted' }, t('audiobook_help'))),
        h('input', { type: 'checkbox', role: 'switch', checked: !!p.audiobook, 'data-k': 'audiobook', onchange: function (e) { send('PLAYLIST_UPDATE', { playlist: { id: id, audiobook: e.target.checked } }); } })),
      p.audiobook && S.bedtime.cfg.start !== undefined && tracks.length ? h('div', { class: 'kv col', 'data-k': 'resume' },
        h('span', { class: 'muted' }, ri >= 0 ? t('resume_at', ri + 1, Number(rs.pos) > 20000 ? fmtTime((Number(rs.pos) - 15000) / 1000) : '') : t('resume_done')),
        ri >= 0 ? h('button', { class: 'btn ghost', 'data-k': 'resumereset', onclick: function () { send('OJ_RESUME_RESET', { playlistId: id }); } }, t('resume_restart')) : null) : null,
      unsorted ? h('div', { class: 'kv' }, h('button', { class: 'btn ghost block', 'data-k': 'sorttracks', onclick: function () {
        optimisticTracks(id, sorted);
        send('PLAYLIST_UPDATE', { playlist: { id: id, tracks: sorted } });
        toast(t('sorted'));
      } }, icon('sort'), t('sort_tracks'))) : null);
    var del = h('div', { class: 'actions' }, h('button', { class: 'btn danger', onclick: function () {
      confirmBox(t('delete_playlist_q', p.title || '—'), t('delete_playlist_text'), t('delete'), true).then(function (ok) {
        if (!ok) return;
        send('PLAYLIST_DELETE', { playlistId: id });
        go('#/');
      });
    } }, icon('trash'), t('delete_playlist')));
    return [head, actions, uploadsBlock(id), canHover ? dropZone(id) : null, list, more, del];
  }
  function optimisticTracks(id, tracks) { if (pls()[id]) { pls()[id].tracks = tracks; render(); } }

  /* drag & drop reorder (mouse + touch through pointer events) */
  var drag = null;
  function startDrag(e, playlistId) {
    var li = e.target.closest('li');
    if (!li) return;
    e.preventDefault();
    var ul = li.parentNode;
    var items = Array.prototype.slice.call(ul.children);
    var from = items.indexOf(li);
    var rect = li.getBoundingClientRect();
    drag = { li: li, ul: ul, from: from, to: from, startY: e.clientY, h: rect.height, id: playlistId, items: items, pointer: e.pointerId };
    ui.dragging = true;
    li.classList.add('dragging');
    try { li.setPointerCapture(e.pointerId); } catch (x) {}
    li.addEventListener('pointermove', onDragMove);
    li.addEventListener('pointerup', onDragEnd);
    li.addEventListener('pointercancel', onDragEnd);
  }
  function onDragMove(e) {
    if (!drag) return;
    var dy = e.clientY - drag.startY;
    drag.li.style.transform = 'translateY(' + dy + 'px)';
    var to = Math.max(0, Math.min(drag.items.length - 1, drag.from + Math.round(dy / drag.h)));
    drag.to = to;
    drag.items.forEach(function (it, i) {
      if (it === drag.li) return;
      var shift = 0;
      if (drag.from < to && i > drag.from && i <= to) shift = -drag.h;
      if (drag.from > to && i < drag.from && i >= to) shift = drag.h;
      it.style.transform = shift ? 'translateY(' + shift + 'px)' : '';
      it.style.transition = 'transform .12s';
    });
    var vh = window.innerHeight;
    if (e.clientY < 80) window.scrollBy(0, -12); else if (e.clientY > vh - 150) window.scrollBy(0, 12);
  }
  function onDragEnd() {
    if (!drag) return;
    var d = drag; drag = null; ui.dragging = false;
    d.items.forEach(function (it) { it.style.transform = ''; it.style.transition = ''; });
    d.li.classList.remove('dragging');
    d.li.removeEventListener('pointermove', onDragMove);
    d.li.removeEventListener('pointerup', onDragEnd);
    d.li.removeEventListener('pointercancel', onDragEnd);
    if (d.to !== d.from && pls()[d.id]) {
      var nt = arr(pls()[d.id].tracks).slice();
      var x = nt.splice(d.from, 1)[0];
      nt.splice(d.to, 0, x);
      optimisticTracks(d.id, nt);
      send('PLAYLIST_UPDATE', { playlist: { id: d.id, tracks: nt } });
    } else render();
  }

  function libraryPickerModal(p) {
    var q = '', sel = {};
    var inPl = {};
    arr(p.tracks).forEach(function (x) { inPl[x] = true; });
    function ids() {
      var c = collator();
      var all = Object.keys(S.db.tracks).filter(function (k) { return !S.db.tracks[k].isUrl; });
      var qq = q.trim().toLowerCase();
      if (qq) all = all.filter(function (k) { var tr = S.db.tracks[k]; return [trackTitle(k), tr.artist, tr.album].join(' ').toLowerCase().indexOf(qq) >= 0; });
      return all.sort(function (a, b) {
        var ta = S.db.tracks[a], tb = S.db.tracks[b];
        return c.compare(ta.album || '', tb.album || '') || c.compare(trackTitle(a), trackTitle(b));
      });
    }
    function count() { return Object.keys(sel).filter(function (k) { return sel[k] && S.db.tracks[k]; }).length; }
    openModal({
      autofocus: 'libq',
      render: function () {
        var list = ids();
        return [h('h3', null, t('from_library') + ' → ' + (p.title || '')),
          h('div', { class: 'search' }, icon('search'), h('input', { class: 'input', 'data-k': 'libq', placeholder: t('search'), value: q,
            oninput: function (e) { q = e.target.value; renderModal(); } })),
          list.length ? h('ul', { class: 'list card', style: 'max-height:50vh;overflow:auto;box-shadow:none;border:1px solid var(--line)' }, list.map(function (k) {
            var tr = S.db.tracks[k];
            return h('li', { class: 'clickable', onclick: function (e) { if (e.target.tagName !== 'INPUT') { sel[k] = !sel[k]; renderModal(); } } },
              h('input', { type: 'checkbox', class: 'check', checked: !!sel[k], 'aria-label': trackTitle(k), onchange: function (e) { sel[k] = e.target.checked; renderModal(); } }),
              h('div', { class: 'grow' }, h('div', { class: 'title ellipsis' }, trackTitle(k)), h('div', { class: 'sub ellipsis' }, trackSub(tr))),
              inPl[k] ? h('span', { class: 'badge' }, t('already_in')) : null);
          })) : h('div', { class: 'empty' }, t('library_empty')),
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
            h('button', { class: 'btn primary', disabled: !count(), 'data-k': 'libadd', onclick: function () {
              var chosen = Object.keys(sel).filter(function (k) { return sel[k] && S.db.tracks[k]; });
              var cur = pls()[p.id] ? arr(pls()[p.id].tracks) : [];
              var nt = cur.concat(chosen);
              send('PLAYLIST_UPDATE', { playlist: { id: p.id, tracks: nt } });
              closeModal(); toast(t('added', chosen.length));
            } }, count() ? t('add_n', count()) : t('add')))];
      }
    });
  }

  function radioModal(p) {
    var name = '', url = '', err = '';
    function ok() {
      var u = url.trim();
      if (!/^https?:\/\/[\w\[]/i.test(u)) { err = t('radio_url_bad'); renderModal(); return; }
      send('PLAYLIST_ADD_STREAM', { playlistId: p.id, title: name.trim() || u, url: u });
      closeModal();
    }
    openModal({
      autofocus: 'rname',
      render: function () {
        return [h('h3', null, t('radio_title')),
          h('label', { class: 'field' }, h('span', null, t('radio_name')), h('input', { class: 'input', 'data-k': 'rname', value: name, maxlength: '100', oninput: function (e) { name = e.target.value; } })),
          h('label', { class: 'field' }, h('span', null, t('radio_url')), h('input', { class: 'input', 'data-k': 'rurl', type: 'url', inputmode: 'url', value: url, placeholder: 'https://',
            oninput: function (e) { url = e.target.value; }, onkeydown: function (e) { if (e.key === 'Enter') ok(); } })),
          err ? h('div', { class: 'banner danger' }, err) : null,
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')), h('button', { class: 'btn primary', onclick: ok }, t('add')))];
      }
    });
  }

  function viewLibrary(tab) {
    tab = tab === 'unused' ? 'unused' : 'all';
    var un = unusedIds();
    var unSet = {}; un.forEach(function (x) { unSet[x] = true; });
    var where = {};
    userPlaylists().forEach(function (p) { arr(p.tracks).forEach(function (x) { (where[x] = where[x] || []).push(p.title || '—'); }); });
    var c = collator();
    var all = Object.keys(S.db.tracks).filter(function (k) { return tab === 'all' || unSet[k]; });
    var qq = ui.search.trim().toLowerCase();
    if (qq) all = all.filter(function (k) { var tr = S.db.tracks[k]; return [trackTitle(k), tr.artist, tr.album].join(' ').toLowerCase().indexOf(qq) >= 0; });
    all.sort(function (a, b) { var ta = S.db.tracks[a], tb = S.db.tracks[b]; return c.compare(ta.album || '', tb.album || '') || c.compare(trackTitle(a), trackTitle(b)); });
    Object.keys(ui.sel).forEach(function (k) { if (all.indexOf(k) < 0) delete ui.sel[k]; });
    var chosen = all.filter(function (k) { return ui.sel[k]; });
    var nAll = Object.keys(S.db.tracks).length;
    return [
      h('div', { class: 'tabs', role: 'tablist' },
        h('button', { class: tab === 'all' ? 'on' : '', role: 'tab', 'aria-selected': String(tab === 'all'), onclick: function () { go('#/library'); } }, t('all') + ' (' + nAll + ')'),
        h('button', { class: tab === 'unused' ? 'on' : '', role: 'tab', 'aria-selected': String(tab === 'unused'), onclick: function () { go('#/library/unused'); } }, t('unused') + ' (' + un.length + ')')),
      h('div', { class: 'actions' }, fileButton(t('add_files'), null, false)),
      uploadsBlock(null),
      h('div', { class: 'search' }, icon('search'), h('input', { class: 'input', 'data-k': 'libsearch', placeholder: t('search'), value: ui.search,
        oninput: function (e) { ui.search = e.target.value; render(); } })),
      all.length ? h('ul', { class: 'card list' }, all.map(function (k) {
        var tr = S.db.tracks[k];
        var w = where[k];
        return h('li', { class: 'clickable', 'data-track': k, onclick: function (e) { if (e.target.tagName !== 'INPUT') { ui.sel[k] = !ui.sel[k]; render(); } } },
          h('input', { type: 'checkbox', class: 'check', checked: !!ui.sel[k], 'aria-label': trackTitle(k), onchange: function (e) { ui.sel[k] = e.target.checked; render(); } }),
          h('div', { class: 'grow' }, h('div', { class: 'title ellipsis' }, (tr.isUrl ? '📻 ' : '') + trackTitle(k)),
            h('div', { class: 'sub ellipsis' }, trackSub(tr)),
            h('div', { class: 'sub ellipsis' }, w ? t('in_playlists') + w.join(', ') : t('in_none'))));
      })) : h('div', { class: 'card empty' }, tab === 'unused' ? t('unused_empty') : t('library_empty')),
      chosen.length ? h('div', { class: 'card selbar' },
        h('span', { class: 'grow small' }, t('selected', chosen.length)),
        h('button', { class: 'btn primary', onclick: function () { addToPlaylistModal(chosen); } }, t('add_to')),
        tab === 'unused' ? h('button', { class: 'btn danger', onclick: function () {
          confirmBox(t('delete_forever_q', chosen.length), t('delete_forever_text'), t('delete'), true).then(function (ok) {
            if (!ok) return;
            var keep = unusedIds().filter(function (x) { return chosen.indexOf(x) < 0; });
            send('PLAYLIST_UPDATE', { playlist: { id: 'TRASH', tracks: keep } });
            ui.sel = {}; toast(t('deleted'));
          });
        } }, icon('trash'), t('delete_forever')) : null) : null
    ];
  }

  function addToPlaylistModal(ids) {
    var list = userPlaylists();
    openModal({
      render: function () {
        return [h('h3', null, t('choose_playlist')),
          h('ul', { class: 'list card', style: 'box-shadow:none;border:1px solid var(--line)' },
            list.map(function (p) {
              return h('li', { class: 'clickable', 'data-pl': p.id, onclick: function () {
                var cur = arr(pls()[p.id] && pls()[p.id].tracks);
                send('PLAYLIST_UPDATE', { playlist: { id: p.id, tracks: cur.concat(ids) } });
                ui.sel = {}; closeModal(); toast(t('added', ids.length)); render();
              } }, tokVisual(p.star, 'xs'), h('div', { class: 'grow' }, h('div', { class: 'title' }, p.title || '—'), h('div', { class: 'sub' }, t('n_tracks', arr(p.tracks).length))));
            }),
            h('li', { class: 'clickable', onclick: function () { closeModal(); newPlaylistModal(ids); ui.sel = {}; } },
              h('div', { class: 'tok xs none' }, icon('plus')), h('div', { class: 'grow title' }, t('new_playlist')))),
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')))];
      }
    });
  }

  var nameDraft = {};
  function viewTokens() {
    var groups = {};
    Object.keys(S.db.tokens).forEach(function (tag) {
      var tk = S.db.tokens[tag];
      if (!tk || !isUserChar(tk.starId)) return;
      (groups[tk.starId] = groups[tk.starId] || []).push(tag);
    });
    var linkedOnly = userPlaylists().filter(function (p) { return p.star && !groups[p.star]; }).map(function (p) { return p.star; });
    var ids = Object.keys(groups).sort(function (a, b) { return charInfo(a).order - charInfo(b).order; });
    function charCard(sid) {
      var p = playlistOfChar(sid);
      var tags = (groups[sid] || []).sort();
      var sel = h('select', { class: 'input', 'aria-label': t('launches') + ' — ' + charName(sid), 'data-char-select': sid, onchange: function (e) {
        var v = e.target.value;
        e.target.blur();
        if (v) send('PLAYLIST_UPDATE', { playlist: { id: v, star: sid } });
        else if (p) send('PLAYLIST_UPDATE', { playlist: { id: p.id, star: false } });
      } }, h('option', { value: '' }, t('none_dash')), userPlaylists().map(function (x) { return h('option', { value: x.id, selected: p && p.id === x.id ? 'selected' : null }, x.title || '—'); }));
      if (p) sel.value = p.id; else sel.value = '';
      return h('div', { class: 'card', style: 'padding:14px 16px;margin-bottom:12px', 'data-char': sid },
        h('div', { class: 'row' }, tokVisual(sid, '', S.nfc.starId === sid),
          h('div', { class: 'grow' }, h('div', { class: 'title', style: 'font-weight:700;font-size:17px' }, charName(sid)),
            h('div', { class: 'small muted' }, tags.length ? tags.length + ' × ' + (lang === 'fr' ? 'jeton' + (tags.length > 1 ? 's' : '') : 'token' + (tags.length > 1 ? 's' : '')) : ''))),
        h('label', { class: 'field' }, h('span', null, t('launches')), sel),
        tags.map(function (tag, i) {
          var tk = S.db.tokens[tag] || {};
          var live = S.nfc.tagId === tag;
          var key = 'name-' + tag;
          var val = nameDraft[tag] !== undefined ? nameDraft[tag] : (tk.name || '');
          function commit() {
            if (rendering || nameDraft[tag] === undefined) return;
            var v = nameDraft[tag].trim();
            delete nameDraft[tag];
            if (v !== (tk.name || '')) { send('TOKEN_EDIT', { tagId: tag, name: v }); toast(t('saved')); }
          }
          return h('div', { class: 'physical', 'data-tag': tag },
            h('span', { class: 'badge' + (live ? ' accent' : '') }, live ? t('on_jooki') : t('token_n', i + 1)),
            h('input', { class: 'input grow', 'data-k': key, value: val, maxlength: '60', placeholder: t('token_name_ph'), 'aria-label': t('token_n', i + 1),
              oninput: function (e) { nameDraft[tag] = e.target.value; },
              onblur: commit, onkeydown: function (e) { if (e.key === 'Enter') { e.target.blur(); } } }),
            h('button', { class: 'icon-btn', 'aria-label': t('forget'), title: t('forget'), onclick: function () {
              confirmBox(t('forget_q'), t('forget_text'), t('forget'), true).then(function (ok) { if (ok) send('TOKEN_DELETE', { tagId: tag }); });
            } }, icon('x')));
        }));
    }
    return [
      h('p', { class: 'muted', style: 'margin-top:0' }, t('tokens_intro')),
      ids.length ? ids.map(charCard) : h('div', { class: 'card empty' }, h('div', { class: 'big' }, '🐉'), t('no_tokens')),
      linkedOnly.length ? [h('div', { class: 'section-title' }, t('other_chars')), linkedOnly.map(charCard)] : null,
      h('p', { class: 'small muted', style: 'text-align:center' }, t('tokens_hint'))
    ];
  }

  /* ---------------- OpenJooki updates (the Jooki itself talks to GitHub) */
  var upd = { state: 'idle', latest: null, lines: '', startedFrom: null };
  function vparts(v) { return String(v || '0').split(/[.-]/).map(function (x) { return parseInt(x, 10) || 0; }); }
  function newer(a, b) {
    var x = vparts(a), y = vparts(b);
    for (var i = 0; i < Math.max(x.length, y.length); i++) { if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0); }
    return false;
  }
  function installed() { return S.device.openjooki || null; }
  function updateAvailable() { return upd.latest && installed() && newer(upd.latest, installed()); }
  function getText(path, cb) {
    var x = new XMLHttpRequest();
    x.open('GET', path + (path.indexOf('?') < 0 ? '?' : '&') + 't=' + Date.now());
    x.timeout = 5000;
    x.onload = function () { cb(x.status === 200 ? x.responseText : null, x.getResponseHeader('Last-Modified')); };
    x.onerror = x.ontimeout = function () { cb(null, null); };
    x.send();
  }
  function checkUpdate() {
    if (upd.state === 'running' || upd.state === 'rebooting' || !installed()) return;
    upd.state = 'checking'; render();
    var t0 = Date.now();
    // the Jooki writes {"pending":true} right away, then the answer from GitHub
    send('OJ_UPDATE_CHECK', {});
    setTimeout(function poll() {
      getText('/oj-latest.json', function (txt) {
        var d = null;
        try { d = JSON.parse(txt); } catch (e) {}
        if (d && !d.pending) {
          if (d.error || !d.version) { upd.state = 'offline'; }
          else { upd.latest = String(d.version); upd.state = 'checked'; }
          render(); return;
        }
        if (Date.now() - t0 > 40000) { upd.state = 'offline'; render(); return; }
        setTimeout(poll, 1500);
      });
    }, 1500);
  }
  function startUpdate() {
    confirmBox(t('upd_q', upd.latest), t('upd_text'), t('upd_now'), false).then(function (ok) {
      if (!ok) return;
      upd.state = 'running'; upd.lines = ''; upd.startedFrom = installed();
      send('OJ_UPDATE_START', {});
      render();
      setTimeout(function poll() {
        if (upd.state !== 'running') return;
        getText('/oj-status.txt', function (txt) {
          if (txt) {
            upd.lines = txt;
            if (/already up to date/i.test(txt)) { upd.state = 'checked'; toast(t('upd_uptodate')); render(); return; }
            if (/ERROR|SAFETY|INVALID|not performed|did not complete|download failed|no network|invalid manifest/i.test(txt) && !/retry/i.test(txt.split('\n').filter(Boolean).pop() || '')) {
              upd.state = 'failed'; render(); return;
            }
          }
          render();
          setTimeout(poll, 3000);
        });
      }, 1500);
    });
  }
  function updateCard() {
    var cur = installed();
    var status = null, action = null;
    if (upd.state === 'checking') status = t('upd_checking');
    else if (upd.state === 'offline') status = t('upd_offline');
    else if (upd.state === 'failed') status = t('upd_failed');
    else if (upd.state === 'checked') status = updateAvailable() ? t('upd_available', upd.latest) : t('upd_uptodate');
    if (upd.state === 'running' || upd.state === 'rebooting') {
      var last = (upd.lines || '').split('\n').filter(Boolean).pop() || '';
      return h('div', { class: 'card', style: 'padding:16px', 'data-k': 'updcard' },
        h('div', { class: 'row' }, h('div', { class: 'spinner', style: 'width:28px;height:28px;border-width:3px;margin:0' }),
          h('b', { class: 'grow' }, upd.state === 'rebooting' ? t('upd_rebooting') : t('upd_running'))),
        h('p', { class: 'small muted' }, t('upd_keep')),
        last ? h('p', { class: 'small', style: 'font-family:ui-monospace,monospace;word-break:break-word' }, last.replace(/^\[[^\]]*\]\s*/, '')) : null);
    }
    if (upd.state === 'checked' && updateAvailable()) action = h('button', { class: 'btn primary block', 'data-k': 'updnow', onclick: startUpdate }, icon('upload'), t('upd_now'));
    else action = h('button', { class: 'btn block', 'data-k': 'updcheck', disabled: upd.state === 'checking' || !cur, onclick: checkUpdate }, t('upd_check'));
    return h('div', { class: 'card', style: 'padding:14px 16px' },
      status ? h('p', { class: 'small', style: 'margin:0 0 10px' + (updateAvailable() ? ';color:var(--accent);font-weight:700' : '') }, status) : null, action);
  }
  var lastOnline = true, backAt = 0;
  function watchUpdateReconnect() {
    if (upd.state === 'running' && !online && lastOnline) upd.state = 'rebooting';
    if (upd.state === 'rebooting' && online && gotState && installed()) {
      if (installed() !== upd.startedFrom) {
        upd.state = 'checked'; toast(t('upd_done', installed())); upd.latest = installed(); backAt = 0;
      } else if (!backAt) {
        backAt = Date.now();
        setTimeout(function () { if (upd.state === 'rebooting' && installed() === upd.startedFrom) { upd.state = 'failed'; render(); } }, 90000);
      }
    }
    lastOnline = online;
  }

  function viewSettings() {
    var d = S.device, pw = S.power, w = S.wifi, cfg = S.audio.config;
    var lvl = pw.level && typeof pw.level === 'object' ? Number(pw.level.p) : NaN;
    var bat = isNaN(lvl) || (lvl === 0 && pw.level && !pw.level.mv) ? '—' : Math.round(lvl / 10) + ' %' + (pw.charging ? ' · ' + t('charging') : pw.connected ? ' · ' + t('plugged') : '');
    var du = obj(d.diskUsage);
    var total = Number(du.total) * 1024, used = Number(du.used) * 1024, free = Number(du.available) * 1024;
    return [
      h('div', { class: 'section-title' }, t('device')),
      h('div', { class: 'card' },
        h('div', { class: 'kv' }, h('span', null, t('device_name')), h('b', null, (d.hostname || '—').replace(/\.local$/, ''))),
        h('div', { class: 'kv' }, h('span', null, t('battery')), h('b', null, bat)),
        wifiRow(w),
        h('div', { class: 'kv' }, h('span', null, t('ip')), h('b', null, (d.ip || location.hostname) + (S.net.name ? ' · ' + S.net.name : ''))),
        h('div', { class: 'kv' }, h('span', null, t('storage')), h('b', null, total ? fmtBytes(free) + ' ' + t('free') + ' / ' + fmtBytes(total) : '—')),
        total ? h('div', { class: 'meter' }, h('i', { style: 'width:' + Math.min(100, Math.round(used / total * 100)) + '%' })) : null,
        h('div', { class: 'kv' }, h('span', null, t('version')), h('b', null, 'OpenJooki ' + (d.openjooki || '—'),
          h('div', { class: 'small muted', style: 'font-weight:400' }, t('web_page') + ' ' + VERSION + (d.firmware ? ' · ' + d.firmware : ''))))),
      updateCard(),
      h('div', { class: 'section-title' }, t('playback')),
      h('div', { class: 'card' },
        h('label', { class: 'switch' }, h('span', null, t('toy_safe')), h('input', { type: 'checkbox', role: 'switch', checked: !!d.toy_safe, 'data-k': 'toysafe',
          onchange: function (e) { send('SET_TOY_SAFE', { enable: e.target.checked }); } })),
        h('label', { class: 'switch' }, h('span', null, t('shuffle')), h('input', { type: 'checkbox', role: 'switch', checked: !!cfg.shuffle_mode, 'data-k': 'shuffle',
          onchange: function (e) { send('SET_CFG', { shuffle_mode: e.target.checked }); } })),
        h('label', { class: 'switch' }, h('span', null, t('repeat')), h('input', { type: 'checkbox', role: 'switch', checked: cfg.repeat_mode === 1 || cfg.repeat_mode === true, 'data-k': 'repeat',
          onchange: function (e) { send('SET_CFG', { repeat_mode: e.target.checked ? 1 : 0 }); } }))),
      bedtimeCard(),
      h('div', { class: 'section-title' }, t('language')),
      h('div', { class: 'card', style: 'padding:12px 16px' }, h('div', { class: 'seg', role: 'group', 'aria-label': t('language') },
        h('button', { class: lang === 'fr' ? 'on' : '', onclick: function () { setLang('fr'); } }, 'Français'),
        h('button', { class: lang === 'en' ? 'on' : '', onclick: function () { setLang('en'); } }, 'English'))),
      h('div', { class: 'actions', style: 'margin-top:24px' }, h('button', { class: 'btn danger', onclick: function () {
        confirmBox(t('power_off_q'), t('power_off_text'), t('power_off'), true).then(function (ok) {
          if (!ok) return;
          send('SHUTDOWN', { src: 'from-web' }); toast(t('power_off_done'));
        });
      } }, icon('power'), t('power_off')))
    ];
  }
  function wifiRow(w) {
    var dbm = Number(w.signal);
    var has = w.signal !== undefined && w.signal !== null && !isNaN(dbm);
    var q = !has ? null : dbm >= -65 ? 'good' : dbm >= -75 ? 'fair' : 'weak';
    var n = S.net, drops = Number(n.drops) || 0;
    return h('div', { class: 'kv col', 'data-k': 'wifirow' },
      h('div', { class: 'row', style: 'width:100%' }, h('span', { class: 'grow' }, t('wifi')),
        h('b', null, (w.ssid || '—') + (has ? ' · ' + dbm + ' dBm' : ''))),
      q ? h('div', { class: 'small wifi-' + q, 'data-k': 'wifiq' }, t('wifi_' + q) + (drops ? ' · ' + t('wifi_drops', drops) : '')) : null,
      q === 'weak' ? h('div', { class: 'small muted' }, t('wifi_advice')) : null);
  }
  function setLang(l) { lang = l; lsSet('oj.lang', l); document.documentElement.lang = l; render(); }

  /* ------------------------------------------------------------------ bedtime */
  function sleepInfo() { var s = S.bedtime.sleep; return s && typeof s === 'object' && s.mode ? s : null; }
  function sleepLeft() {
    var s = sleepInfo();
    if (!s || s.remaining === undefined || s.remaining === null) return null;
    return Math.max(0, Number(s.remaining) - (Date.now() - sleepStamp) / 1000);
  }
  function sleepText() {
    var s = sleepInfo();
    if (!s) return t('sleep_timer');
    return (s.mode === 'track' ? t('sleep_at_end') : t('sleep_left', fmtTime(sleepLeft()))) + (s.auto ? ' · ' + t('sleep_auto') : '');
  }
  function sleepShort() { var s = sleepInfo(); return !s ? '' : s.mode === 'track' ? t('sleep_track') : fmtTime(sleepLeft()); }
  function hm(m) { m = Number(m) || 0; var hh = Math.floor(m / 60) % 24, mm = m % 60; return (hh < 10 ? '0' : '') + hh + ':' + (mm < 10 ? '0' : '') + mm; }
  // the Jooki keeps UTC: tell it the family's time zone (Europe: summer time rule handled on the Jooki)
  function browserClock() {
    var y = new Date().getFullYear();
    var jan = new Date(y, 0, 1).getTimezoneOffset(), jul = new Date(y, 6, 1).getTimezoneOffset();
    var zone = '';
    try { zone = Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch (e) {}
    if (jan !== jul && /^Europe\//.test(zone)) return { tzbase: -Math.max(jan, jul), tzdst: 'EU' };
    return { tzbase: -new Date().getTimezoneOffset(), tzdst: 'none' };
  }
  var clockSynced = false;
  function syncClock() {
    var c = S.bedtime.cfg;
    if (clockSynced || c.tzbase === undefined || !online) return;
    clockSynced = true;
    var b = browserClock();
    if (b.tzbase !== c.tzbase || b.tzdst !== c.tzdst) send('OJ_BEDTIME_SET', b);
  }
  function setBedtime(p) { var b = browserClock(); p.tzbase = b.tzbase; p.tzdst = b.tzdst; send('OJ_BEDTIME_SET', p); }
  function sleepPanel() {
    var s = sleepInfo();
    return h('div', { class: 'sleep' },
      h('div', { class: 'row small muted sleephead' }, icon('moon'), h('span', { 'data-sleep': '1' }, sleepText())),
      h('div', { class: 'chips' },
        [10, 20, 30, 45, 60].map(function (m) {
          return h('button', { class: 'toggle', 'data-sleep-min': String(m), onclick: function () { send('OJ_SLEEP', { minutes: m }); } }, t('sleep_min', m));
        }),
        h('button', { class: 'toggle' + (s && s.mode === 'track' ? ' on' : ''), 'data-sleep-min': 'track', onclick: function () { send('OJ_SLEEP', { mode: 'track' }); } }, t('sleep_track')),
        s ? h('button', { class: 'toggle', 'data-k': 'sleepoff', 'aria-label': t('sleep_cancel'), onclick: function () { send('OJ_SLEEP', { cancel: true }); } }, icon('x'), t('sleep_off')) : null));
  }
  var nightVolDrag = null;
  function bedtimeCard() {
    var c = S.bedtime.cfg;
    if (c.start === undefined) return null; // firmware without bedtime
    var mv = nightVolDrag !== null ? nightVolDrag : Number(c.maxvol) || 100;
    var timers = [0, 10, 15, 20, 30, 45, 60];
    if (timers.indexOf(Number(c.timer)) < 0) { timers.push(Number(c.timer)); timers.sort(function (a, b) { return a - b; }); }
    function volLabel(v) { return t('night_maxvol') + ' : ' + (v >= 100 ? t('night_nolimit') : v + ' %'); }
    return [h('div', { class: 'section-title' }, t('bedtime')),
      h('div', { class: 'card', 'data-k': 'bedcard' },
        h('label', { class: 'switch' }, h('div', null, h('div', null, t('night_mode')), h('div', { class: 'small muted' }, t('night_help'))),
          h('input', { type: 'checkbox', role: 'switch', checked: !!c.enabled, 'data-k': 'nighton', onchange: function (e) { setBedtime({ enabled: e.target.checked }); } })),
        c.enabled ? [
          h('div', { class: 'kv', 'data-k': 'nightstatus' }, S.bedtime.night ? h('b', { class: 'accent-text' }, t('night_now')) : h('span', { class: 'muted' }, t('night_next', hm(c.start)))),
          h('div', { class: 'timepair' },
            h('label', { class: 'field' }, h('span', null, t('night_from')), h('input', { class: 'input', type: 'time', value: hm(c.start), 'data-k': 'nightstart',
              onchange: function (e) { if (e.target.value) setBedtime({ start: e.target.value }); } })),
            h('label', { class: 'field' }, h('span', null, t('night_to')), h('input', { class: 'input', type: 'time', value: hm(c.stop), 'data-k': 'nightstop',
              onchange: function (e) { if (e.target.value) setBedtime({ stop: e.target.value }); } }))),
          h('label', { class: 'field pad' }, h('span', null, t('night_timer')),
            h('select', { class: 'input', 'data-k': 'nighttimer', onchange: function (e) { e.target.blur(); setBedtime({ timer: Number(e.target.value) }); } },
              timers.map(function (m) { return h('option', { value: String(m), selected: Number(c.timer) === m ? 'selected' : null }, m ? t('sleep_min', m) : t('night_timer_none')); }))),
          h('label', { class: 'field pad' }, h('span', { 'data-nightvol': '1' }, volLabel(mv)),
            h('input', { class: 'range', type: 'range', min: '10', max: '100', step: '5', value: String(mv), 'data-k': 'nightvol',
              oninput: function (e) { nightVolDrag = Number(e.target.value); var l = document.querySelector('[data-nightvol]'); if (l) l.textContent = volLabel(nightVolDrag); },
              onchange: function (e) { nightVolDrag = null; setBedtime({ maxvol: Number(e.target.value) }); } })),
          h('label', { class: 'switch' }, h('span', null, t('night_dim')), h('input', { type: 'checkbox', role: 'switch', checked: !!c.dim, 'data-k': 'nightdim',
            onchange: function (e) { setBedtime({ dim: e.target.checked }); } })),
          h('p', { class: 'small muted pad', style: 'margin:4px 0 14px' }, t('night_clock'))
        ] : null)];
  }
  function sortedTracks(list) {
    var c = collator();
    return list.slice().sort(function (a, b) { return c.compare(trackTitle(a), trackTitle(b)) || (a < b ? -1 : a > b ? 1 : 0); });
  }

  /* ------------------------------------------------------------------ player */
  function isPlaying() { return S.audio.playback.state === 'PLAYING' || S.audio.playback.state === 'STARTING'; }
  function hasNow() { var np = S.audio.nowPlaying; return !!(np && np.playlistId && np.uri); }
  function curPos() {
    var pb = S.audio.playback;
    var p = Number(pb.position_ms) || 0;
    if (pb.state === 'PLAYING') p += Date.now() - posStamp;
    var d = Number(S.audio.nowPlaying.duration_ms) || 0;
    return d ? Math.min(p, d) : p;
  }
  function playerBar() {
    var np = S.audio.nowPlaying;
    var pl = pls()[np.playlistId];
    var now = hasNow();
    var cover = h('div', { class: 'cover' });
    var fallback = function () { return now && pl && pl.star ? tokVisual(pl.star, 'sm') : icon('note'); };
    if (now && np.image) {
      var ci = h('img', { src: np.image, alt: '' });
      ci.onerror = function () { ci.replaceWith(fallback()); };
      cover.appendChild(ci);
    } else cover.appendChild(fallback());
    var d = Number(np.duration_ms) || 0;
    return h('div', { class: 'player' + (now ? '' : ' idle'), 'data-k': 'player' },
      h('div', { class: 'prog' }, h('i', { 'data-prog': '1', style: 'width:' + (d ? Math.round(curPos() / d * 100) : 0) + '%' })),
      cover,
      h('div', { class: 'info', role: 'button', tabindex: '0', 'aria-label': t('open_player'), onclick: function () { if (now) nowPlayingModal(); },
        onkeydown: function (e) { if (e.key === 'Enter' && now) nowPlayingModal(); } },
        h('div', { class: 't ellipsis' }, now ? cleanTitle(np.track || trackTitle(np.trackId)) : t('nothing_playing')),
        h('div', { class: 's ellipsis' }, sleepInfo() ? h('span', { class: 'sleepmini' }, icon('moon'), h('span', { 'data-sleep-short': '1' }, sleepShort())) : null,
          now ? (np.source || (pl && pl.title) || '') : t('nothing_hint'))),
      now ? h('button', { class: 'icon-btn', 'aria-label': t('prev'), onclick: function () { send('DO_PREV', {}); } }, icon('prev')) : null,
      now ? h('button', { class: 'icon-btn accent', 'aria-label': isPlaying() ? t('pause') : t('play'), 'data-k': 'pp',
        onclick: function () { send(isPlaying() ? 'DO_PAUSE' : 'DO_PLAY', {}); } }, icon(isPlaying() ? 'pause' : 'play')) : null,
      now ? h('button', { class: 'icon-btn', 'aria-label': t('next'), onclick: function () { send('DO_NEXT', {}); } }, icon('next')) : null);
  }
  var seeking = false, volDrag = null;
  function nowPlayingModal() {
    openModal({
      live: true,
      sig: function () {
        var np = S.audio.nowPlaying, c = S.audio.config;
        var sl = sleepInfo() || {};
        return [np.playlistId, np.trackId, np.trackIndex, S.audio.playback.state, c.volume, c.shuffle_mode, c.repeat_mode, np.duration_ms, sl.mode, sl.total, sl.auto].join('|');
      },
      render: function () {
        var np = S.audio.nowPlaying, pl = pls()[np.playlistId];
        var cfg = S.audio.config;
        var d = Number(np.duration_ms) || 0;
        var stream = np.service === 'STREAM';
        var art = h('div', { class: 'art' });
        if (np.image) {
          var ai = h('img', { src: np.image, alt: '' });
          ai.onerror = function () { ai.replaceWith(tokVisual(pl && pl.star, '')); };
          art.appendChild(ai);
        } else art.appendChild(tokVisual(pl && pl.star, ''));
        var vol = volDrag !== null ? volDrag : Number(cfg.volume) || 0;
        return h('div', { class: 'np' }, art,
          h('div', { class: 't' }, cleanTitle(np.track || trackTitle(np.trackId)) || '—'),
          h('div', { class: 'muted' }, [np.artist && np.artist !== 'unknown' ? np.artist : null, np.source || (pl && pl.title)].filter(Boolean).join(' · ')),
          stream ? h('div', { class: 'badge accent', style: 'margin-top:12px' }, t('live')) : [
            h('input', { class: 'range', type: 'range', min: '0', max: String(d || 1), value: String(Math.round(curPos())), 'aria-label': 'position', 'data-k': 'seek', 'data-seek': '1',
              oninput: function () { seeking = true; }, onchange: function (e) { seeking = false; send('SEEK', { position_ms: Math.max(1, Number(e.target.value)) }); } }),
            h('div', { class: 'times' }, h('span', { 'data-cur': '1' }, fmtTime(curPos() / 1000)), h('span', null, fmtTime(d / 1000)))],
          h('div', { class: 'controls' },
            h('button', { class: 'icon-btn', 'aria-label': t('prev'), onclick: function () { send('DO_PREV', {}); } }, icon('prev')),
            h('button', { class: 'icon-btn accent', 'aria-label': isPlaying() ? t('pause') : t('play'), 'data-k': 'nppp', onclick: function () { send(isPlaying() ? 'DO_PAUSE' : 'DO_PLAY', {}); } }, icon(isPlaying() ? 'pause' : 'play')),
            h('button', { class: 'icon-btn', 'aria-label': t('next'), onclick: function () { send('DO_NEXT', {}); } }, icon('next'))),
          h('div', { class: 'vol' }, icon('vol'), h('input', { class: 'range', type: 'range', min: '0', max: '100', step: '5', value: String(vol), 'aria-label': t('volume'), 'data-k': 'vol',
            oninput: function (e) { volDrag = Number(e.target.value); }, onchange: function (e) { volDrag = null; send('SET_VOL', { vol: Number(e.target.value) }); } })),
          h('div', { class: 'toggles' },
            h('button', { class: 'toggle' + (cfg.shuffle_mode ? ' on' : ''), 'aria-pressed': String(!!cfg.shuffle_mode), onclick: function () { send('SET_CFG', { shuffle_mode: !cfg.shuffle_mode }); } }, icon('shuffle'), t('shuffle')),
            h('button', { class: 'toggle' + (cfg.repeat_mode === 1 ? ' on' : ''), 'aria-pressed': String(cfg.repeat_mode === 1), onclick: function () { send('SET_CFG', { repeat_mode: cfg.repeat_mode === 1 ? 0 : 1 }); } }, icon('repeat'), t('repeat'))),
          S.bedtime.cfg.start !== undefined ? sleepPanel() : null,
          h('div', { class: 'foot' }, h('button', { class: 'btn block', onclick: closeModal }, t('close'))));
      }
    });
  }
  setInterval(function () {
    if (sleepInfo()) {
      Array.prototype.forEach.call(document.querySelectorAll('[data-sleep]'), function (el) { el.textContent = sleepText(); });
      Array.prototype.forEach.call(document.querySelectorAll('[data-sleep-short]'), function (el) { el.textContent = sleepShort(); });
    }
    if (!hasNow() || S.audio.playback.state !== 'PLAYING') return;
    var d = Number(S.audio.nowPlaying.duration_ms) || 0;
    var p = curPos();
    var bar = document.querySelector('[data-prog]');
    if (bar && d) bar.style.width = Math.round(p / d * 100) + '%';
    if (!seeking) {
      var r = document.querySelector('[data-seek]'); if (r) r.value = String(Math.round(p));
      var c = document.querySelector('[data-cur]'); if (c) c.textContent = fmtTime(p / 1000);
    }
  }, 500);

  /* ------------------------------------------------------------------ render */
  var root, rq = false, rendering = false, pendingRender = false;
  document.addEventListener('focusout', function (e) { if (pendingRender && e.target && e.target.tagName === 'SELECT') setTimeout(render, 0); });
  document.addEventListener('change', function (e) { if (pendingRender && e.target && e.target.tagName === 'SELECT') setTimeout(render, 0); });
  function scheduleRender() { if (rq) return; rq = true; requestAnimationFrame(function () { rq = false; render(); }); }
  function navLink(hash, name, ic, label) {
    var r = route().name;
    var active = r === name || (name === 'playlists' && r === 'p');
    return h('a', { href: hash, class: active ? 'active' : '', 'aria-current': active ? 'page' : null }, icon(ic), h('span', null, label));
  }
  function render() {
    if (!root) return;
    watchUpdateReconnect();
    if (ui.dragging || nightVolDrag !== null) return;
    var ae = document.activeElement;
    if (ae && ae.tagName === 'SELECT' && root.contains(ae)) { pendingRender = true; return; }
    pendingRender = false;
    var keep = captureFocus(root);
    var r = route();
    var title, body, back = null;
    if (!gotState) {
      body = h('div', { class: 'connect-screen' }, h('div', { class: 'spinner' }),
        h('div', null, online || !everOnline ? t('connecting') : t('offline')),
        !online && retryDelay > 1600 ? h('p', { class: 'small muted' }, t('offline_long')) : null,
        !online && retryDelay > 1600 ? h('button', { class: 'btn', onclick: function () { retryDelay = 1000; connect(); } }, t('retry')) : null);
      title = lang === 'fr' ? 'Mon Jooki' : 'My Jooki';
    } else if (r.name === 'p') {
      var p = pls()[r.arg];
      title = p ? (p.title || '—') : t('playlists');
      back = '#/';
      body = viewPlaylist(r.arg);
    } else if (r.name === 'tokens') { title = t('tokens'); body = viewTokens(); }
    else if (r.name === 'library') { title = t('library'); body = viewLibrary(r.arg); }
    else if (r.name === 'settings') { title = t('settings'); body = viewSettings(); }
    else { title = t('playlists'); body = viewPlaylists(); }
    document.title = gotState ? title + ' — OpenJooki' : 'OpenJooki';
    var conn = h('div', { class: 'conn ' + (online ? 'on' : 'off'), role: 'status', 'aria-live': 'polite' }, h('i'), online ? t('connected') : t('offline'));
    var shell = h('div', { class: 'shell' },
      h('header', { class: 'topbar' },
        back ? h('a', { class: 'icon-btn', href: back, 'aria-label': t('back') }, icon('back')) : h('div', { class: 'brand' }, h('div', { class: 'dot' }, 'J')),
        h('div', { class: 'titles' },
          h('a', { class: 'wordmark', href: '#/', 'aria-label': 'OpenJooki' }, 'Open', h('span', null, 'Jooki')),
          h('h1', null, title)), conn),
      !online && gotState ? h('div', { class: 'banner danger', style: 'margin:12px 16px 0' }, t('offline_long')) : null,
      h('main', { id: 'main' }, body),
      h('nav', { class: 'nav', 'aria-label': 'Navigation' },
        h('a', { class: 'nav-brand', href: '#/', 'aria-hidden': 'true', tabindex: '-1' }, h('span', { class: 'dot' }, 'J'), h('span', null, 'Open', h('b', null, 'Jooki'))),
        navLink('#/', 'playlists', 'list', t('playlists')),
        navLink('#/tokens', 'tokens', 'token', t('tokens')),
        navLink('#/library', 'library', 'lib', t('library')),
        navLink('#/settings', 'settings', 'gear', t('settings'))),
      gotState ? playerBar() : null);
    rendering = true;
    try {
      root.innerHTML = '';
      root.appendChild(shell);
      restoreFocus(root, keep);
    } finally { rendering = false; }
    if (modal && modal.live && volDrag === null && !seeking) {
      var sig = modal.sig ? modal.sig() : '';
      if (sig !== modal.lastSig) { modal.lastSig = sig; renderModal(); }
    }
  }

  /* ------------------------------------------------------------------ boot */
  function boot() {
    document.documentElement.lang = lang;
    root = document.getElementById('app');
    toastBox = h('div', { class: 'toasts', 'aria-live': 'polite' });
    modalRoot = h('div');
    document.body.appendChild(toastBox);
    document.body.appendChild(modalRoot);
    if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
      navigator.serviceWorker.getRegistrations().then(function (rs) { rs.forEach(function (r) { r.unregister(); }); }).catch(function () {});
    }
    render();
    connect();
  }
  window.OJ = { state: S, send: send, version: VERSION };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
